import CoreGraphics
import Foundation
import CGVirtualDisplayShim

/// Pantalla virtual creada por el propio emisor (modo extendido, ADR-006).
///
/// Usa las clases `CGVirtualDisplay*` de CoreGraphics vía `CGVirtualDisplayShim`:
/// es el mismo mecanismo de DeskPad/BetterDisplay y sustituye a BetterDisplay
/// como dependencia externa. La display existe mientras este objeto esté vivo
/// (al liberarse, macOS la desconecta como si se hubiera desenchufado).
final class VirtualDisplay {

    private let display: CGVirtualDisplay

    let displayID: CGDirectDisplayID

    /// Crea una pantalla virtual con los modos dados y la deja conectada.
    init(name: String, modes: [(width: Int, height: Int)]) throws {
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(DispatchQueue.main)
        descriptor.name = name
        descriptor.maxPixelsWide = UInt32(modes.map(\.width).max() ?? 2560)
        descriptor.maxPixelsHigh = UInt32(modes.map(\.height).max() ?? 1440)
        // Tamaño físico inventado (≈27"): solo influye en la densidad de píxeles
        // que reporta macOS, no en el stream.
        descriptor.sizeInMillimeters = CGSize(width: 600, height: 340)
        descriptor.productID = 0x534D // "SM"
        descriptor.vendorID = 0x5343 // "SC"
        descriptor.serialNum = 0x0001

        // El init no es failable en ObjC: si algo falla, macOS lo reporta al
        // aplicar los modos (abajo).
        let display = CGVirtualDisplay(descriptor: descriptor)

        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 0
        settings.modes = modes.map {
            CGVirtualDisplayMode(width: UInt($0.width), height: UInt($0.height), refreshRate: 60)
        }
        guard display.apply(settings) else {
            throw SenderError.connectionFailed("la pantalla virtual rechazó sus modos")
        }

        self.display = display
        displayID = display.displayID
    }

    deinit {
        // Sin retención explícita, macOS retira la display al morir el objeto.
    }
}
