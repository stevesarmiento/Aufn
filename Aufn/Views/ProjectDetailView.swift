import SwiftUI

struct ProjectDetailView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(AudioEngineController.self) private var engine

    let projectID: UUID

    @State private var showingSettings = false
    @State private var openSwipeTrackID: UUID?
    // Multi-select: row ids (tracks plus the metronome sentinel). Non-empty
    // means "selection mode": rows toggle on tap, the transport becomes the
    // action bar. Idle-only — the head is Stop while the transport runs.
    @State private var selectedRowIDs: Set<UUID> = []
    @State private var confirmingSelectionDelete = false
    @State private var exportingSelection = false

    private var isSelecting: Bool { !selectedRowIDs.isEmpty }

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
                    SwipeRow(
                        id: MetronomeSettings.rowID,
                        openRowID: $openSwipeTrackID,
                        isSelected: selectedRowIDs.contains(MetronomeSettings.rowID),
                        inSelectionMode: isSelecting,
                        onToggleSelection: { toggleSelection(MetronomeSettings.rowID) },
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
                        MetronomeRowView(
                            settings: settings,
                            project: project,
                            isSelected: selectedRowIDs.contains(MetronomeSettings.rowID),
                            inSelectionMode: isSelecting
                        )
                    }
                }
                ForEach(project.tracks) { track in
                    SwipeRow(
                        id: track.id,
                        openRowID: $openSwipeTrackID,
                        isSelected: selectedRowIDs.contains(track.id),
                        inSelectionMode: isSelecting,
                        onToggleSelection: { toggleSelection(track.id) },
                        deleteTitle: "Delete \"\(track.name)\"?",
                        onDelete: {
                            withAnimation(.snappy) {
                                engine.removeTrack(trackID: track.id)
                                store.deleteTrack(track, from: project)
                                openSwipeTrackID = nil
                            }
                        }
                    ) {
                        TrackRowView(
                            track: track,
                            project: project,
                            isSelected: selectedRowIDs.contains(track.id),
                            inSelectionMode: isSelecting
                        )
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
                withAnimation(.discloseClose) { openSwipeTrackID = nil }
            }
        }
        .onChange(of: engine.state) { _, state in
            // The head becomes Stop the moment the transport runs; selection
            // can't coexist with it.
            if state != .idle, isSelecting {
                withAnimation(.snappy) { selectedRowIDs = [] }
            }
        }
        .onChange(of: rowIDs(in: project)) { _, ids in
            // A row that vanished underneath us (take landed, metronome
            // removed elsewhere) drops out of the selection.
            selectedRowIDs.formIntersection(ids)
        }
        // Photos-style: the title carries the count while selecting.
        .navigationTitle(isSelecting ? "\(selectedRowIDs.count) Selected" : project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // A pill of two: + creates workspace content (metronome now,
            // loop tracks later — audio takes stay on the record head), the
            // ellipsis opens the workspace drawer with everything else.
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("Metronome", systemImage: "metronome") {
                        Haptics.tap()
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
                    Haptics.tap()
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
                // The transport steps aside for the action pill while rows
                // are selected; both grow out of the bottom edge.
                if isSelecting {
                    SelectionActionBar(
                        canExport: project.tracks.contains { selectedRowIDs.contains($0.id) },
                        onCancel: { withAnimation(.snappy) { selectedRowIDs = [] } },
                        onDelete: { confirmingSelectionDelete = true },
                        onExport: { exportingSelection = true }
                    )
                    .transition(.disclose(anchor: .bottom, edge: .bottom))
                } else {
                    TransportBar(engine: engine, project: project)
                        .transition(.disclose(anchor: .bottom))
                }
            }
            .animation(.snappy, value: isSelecting)
            // Full width regardless of what the inset holds (the action pill
            // hugs its content), so the scrim below always spans the screen.
            .frame(maxWidth: .infinity)
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
        .sheet(isPresented: $exportingSelection) {
            // The drawer declares its own detents and glass; over the black
            // workspace it reads the same as over the settings sheet.
            if let fresh = store.project(id: projectID) {
                ExportDrawer(project: fresh, trackIDs: selectedRowIDs.subtracting([MetronomeSettings.rowID]))
            }
        }
        .alert(deleteCopy(for: project).title, isPresented: $confirmingSelectionDelete) {
            Button("Cancel", role: .cancel) {}
            Button(deleteCopy(for: project).button, role: .destructive) { deleteSelection() }
        } message: {
            Text(deleteCopy(for: project).message)
        }
        .alert("Audio Error", isPresented: engineErrorShown) {
            Button("OK", role: .cancel) { engine.clearError() }
        } message: {
            Text(engine.lastError ?? "")
        }
    }

    // MARK: - Selection

    private func toggleSelection(_ id: UUID) {
        guard engine.state == .idle else { return }
        withAnimation(.snappy) {
            openSwipeTrackID = nil
            selectedRowIDs.formSymmetricDifference([id])
        }
    }

    /// Every selectable row id the project currently has.
    private func rowIDs(in project: Project) -> Set<UUID> {
        var ids = Set(project.tracks.map(\.id))
        if project.metronome != nil { ids.insert(MetronomeSettings.rowID) }
        return ids
    }

    private func deleteCopy(for project: Project) -> SelectionDeleteCopy {
        SelectionDeleteCopy(
            trackNames: project.tracks.filter { selectedRowIDs.contains($0.id) }.map(\.name),
            includesMetronome: selectedRowIDs.contains(MetronomeSettings.rowID)
        )
    }

    private func deleteSelection() {
        // Fresh copy, not the render-time snapshot (same reason as the row
        // delete). removeTrack is a no-op while idle but keeps the
        // orchestration right if selection ever becomes allowed mid-transport.
        guard engine.state == .idle, let fresh = store.project(id: projectID) else { return }
        let removingMetronome = selectedRowIDs.contains(MetronomeSettings.rowID)
        let trackIDs = selectedRowIDs.subtracting([MetronomeSettings.rowID])
        withAnimation(.snappy) {
            for id in trackIDs { engine.removeTrack(trackID: id) }
            if removingMetronome { engine.removeMetronome() }
            store.deleteTracks(ids: trackIDs, removingMetronome: removingMetronome, from: fresh)
            selectedRowIDs = []
            openSwipeTrackID = nil
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

