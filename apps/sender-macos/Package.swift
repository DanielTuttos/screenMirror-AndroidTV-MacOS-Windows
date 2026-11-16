// swift-tools-version: 5.9
import PackageDescription

// Emisor de ScreenMirror para macOS (fase 2).
// Sin Xcode: se construye con `swift build` y se empaqueta en .app en la fase 4.
let package = Package(
    name: "ScreenMirrorSender",
    platforms: [
        .macOS(.v13),
    ],
    targets: [
        // Declaraciones de la API privada de displays virtuales (ver cabecera).
        .target(
            name: "CGVirtualDisplayShim",
            path: "Sources/CGVirtualDisplayShim"
        ),
        .executableTarget(
            name: "ScreenMirrorSender",
            dependencies: ["CGVirtualDisplayShim"],
            path: "Sources/ScreenMirrorSender"
        ),
        .testTarget(
            name: "ScreenMirrorSenderTests",
            dependencies: ["ScreenMirrorSender"],
            path: "Tests/ScreenMirrorSenderTests"
        ),
    ]
)
