import SwiftUI

struct ProjectListView: View {
    @Environment(ProjectStore.self) private var store

    @State private var renamingProject: Project?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            Group {
                if store.projects.isEmpty {
                    emptyState
                } else {
                    projectList
                }
            }
            .navigationTitle("Aufn")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Project", systemImage: "plus", action: createProject)
                }
            }
            .navigationDestination(for: UUID.self) { projectID in
                ProjectDetailView(projectID: projectID)
            }
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
    }

    private var projectList: some View {
        List {
            ForEach(store.projects) { project in
                NavigationLink(value: project.id) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name)
                            .font(.headline)
                        Text("\(project.tracks.count) track\(project.tracks.count == 1 ? "" : "s") · \(project.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        store.deleteProject(project)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        renamingProject = project
                        renameText = project.name
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                }
            }
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

    private var renameAlertShown: Binding<Bool> {
        Binding(
            get: { renamingProject != nil },
            set: { if !$0 { renamingProject = nil } }
        )
    }

    private func createProject() {
        let number = store.projects.count + 1
        _ = try? store.createProject(named: "Project \(number)")
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
