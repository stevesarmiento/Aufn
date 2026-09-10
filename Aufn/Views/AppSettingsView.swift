import SwiftUI

/// App-wide settings, reached from the projects grid: the same full-screen
/// sheet shape as the workspace settings, with sub-pages pushed. Only
/// Appearance for now; new sections slot in as more global prefs appear.
struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("activeAppIcon") private var activeAppIcon = AppIconCatalog.primaryKey
    @State private var path = NavigationPath()

    enum Route: Hashable {
        case appIcon
    }

    private var activeIconName: String {
        AppIconCatalog.option(forStorageKey: activeAppIcon)?.displayName ?? AppIconCatalog.primaryDisplayName
    }

    var body: some View {
        NavigationStack(path: $path) {
            SettingsSubPage(title: "Settings") {
                SettingsSectionHeader("Appearance")
                SettingsLinkRow(
                    iconName: "app.dashed",
                    title: "App Icon",
                    description: "Using \(activeIconName)."
                ) {
                    path.append(Route.appIcon)
                }
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

#Preview("App settings") {
    Color.black
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            AppSettingsView()
        }
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
}
