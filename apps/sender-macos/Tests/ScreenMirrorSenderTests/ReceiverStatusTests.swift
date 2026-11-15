import XCTest

@testable import ScreenMirrorSender

final class ReceiverStatusTests: XCTestCase {
    func testParsesTheStatusPayload() throws {
        let json = Data(#"{"app":"ScreenMirror Receiver","proto":0,"name":"TV Salon","id":"uuid","maxW":2560,"maxH":1440,"codec":"h264","busy":false}"#.utf8)

        let status = try ReceiverStatus.parse(json)

        XCTAssertEqual(status.name, "TV Salon")
        XCTAssertEqual(status.maxW, 2560)
        XCTAssertEqual(status.maxH, 1440)
        XCTAssertFalse(status.busy)
    }

    func testToleratesMissingOptionalFields() throws {
        let json = Data(#"{"maxW":1920,"maxH":1080}"#.utf8)

        let status = try ReceiverStatus.parse(json)

        XCTAssertEqual(status.name, "TV")
        // `busy` ausente = false: la app no debe tratarlo como "ocupada" por no venir.
        XCTAssertFalse(status.busy)
    }

    func testFailsLoudlyOnGarbage() {
        XCTAssertThrowsError(try ReceiverStatus.parse(Data("hola".utf8))) { error in
            XCTAssertEqual(error as? SenderError, .invalidStatus)
        }
    }

    func testFailsWhenResolutionIsMissing() {
        let json = Data(#"{"name":"TV"}"#.utf8)

        XCTAssertThrowsError(try ReceiverStatus.parse(json)) { error in
            XCTAssertEqual(error as? SenderError, .invalidStatus)
        }
    }

    func testPairingPinMustBeSixDigits() async {
        let client = ReceiverClient()

        do {
            _ = try await client.pair(host: "192.168.10.63", pin: "123")
            XCTFail("un PIN corto debe rechazarse antes de tocar la red")
        } catch let error as SenderError {
            guard case .pairingRejected = error else {
                return XCTFail("error inesperado: \(error)")
            }
        } catch {
            XCTFail("error inesperado: \(error)")
        }
    }
}
