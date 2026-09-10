import SwiftUI

/// The workspace settings, Lumo-style: a full-screen sheet whose root lists
/// the mix and capture settings and pushes sub-pages for the deeper ones.
/// Master volume lives inline on the root; sample rate and microphone (input
/// device + mic position) push. Export isn't a setting — it's an action, so
/// it rides in the toolbar and opens as a drawer over the sheet.
struct WorkspaceSettingsView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(AudioEngineController.self) private var engine
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID

    @State private var path = NavigationPath()
    @State private var masterVolume: Float = 1
    @State private var showingExport = false
    @AppStorage("preferredSampleRate") private var preferredSampleRate: Double = 48_000

    enum Route: Hashable {
        case sampleRate
        case microphone
    }

    private var isIdle: Bool { engine.state == .idle }
    private var hasTracks: Bool { !(store.project(id: projectID)?.tracks.isEmpty ?? true) }

    var body: some View {
        NavigationStack(path: $path) {
            SettingsSubPage(title: "Settings") {
                SettingsSectionHeader("Mix")
                masterVolumeRow
                SettingsToggle(title: "Repeat Playback", systemImageName: "repeat", isOn: repeatPlayback)
                SettingsFootnote("Master volume is part of the workspace's mix — applied to playback and the stereo mixdown. Repeat wraps playback from the end back to the start until you stop it.")

                SettingsSectionHeader("Capture")
                SettingsLinkRow(
                    iconName: "dial.medium",
                    title: "Sample Rate",
                    description: "Recording at \(formattedRate)."
                ) {
                    path.append(Route.sampleRate)
                }
                .disabled(!isIdle)
                .opacity(isIdle ? 1 : 0.5)
                SettingsLinkRow(
                    iconName: "mic",
                    title: "Microphone",
                    description: "Input device and mic position."
                ) {
                    path.append(Route.microphone)
                }
                .disabled(!isIdle)
                .opacity(isIdle ? 1 : 0.5)
                if !isIdle {
                    SettingsFootnote("Capture settings are locked while the transport is running.", systemImageName: "lock")
                }
            }
            // Pushed steps would otherwise paint an opaque navigation
            // background over the sheet; keep it clear so the shade never
            // shifts.
            .containerBackground(.clear, for: .navigation)
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
                // Export is an action, not a setting: share affordance in
                // the corner, results in a drawer over the sheet.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.soft()
                        showingExport = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .disabled(!hasTracks)
                    .accessibilityLabel("Export")
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .sampleRate:
                    SampleRatePicker(lockedRate: store.project(id: projectID)?.sampleRate)
                case .microphone:
                    MicrophoneSettingsView()
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showingExport) {
            if let project = store.project(id: projectID) {
                ExportDrawer(project: project)
            }
        }
        .task {
            masterVolume = store.project(id: projectID)?.masterVolume ?? 1
        }
    }

    /// Inline, not a page: live on the engine while dragging, persisted to
    /// the project (and thus the mixdown export) on release.
    private var masterVolumeRow: some View {
        HStack {
            Image(systemName: "speaker.wave.2")
                .font(.system(size: 16))
                .bold()
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 28)
                .padding(.trailing, 5)

            Text("Master Volume")
                .fontDesign(.rounded)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .bold()

            Spacer()

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
            .frame(maxWidth: 150)
            .tint(Color.accentColor)
            .accessibilityLabel("Master volume")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .foregroundStyle(Color.white.opacity(0.07))
        )
    }

    /// Live: toggling mid-play reschedules through the engine.
    private var repeatPlayback: Binding<Bool> {
        Binding(
            get: { store.project(id: projectID)?.repeatPlayback ?? false },
            set: { newValue in
                guard var project = store.project(id: projectID) else { return }
                project.repeatPlayback = newValue
                store.update(project)
                engine.updateMix(for: project)
            }
        )
    }

    private var formattedRate: String {
        let khz = preferredSampleRate / 1000
        return khz == khz.rounded() ? "\(Int(khz)) kHz" : "\(khz) kHz"
    }
}

/// One page for everything microphone: which input device records, and —
/// for the built-in mic — which capsule and pickup pattern.
struct MicrophoneSettingsView: View {
    var body: some View {
        SettingsSubPage(title: "Microphone") {
            InputDeviceSection()
            MicPositionSection()
        }
    }
}

#Preview("Workspace settings") {
    let store = PreviewData.store()
    Color.black
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            WorkspaceSettingsView(projectID: PreviewData.demoProject(in: store).id)
                .environment(store)
                .environment(AudioEngineController(store: store))
        }
    .preferredColorScheme(.dark)
}
