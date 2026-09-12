import AVFAudio
import SwiftUI

/// App-wide settings, reached from the projects grid: the same full-screen
/// sheet shape as the workspace settings, with sub-pages pushed. New sections
/// slot in as more global prefs appear.
struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path = NavigationPath()

    enum Route: Hashable {
        case appIcon
    }

    var body: some View {
        NavigationStack(path: $path) {
            SettingsSubPage(title: "Settings") {
                SettingsSectionHeader("Appearance")
                SettingsLinkRow(iconName: "app.dashed", title: "App Icon") {
                    path.append(Route.appIcon)
                }

                SettingsSectionHeader("Permissions")
                MicrophonePermissionToggle()
                SettingsFootnote("Aufn uses the microphone only to record takes. iOS asks once — after that the switch opens the system Settings, where the real change is made.")
            }
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
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .appIcon:
                    AppIconPickerView()
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

/// The one permission Aufn asks for, as a switch. iOS only lets an app raise
/// the mic prompt while the choice is undecided and never lets it revoke
/// access, so the switch can genuinely flip only on a first grant — every
/// other direction hands off to the system Settings, and the switch snaps
/// back until that trip actually changes something.
private struct MicrophonePermissionToggle: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var permission: MicPermission = .current

    var body: some View {
        SettingsToggle(
            title: "Microphone",
            systemImageName: "mic",
            isOn: Binding(
                get: { permission == .granted },
                set: { request(on: $0) }
            )
        )
        .onChange(of: scenePhase) { _, phase in
            // Coming back from the system Settings picks up a flipped switch.
            if phase == .active {
                permission = .current
            }
        }
    }

    private func request(on: Bool) {
        Haptics.tap()
        guard permission == .undetermined, on else {
            openSystemSettings()
            return
        }
        Task {
            _ = await AVAudioApplication.requestRecordPermission()
            permission = .current
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private enum MicPermission {
    case granted, denied, undetermined

    static var current: MicPermission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        default: .undetermined
        }
    }
}

#Preview("App settings") {
    Color.black
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            AppSettingsView()
        }
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
}
