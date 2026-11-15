import Foundation

// Punto de entrada. Dos modos:
//  - `--cli`: pipeline completo por línea de comandos (para probar sin GUI).
//  - sin `--cli`: app de menú de barra.
// dispatchMain() mantiene vivo el proceso mientras el Task corre en el MainActor.
if CommandLine.arguments.contains("--cli") {
    Task { @MainActor in
        exit(await CLIStreamer.run())
    }
    dispatchMain()
} else {
    SenderApp.main()
}
