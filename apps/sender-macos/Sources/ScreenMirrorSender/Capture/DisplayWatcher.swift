import CoreGraphics
import Foundation

/// Observa cambios de configuración de una display (resolución, orientación, conexión).
///
/// Dos vías, porque el callback de CoreGraphics **no se propaga entre procesos**
/// (verificado: un cambio hecho por otro proceso nunca llega al registrado aquí):
///   1. `CGDisplayRegisterReconfigurationCallback` — reacción inmediata a los
///      cambios que hace nuestro propio proceso.
///   2. Polling de `CGDisplayBounds` cada 2 s — cubre cambios externos
///      (Ajustes del sistema, otra app). Barato: una comparación de CGRect.
final class DisplayWatcher {
    private let displayID: CGDirectDisplayID
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "tv.screenmirror.sender.displaywatch")
    private var pending: DispatchWorkItem?
    private var registered = false
    private var lastBounds: CGRect
    private var pollTimer: DispatchSourceTimer?

    init(displayID: CGDirectDisplayID, onChange: @escaping () -> Void) {
        self.displayID = displayID
        self.onChange = onChange
        lastBounds = CGDisplayBounds(displayID)
        registered = CGDisplayRegisterReconfigurationCallback(Self.callback, context) == .success
        if !registered { NSLog("DisplayWatcher: no se pudo registrar el callback de display") }
        startPolling()
    }

    deinit {
        if registered {
            CGDisplayRemoveReconfigurationCallback(Self.callback, context)
        }
        pollTimer?.cancel()
    }

    /// Contexto C para el callback: puntero opaco a este watcher (sin retener: lo desregistra su deinit).
    private var context: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }

    private static let callback: CGDisplayReconfigurationCallBack = { changedID, flags, userInfo in
        guard let userInfo else { return }
        let watcher = Unmanaged<DisplayWatcher>.fromOpaque(userInfo).takeUnretainedValue()
        watcher.handle(changedID: changedID, flags: flags)
    }

    private func handle(changedID: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags) {
        // Solo la display que estamos emitiendo: cambios de otras no nos afectan.
        guard changedID == displayID else { return }
        // .setModeFlag = cambió resolución/rotación; .desktopShapeChangedFlag = cambió el arranque de escritorios.
        guard flags.contains(.setModeFlag) || flags.contains(.desktopShapeChangedFlag) else { return }
        notify()
    }

    /// Vía polling: detecta cambios hechos por otros procesos (el callback no los trae).
    private func poll() {
        let bounds = CGDisplayBounds(displayID)
        guard bounds != lastBounds else { return }
        lastBounds = bounds
        notify()
    }

    /// Un cambio dispara varios avisos seguidos (callback + polls): se agrupan en una sola reacción.
    private func notify() {
        pending?.cancel()
        let work = DispatchWorkItem { [onChange] in onChange() }
        pending = work
        queue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + .seconds(2),
            repeating: .seconds(2),
        )
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        pollTimer = timer
    }
}
