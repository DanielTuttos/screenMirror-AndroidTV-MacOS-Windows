import XCTest

@testable import ScreenMirrorSender

final class ReconnectPolicyTests: XCTestCase {

    func testBackoffCreceExponencialmenteHastaElTope() {
        XCTAssertEqual(ReconnectPolicy.delaySeconds(forAttempt: 1), 0.5)
        XCTAssertEqual(ReconnectPolicy.delaySeconds(forAttempt: 2), 1.0)
        XCTAssertEqual(ReconnectPolicy.delaySeconds(forAttempt: 3), 2.0)
        XCTAssertEqual(ReconnectPolicy.delaySeconds(forAttempt: 4), 4.0)
        XCTAssertEqual(ReconnectPolicy.delaySeconds(forAttempt: 5), 5.0, "llega al tope")
        XCTAssertEqual(ReconnectPolicy.delaySeconds(forAttempt: 20), 5.0, "nunca supera el tope")
    }

    func testIntentoInvalidoNoEspera() {
        XCTAssertEqual(ReconnectPolicy.delaySeconds(forAttempt: 0), 0)
        XCTAssertEqual(ReconnectPolicy.delaySeconds(forAttempt: -3), 0)
    }

    func testErroresFatalesNoSeReintentan() {
        XCTAssertTrue(ReconnectPolicy.isFatal(SenderError.screenRecordingDenied))
        XCTAssertTrue(ReconnectPolicy.isFatal(SenderError.unauthorized))
        XCTAssertTrue(ReconnectPolicy.isFatal(SenderError.displayNotFound))
        XCTAssertTrue(ReconnectPolicy.isFatal(SenderError.pairingRejected("pin")))
    }

    func testErroresDeRedSeReintentan() {
        XCTAssertFalse(ReconnectPolicy.isFatal(SenderError.connectionFailed("timeout")))
        XCTAssertFalse(ReconnectPolicy.isFatal(SenderError.receiverBusy))
        XCTAssertFalse(ReconnectPolicy.isFatal(SenderError.unexpectedStatus(500)))
        XCTAssertFalse(ReconnectPolicy.isFatal(SenderError.encoderFailed("vt")))
        // Un error que no es del dominio tampoco debe tumbar la sesión para siempre.
        XCTAssertFalse(ReconnectPolicy.isFatal(URLError(.timedOut)))
    }
}
