import XCTest

@testable import ScreenMirrorSender

final class DiscoveredReceiverTests: XCTestCase {
    func testBuildsFromProtocolTxtRecords() {
        let txt = ["v": "0", "id": "b6c8a0f7", "name": "AI PONT", "pin": "true"]

        let receiver = DiscoveredReceiver(name: "AI PONT", host: "192.168.10.63", port: 9471, txt: txt)

        XCTAssertEqual(receiver.deviceId, "b6c8a0f7")
        XCTAssertTrue(receiver.needsPairing)
        XCTAssertEqual(receiver.host, "192.168.10.63")
        XCTAssertEqual(receiver.port, 9471)
    }

    func testToleratesMissingTxtRecords() {
        // Un receptor viejo o un anuncio sin TXT no debe romper la lista.
        let receiver = DiscoveredReceiver(name: "TV", host: "10.0.0.2", port: 9471, txt: [:])

        XCTAssertNil(receiver.deviceId)
        XCTAssertFalse(receiver.needsPairing)
        // Sin `id` estable, la identidad cae al nombre + IP para que la UI no duplique filas.
        XCTAssertEqual(receiver.id, "TV@10.0.0.2")
    }

    func testIdPrefersThePermanentDeviceId() {
        let receiver = DiscoveredReceiver(
            name: "AI PONT",
            host: "192.168.10.63",
            port: 9471,
            txt: ["id": "uuid-1"],
        )

        XCTAssertEqual(receiver.id, "uuid-1")
    }
}
