import XCTest
@testable import ScreenMirrorSender

final class KeychainTokenStoreTests: XCTestCase {
    private let host = "192.168.10.99"
    // Servicio propio de los tests: nunca toca los tokens reales de la app.
    private let store = KeychainTokenStore(service: "tv.screenmirror.sender.tests")

    override func setUpWithError() throws {
        try store.removeToken(forHost: host)
    }

    override func tearDownWithError() throws {
        try store.removeToken(forHost: host)
    }

    func testReturnsNilWhenNothingIsSaved() {
        XCTAssertNil(store.token(forHost: host))
    }

    func testSavesAndReadsBackTheToken() throws {
        try store.save(token: "abc123", forHost: host)
        XCTAssertEqual(store.token(forHost: host), "abc123")
    }

    func testSavingAgainReplacesTheToken() throws {
        try store.save(token: "old", forHost: host)
        try store.save(token: "new", forHost: host)
        XCTAssertEqual(store.token(forHost: host), "new")
    }

    func testRemoveDeletesAndToleratesMissing() throws {
        try store.save(token: "abc123", forHost: host)
        try store.removeToken(forHost: host)
        XCTAssertNil(store.token(forHost: host))
        XCTAssertNoThrow(try store.removeToken(forHost: host))
    }
}
