import Foundation
import Observation

@MainActor @Observable
final class AppModel {
    enum Phase { case server, connecting, login, tracking }
    var phase: Phase = .server
    var server = UserDefaults.standard.string(forKey: "server") ?? ""
    var username = ""
    var errorMessage: String?
    var tracks: [Track] = []
    var selectedID: String?
    var details: TrackDetails?
    var loadingDetails = false
    var busy = false
    var updatedAt: Date?
    var reconnecting = false
    var query = ""
    var filter = VehicleFilter.all
    private var client: TrackingClient?
    private let store = SessionStore()
    private var generation = UUID()
    private var refreshingGeneration: UUID?
    private var selectionRequest = UUID()
    // A previous server may finish rotating credentials after it leaves the screen.
    // Only the latest client for each origin may persist that origin's session.
    private var sessionOwners: [String: UUID] = [:]

    enum VehicleFilter: String, CaseIterable, Identifiable {
        case all = "All", aircraft = "Aircraft", vessels = "Vessels"
        var id: String { rawValue }
    }

    var visibleTracks: [Track] {
        tracks.filter { track in
            (filter == .all || (filter == .aircraft) == track.isAircraft) &&
            (query.isEmpty || [track.name, track.identity, track.registration, track.callsign, track.destination]
                .contains { $0.localizedCaseInsensitiveContains(query) })
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var selectedTrack: Track? { tracks.first { $0.id == selectedID } }

    func connect() async {
        guard !busy else { return }
        busy = true; errorMessage = nil; phase = .connecting
        generation = UUID()
        let currentGeneration = generation
        var connection: TrackingClient?
        defer { if currentGeneration == generation { busy = false } }
        do {
            let normalized = try normalizeServer(server: server)
            server = normalized
            let session = try store.read(server: normalized)
            let candidate = try TrackingClient(server: normalized, session: session)
            connection = candidate; client = candidate
            sessionOwners[normalized] = currentGeneration
            let status = try await candidate.connect()
            let saved = try await persist(candidate, owner: currentGeneration)
            guard currentGeneration == generation else { return }
            server = normalized; username = saved?.username ?? ""
            UserDefaults.standard.set(normalized, forKey: "server")
            phase = status.authRequired && !status.authenticated ? .login : .tracking
            if phase == .tracking { await refresh() }
        } catch { await handle(error, connection: connection, owner: currentGeneration, fallback: .server) }
    }

    func login(password: String) async {
        guard let connection = client, !busy else { return }
        let currentGeneration = generation
        let origin = connection.server()
        busy = true; errorMessage = nil
        defer { if currentGeneration == generation { busy = false } }
        do {
            _ = try await connection.login(username: username, password: password)
            let session = try await persist(connection, owner: currentGeneration)
            guard currentGeneration == generation else { return }
            server = origin; username = session?.username ?? username
            phase = .tracking
            await refresh()
        } catch { await handle(error, connection: connection, owner: currentGeneration, fallback: .login) }
    }

    func refresh() async {
        guard let connection = client, phase == .tracking, refreshingGeneration != generation else { return }
        let currentGeneration = generation
        refreshingGeneration = currentGeneration
        defer { if refreshingGeneration == currentGeneration { refreshingGeneration = nil } }
        do {
            let incoming = try await connection.activeTracks()
            _ = try await persist(connection, owner: currentGeneration)
            guard currentGeneration == generation else { return }
            tracks = incoming
            updatedAt = Date(); reconnecting = false; errorMessage = nil
        } catch {
            await handle(error, connection: connection, owner: currentGeneration, fallback: .tracking)
            if currentGeneration == generation { reconnecting = true }
        }
    }

    func dismissSelection() {
        selectionRequest = UUID()
        selectedID = nil; details = nil; loadingDetails = false
    }

    func select(_ id: String?) async {
        selectionRequest = UUID()
        let request = selectionRequest
        selectedID = id; details = nil; loadingDetails = false
        guard let id, let connection = client else { return }
        let currentGeneration = generation
        loadingDetails = true
        defer { if request == selectionRequest { loadingDetails = false } }
        do {
            let result = try await connection.trackDetails(id: id)
            _ = try await persist(connection, owner: currentGeneration)
            guard currentGeneration == generation, request == selectionRequest else { return }
            details = result
        } catch {
            await handle(error, connection: connection, owner: currentGeneration, fallback: .tracking, selection: request)
        }
    }

    func changeServer() {
        generation = UUID(); client = nil; tracks = []; details = nil; selectedID = nil
        selectionRequest = UUID(); loadingDetails = false; busy = false
        updatedAt = nil; errorMessage = nil; phase = .server; reconnecting = false
        username = ""; query = ""; filter = .all
    }

    func signOut() async {
        guard let connection = client, !busy else { return }
        let origin = connection.server()
        // Stop in-flight responses from recreating credentials after local sign-out.
        sessionOwners.removeValue(forKey: origin)
        do {
            try store.write(nil, server: origin)
        } catch {
            sessionOwners[origin] = generation
            errorMessage = error.localizedDescription
            return
        }
        changeServer()
        let currentGeneration = generation
        busy = true
        defer { if currentGeneration == generation { busy = false } }
        do {
            try await connection.signOut()
        } catch {
            guard currentGeneration == generation else { return }
            errorMessage = "Signed out on this device. The server could not confirm revocation; revoke the session in account settings if needed."
        }
    }

    func resume() async {
        if phase == .server && !server.isEmpty { await connect() }
        else if phase == .tracking { await refresh() }
    }

    private func persist(_ connection: TrackingClient, owner: UUID) async throws -> SavedSession? {
        let session = await connection.savedSession()
        let origin = connection.server()
        guard sessionOwners[origin] == owner else { return nil }
        try store.write(session, server: origin)
        return session
    }

    private func handle(_ error: Error, connection: TrackingClient?, owner: UUID, fallback: Phase, selection: UUID? = nil) async {
        // Refresh rotation must be saved even when the subsequent tracking call fails.
        var reportedError = error
        if let connection {
            do { _ = try await persist(connection, owner: owner) }
            catch { reportedError = error }
        }
        guard owner == generation, selection == nil || selection == selectionRequest else { return }
        if error is CancellationError { return }
        if case ClientError.SignInRequired = reportedError {
            phase = .login
        } else {
            phase = fallback
        }
        errorMessage = (reportedError as? ClientError)?.userMessage ?? reportedError.localizedDescription
    }
}

extension ClientError {
    var userMessage: String {
        switch self {
        case .InvalidServer(let message), .Connection(let message), .Server(let message):
            return message
        case .SignInRequired:
            return "Sign in to continue. Your saved session may have expired."
        case .InvalidCredentials:
            return "The username or password is incorrect. Please try again."
        }
    }
}
