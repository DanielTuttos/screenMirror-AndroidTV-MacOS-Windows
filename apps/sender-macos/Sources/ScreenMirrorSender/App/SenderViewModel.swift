import CoreGraphics
import Foundation

/// Estado de la UI del menú de barra. No conoce ScreenCaptureKit ni VideoToolbox:
/// habla con `ReceiverClient` y `StreamSession` (flujo ui → caso de uso → data).
@MainActor
final class SenderViewModel: ObservableObject {
    @Published var host: String = ""
    @Published var pin: String = ""
    @Published var token: String?
    @Published var receiverName: String?
    @Published var maxResolution: String?
    @Published var receivers: [DiscoveredReceiver] = []
    @Published var displays: [DisplayDescriptor] = []
    @Published var selectedDisplayID: String?
    /// FPS deseados (30 para menos uso de red/batería o 60 para máxima fluidez).
    @Published var targetFps: Int = 60
    /// Pantalla virtual propia creada por el emisor (nil = no creada, ADR-006).
    @Published private(set) var virtualDisplay: VirtualDisplay?
    @Published var isStreaming = false
    /// El driver «ScreenMirror TV» aporta la salida de sonido que va a la TV (drivers/macos-audio).
    @Published private(set) var isAudioDriverInstalled = SystemAudioTap.isDeviceInstalled()
    @Published var statsText: String?
    @Published var errorText: String?

    private let receiverClient = ReceiverClient()
    private let session = StreamSession()
    private let browser = ReceiverBrowser()
    private let tokenStore: TokenStore
    private let audioConnection = AudioDriverConnection()

    init(tokenStore: TokenStore = KeychainTokenStore()) {
        self.tokenStore = tokenStore
        // Tras conectar el socket con el driver, le damos un breve instante a coreaudiod
        // para publicar el dispositivo antes de comprobar el estado para la UI.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isAudioDriverInstalled = SystemAudioTap.isDeviceInstalled()
        }
        // Los callbacks llegan desde las colas de captura y de red: la UI solo se
        // toca en el hilo principal.
        browser.onUpdate = { [weak self] list in
            DispatchQueue.main.async { self?.receivers = list }
        }
        browser.start()
        session.onStateChange = { [weak self] state in
            DispatchQueue.main.async {
                guard let self else { return }
                switch state {
                case .streaming:
                    self.isStreaming = true
                    self.errorText = nil
                case .reconnecting(let reason):
                    // Sigue "emitendo": el botón debe seguir ofreciendo detener.
                    self.isStreaming = true
                    self.statsText = "Reconectando… (\(reason))"
                case .stopped:
                    self.isStreaming = false
                    self.statsText = nil
                case .idle:
                    break
                }
            }
        }
        session.onStats = { [weak self] stats in
            DispatchQueue.main.async {
                self?.statsText = "\(stats.fps) fps · \(stats.bitrateKbps) kbps"
            }
        }
    }

    func refreshDisplays() {
        isAudioDriverInstalled = SystemAudioTap.isDeviceInstalled()
        guard ScreenCaptureHandler.requestPermission() else {
            errorText = SenderError.screenRecordingDenied.localizedDescription
            return
        }
        Task {
            do {
                // macOS tarda un poco en listar una pantalla virtual recién creada:
                // si no aparece a la primera, se reintenta una vez.
                var list = try await ScreenCaptureHandler.availableDisplays()
                if let pending = virtualDisplay?.displayID,
                   !list.contains(where: { $0.id == String(pending) }) {
                    try await Task.sleep(nanoseconds: 500_000_000)
                    list = try await ScreenCaptureHandler.availableDisplays()
                }
                displays = list
                // Preserva la selección; si la pantalla elegida ya no existe
                // (p. ej. se retiró la virtual), vuelve a la principal.
                if selectedDisplayID == nil || !list.contains(where: { $0.id == selectedDisplayID }) {
                    selectedDisplayID = list.first(where: \.isMain)?.id ?? list.first?.id
                }
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    /// Crea o retira la pantalla virtual propia (botón de la GUI, ADR-006).
    func setVirtualDisplay(enabled: Bool) {
        if enabled {
            // Cambiar de pantalla en mitad de una emisión deja la UI mostrando
            // una pantalla que no se está emitiendo: mejor avisar.
            guard !isStreaming else {
                errorText = "Detén la emisión antes de crear la pantalla virtual."
                return
            }
            do {
                let display = try VirtualDisplay(name: "ScreenMirror", size: (2560, 1440))
                virtualDisplay = display
                selectedDisplayID = String(display.displayID)
                errorText = nil
                refreshDisplays()
            } catch {
                errorText = error.localizedDescription
            }
            return
        }
        // Si se emite desde la virtual, primero se corta la sesión: la captura
        // apunta a una pantalla que va a desaparecer.
        if let display = virtualDisplay, isStreaming,
           selectedDisplayID == String(display.displayID) {
            Task {
                await session.stop()
                releaseVirtualDisplay()
            }
        } else {
            releaseVirtualDisplay()
        }
    }

    /// Al liberarse el objeto, macOS retira la display (como desenchufarla).
    private func releaseVirtualDisplay() {
        virtualDisplay = nil
        selectedDisplayID = nil
        refreshDisplays()
    }

    func fetchStatus() {
        Task {
            do {
                let status = try await receiverClient.fetchStatus(host: host)
                receiverName = status.name
                maxResolution = "\(status.maxW)x\(status.maxH)"
                errorText = nil
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    /// Elige una TV de la lista descubierta y consulta su estado.
    func select(_ receiver: DiscoveredReceiver) {
        host = receiver.host
        loadStoredToken()
        fetchStatus()
    }

    /// Recupera el token guardado de esta TV (nil si nunca se emparejó). Si ya
    /// caducó, el primer intento de emitir lo descarta y pide el PIN de nuevo.
    func loadStoredToken() {
        token = tokenStore.token(forHost: host)
    }

    func pair() {
        Task {
            do {
                let newToken = try await receiverClient.pair(host: host, pin: pin)
                token = newToken
                errorText = nil
                try tokenStore.save(token: newToken, forHost: host)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    /// Token caducado o revocado: se borra para que la UI vuelva a pedir el PIN.
    private func discardToken() {
        token = nil
        do {
            try tokenStore.removeToken(forHost: host)
        } catch {
            errorText = error.localizedDescription
        }
    }

    func toggleStream() {
        if isStreaming {
            Task { await session.stop() }
            return
        }
        guard let token else {
            errorText = "Empareja primero con el PIN de la TV."
            return
        }
        guard
            let selectedDisplayID,
            let displayID = CGDirectDisplayID(selectedDisplayID)
        else {
            errorText = "Elige qué pantalla emitir."
            return
        }

        Task {
            do {
                try await session.start(host: host, token: token, displayID: displayID, fps: targetFps)
            } catch {
                errorText = error.localizedDescription
                if error as? SenderError == .unauthorized { discardToken() }
            }
        }
    }
}
