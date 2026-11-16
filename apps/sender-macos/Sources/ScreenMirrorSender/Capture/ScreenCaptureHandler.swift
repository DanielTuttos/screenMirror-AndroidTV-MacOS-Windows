import AppKit
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Captura una pantalla con ScreenCaptureKit y entrega cada frame al codificador.
///
/// La misma clase sirve para **espejo** (pantalla principal) y para **extender** (cualquier
/// otra display, virtual o física): solo cambia el `displayID` que se le pase (ADR-006).
final class ScreenCaptureHandler: NSObject {
    private var stream: SCStream?
    // Cola corta y de alta prioridad: si se acumulan frames, preferimos descartarlos
    // antes que acumular latencia (regla: latencia > features).
    private let sampleQueue = DispatchQueue(label: "tv.screenmirror.sender.capture", qos: .userInteractive)

    var onFrame: ((CMSampleBuffer) -> Void)?
    var onAudio: ((CMSampleBuffer) -> Void)?
    var onError: ((Error) -> Void)?

    /// macOS exige el permiso de Grabación de pantalla. Devuelve false si la persona lo rechazó.
    static func requestPermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        return CGRequestScreenCaptureAccess()
    }

    /// Lista las displays del Mac. El dominio recibe `DisplayDescriptor`, no tipos de Apple.
    /// MainActor porque lee `NSScreen`, que es de AppKit y solo debe tocarse en el hilo principal.
    @MainActor
    static func availableDisplays() async throws -> [DisplayDescriptor] {
        let content = try await shareableContent()
        return content.displays.map { display in
            DisplayDescriptor(
                id: String(display.displayID),
                name: name(of: display.displayID),
                width: CGDisplayPixelsWide(display.displayID),
                height: CGDisplayPixelsHigh(display.displayID),
                isMain: display.displayID == CGMainDisplayID(),
            )
        }
    }

    func start(displayID: CGDirectDisplayID, width: Int, height: Int, fps: Int, capturesAudio: Bool = true) async throws {
        let content = try await Self.shareableContent()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw SenderError.displayNotFound
        }

        let configuration = SCStreamConfiguration()
        // SCK escala el contenido de la pantalla al tamaño pedido: así el stream sale
        // con la resolución que ya hemos ajustado al techo de la TV.
        configuration.width = width
        configuration.height = height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: Int32(fps))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        // Cola corta: los frames viejos no sirven, solo estorban la latencia.
        configuration.queueDepth = 3
        // Audio PCM del sistema (espejo de lo que suena en el Mac) para el endpoint /audio.
        configuration.capturesAudio = capturesAudio
        if capturesAudio {
            configuration.excludesCurrentProcessAudio = false
        }

        let stream = SCStream(
            filter: SCContentFilter(display: display, excludingWindows: []),
            configuration: configuration,
            delegate: self,
        )
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        if capturesAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        }
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async throws {
        guard let stream else { return }
        self.stream = nil
        try await stream.stopCapture()
    }

    private static func shareableContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch let error as SCStreamError where error.code == .userDeclined {
            throw SenderError.screenRecordingDenied
        }
    }

    private static func name(of displayID: CGDirectDisplayID) -> String {
        // La clave del deviceDescription que lleva el CGDirectDisplayID es "NSScreenNumber"
        // (verificado en runtime: no hay constante AppKit pública para ella).
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        let screen = NSScreen.screens.first { screen in
            (screen.deviceDescription[screenNumberKey] as? NSNumber)?.uint32Value == displayID
        }
        return screen?.localizedName ?? "Pantalla \(displayID)"
    }
}

extension ScreenCaptureHandler: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            onFrame?(sampleBuffer)
        case .audio:
            onAudio?(sampleBuffer)
        default:
            break
        }
    }
}

extension ScreenCaptureHandler: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError?(error)
    }
}
