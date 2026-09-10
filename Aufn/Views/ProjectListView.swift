import SwiftUI

/// The projects grid: two columns of tinted cards. Tap opens the workspace,
/// the card's circle plays the mix in place, long-press manages the project.
/// The gear opens app-wide settings.
struct ProjectListView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(AudioEngineController.self) private var engine

    @State private var path: [UUID] = []
    @State private var showingSettings = false
    @State private var renamingProject: Project?
    @State private var renameText = ""
    @State private var customizingProject: Project?
    @State private var deletingProject: Project?

    private static let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.projects.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("App Settings", systemImage: "gearshape") {
                        Haptics.soft()
                        showingSettings = true
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New Project", systemImage: "plus", action: createProject)
                }
            }
            .navigationDestination(for: UUID.self) { projectID in
                ProjectDetailView(projectID: projectID)
            }
        }
        .sheet(isPresented: $showingSettings) {
            AppSettingsView()
        }
        .sheet(item: $customizingProject) { project in
            ProjectAppearanceSheet(projectID: project.id)
        }
        .alert("Rename Project", isPresented: renameAlertShown) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let project = renamingProject, !renameText.isEmpty {
                    store.renameProject(project, to: renameText)
                }
                renamingProject = nil
            }
            Button("Cancel", role: .cancel) { renamingProject = nil }
        }
        .confirmationDialog(
            "Delete \(deletingProject?.name ?? "Project")?",
            isPresented: deleteDialogShown,
            titleVisibility: .visible
        ) {
            Button("Delete Project", role: .destructive) {
                if let project = deletingProject {
                    if engine.playingProjectID == project.id {
                        stopListPlayback()
                    }
                    withAnimation(.snappy) {
                        store.deleteProject(project)
                    }
                }
                deletingProject = nil
            }
            Button("Cancel", role: .cancel) { deletingProject = nil }
        } message: {
            Text("Every track in this project is removed. This can't be undone.")
        }
        .alert("Playback Error", isPresented: errorShown) {
            Button("OK") { engine.clearError() }
        } message: {
            Text(engine.lastError ?? "")
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: Self.columns, spacing: 14) {
                ForEach(store.projects) { project in
                    ProjectCard(
                        project: project,
                        isPlaying: engine.playingProjectID == project.id,
                        onOpen: { path.append(project.id) },
                        onPlay: { togglePlayback(of: project) }
                    )
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") {
                            renamingProject = project
                            renameText = project.name
                        }
                        Button("Customize", systemImage: "paintpalette") {
                            customizingProject = project
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            deletingProject = project
                        }
                    }
                    .transition(.blurReplace)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .animation(.snappy, value: store.projects)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Record, ship, delete.", systemImage: "waveform")
        } description: {
            Text("Create a project and start layering tracks.")
        } actions: {
            Button("New Project", action: createProject)
                .buttonStyle(.glassProminent)
        }
    }

    // MARK: - Playback from the grid

    /// One transport: starting a card stops whatever else was playing.
    private func togglePlayback(of project: Project) {
        if engine.playingProjectID == project.id {
            stopListPlayback()
        } else if let fresh = store.project(id: project.id) {
            engine.startPlayback(of: fresh)
        }
    }

    private func stopListPlayback() {
        engine.stopTransport()
        AudioSessionController.shared.deactivate()
    }

    // MARK: - Bindings

    private var renameAlertShown: Binding<Bool> {
        Binding(
            get: { renamingProject != nil },
            set: { if !$0 { renamingProject = nil } }
        )
    }

    private var deleteDialogShown: Binding<Bool> {
        Binding(
            get: { deletingProject != nil },
            set: { if !$0 { deletingProject = nil } }
        )
    }

    private var errorShown: Binding<Bool> {
        Binding(
            get: { engine.lastError != nil },
            set: { if !$0 { engine.clearError() } }
        )
    }

    private func createProject() {
        let number = store.projects.count + 1
        withAnimation(.snappy) {
            _ = try? store.createProject(named: "Project \(number)")
        }
    }
}

#Preview("Projects") {
    let store = PreviewData.store()
    ProjectListView()
        .fontDesign(.rounded)
        .environment(store)
        .environment(AudioEngineController(store: store))
        .preferredColorScheme(.dark)
}

#Preview("Empty") {
    let store = PreviewData.store(seeded: false)
    ProjectListView()
        .fontDesign(.rounded)
        .environment(store)
        .environment(AudioEngineController(store: store))
        .preferredColorScheme(.dark)
}
