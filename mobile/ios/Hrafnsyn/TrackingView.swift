import SwiftUI
import MapKit

struct TrackingView: View {
    @Bindable var model: AppModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showSettings = false
    @State private var showTraffic = false
    @State private var showPhoneDetails = false
    @State private var camera: MapCameraPosition = .automatic
    @State private var mapRect = MKMapRect.world
    @State private var mapSize = CGSize(width: 390, height: 800)

    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    trafficList
                        .navigationTitle("Traffic")
                        .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
                        .toolbar { settingsButton }
                } detail: {
                    mapContent
                        .navigationTitle(model.selectedTrack?.name ?? "Live map")
                        .navigationBarTitleDisplayMode(.inline)
                        .inspector(isPresented: Binding(get: { model.selectedID != nil }, set: { if !$0 { Task { await model.select(nil) } } })) {
                            TrackDetailView(model: model)
                                .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
                        }
                }
            } else {
                NavigationStack {
                    mapContent
                        .navigationTitle("Hrafnsyn")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button { showTraffic = true } label: { Label("Traffic", systemImage: "list.bullet") }
                            }
                            settingsButton
                        }
                        .sheet(isPresented: $showTraffic) {
                            NavigationStack {
                                trafficList.navigationTitle("Traffic")
                                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showTraffic = false } } }
                            }.presentationDetents([.medium, .large])
                        }
                        .sheet(isPresented: $showPhoneDetails, onDismiss: { model.dismissSelection() }) {
                            NavigationStack {
                                TrackDetailView(model: model)
                                    .navigationTitle(model.selectedTrack?.name ?? "Track details")
                                    .navigationBarTitleDisplayMode(.inline)
                                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPhoneDetails = false } } }
                            }.presentationDetents([.medium, .large])
                        }
                }
            }
        }
        .sheet(isPresented: $showSettings) { settings }
        .onChange(of: model.selectedID) { _, id in
            guard let id, let track = model.tracks.first(where: { $0.id == id }) else { return }
            camera = .region(MKCoordinateRegion(center: track.coordinate, span: .init(latitudeDelta: 2, longitudeDelta: 2)))
            if sizeClass != .regular {
                showTraffic = false
                // Let the traffic sheet finish its dismissal before presenting details.
                Task { try? await Task.sleep(for: .milliseconds(350)); showPhoneDetails = model.selectedID == id }
            }
        }
    }

    private var mapContent: some View {
        Map(position: $camera) {
            ForEach(markerGroups) { group in
                Annotation(group.tracks.count == 1 ? group.tracks[0].name : "", coordinate: group.coordinate) {
                    if group.tracks.count > 1 {
                        Button { camera = .region(group.region) } label: {
                            if let selected = group.selectedTrack {
                                ZStack {
                                    Image(systemName: selected.isAircraft ? "airplane" : "ferry.fill")
                                        .font(.body.weight(.semibold))
                                        .rotationEffect(.degrees(selected.isAircraft ? selected.headingDegrees - 90 : 0))
                                        .foregroundStyle(Color(uiColor: .systemBackground))
                                        .frame(width: 30, height: 30)
                                        .background(selected.vehicleColor, in: Circle())
                                    Text(group.tracks.count.formatted())
                                        .font(.caption2.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(Color(uiColor: .systemBackground))
                                        .padding(5).background(selected.vehicleColor, in: Capsule())
                                        .offset(x: 20, y: -22)
                                }.frame(width: 64, height: 64)
                            } else {
                            Text(group.tracks.count.formatted()).font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Color(uiColor: .systemBackground)).padding(8)
                                .background(Color.accentColor, in: Circle()).frame(minWidth: 44, minHeight: 44)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(group.selectedTrack.map { "Selected \($0.name). Zoom into \(group.tracks.count) tracks" } ?? "Zoom into \(group.tracks.count) tracks")
                    } else {
                    let track = group.tracks[0]
                    Button { Task { await model.select(track.id) } } label: {
                        Image(systemName: track.isAircraft ? "airplane" : "ferry.fill")
                            .font(.body.weight(.semibold))
                            .rotationEffect(.degrees(track.isAircraft ? track.headingDegrees - 90 : 0))
                            .foregroundStyle(model.selectedID == track.id ? Color(uiColor: .systemBackground) : track.vehicleColor)
                            .frame(width: 26, height: 26)
                            .background(model.selectedID == track.id ? track.vehicleColor : Color(uiColor: .systemBackground), in: Circle())
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(track.name), \(track.isAircraft ? "aircraft" : "vessel"), \(Int(track.speedKnots)) knots")
                    }
                }
            }
            if let route = model.details?.route, route.count > 1 {
                MapPolyline(coordinates: route.map { .init(latitude: $0.latitude, longitude: $0.longitude) })
                    .stroke(.teal, lineWidth: 3)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { mapSize = $0 }
        .onMapCameraChange(frequency: .onEnd) { context in
            let rect = context.rect
            if abs(rect.width - mapRect.width) > max(mapRect.width / 100, 1)
                || abs(rect.height - mapRect.height) > max(mapRect.height / 100, 1) {
                mapRect = rect
            }
        }
        .onAppear { fitAllTracks() }
        .onChange(of: model.tracks.isEmpty) { _, empty in if !empty { fitAllTracks() } }
        .mapControls { MapCompass(); MapScaleView() }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if let message = model.errorMessage {
                    HStack(alignment: .top) {
                        Image(systemName: "wifi.exclamationmark")
                        Text(message).font(.footnote)
                        Spacer(minLength: 0)
                        Button("Retry") { Task { await model.refresh() } }
                    }.padding().foregroundStyle(.primary)
                }
                HStack {
                    Label(model.reconnecting ? "Reconnecting" : "\(model.tracks.count) active", systemImage: model.reconnecting ? "arrow.trianglehead.clockwise" : "dot.radiowaves.left.and.right")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if let updated = model.updatedAt {
                        TimelineView(.periodic(from: .now, by: 5)) { _ in
                            Text(updated, style: .relative).font(.caption).foregroundStyle(.secondary)
                                .accessibilityLabel("Last updated \(updated.formatted(date: .omitted, time: .standard))")
                        }
                    }
                    Button { fitAllTracks() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                        .frame(width: 44, height: 44).accessibilityLabel("Fit all tracks")
                }.padding(.horizontal)
            }
            .background(.regularMaterial)
        }
        .overlay {
            if model.tracks.isEmpty && model.updatedAt != nil {
                ContentUnavailableView("No active tracks", systemImage: "map", description: Text("Tracks appear here when your server receives aircraft or vessel positions."))
                    .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)).padding()
                    .allowsHitTesting(false)
            }
        }
    }

    private var trafficList: some View {
        List {
            Section {
                Picker("Vehicle type", selection: $model.filter) {
                    ForEach(AppModel.VehicleFilter.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }
            Section {
                ForEach(model.visibleTracks, id: \.id) { track in
                    Button { Task { await model.select(track.id) } } label: {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(track.name, systemImage: track.isAircraft ? "airplane" : "ferry")
                                    .font(.headline).foregroundStyle(.primary)
                                Text(track.registration.isEmpty ? track.identity : track.registration)
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("\(Int(track.speedKnots)) kn · \(track.isAircraft ? "Aircraft" : "Vessel")")
                                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            }.padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        } else {
                        HStack(spacing: 12) {
                            Image(systemName: track.isAircraft ? "airplane" : "ferry")
                                .foregroundStyle(track.vehicleColor).frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.name).font(.headline).foregroundStyle(.primary)
                                Text(track.registration.isEmpty ? track.identity : track.registration)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("\(Int(track.speedKnots)) kn").font(.subheadline.monospacedDigit()).foregroundStyle(.primary)
                                Text(track.isAircraft ? "Aircraft" : "Vessel").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 5).contentShape(Rectangle())
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(model.selectedID == track.id ? Color.teal.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground))
                }
            } header: { Text("\(model.visibleTracks.count) tracks") }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $model.query, prompt: "Name, callsign or registration")
        .refreshable { await model.refresh() }
        .overlay {
            if model.visibleTracks.isEmpty && !model.query.isEmpty {
                ContentUnavailableView.search(text: model.query)
            }
        }
    }

    private var markerGroups: [MarkerGroup] {
        let tracks = model.visibleTracks
        let width = max(mapRect.width, 1), height = max(mapRect.height, 1)
        let projected = tracks.map { track in
            let point = MKMapPoint(track.coordinate)
            return CGPoint(x: point.x / width * mapSize.width, y: point.y / height * mapSize.height)
        }
        // Merge neighboring centroids as well as nearby contacts. Grid boundaries
        // must never produce overlapping count bubbles or ambiguous hit targets.
        let selectedIndex = tracks.firstIndex { $0.id == model.selectedID }
        return MapClustering.groups(projected, clearance: dynamicTypeSize.isAccessibilitySize || selectedIndex != nil ? 80 : 58,
                                    anchoredIndex: selectedIndex).map { indices in
            MarkerGroup(id: indices.map { tracks[$0].id }.sorted().joined(separator: ":"),
                        tracks: indices.map { tracks[$0] }, selectedID: model.selectedID)
        }

    }

    private func fitAllTracks() {
        guard !model.visibleTracks.isEmpty else { return }
        // Freeze an explicit region: automatic fitting plus changing clusters
        // creates a camera/layout feedback loop on wide iPad maps.
        camera = .region(MarkerGroup(id: "all", tracks: model.visibleTracks).region)
    }

    @ToolbarContentBuilder private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showSettings = true } label: { Label("Server settings", systemImage: "gearshape") }
        }
    }

    private var settings: some View {
        NavigationStack {
            Form {
                Section("Connected server") {
                    Text(model.server).textSelection(.enabled)
                    LabeledContent("Access", value: model.username.isEmpty ? "Public" : model.username)
                }
                Section {
                    Button("Change server") { showSettings = false; model.changeServer() }
                    if !model.username.isEmpty {
                        Button("Sign out", role: .destructive) { showSettings = false; Task { await model.signOut() } }
                    }
                } footer: { Text("Changing servers keeps each server’s session separate. Signing out removes this server’s saved session from this device.") }
            }
            .navigationTitle("Server")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSettings = false } } }
        }
        .presentationSizing(.form)
    }
}

struct TrackDetailView: View {
    @Bindable var model: AppModel
    var body: some View {
        Group {
            if let track = model.selectedTrack ?? model.details?.track {
                List {
                    Section {
                        Label(track.name, systemImage: track.isAircraft ? "airplane" : "ferry")
                            .font(.title2.weight(.semibold)).foregroundStyle(track.vehicleColor)
                        Text(track.sourceName).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Section("Position") {
                        LabeledContent("Speed", value: "\(Int(track.speedKnots)) kn")
                        LabeledContent("Heading", value: "\(Int(track.headingDegrees))°")
                        if track.isAircraft { LabeledContent("Altitude", value: "\(track.altitudeFeet.formatted()) ft") }
                        LabeledContent("Latitude", value: track.latitude.formatted(.number.precision(.fractionLength(4))))
                        LabeledContent("Longitude", value: track.longitude.formatted(.number.precision(.fractionLength(4))))
                        LabeledContent("Observed", value: Date(timeIntervalSince1970: Double(track.observedAt)).formatted(date: .abbreviated, time: .shortened))
                    }.monospacedDigit()
                    Section("Identity") {
                        LabeledContent("Identifier", value: track.identity)
                        if !track.registration.isEmpty { LabeledContent("Registration", value: track.registration) }
                        if !track.callsign.isEmpty { LabeledContent("Callsign", value: track.callsign) }
                        if !track.country.isEmpty { LabeledContent("Country", value: track.country) }
                        if !track.destination.isEmpty { LabeledContent("Destination", value: track.destination) }
                    }
                    Section("Recent route · 6 hours") {
                        if model.loadingDetails { ProgressView("Loading route…") }
                        else if let details = model.details {
                            LabeledContent("Positions", value: details.route.count.formatted())
                            LabeledContent("Distance", value: "\((details.distanceMeters / 1000).formatted(.number.precision(.fractionLength(1)))) km")
                            if details.route.isEmpty { Text("No recent positions are available.").foregroundStyle(.secondary) }
                        } else {
                            Text("Route could not be loaded.").foregroundStyle(.secondary)
                            Button("Try again") { Task { await model.select(track.id) } }
                        }
                    }
                }.listStyle(.insetGrouped).textSelection(.enabled)
            } else {
                ContentUnavailableView("Select a track", systemImage: "scope", description: Text("Choose an aircraft or vessel to inspect its position and recent route."))
            }
        }
    }
}

extension Track {
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var vehicleColor: Color { isAircraft ? .accentColor : .indigo }
}

private struct MarkerGroup: Identifiable {
    let id: String
    let tracks: [Track]
    var selectedID: String? = nil
    var selectedTrack: Track? { tracks.first { $0.id == selectedID } }
    var coordinate: CLLocationCoordinate2D {
        if let selectedTrack { return selectedTrack.coordinate }
        let points = tracks.map { MKMapPoint($0.coordinate) }
        return MKMapPoint(x: points.map(\.x).reduce(0, +) / Double(points.count),
                          y: points.map(\.y).reduce(0, +) / Double(points.count)).coordinate
    }
    var region: MKCoordinateRegion {
        let latitudes = tracks.map(\.latitude), longitudes = tracks.map(\.longitude)
        return .init(center: coordinate, span: .init(
            latitudeDelta: max((latitudes.max()! - latitudes.min()!) * 1.8, 0.02),
            longitudeDelta: max((longitudes.max()! - longitudes.min()!) * 1.8, 0.02)))
    }
}
