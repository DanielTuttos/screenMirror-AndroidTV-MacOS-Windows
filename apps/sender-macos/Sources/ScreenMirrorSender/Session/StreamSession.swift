import CoreGraphics
import CoreMedia
import Foundation

/// Caso de uso "emitir en la TV": cablea captura → codificador → transporte.
///
/// Es la contraparte del `ReceiverRuntimeImpl` del receptor: la UI no ve ni
/// ScreenCaptureKit ni VideoToolbox, solo `start`/`stop` y los callbacks de estado.
final class StreamSession {
    struct Stats: Equatable {
        var frames: Int = 0
        var bytes: Int = 0
        var fps: Int = 0
        var bitrateKbps: Int = 0
    }

    enum State: Equatable {
        case idle
        case streaming(StreamConfig)
        /// La sesión cayó (o cambió la display) y se está reintentando con backoff.
        case reconnecting(String)
        case stopped(String)
    }

    /// Parámetros de la sesión en curso: con ellos se reabre el stream tras una caída.
    private struct SessionParams {
        let host: String
        let token: String
        let displayID: CGDirectDisplayID
        let fps: Int
        let cap: (width: Int, height: Int)?
        let withAudio: Bool
    }

    private let receiverClient: ReceiverClient
    private let capture = ScreenCaptureHandler()
    private var encoder: H264Encoder?
    private var streamClient: StreamClient?
    private var audioClient: StreamClient?
    private var audioTap: SystemAudioTap?
    private var stats = Stats()
    private var statsStartedAt: CMTime?
    private let statsQueue = DispatchQueue(label: "tv.screenmirror.sender.stats")

    /// true mientras la sesión *debería* estar viva (hasta `stop()` o un fallo fatal).
    private var isActive = false
    /// Evita bucles de reconexión concurrentes cuando caen vídeo y red a la vez.
    private var reconnecting = false
    private var sessionParams: SessionParams?
    private var displayWatcher: DisplayWatcher?

    var onStateChange: ((State) -> Void)?
    var onStats: ((Stats) -> Void)?

    init(receiverClient: ReceiverClient = ReceiverClient()) {
        self.receiverClient = receiverClient
    }

    /// Lanza el stream. `displayID` = pantalla a capturar: la principal es *espejo*,
    /// cualquier otra es *extender* (ADR-006). El receptor ya conoce su techo por `/status`.
    /// `cap` permite forzar un techo por debajo del del receptor (para tests A/B de nitidez).
    /// `withAudio` abre además `POST /audio` con el PCM del sistema (spec: docs/protocol.md).
    ///
    /// Si la conexión se cae después, la sesión **se reconecta sola** (backoff en
    /// `ReconnectPolicy`) hasta que se pida `stop()` o aparezca un error fatal.
    @MainActor
    func start(
        host: String,
        token: String,
        displayID: CGDirectDisplayID,
        fps: Int = Protocol.defaultFps,
        cap: (width: Int, height: Int)? = nil,
        withAudio: Bool = true,
    ) async throws {
        let params = SessionParams(
            host: host,
            token: token,
            displayID: displayID,
            fps: fps,
            cap: cap,
            withAudio: withAudio,
        )
        isActive = true
        sessionParams = params

        do {
            try await connect(params)
        } catch {
            isActive = false
            sessionParams = nil
            throw error
        }

        watchDisplayChanges(displayID)
    }

    @MainActor
    func stop() async {
        // Esperamos el cierre: si no, la CLI hace `exit()` y el terminador chunked
        // ("0\r\n\r\n") se pierde → el receptor ve un RST en vez de un EOF limpio.
        isActive = false
        sessionParams = nil
        displayWatcher = nil
        await teardown()
        onStateChange?(.stopped("Detenido"))
    }

    // MARK: - Privado

    /// Abre vídeo (+audio) y arranca la captura con los parámetros dados.
    /// Lanza si algo falla: quien decide si se reintenta es el bucle de reconexión.
    @MainActor
    private func connect(_ params: SessionParams) async throws {
        let status = try await receiverClient.fetchStatus(host: params.host)

        let displays = try await ScreenCaptureHandler.availableDisplays()
        guard let display = displays.first(where: { $0.id == String(params.displayID) }) else {
            throw SenderError.displayNotFound
        }

        // Se reconsulta /status y se reenumera la display en cada intento: así una
        // caída aprovecha para adaptarse a un techo nuevo o a una resolución cambiada.
        let ceiling = params.cap ?? (status.maxW, status.maxH)
        var config = StreamConfig(width: display.width, height: display.height, fps: params.fps)
            .fitted(maxWidth: ceiling.width, maxHeight: ceiling.height)
        config.bitrateKbps = StreamConfig.bitrateKbps(forWidth: config.width, height: config.height)

        let encoder = try H264Encoder(config: config)
        let streamClient = try StreamClient(host: params.host)

        // Abrimos primero: si la TV está ocupada (409) o rechaza la resolución (413)
        // lo sabemos antes de arrancar la captura.
        _ = try await streamClient.open(query: config.query(token: params.token))

        // El audio es opcional por spec: sin el driver «ScreenMirror TV», o si la sesión de
        // audio no abre (409 por una sesión colgada, red…), seguimos con vídeo solo.
        var audioClient: StreamClient?
        var audioTap: SystemAudioTap?
        if params.withAudio {
            do {
                let tap = try SystemAudioTap()
                audioTap = tap
                audioClient = try await openAudio(host: params.host, token: params.token, format: tap.format)
            } catch {
                audioTap = nil
                print("⚠ Audio no disponible (\(error.localizedDescription)): emitimos solo vídeo")
            }
        }

        self.encoder = encoder
        self.streamClient = streamClient
        self.audioClient = audioClient
        self.audioTap = audioTap
        wireCallbacks(encoder: encoder, streamClient: streamClient, capture: capture, audioClient: audioClient, audioTap: audioTap)

        do {
            try await capture.start(
                displayID: params.displayID,
                width: config.width,
                height: config.height,
                fps: params.fps,
            )
            try audioTap?.start()
        } catch {
            await teardown()
            throw error
        }

        statsStartedAt = nil
        onStateChange?(.streaming(config))
    }

    /// Abre `POST /audio` con el formato PCM real del tap (spec: docs/protocol.md).
    private func openAudio(host: String, token: String, format: SystemAudioTap.Format) async throws -> StreamClient {
        let client = try StreamClient(host: host, path: Protocol.pathAudio, contentType: Protocol.contentTypePcm)
        let query = "token=\(token)&sr=\(format.sampleRate)&ch=\(format.channels)"
        _ = try await client.open(query: query)
        return client
    }

    private func wireCallbacks(
        encoder: H264Encoder,
        streamClient: StreamClient,
        capture: ScreenCaptureHandler,
        audioClient: StreamClient?,
        audioTap: SystemAudioTap?,
    ) {
        capture.onFrame = { [weak self] sampleBuffer in
            guard let self, let encoder = self.encoder else { return }
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                encoder.encode(pixelBuffer, at: time)
            }
            self.recordFrame(at: time)
        }
        capture.onError = { [weak self] error in
            self?.fail(with: error)
        }
        audioTap?.onPCM = { pcm in audioClient?.send(pcm) }
        encoder.onAccessUnit = { [weak self] accessUnit in
            self?.streamClient?.send(accessUnit)
            self?.recordBytes(accessUnit.count)
        }
        encoder.onError = { [weak self] error in
            self?.fail(with: error)
        }
        streamClient.onDisconnect = { [weak self] error in
            self?.fail(with: error)
        }
    }

    private func teardown() async {
        capture.onFrame = nil
        capture.onError = nil
        audioTap?.onPCM = nil
        encoder?.onAccessUnit = nil
        encoder?.onError = nil

        let capture = capture
        let encoder = encoder
        let streamClient = streamClient
        let audioClient = audioClient
        let audioTap = audioTap
        self.encoder = nil
        self.streamClient = nil
        self.audioClient = nil
        self.audioTap = nil

        // Primero el tap: así el Mac recupera su sonido aunque el resto del cierre tarde.
        audioTap?.stop()
        // Los callbacks ya están desenganchados: el estado se informó en `stop()`/`fail(with:)`,
        // así que un fallo al detener la captura no cambia nada para quien nos escucha.
        try? await capture.stop()
        encoder?.finish()
        // Audio primero: es la conexión más reciente y su cierre no debe esperar al vídeo.
        await audioClient?.close()
        await streamClient?.close()
    }

    /// Fallo en plena emisión (red, decoder, captura): si la sesión sigue activa,
    /// se reconecta sola; si no, se informa el estado y ya.
    private func fail(with error: Error) {
        guard isActive else {
            onStateChange?(.stopped(error.localizedDescription))
            return
        }
        Task { await reconnect(reason: error.localizedDescription) }
    }

    /// Bucle de reconexión con backoff. Sale al reconectar, al pedir `stop()`
    /// o al encontrar un error fatal (permiso, token caducado, pantalla ida).
    @MainActor
    private func reconnect(reason initialReason: String) async {
        guard !reconnecting else { return } // caídas simultáneas (vídeo + red): un solo bucle
        reconnecting = true
        defer { reconnecting = false }

        var reason = initialReason
        var attempt = 1

        while isActive {
            let delay = ReconnectPolicy.delaySeconds(forAttempt: attempt)
            onStateChange?(.reconnecting("\(reason) · reintento \(attempt)"))
            if delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    return // cancelado
                }
            }
            guard isActive else { return }

            do {
                guard let params = sessionParams else { return }
                await teardown() // limpiar la sesión rota antes de montar la nueva
                try await connect(params)
                return // reconectado
            } catch {
                if ReconnectPolicy.isFatal(error) {
                    isActive = false
                    sessionParams = nil
                    displayWatcher = nil
                    await teardown()
                    onStateChange?(.stopped(error.localizedDescription))
                    return
                }
                reason = error.localizedDescription
                attempt += 1
            }
        }
    }

    /// Reinicia la sesión cuando cambia la resolución/orientación de la display emmitida:
    /// la captura anterior queda obsoleta y hay que reabrirla con el tamaño nuevo.
    private func watchDisplayChanges(_ displayID: CGDirectDisplayID) {
        displayWatcher = DisplayWatcher(displayID: displayID) { [weak self] in
            guard let self, self.isActive else { return }
            Task { await self.reconnect(reason: "Cambió la resolución o la orientación de la pantalla") }
        }
    }

    private func recordFrame(at time: CMTime) {
        statsQueue.async { [weak self] in
            guard let self else { return }
            if statsStartedAt == nil { statsStartedAt = time }
            stats.frames += 1
            let elapsed = CMTimeGetSeconds(CMTimeSubtract(time, statsStartedAt ?? time))
            guard elapsed >= 1.0 else { return }
            stats.fps = Int((Double(stats.frames) / elapsed).rounded())
            stats.bitrateKbps = Int((Double(stats.bytes) * 8 / elapsed / 1000).rounded())
            stats.frames = 0
            stats.bytes = 0
            statsStartedAt = time
            let snapshot = stats
            DispatchQueue.main.async { self.onStats?(snapshot) }
        }
    }

    private func recordBytes(_ count: Int) {
        statsQueue.async { [weak self] in
            self?.stats.bytes += count
        }
    }
}
