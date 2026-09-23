import SwiftUI

/// Customize a project's card colour. The change writes straight through to
/// the store — the live card at the top is the confirmation.
struct ProjectAppearanceSheet: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID

    var body: some View {
        NavigationStack {
            SettingsSubPage(title: "Customize", paintsBackdrop: false) {
                if let project = store.project(id: projectID) {
                    ProjectCard(project: project, showsPlayButton: false)
                        .frame(maxWidth: 220)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)
                        .allowsHitTesting(false)

                    SettingsSectionHeader("Color")
                    tintRow(selected: project.tint)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
    }

    private func tintRow(selected: ProjectTint) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(ProjectTint.allCases, id: \.self) { tint in
                    let isSelected = tint == selected
                    Button {
                        Haptics.tap()
                        update { $0.tint = tint }
                    } label: {
                        Circle()
                            .fill(tint.color)
                            .frame(width: 36, height: 36)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.accentColor, lineWidth: 2)
                                    .padding(-4)
                                    .opacity(isSelected ? 1 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(tint.displayName) tint")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(6)
        }
        .animation(.snappy(duration: 0.2), value: selected)
    }

    private func update(_ change: (inout Project) -> Void) {
        guard var project = store.project(id: projectID) else { return }
        change(&project)
        guard project != store.project(id: projectID) else { return }
        store.update(project)
    }
}

#Preview("Customize") {
    let store = PreviewData.store()
    Color.black
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            ProjectAppearanceSheet(projectID: PreviewData.demoProject(in: store).id)
                .environment(store)
                .environment(AudioEngineController(store: store))
        }
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
}
