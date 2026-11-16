import CoreGraphics
import Foundation

/// Modo CLI: permite probar el pipeline completo (emparejar → capturar → codificar → emitir)
/// sin tocar la GUI. Es el "algo ejecutable" de la fase 2 mientras madura el menú de barra.
///
/// Uso:
///   swift run ScreenMirrorSender --cli --host 192.168.10.63 --pin 123456 [--display main|0] [--seconds 30]
@MainActor
enum CLIStreamer {
    static func run() async -> Int32 {
        let arguments = Arguments(CommandLine.arguments)

        if arguments.discover {
            return await discover()
        }

        guard let host = arguments.host else {
            printUsage()
            return 2
        }

        let receiver = ReceiverClient()
        do {
            let token: String
            if let explicitToken = arguments.token {
                token = explicitToken
            } else if let pin = arguments.pin {
                print("==> Emparejando con \(host)…")
                token = try await receiver.pair(host: host, pin: pin)
            } else {
                print("Falta el PIN (--pin) o el token (--token).")
                printUsage()
                return 2
            }

            let status = try await receiver.fetchStatus(host: host)
            print("==> \(status.name): máximo \(status.maxW)x\(status.maxH)\(status.busy ? " · ocupada" : "")")

            let displays = try await ScreenCaptureHandler.availableDisplays()
            let displayID = try await selectDisplay(from: displays, selector: arguments.display)

            let session = StreamSession()
            session.onStateChange = { state in
                switch state {
                case .streaming(let config):
                    print("==> Emitiendo \(config.width)x\(config.height) @ \(config.fps) fps · \(config.bitrateKbps) kbps")
                    print("    (Ctrl+C para cortar)")
                case .stopped(let reason):
                    print("\n==> \(reason)")
                case .idle:
                    break
                }
            }
            session.onStats = { stats in
                print("\r    \(stats.fps) fps · \(stats.bitrateKbps) kbps    ", terminator: "")
                fflush(stdout)
            }

            try await session.start(
                host: host,
                token: token,
                displayID: displayID,
                fps: arguments.fps,
                cap: arguments.cap,
                withAudio: arguments.audio,
            )
            await wait(seconds: arguments.seconds)
            await session.stop()
            print("\n==> Detenido.")
            return 0
        } catch {
            print("\nError: \(error.localizedDescription)")
            return 1
        }
    }

    private static func discover() async -> Int32 {
        let browser = ReceiverBrowser()
        print("Buscando TVs en la red (mDNS, ~5 s)…")

        var found: [DiscoveredReceiver] = []
        browser.onUpdate = { found = $0 }
        browser.start()
        do {
            try await Task.sleep(nanoseconds: 5_000_000_000)
        } catch {
            browser.stop()
            return 1
        }
        browser.stop()

        if found.isEmpty {
            print("No se encontró ninguna TV. ¿Están en la misma red? (o usa --host <ip>)")
            return 1
        }
        print("TVs encontradas:")
        for receiver in found {
            let pairing = receiver.needsPairing ? "· emparejamiento pendiente" : ""
            print("  \(receiver.name)  \(receiver.host):\(receiver.port)  \(pairing)")
        }
        return 0
    }

    private static func selectDisplay(from displays: [DisplayDescriptor], selector: String) async throws -> CGDirectDisplayID {
        print("Pantallas disponibles:")
        for (index, display) in displays.enumerated() {
            let role = display.isMain ? "espejo" : "extender"
            print("  [\(index)] \(display.name) \(display.width)x\(display.height) · \(role)")
        }

        if selector == "main" { return CGMainDisplayID() }
        if let index = Int(selector), displays.indices.contains(index) {
            return CGDirectDisplayID(displays[index].id) ?? CGMainDisplayID()
        }
        if let id = UInt32(selector), displays.contains(where: { $0.id == selector }) {
            return id
        }
        throw SenderError.displayNotFound
    }

    private static func wait(seconds: Int) async {
        if seconds > 0 {
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            } catch {
                return // cancelado por quien nos llamó
            }
            return
        }
        // Sin límite de tiempo: Ctrl+C corta el proceso y el receptor ve el cierre de conexión.
        while true {
            do {
                try await Task.sleep(nanoseconds: 600_000_000_000)
            } catch {
                return
            }
        }
    }

    private static func printUsage() {
        print("""
        Uso: swift run ScreenMirrorSender --cli [--discover | --host <ip-tv>] [opciones]

          --discover         lista las TVs encontradas por mDNS y sale
          --host <ip>        IP de la TV (obligatorio salvo con --discover)
          --pin <6 dígitos>   emparejar con el PIN que muestra la TV
          --token <hex>      usar un token ya emitido (salta el PIN)
          --display <sel>    main (por defecto) | índice de la lista | id de display
          --max <WxH>        techo de resolución (p. ej. 1920x1080 para el A/B de nitidez)
          --fps <n>          frames por segundo (por defecto 30)
          --no-audio         no enviar el sonido al TV (por defecto se envía)
          --seconds <n>      duración en segundos (por defecto: hasta Ctrl+C)
        """)
    }

    private struct Arguments {
        let host: String?
        let pin: String?
        let token: String?
        let display: String
        let fps: Int
        let seconds: Int
        /// Techo de resolución forzado (para A/B): nil = usar el del receptor.
        let cap: (width: Int, height: Int)?
        /// Modo descubrimiento: listar las TVs de la red y salir.
        let discover: Bool
        /// Emitir también el sonido (`POST /audio`); desactivable con `--no-audio`.
        let audio: Bool

        init(_ args: [String]) {
            func value(_ flag: String) -> String? {
                guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
                return args[index + 1]
            }
            host = value("--host")
            pin = value("--pin")
            token = value("--token")
            display = value("--display") ?? "main"
            fps = Int(value("--fps") ?? "") ?? Protocol.defaultFps
            seconds = Int(value("--seconds") ?? "") ?? 0
            cap = Self.parseCap(value("--max"))
            discover = args.contains("--discover")
            audio = !args.contains("--no-audio")
        }

        private static func parseCap(_ raw: String?) -> (width: Int, height: Int)? {
            guard let raw else { return nil }
            let parts = raw.lowercased().split(separator: "x")
            guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]) else { return nil }
            return (width, height)
        }
    }
}
