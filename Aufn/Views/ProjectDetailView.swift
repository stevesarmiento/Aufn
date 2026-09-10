import SwiftUI

struct ProjectDetailView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(AudioEngineController.self) private var engine

    let projectID: UUID

    @State private var showingSettings = false
    @State private var openSwipeTrackID: UUID?

    var body: some View {
        Group {
            if let project = store.project(id: projectID) {
                content(for: project)
            } else {
                ContentUnavailableView("Project not found", systemImage: "questionmark.folder")
            }
        }
        .onAppear {
            // Playback started from the projects grid for another project
            // must not leak into this workspace's transport.
            if engine.playingProjectID != projectID {
                engine.stopForLifecycle()
            }
        }
        .onDisappear {
            // Keep a take in progress (finalize + persist) rather than
            // discard it, then hand the session back so other apps' audio
            // can resume.
            engine.stopForLifecycle()
            AudioSessionController.shared.deactivate()
        }
    }

    private func content(for project: Project) -> some View {
        ScrollView {
            // Eager VStack on purpose: track counts are small, and a lazy
            // stack's late row materialization made scrolling to the bottom
            // hitch once rows had different heights (expanded mixers).
            VStack(spacing: 12) {
                if project.tracks.isEmpty && project.metronome == nil && engine.state != .recording {
                    emptyState
                }
                if let settings = project.metronome {
                    SwipeToDeleteRow(
                        id: MetronomeSettings.rowID,
                        openRowID: $openSwipeTrackID,
                        deleteTitle: "Remove Metronome?",
                        deleteButtonTitle: "Remove Metronome",
                        deleteMessage: "You can add it back from the menu.",
                        deleteAccessibilityLabel: "Remove metronome",
                        onDelete: {
                            withAnimation(.snappy) {
                                engine.removeMetronome()
                                // Fresh copy, not the render-time snapshot: a take
                                // may have landed since the row was drawn.
                                if var fresh = store.project(id: projectID) {
                                    fresh.metronome = nil
                                    store.update(fresh)
                                }
                                openSwipeTrackID = nil
                            }
                        }
                    ) {
                        MetronomeRowView(settings: settings, project: project)
                    }
                }
                ForEach(project.tracks) { track in
                    SwipeToDeleteRow(
                        id: track.id,
                        openRowID: $openSwipeTrackID,
                        deleteTitle: "Delete \"\(track.name)\"?",
                        onDelete: {
                            withAnimation(.snappy) {
                                engine.removeTrack(trackID: track.id)
                                store.deleteTrack(track, from: project)
                                openSwipeTrackID = nil
                            }
                        }
                    ) {
                        TrackRowView(track: track, project: project)
                    }
                }
                if engine.state == .recording {
                    LiveTrackRowView(engine: engine)
                }
            }
            .padding()
            .padding(.bottom, 120)
        }
        .onScrollPhaseChange { _, newPhase in
            if newPhase == .interacting, openSwipeTrackID != nil {
                withAnimation(.snappy) { openSwipeTrackID = nil }
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // A pill of two: + creates workspace content (metronome now,
            // loop tracks later — audio takes stay on the record head), the
            // ellipsis opens the workspace drawer with everything else.
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("Metronome", systemImage: "metronome") {
                        withAnimation(.snappy) {
                            if var fresh = store.project(id: projectID) {
                                fresh.metronome = MetronomeSettings()
                                store.update(fresh)
                            }
                        }
                    }
                    .disabled(project.metronome != nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add")
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Settings")
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if engine.state == .recording && AudioSessionController.shared.isOutputBuiltInSpeaker && (!project.tracks.isEmpty || project.metronome != nil) {
                    Label("Use headphones for clean overdubs", systemImage: "headphones")
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)
                }
                TransportBar(engine: engine, project: project)
            }
            .padding(.bottom, 8)
            // Scrim so track cards fade out under the floating transport
            // instead of colliding with the tape dots. Overshoots the inset's
            // top so the fade begins above the transport, and runs into the
            // home-indicator area so nothing peeks out at the very bottom.
            .background {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.85), location: 0.4),
                        .init(color: .black, location: 0.75),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .padding(.top, -32)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showingSettings) {
            WorkspaceSettingsView(projectID: projectID)
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

#Preview("Project") {
    let store = PreviewData.store()
    NavigationStack {
        ProjectDetailView(projectID: PreviewData.demoProject(in: store).id)
    }
    .fontDesign(.rounded)
    .environment(store)
    .environment(AudioEngineController(store: store))
    .preferredColorScheme(.dark)
}

#Preview("Empty project") {
    let store = PreviewData.store()
    NavigationStack {
        ProjectDetailView(projectID: store.projects.last?.id ?? UUID())
    }
    .fontDesign(.rounded)
    .environment(store)
    .environment(AudioEngineController(store: store))
    .preferredColorScheme(.dark)
}

