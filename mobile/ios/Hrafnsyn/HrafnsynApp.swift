import SwiftUI

@main
struct HrafnsynApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .tint(.accentColor)
                .task {
                    await model.resume()
                    #if DEBUG
                    // Reproducible native inspection without altering the Release app.
                    let arguments = ProcessInfo.processInfo.arguments
                    if let index = arguments.firstIndex(of: "-inspect-track"), arguments.indices.contains(index + 1),
                       model.tracks.contains(where: { $0.id == arguments[index + 1] }) {
                        await model.select(arguments[index + 1])
                    }
                    #endif
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await model.resume() } }
                }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(model.reconnecting ? 15 : 5))
                        guard !Task.isCancelled else { return }
                        await model.refresh()
                    }
                }
        }
    }
}

struct RootView: View {
    @Bindable var model: AppModel
    var body: some View {
        Group {
            switch model.phase {
            case .server, .connecting: ServerView(model: model)
            case .login: LoginView(model: model)
            case .tracking: TrackingView(model: model)
            }
        }
    }
}

struct ServerView: View {
    @Bindable var model: AppModel
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Aircraft & vessels, together", systemImage: "map")
                        .font(.title2.weight(.semibold))
                        .padding(.vertical, 12)
                    Text("Connect to your Hrafnsyn server to follow live traffic and explore recent routes.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    TextField("https://tracking.example.com:50051", text: $model.server)
                        .disabled(model.busy)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Server address")
                        .submitLabel(.go)
                        .onSubmit { Task { await model.connect() } }
                    Button { Task { await model.connect() } } label: {
                        HStack {
                            Text(model.busy ? "Connecting…" : "Connect to server")
                            Spacer()
                            if model.busy { ProgressView() } else { Image(systemName: "arrow.right") }
                        }
                        .frame(minHeight: 32)
                    }
                    .disabled(model.server.trimmingCharacters(in: .whitespaces).isEmpty || model.busy)
                } header: { Text("Your server") } footer: {
                    Text("Use the server’s gRPC address. You’ll be asked to sign in only if access is restricted. Sessions are saved securely on this device.")
                }
                if let message = model.errorMessage { ErrorSection(message: message) }
            }
            .navigationTitle("Hrafnsyn")
            .formStyle(.grouped)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }
}

struct LoginView: View {
    @Bindable var model: AppModel
    @State private var password = ""
    @FocusState private var passwordFocused: Bool
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("This server requires sign-in", systemImage: "lock")
                        .font(.headline)
                    Text(model.server).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Section {
                    TextField("Username", text: $model.username)
                        .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.next).onSubmit { passwordFocused = true }
                    SecureField("Password", text: $password)
                        .textContentType(.password).focused($passwordFocused).submitLabel(.go)
                        .onSubmit { submit() }
                    Button(action: submit) {
                        HStack { Text("Sign in"); Spacer(); if model.busy { ProgressView() } }
                            .frame(minHeight: 32)
                    }.disabled(model.username.isEmpty || password.isEmpty || model.busy)
                } footer: { Text("Your session is saved in Keychain. Your password is never stored.") }
                if let message = model.errorMessage { ErrorSection(message: message) }
            }
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Sign in")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Change server") { password = ""; model.changeServer() }.disabled(model.busy) } }
        }
    }
    private func submit() {
        guard !model.busy, !password.isEmpty, !model.username.isEmpty else { return }
        let submitted = password
        password = ""
        Task { await model.login(password: submitted) }
    }
}

struct ErrorSection: View {
    let message: String
    var body: some View {
        Section { Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently) }
    }
}
