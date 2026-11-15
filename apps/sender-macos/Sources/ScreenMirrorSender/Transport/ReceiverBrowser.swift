import Foundation
import Network

/// Descubre las TVs de ScreenMirror en la red local (mDNS `_screenmirror._tcp`).
///
/// NWBrowser da el nombre del servicio pero no la IP: para resolverla abrimos una
/// conexión efímera a cada servicio y leemos `remoteEndpoint` (la resolución la hace
/// el sistema, sin bloquear el hilo principal). La conexión se cancela al saber la IP.
final class ReceiverBrowser {
    private let browser: NWBrowser
    private let queue = DispatchQueue(label: "tv.screenmirror.sender.browser")

    /// Estado observable para la UI: la lista completa se re-emite en cada cambio.
    private(set) var receivers: [DiscoveredReceiver] = [] {
        didSet { onUpdate?(receivers) }
    }

    var onUpdate: (([DiscoveredReceiver]) -> Void)?

    private var resolvers: [NWConnection] = []

    init() {
        browser = NWBrowser(
            for: .bonjour(type: Protocol.serviceType, domain: nil),
            using: .tcp,
        )
    }

    func start() {
        browser.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .failed(let error) = state {
                // Sin mDNS el usuario siempre puede teclear la IP: se avisa, no se traga.
                NSLog("ReceiverBrowser: mDNS falló — \(error)")
                self.receivers = []
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            self.dropMissing(known: results)
            results.forEach { self.resolve($0) }
        }
        browser.start(queue: queue)
    }

    func stop() {
        browser.cancel()
        resolvers.forEach { $0.cancel() }
        resolvers = []
    }

    // MARK: - Privado

    /// Quita de la lista las TVs que desaparecieron de la red (apagado, fuera de cobertura).
    private func dropMissing(known results: Set<NWBrowser.Result>) {
        let alive = results.compactMap { Self.serviceName(of: $0) }
        receivers.removeAll { !alive.contains($0.name) }
    }

    private static func serviceName(of result: NWBrowser.Result) -> String? {
        guard case let .service(name, _, _, _) = result.endpoint else { return nil }
        return name
    }

    /// Resuelve el endpoint del servicio a IP + puerto y lo añade a la lista.
    private func resolve(_ result: NWBrowser.Result) {
        guard case let .service(name, _, _, _) = result.endpoint else { return }

        let connection = NWConnection(to: result.endpoint, using: .tcp)
        resolvers.append(connection)

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                if case let .hostPort(host, port) = connection.currentPath?.remoteEndpoint {
                    self.upsert(
                        DiscoveredReceiver(
                            name: name,
                            host: Self.ipString(host),
                            port: port.rawValue,
                            txt: Self.txtRecords(from: result),
                        )
                    )
                }
                connection.cancel()
            case .failed:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private static func txtRecords(from result: NWBrowser.Result) -> [String: String] {
        guard case let .bonjour(txt) = result.metadata else { return [:] }
        var dictionary: [String: String] = [:]
        for (key, value) in txt {
            dictionary[key] = String(describing: value)
        }
        return dictionary
    }

    private static func ipString(_ host: NWEndpoint.Host) -> String {
        // NWEndpoint.Host no expone rawValue en Swift: su descripción ya es la IP textual.
        String(describing: host)
    }

    private func upsert(_ receiver: DiscoveredReceiver) {
        // Varias interfaces (Wi-Fi + Ethernet) pueden resolver el mismo servicio:
        // nos quedamos con la primera IP que responda por nombre.
        guard !receivers.contains(where: { $0.name == receiver.name }) else { return }
        receivers.append(receiver)
        receivers.sort { $0.name < $1.name }
    }
}
