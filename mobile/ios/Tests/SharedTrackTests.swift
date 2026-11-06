import XCTest
@testable import Hrafnsyn

@MainActor
final class SharedTrackTests: XCTestCase {
    func testFoundationPreservesCustomSchemeWrapperForLoopbackWebLink() throws {
        let url = try XCTUnwrap(URL(string: "hrafnsyn://open?url=http%3A%2F%2Flocalhost%3A4088%2F%3Frange%3D6%26identity%3D378113455%26vehicle%3Dvessel"))
        let parsed = try parseSharedTrackLink(url: url.absoluteString)
        XCTAssertEqual(parsed.webOrigin, "http://localhost:4088")
        XCTAssertEqual(parsed.identity, "378113455")
    }

    private func defaults(server: String = "https://tracking.example") -> UserDefaults {
        let name = "HrafnsynSharingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(server, forKey: "server")
        return defaults
    }

    private func link(_ identity: String, origin: String = "https://tracking.example", hours: Int32 = 6) throws -> URL {
        URL(string: try makeTrackShareUrl(webOrigin: origin, vehicle: "vessel", identity: identity, historyHours: hours))!
    }

    func testCurrentServerLinkOpensInactiveTrackAndSharesCanonicalWebURL() async throws {
        let connection = StubTrackingConnection(origin: "https://rpc.example:50051", website: "https://tracking.example")
        let model = AppModel(defaults: defaults(server: connection.origin), store: MemorySessions(), makeClient: { _, _ in connection })
        await model.connect()
        await model.openSharedURL(try link("JOY & friends", hours: 24))
        XCTAssertEqual(model.phase, .tracking)
        XCTAssertEqual(model.selectedTrack?.identity, "JOY & friends")
        XCTAssertTrue(model.tracks.isEmpty)
        XCTAssertEqual(model.mapTracks.count, 1, "Inactive shared tracks remain visible on the map")
        XCTAssertEqual(model.selectionHistoryHours, 24)
        XCTAssertEqual(try parseSharedTrackLink(url: XCTUnwrap(model.selectedShareURL).absoluteString).webOrigin,
                       "https://tracking.example")
        XCTAssertFalse(model.selectedShareURL!.absoluteString.contains("rpc.example"))
        XCTAssertNil(model.sharedServerPrompt)
    }

    func testUnknownServerNeedsConfirmationAndUsesOnlyItsOwnSavedSession() async throws {
        let sessions = MemorySessions()
        sessions.values["https://tracking.example"] = testSession("old-server")
        sessions.values["https://other.example"] = testSession("other-server")
        var constructed: [(String, String?)] = []
        let model = AppModel(defaults: defaults(), store: sessions, makeClient: { origin, session in
            constructed.append((origin, session?.username))
            return StubTrackingConnection(origin: origin, website: origin)
        })
        await model.openSharedURL(try link("123", origin: "https://other.example"))
        XCTAssertNotNil(model.sharedServerPrompt)
        XCTAssertTrue(constructed.isEmpty)
        XCTAssertEqual(model.server, "https://tracking.example")
        await model.confirmSharedServer("https://other.example")
        XCTAssertEqual(constructed.count, 1)
        XCTAssertEqual(constructed.first?.0, "https://other.example")
        XCTAssertEqual(constructed.first?.1, "other-server")
        XCTAssertEqual(model.selectedTrack?.identity, "123")
    }

    func testSavedWebsiteMappingPromptsBeforeSwitchingToItsDistinctGRPCOrigin() async throws {
        let preferences = defaults()
        preferences.set(["https://other.example": "https://rpc.other.example:50051"], forKey: "webServers")
        let connection = StubTrackingConnection(origin: "https://rpc.other.example:50051", website: "https://other.example")
        let model = AppModel(defaults: preferences, store: MemorySessions(), makeClient: { origin, _ in
            XCTAssertEqual(origin, connection.origin)
            return connection
        })
        await model.openSharedURL(try link("saved", origin: "https://other.example"))
        XCTAssertEqual(model.sharedServerPrompt?.suggestedServer, connection.origin)
        XCTAssertEqual(model.sharedServerPrompt?.knownServer, true)
        XCTAssertNil(model.selectedID)
        await model.confirmSharedServer(connection.origin)
        XCTAssertEqual(model.selectedTrack?.identity, "saved")
    }

    func testPendingTargetSurvivesLogin() async throws {
        let connection = StubTrackingConnection(origin: "https://tracking.example", requiresLogin: true)
        let model = AppModel(defaults: defaults(), store: MemorySessions(), makeClient: { _, _ in connection })
        await model.openSharedURL(try link("after-login"))
        XCTAssertEqual(model.phase, .login)
        XCTAssertNil(model.selectedID)
        model.username = "reader"
        await model.login(password: "test-only-password")
        XCTAssertEqual(model.phase, .tracking)
        XCTAssertEqual(model.selectedTrack?.identity, "after-login")
        XCTAssertFalse(model.selectedShareURL!.absoluteString.contains("test-only"))
    }

    func testLastLinkWinsWhenEarlierLookupCompletesLater() async throws {
        let started = expectation(description: "First lookup started")
        let gate = Suspension()
        let connection = StubTrackingConnection(origin: "https://tracking.example")
        connection.lookup = { identity in
            if identity == "first" { started.fulfill(); await gate.wait() }
            return testDetails(identity)
        }
        let model = AppModel(defaults: defaults(), store: MemorySessions(), makeClient: { _, _ in connection })
        await model.connect()
        let first = Task { await model.openSharedURL(try! link("first")) }
        await fulfillment(of: [started], timeout: 3)
        await model.openSharedURL(try link("second"))
        await gate.release()
        await first.value
        XCTAssertEqual(model.selectedTrack?.identity, "second")
        XCTAssertFalse(model.loadingDetails)
    }

    func testIdentityLookupRequiringNewLoginRetainsTarget() async throws {
        let connection = StubTrackingConnection(origin: "https://tracking.example")
        connection.lookup = { identity in
            guard connection.session != nil else { throw ClientError.SignInRequired }
            return testDetails(identity)
        }
        let model = AppModel(defaults: defaults(), store: MemorySessions(), makeClient: { _, _ in connection })
        await model.connect()
        await model.openSharedURL(try link("expired-session"))
        XCTAssertEqual(model.phase, .login)
        XCTAssertNil(model.selectedID)
        model.username = "reader"
        await model.login(password: "test-only-password")
        XCTAssertEqual(model.selectedTrack?.identity, "expired-session")
    }

    func testOldServerWithoutWebsiteMetadataStillConnectsWithoutInventingShareAddress() async throws {
        let connection = StubTrackingConnection(origin: "https://rpc.example:50051", website: "")
        let model = AppModel(defaults: defaults(server: connection.origin), store: MemorySessions(), makeClient: { _, _ in connection })
        await model.connect()
        await model.select("local-track")
        XCTAssertEqual(model.phase, .tracking)
        XCTAssertNotNil(model.selectedTrack)
        XCTAssertNil(model.selectedShareURL)
    }

    func testColdStartLinkArrivingDuringConnectionIsNotLost() async throws {
        let started = expectation(description: "Connection started")
        let gate = Suspension()
        let connection = StubTrackingConnection(origin: "https://tracking.example")
        connection.beforeConnect = { started.fulfill(); await gate.wait() }
        let model = AppModel(defaults: defaults(), store: MemorySessions(), makeClient: { _, _ in connection })
        let startup = Task { await model.resume() }
        await fulfillment(of: [started], timeout: 3)
        await model.openSharedURL(try link("cold-start"))
        await gate.release()
        await startup.value
        XCTAssertEqual(model.selectedTrack?.identity, "cold-start")
        XCTAssertFalse(model.busy)
    }

    func testColdStartSeparateRPCMappingOpensWithoutSwitchPrompt() async throws {
        let preferences = defaults(server: "https://rpc.example:50051")
        preferences.set(["https://tracking.example": "https://rpc.example:50051"], forKey: "webServers")
        let connection = StubTrackingConnection(origin: "https://rpc.example:50051", website: "https://tracking.example")
        let model = AppModel(defaults: preferences, store: MemorySessions(), makeClient: { _, _ in connection })
        await model.openSharedURL(try link("cold-separate"))
        XCTAssertNil(model.sharedServerPrompt)
        XCTAssertEqual(model.selectedTrack?.identity, "cold-separate")
    }

    func testUnverifiedSeparateRPCDoesNotQueryTrackAndRetryFetchesMetadata() async throws {
        let connection = StubTrackingConnection(origin: "https://rpc.example:50051", website: "https://tracking.example")
        connection.metadataFailure = ClientError.Connection(reason: "Metadata unavailable")
        var queried = false
        connection.lookup = { identity in queried = true; return testDetails(identity) }
        let model = AppModel(defaults: defaults(server: ""), store: MemorySessions(), makeClient: { _, _ in connection })
        await model.openSharedURL(try link("verify-first"))
        await model.confirmSharedServer(connection.origin)
        XCTAssertFalse(queried)
        XCTAssertNotNil(model.sharedLinkError)
        connection.metadataFailure = nil
        await model.retrySharedLink()
        XCTAssertTrue(queried)
        XCTAssertEqual(model.selectedTrack?.identity, "verify-first")
    }

    func testOpeningSameTrackAgainPublishesNewNavigationIntentAndRange() async throws {
        let connection = StubTrackingConnection(origin: "https://tracking.example")
        let model = AppModel(defaults: defaults(), store: MemorySessions(), makeClient: { _, _ in connection })
        await model.openSharedURL(try link("same"))
        let previous = model.sharedSelectionRevision
        await model.openSharedURL(try link("same", hours: 24))
        XCTAssertNotEqual(model.sharedSelectionRevision, previous)
        XCTAssertEqual(model.selectedTrack?.identity, "same")
        XCTAssertEqual(model.selectionHistoryHours, 24)
    }

    func testCancellingAConfirmationKeepsCurrentConnectionAndSelection() async throws {
        let connection = StubTrackingConnection(origin: "https://tracking.example")
        let model = AppModel(defaults: defaults(), store: MemorySessions(), makeClient: { _, _ in connection })
        await model.connect()
        await model.openSharedURL(try link("original"))
        await model.openSharedURL(try link("elsewhere", origin: "https://other.example"))
        model.cancelSharedLink()
        XCTAssertEqual(model.server, connection.origin)
        XCTAssertEqual(model.selectedTrack?.identity, "original")
        XCTAssertEqual(model.phase, .tracking)
    }

    func testInvalidLinkDoesNotConnectOrRetainAnOldPendingDestination() async throws {
        var connections = 0
        let model = AppModel(defaults: defaults(), store: MemorySessions(), makeClient: { origin, _ in
            connections += 1
            return StubTrackingConnection(origin: origin)
        })
        await model.openSharedURL(try link("old", origin: "https://other.example"))
        await model.openSharedURL(URL(string: "https://user:password@other.example/?vehicle=vessel&identity=123")!)
        XCTAssertEqual(connections, 0)
        XCTAssertNil(model.sharedServerPrompt)
        XCTAssertNotNil(model.sharedLinkError)
        XCTAssertFalse(model.canRetrySharedLink)
    }

    func testMismatchedWebsiteDoesNotResolveIdentityOnWrongServer() async throws {
        let connection = StubTrackingConnection(origin: "https://wrong.example", website: "https://wrong.example")
        connection.lookup = { _ in XCTFail("Must not query a different instance"); return testDetails("wrong") }
        let model = AppModel(defaults: defaults(), store: MemorySessions(), makeClient: { _, _ in connection })
        await model.openSharedURL(try link("123", origin: "https://other.example"))
        await model.confirmSharedServer(connection.origin)
        XCTAssertNil(model.selectedID)
        XCTAssertNotNil(model.sharedLinkError)
        await model.retrySharedLink()
        XCTAssertEqual(model.sharedServerPrompt?.webOrigin, "https://other.example")
    }
}

private final class MemorySessions: SessionStorage {
    var values: [String: SavedSession] = [:]
    func read(server: String) throws -> SavedSession? { values[server] }
    func write(_ session: SavedSession?, server: String) throws { values[server] = session }
}

private final class StubTrackingConnection: TrackingClientProtocol, @unchecked Sendable {
    let origin: String
    let website: String
    var requiresLogin: Bool
    var session: SavedSession?
    var beforeConnect: (() async -> Void)?
    var lookup: ((String) async throws -> TrackDetails)?
    var metadataFailure: Error?
    init(origin: String, website: String? = nil, requiresLogin: Bool = false) {
        self.origin = origin; self.website = website ?? origin; self.requiresLogin = requiresLogin
    }
    func server() -> String { origin }
    func connect() async throws -> ConnectionStatus {
        await beforeConnect?()
        return ConnectionStatus(authRequired: requiresLogin, authenticated: session != nil)
    }
    func login(username: String, password: String) async throws -> SavedSession {
        let value = testSession(username); session = value; return value
    }
    func savedSession() async -> SavedSession? { session }
    func signOut() async throws { session = nil }
    func activeTracks() async throws -> [Track] { [] }
    func trackDetails(id: String) async throws -> TrackDetails {
        var result = testDetails(id)
        result.track?.id = id
        return result
    }
    func serverWebUrl() async throws -> String {
        if let metadataFailure { throw metadataFailure }
        return website
    }
    func getTrackByIdentity(vehicle: String, identity: String, historyHours: Int32) async throws -> TrackDetails {
        if let lookup { return try await lookup(identity) }
        return testDetails(identity)
    }
}

private actor Suspension {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

private func testSession(_ username: String) -> SavedSession {
    SavedSession(accessToken: "test-access", refreshToken: "test-refresh", accessExpiresAt: 0,
                 refreshExpiresAt: 0, sessionId: "test-session", username: username)
}

private func testDetails(_ identity: String) -> TrackDetails {
    TrackDetails(track: Track(id: "id-" + identity, name: identity, identity: identity, callsign: "", registration: "",
                              country: "", destination: "", sourceName: "Test", isAircraft: false,
                              latitude: 36.4, longitude: -5.1, speedKnots: 0, headingDegrees: 0,
                              altitudeFeet: 0, observedAt: 1_700_000_000), route: [], distanceMeters: 0)
}
