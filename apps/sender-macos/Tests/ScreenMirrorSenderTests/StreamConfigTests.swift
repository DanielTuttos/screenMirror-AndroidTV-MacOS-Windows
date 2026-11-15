import XCTest

@testable import ScreenMirrorSender

final class StreamConfigTests: XCTestCase {
    func testFittedKeepsResolutionWhenItAlreadyFits() {
        let config = StreamConfig(width: 1920, height: 1080)

        XCTAssertEqual(config.fitted(maxWidth: 2560, maxHeight: 1440), config)
    }

    func testFittedReducesKeepingAspectAndEvenDimensions() {
        let config = StreamConfig(width: 3456, height: 2234)

        let fitted = config.fitted(maxWidth: 2560, maxHeight: 1440)

        XCTAssertEqual(fitted.height, 1440)
        XCTAssertEqual(fitted.width, 2226)
        XCTAssertEqual(fitted.width % 2, 0)
        XCTAssertEqual(fitted.height % 2, 0)
        // La proporción no se deforma: la TV estiraría el stream si cambiara.
        XCTAssertEqual(Double(fitted.width) / Double(fitted.height), 3456.0 / 2234.0, accuracy: 0.01)
    }

    func testFittedNeverUpscales() {
        let config = StreamConfig(width: 1280, height: 720)

        XCTAssertEqual(config.fitted(maxWidth: 2560, maxHeight: 1440), config)
    }

    func testFittedNeverProducesOddDimensions() {
        let config = StreamConfig(width: 1919, height: 1079)

        let fitted = config.fitted(maxWidth: 1000, maxHeight: 1000)

        XCTAssertEqual(fitted.width % 2, 0)
        XCTAssertEqual(fitted.height % 2, 0)
        XCTAssertGreaterThanOrEqual(fitted.width, 2)
        XCTAssertGreaterThanOrEqual(fitted.height, 2)
    }

    func testBitrateScalesWithPixels() {
        // 8 Mbps @1080p es la referencia validada en fase 1.
        XCTAssertEqual(StreamConfig.bitrateKbps(forWidth: 1920, height: 1080), 8_000)
        XCTAssertEqual(StreamConfig.bitrateKbps(forWidth: 2560, height: 1440), 14_222)
    }

    func testBitrateHasFloorSoSmallStreamsStayDecodable() {
        XCTAssertGreaterThanOrEqual(StreamConfig.bitrateKbps(forWidth: 320, height: 180), 500)
    }

    func testQueryMatchesTheProtocolSpec() {
        let config = StreamConfig(width: 2560, height: 1440, fps: 30, keyint: 60, bitrateKbps: 14_222)

        XCTAssertEqual(
            config.query(token: "abc123"),
            "token=abc123&w=2560&h=1440&fps=30&keyint=60&br=14222",
        )
    }
}
