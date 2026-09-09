import SwiftUI

struct ProjectDetailView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(AudioEngineController.self) private var engine

    let projectID: UUID

    @State private var showingExport = false
    @State private var showingSampleRate = false
    @State private var showingInputPicker = false

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
                    Button("Sample Rate…", systemImage: "dial.medium") {
                        showingSampleRate = true
                    }
                    Button("Microphone…", systemImage: "mic") {
                        showingInputPicker = true
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
            SampleRatePicker()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingInputPicker) {
            InputPicker()
                .presentationDetents([.medium, .large])
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
