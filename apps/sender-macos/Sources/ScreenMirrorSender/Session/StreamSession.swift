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
        case stopped(String)
    }

    private let receiverClient: ReceiverClient
    private let capture = ScreenCaptureHandler()
    private var encoder: H264Encoder?
    private var streamClient: StreamClient?
    private var stats = Stats()
    private var statsStartedAt: CMTime?
    private let statsQueue = DispatchQueue(label: "tv.screenmirror.sender.stats")

    var onStateChange: ((State) -> Void)?
    var onStats: ((Stats) -> Void)?

    init(receiverClient: ReceiverClient = ReceiverClient()) {
        self.receiverClient = receiverClient
    }

    /// Lanza el stream. `displayID` = pantalla a capturar: la principal es *espejo*,
    /// cualquier otra es *extender* (ADR-006). El receptor ya conoce su techo por `/status`.
    /// `cap` permite forzar un techo por debajo del del receptor (para tests A/B de nitidez).
    @MainActor
    func start(
        host: String,
        token: String,
        displayID: CGDirectDisplayID,
        fps: Int = Protocol.defaultFps,
        cap: (width: Int, height: Int)? = nil,
    ) async throws {
        let status = try await receiverClient.fetchStatus(host: host)

        let displays = try await ScreenCaptureHandler.availableDisplays()
        guard let display = displays.first(where: { $0.id == String(displayID) }) else {
            throw SenderError.displayNotFound
        }

        let ceiling = cap ?? (status.maxW, status.maxH)
        var config = StreamConfig(width: display.width, height: display.height, fps: fps)
            .fitted(maxWidth: ceiling.width, maxHeight: ceiling.height)
        config.bitrateKbps = StreamConfig.bitrateKbps(forWidth: config.width, height: config.height)

        let encoder = try H264Encoder(config: config)
        let streamClient = try StreamClient(host: host)

        // Abrimos primero: si la TV está ocupada (409) o rechaza la resolución (413)
        // lo sabemos antes de arrancar la captura.
        _ = try await streamClient.open(query: config.query(token: token))

        self.encoder = encoder
        self.streamClient = streamClient
        wireCallbacks(encoder: encoder, streamClient: streamClient, capture: capture)

        do {
            try await capture.start(displayID: displayID, width: config.width, height: config.height, fps: fps)
        } catch {
            await teardown()
            throw error
        }

        statsStartedAt = nil
        onStateChange?(.streaming(config))
    }

    func stop() async {
        // Esperamos el cierre: si no, la CLI hace `exit()` y el terminador chunked
        // ("0\r\n\r\n") se pierde → el receptor ve un RST en vez de un EOF limpio.
        await teardown()
        onStateChange?(.stopped("Detenido"))
    }

    // MARK: - Privado

    private func wireCallbacks(encoder: H264Encoder, streamClient: StreamClient, capture: ScreenCaptureHandler) {
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
        encoder?.onAccessUnit = nil
        encoder?.onError = nil

        let capture = capture
        let encoder = encoder
        let streamClient = streamClient
        self.encoder = nil
        self.streamClient = nil

        // Los callbacks ya están desenganchados: el estado se informó en `stop()`/`fail(with:)`,
        // así que un fallo al detener la captura no cambia nada para quien nos escucha.
        try? await capture.stop()
        encoder?.finish()
        await streamClient?.close()
    }

    private func fail(with error: Error) {
        // El origen del fallo puede ser la propia red: no bloqueamos el callback esperando.
        Task { await teardown() }
        onStateChange?(.stopped(error.localizedDescription))
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
