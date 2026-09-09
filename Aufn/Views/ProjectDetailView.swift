import SwiftUI

struct ProjectDetailView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(AudioEngineController.self) private var engine

    let projectID: UUID

    @State private var showingExport = false
    @State private var showingSampleRate = false
    @State private var showingInputPicker = false
    @State private var showingMasterVolume = false
    @AppStorage("rawCapture") private var rawCapture = true

    var body: some View {
        Group {
            if let project = store.project(id: projectID) {
                content(for: project)
            } else {
                ContentUnavailableView("Project not found", systemImage: "questionmark.folder")
            }
        }
        .onDisappear {
            engine.stopTransport()
        }
    }

    private func content(for project: Project) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if project.tracks.isEmpty && engine.state != .recording {
                    emptyState
                }
                ForEach(project.tracks) { track in
                    TrackRowView(track: track, project: project)
                        .contextMenu {
                            Button(role: .destructive) {
                                store.deleteTrack(track, from: project)
                            } label: {
                                Label("Delete Track", systemImage: "trash")
                            }
                        }
                }
                if engine.state == .recording {
                    LiveTrackRowView(engine: engine)
                }
            }
            .padding()
            .padding(.bottom, 120)
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Export…", systemImage: "square.and.arrow.up") {
                        showingExport = true
                    }
                    .disabled(project.tracks.isEmpty)
                    Button("Master Volume…", systemImage: "speaker.wave.2") {
                        showingMasterVolume = true
                    }
                    .disabled(project.tracks.isEmpty)
                    Button("Sample Rate…", systemImage: "dial.medium") {
                        showingSampleRate = true
                    }
                    Button("Microphone…", systemImage: "mic") {
                        showingInputPicker = true
                    }
                    Divider()
                    Toggle(isOn: $rawCapture) {
                        Label("Raw Capture", systemImage: "waveform.badge.magnifyingglass")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if engine.state == .recording && AudioSessionController.shared.isOutputBuiltInSpeaker && !project.tracks.isEmpty {
                    Label("Use headphones for clean overdubs", systemImage: "headphones")
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)
                }
                TransportBar(engine: engine, project: project)
            }
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showingExport) {
            ExportSheet(project: project)
        }
        .sheet(isPresented: $showingSampleRate) {
            SampleRatePicker(lockedRate: store.project(id: projectID)?.sampleRate)
        }
        .sheet(isPresented: $showingInputPicker) {
            InputPicker()
        }
        .sheet(isPresented: $showingMasterVolume) {
            MasterVolumeSheet(projectID: projectID)
        }
        .alert("Audio Error", isPresented: engineErrorShown) {
            Button("OK", role: .cancel) { engine.clearError() }
        } message: {
            Text(engine.lastError ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "record.circle")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text("Tap record to lay down the first track.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 80)
    }

    private var engineErrorShown: Binding<Bool> {
        Binding(
            get: { engine.lastError != nil },
            set: { if !$0 { engine.clearError() } }
        )
    }
}

/// Master volume as a tucked-away mix setting: live while dragging, persisted
/// to the project (and thus the mixdown export) on release. Deliberately
/// separate from the phone's hardware volume, which only controls loudness.
struct MasterVolumeSheet: View {
    @Environment(ProjectStore.self) private var store
    @Environment(AudioEngineController.self) private var engine

    let projectID: UUID

    @State private var masterVolume: Float = 1

    var body: some View {
        FittedSheet(title: "Master Volume") {
            HStack(spacing: 12) {
                Image(systemName: "speaker.wave.1")
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { masterVolume },
                        set: { masterVolume = $0; engine.setMasterVolume($0) }
                    ),
                    in: 0...1
                ) { editing in
                    if !editing, var project = store.project(id: projectID) {
                        project.masterVolume = masterVolume
                        store.update(project)
                    }
                }
                .accessibilityLabel("Master volume")
                Image(systemName: "speaker.wave.3")
                    .foregroundStyle(.secondary)
            }
            .sheetCard()
            Text("Part of the project's mix — applied to playback and the stereo mixdown. Use the volume buttons for loudness.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .sheetCard()
        }
        .task {
            masterVolume = store.project(id: projectID)?.masterVolume ?? 1
        }
    }
}
