import Foundation

/// Una TV encontrada por mDNS, descrita sin Network.framework:
/// el `domain` no conoce NWBrowser (flujo ui → caso de uso → data → core).
struct DiscoveredReceiver: Identifiable, Equatable, Hashable {
    /// Nombre del servicio (= nombre de la TV, igual que `name` en `/status`).
    let name: String
    /// IP resuelta del host de la TV.
    let host: String
    let port: UInt16
    /// UUID permanente del receptor (TXT `id`): identidad estable entre reinicios.
    let deviceId: String?
    /// `true` si la TV está esperando emparejamiento (TXT `pin`).
    let needsPairing: Bool

    var id: String { deviceId ?? "\(name)@\(host)" }

    /// Crea el receptor a partir de los registros TXT del anuncio (spec: docs/protocol.md).
    /// Puro y testeable: el emisor no necesita entender mDNS, solo estos campos.
    init(name: String, host: String, port: UInt16, txt: [String: String]) {
        self.name = name
        self.host = host
        self.port = port
        self.deviceId = txt["id"]
        self.needsPairing = txt["pin"] == "true"
    }
}
