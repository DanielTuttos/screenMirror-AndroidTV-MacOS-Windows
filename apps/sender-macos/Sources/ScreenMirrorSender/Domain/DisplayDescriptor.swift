import Foundation

/// Una pantalla del Mac descrita sin APIs de Apple: el `domain` no conoce ScreenCaptureKit.
///
/// `isMain` distingue los dos modos que pide el usuario:
/// la principal es **espejo**, cualquier otra es **extender** (ver ADR-006).
struct DisplayDescriptor: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let width: Int
    let height: Int
    let isMain: Bool

    var isExtension: Bool { !isMain }
}
