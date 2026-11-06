import XCTest
@testable import Hrafnsyn

final class SessionStoreTests: XCTestCase {
    func testSecureSessionRoundTripAndOriginIsolation() throws {
        let store = SessionStore()
        let first = "https://keychain-test-\(UUID().uuidString.lowercased()).invalid"
        let second = first + ":50051"
        defer { try? store.write(nil, server: first); try? store.write(nil, server: second) }
        let session = SavedSession(accessToken: "test-access", refreshToken: "test-refresh",
                                   accessExpiresAt: 900, refreshExpiresAt: 3600,
                                   sessionId: "test-session", username: "test-user")
        try store.write(session, server: first)
        XCTAssertEqual(try store.read(server: first)?.refreshToken, "test-refresh")
        XCTAssertNil(try store.read(server: second))
        let rotated = SavedSession(accessToken: "rotated-access", refreshToken: "rotated-refresh",
                                   accessExpiresAt: 1800, refreshExpiresAt: 7200,
                                   sessionId: "test-session", username: "test-user")
        try store.write(rotated, server: first)
        XCTAssertEqual(try store.read(server: first)?.refreshToken, "rotated-refresh")
        try store.write(nil, server: first)
        XCTAssertNil(try store.read(server: first))
    }
}
