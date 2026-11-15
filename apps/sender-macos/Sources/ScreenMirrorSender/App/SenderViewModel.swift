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
    @Published var isStreaming = false
    @Published var statsText: String?
    @Published var errorText: String?

    private let receiverClient = ReceiverClient()
    private let session = StreamSession()
    private let browser = ReceiverBrowser()

    init() {
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
        guard ScreenCaptureHandler.requestPermission() else {
            errorText = SenderError.screenRecordingDenied.localizedDescription
            return
        }
        Task {
            do {
                displays = try await ScreenCaptureHandler.availableDisplays()
                if selectedDisplayID == nil {
                    selectedDisplayID = displays.first(where: \.isMain)?.id ?? displays.first?.id
                }
            } catch {
                errorText = error.localizedDescription
            }
        }
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
        token = nil // El token es de una sesión concreta: al cambiar de TV hay que emparejar de nuevo.
        fetchStatus()
    }

    func pair() {
        Task {
            do {
                token = try await receiverClient.pair(host: host, pin: pin)
                errorText = nil
            } catch {
                errorText = error.localizedDescription
            }
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
                try await session.start(host: host, token: token, displayID: displayID)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
