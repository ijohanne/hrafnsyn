import Foundation
import Observation

protocol SessionStorage {
    func read(server: String) throws -> SavedSession?
    func write(_ session: SavedSession?, server: String) throws
}
extension SessionStore: SessionStorage {}

@MainActor @Observable
final class AppModel {
    enum Phase { case server, connecting, login, tracking }
    var phase: Phase = .server
    var server: String
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
    var webOrigin: String?
    var sharedServerPrompt: SharedServerPrompt?
    var sharedLinkError: String?
    var selectionHistoryHours: Int32 = 6
    var selectionFromLink = false
    var sharedSelectionRevision = UUID()
    private var client: (any TrackingClientProtocol)?
    private let store: any SessionStorage
    private let defaults: UserDefaults
    private let makeClient: (String, SavedSession?) throws -> any TrackingClientProtocol
    private var pendingSharedTrack: PendingSharedTrack?
    private var openingSharedTrack: UUID?
    private var generation = UUID()
    private var refreshingGeneration: UUID?
    private var selectionRequest = UUID()
    // A previous server may finish rotating credentials after it leaves the screen.
    // Only the latest client for each origin may persist that origin's session.
    private var sessionOwners: [String: UUID] = [:]

    init(defaults: UserDefaults = .standard, store: any SessionStorage = SessionStore(),
         makeClient: @escaping (String, SavedSession?) throws -> any TrackingClientProtocol = {
             try TrackingClient(server: $0, session: $1)
         }) {
        self.defaults = defaults; self.store = store; self.makeClient = makeClient
        server = defaults.string(forKey: "server") ?? ""
    }

    struct SharedServerPrompt: Identifiable {
        let id: UUID
        let webOrigin: String
        let suggestedServer: String
        let knownServer: Bool
    }
    private struct PendingSharedTrack {
        let id: UUID
        let link: SharedTrackLink
        var server: String?
    }

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
    var selectedTrack: Track? {
        tracks.first { $0.id == selectedID } ?? (details?.track?.id == selectedID ? details?.track : nil)
    }

    var mapTracks: [Track] {
        guard let selected = selectedTrack, !visibleTracks.contains(where: { $0.id == selected.id }) else { return visibleTracks }
        return visibleTracks + [selected]
    }

    var selectedShareURL: URL? {
        guard let track = selectedTrack, let webOrigin,
              let value = try? makeTrackShareUrl(webOrigin: webOrigin, vehicle: track.isAircraft ? "plane" : "vessel",
                                                  identity: track.identity, historyHours: selectionHistoryHours) else { return nil }
        return URL(string: value)
    }
    var canRetrySharedLink: Bool { pendingSharedTrack != nil && sharedServerPrompt == nil }

    func connect() async {
        guard !busy else { return }
        busy = true; errorMessage = nil; phase = .connecting
        generation = UUID()
        let currentGeneration = generation
        var connection: (any TrackingClientProtocol)?
        defer { if currentGeneration == generation { busy = false } }
        do {
            let normalized = try normalizeServer(server: server)
            server = normalized
            let session = try store.read(server: normalized)
            let candidate = try makeClient(normalized, session)
            connection = candidate; client = candidate
            sessionOwners[normalized] = currentGeneration
            let status = try await candidate.connect()
            let saved = try await persist(candidate, owner: currentGeneration)
            guard currentGeneration == generation else { return }
            server = normalized; username = saved?.username ?? ""
            defaults.set(normalized, forKey: "server")
            phase = status.authRequired && !status.authenticated ? .login : .tracking
            if phase == .tracking { await connected(candidate, owner: currentGeneration) }
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
            await connected(connection, owner: currentGeneration)
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
        pendingSharedTrack = nil; sharedLinkError = nil
        selectionFromLink = false
        selectionRequest = UUID()
        selectedID = nil; details = nil; loadingDetails = false
    }

    func select(_ id: String?) async {
        pendingSharedTrack = nil; sharedLinkError = nil; selectionHistoryHours = 6
        selectionFromLink = false
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
        pendingSharedTrack = nil; sharedServerPrompt = nil; sharedLinkError = nil
        resetConnection()
    }

    private func resetConnection() {
        generation = UUID(); client = nil; tracks = []; details = nil; selectedID = nil
        selectionRequest = UUID(); loadingDetails = false; busy = false
        updatedAt = nil; errorMessage = nil; phase = .server; reconnecting = false
        username = ""; query = ""; filter = .all
        webOrigin = nil; openingSharedTrack = nil; selectionHistoryHours = 6
        selectionFromLink = false
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
        guard sharedServerPrompt == nil else { return }
        if phase == .server && !server.isEmpty { await connect() }
        else if phase == .tracking { await refresh(); await openPendingSharedTrack() }
    }

    func openSharedURL(_ url: URL) async {
        do {
            let link = try parseSharedTrackLink(url: url.absoluteString)
            let request = UUID()
            // A newly received link owns the destination, including while an
            // earlier connection or identity lookup is suspended.
            selectionRequest = UUID(); sharedLinkError = nil; loadingDetails = false
            let currentServer = try? normalizeServer(server: server)
            let known = defaults.dictionary(forKey: "webServers") as? [String: String] ?? [:]
            let matchesCurrent = currentServer != nil &&
                (webOrigin == link.webOrigin || currentServer == link.webOrigin || known[link.webOrigin] == currentServer)
            let target = matchesCurrent ? currentServer : known[link.webOrigin]
            pendingSharedTrack = PendingSharedTrack(id: request, link: link, server: target)
            if matchesCurrent {
                sharedServerPrompt = nil
                if phase == .tracking { await openPendingSharedTrack() }
                else if phase == .server && !busy { await connect() }
            } else {
                sharedServerPrompt = SharedServerPrompt(id: request, webOrigin: link.webOrigin,
                                                        suggestedServer: target ?? link.webOrigin, knownServer: target != nil)
            }
        } catch {
            pendingSharedTrack = nil; sharedServerPrompt = nil; selectionRequest = UUID(); loadingDetails = false
            sharedLinkError = "This is not a valid Hrafnsyn track link."
        }
    }

    func confirmSharedServer(_ address: String) async {
        guard let prompt = sharedServerPrompt, var pending = pendingSharedTrack, prompt.id == pending.id else { return }
        do {
            let normalized = try normalizeServer(server: address)
            pending.server = normalized
            resetConnection()
            pendingSharedTrack = pending; sharedServerPrompt = nil; sharedLinkError = nil
            server = normalized
            await connect()
        } catch {
            sharedLinkError = (error as? ClientError)?.userMessage ?? error.localizedDescription
        }
    }

    func cancelSharedLink() {
        pendingSharedTrack = nil; sharedServerPrompt = nil; sharedLinkError = nil
        selectionRequest = UUID(); loadingDetails = false
    }

    func retrySharedLink() async {
        if let pending = pendingSharedTrack, let webOrigin, webOrigin != pending.link.webOrigin {
            sharedServerPrompt = SharedServerPrompt(id: pending.id, webOrigin: pending.link.webOrigin,
                                                    suggestedServer: pending.link.webOrigin, knownServer: false)
        } else if webOrigin == nil, let connection = client, phase == .tracking {
            await connected(connection, owner: generation)
        } else {
            await openPendingSharedTrack()
        }
    }

    private func connected(_ connection: any TrackingClientProtocol, owner: UUID) async {
        var advertised = ""
        var metadataError: Error?
        do {
            advertised = try await connection.serverWebUrl()
        } catch {
            metadataError = error
        }
        do {
            _ = try await persist(connection, owner: owner)
        } catch {
            await handle(error, connection: connection, owner: owner, fallback: .tracking)
            return
        }
        guard owner == generation else { return }
        if let metadataError, case ClientError.SignInRequired = metadataError {
            await handle(metadataError, connection: connection, owner: owner, fallback: .tracking)
            return
        }
        // Older servers can still track without advertising a share URL.
        if !advertised.isEmpty, let normalized = try? normalizeServer(server: advertised) {
            webOrigin = normalized
            var known = defaults.dictionary(forKey: "webServers") as? [String: String] ?? [:]
            known[normalized] = connection.server()
            defaults.set(known, forKey: "webServers")
        }
        await refresh()
        await openPendingSharedTrack()
    }

    private func openPendingSharedTrack() async {
        guard phase == .tracking, sharedServerPrompt == nil, let connection = client,
              let pending = pendingSharedTrack, pending.server == connection.server(),
              openingSharedTrack != pending.id else { return }
        if let webOrigin, webOrigin != pending.link.webOrigin {
            sharedLinkError = "This server uses a different website address. Choose the server that hosts the shared link."
            return
        }
        let known = defaults.dictionary(forKey: "webServers") as? [String: String] ?? [:]
        if webOrigin == nil && pending.link.webOrigin != connection.server() && known[pending.link.webOrigin] != connection.server() {
            sharedLinkError = "This server has not confirmed the shared website address. Retry to check it again."
            return
        }
        let owner = generation
        let request = UUID()
        selectionRequest = request; openingSharedTrack = pending.id; loadingDetails = true
        sharedLinkError = nil
        defer {
            if openingSharedTrack == pending.id { openingSharedTrack = nil }
            if selectionRequest == request { loadingDetails = false }
        }
        do {
            let result = try await connection.getTrackByIdentity(vehicle: pending.link.vehicle,
                                                                 identity: pending.link.identity,
                                                                 historyHours: pending.link.historyHours)
            _ = try await persist(connection, owner: owner)
            guard owner == generation, selectionRequest == request, pendingSharedTrack?.id == pending.id else { return }
            guard let track = result.track else {
                sharedLinkError = "The shared track is no longer available on this server."
                return
            }
            selectionFromLink = true
            details = result; selectedID = track.id; selectionHistoryHours = pending.link.historyHours
            sharedSelectionRevision = UUID()
            pendingSharedTrack = nil
        } catch {
            var reportedError = error
            do { _ = try await persist(connection, owner: owner) }
            catch { reportedError = error }
            guard owner == generation, selectionRequest == request, pendingSharedTrack?.id == pending.id else { return }
            if case ClientError.SignInRequired = reportedError {
                phase = .login
            } else {
                sharedLinkError = (reportedError as? ClientError)?.userMessage ?? reportedError.localizedDescription
            }
        }
    }

    private func persist(_ connection: any TrackingClientProtocol, owner: UUID) async throws -> SavedSession? {
        let session = await connection.savedSession()
        let origin = connection.server()
        guard sessionOwners[origin] == owner else { return nil }
        try store.write(session, server: origin)
        return session
    }

    private func handle(_ error: Error, connection: (any TrackingClientProtocol)?, owner: UUID, fallback: Phase, selection: UUID? = nil) async {
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
