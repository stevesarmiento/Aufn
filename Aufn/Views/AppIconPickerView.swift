import SwiftUI
import UIKit

/// The App Icon page: a grid of icon tiles, accent ring on the active one.
/// Ported from Lumo's picker, minus paging (Aufn has a handful of icons) and
/// with the stored value written only after the system accepts the change.
struct AppIconPickerView: View {
    @AppStorage("activeAppIcon") private var activeAppIcon = AppIconCatalog.primaryKey
    @State private var options = AppIconCatalog.options
    @State private var failure: String?

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        SettingsSubPage(title: "App Icon") {
            LazyVGrid(columns: Self.columns, spacing: 18) {
                ForEach(options) { option in
                    tile(for: option)
                }
            }
            .padding(.vertical, 8)
            .animation(.snappy(duration: 0.2), value: activeAppIcon)

            if options.count == 1 {
                SettingsFootnote("More icons appear here as they're added to the app.")
            }
            if let failure {
                SettingsFootnote(failure, systemImageName: "exclamationmark.triangle")
            }
        }
        .task {
            // The system is the source of truth; a stored value that never
            // took (or a reinstall) must not show a stale ring.
            activeAppIcon = UIApplication.shared.alternateIconName ?? AppIconCatalog.primaryKey
        }
    }

    private func tile(for option: AppIconOption) -> some View {
        let isActive = activeAppIcon == option.storageKey
        return Button {
            Haptics.tap()
            Task { await select(option) }
        } label: {
            VStack(spacing: 8) {
                AppIconTile(option: option)
                    .frame(width: 68, height: 68)
                    .clipShape(.rect(cornerRadius: 15, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                            .padding(-5)
                            .opacity(isActive ? 1 : 0)
                    )
                Text(option.displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(isActive ? 0.9 : 0.6))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.displayName)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func select(_ option: AppIconOption) async {
        guard option.storageKey != activeAppIcon else { return }
        do {
            try await UIApplication.shared.setAlternateIconName(option.name)
            activeAppIcon = option.storageKey
            failure = nil
        } catch {
            // Leave the ring where it was; the system declined the change.
            failure = "Couldn't change the icon. \(error.localizedDescription)"
        }
    }
}

/// Renders an icon's artwork: an optional `<name>-preview` imageset wins,
/// otherwise the PNG the build copied out of the appiconset, otherwise the
/// primary's actool-emitted icon files.
struct AppIconTile: View {
    let option: AppIconOption

    var body: some View {
        if let image = AppIconImage.image(for: option) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    Image(systemName: "app.dashed")
                        .foregroundStyle(.white.opacity(0.4))
                )
        }
    }
}

@MainActor
enum AppIconImage {
    /// Decoded once per icon: the source PNGs are 1024 px.
    private static var cache: [String: UIImage] = [:]
    private static let thumbnailSide: CGFloat = 256

    static func image(for option: AppIconOption, info: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> UIImage? {
        if let cached = cache[option.storageKey] { return cached }
        let image = load(for: option, info: info)
        if let image { cache[option.storageKey] = image }
        return image
    }

    private static func load(for option: AppIconOption, info: [String: Any]) -> UIImage? {
        if let preview = UIImage(named: "\(option.storageKey)-preview") {
            return preview
        }
        if let url = Bundle.main.url(forResource: "\(option.storageKey)-icon-preview", withExtension: "png"),
           let full = UIImage(contentsOfFile: url.path) {
            return full.preparingThumbnail(of: CGSize(width: thumbnailSide, height: thumbnailSide)) ?? full
        }
        guard let icons = info["CFBundleIcons"] as? [String: Any] else { return nil }
        let entry: [String: Any]?
        if let name = option.name {
            entry = (icons["CFBundleAlternateIcons"] as? [String: Any])?[name] as? [String: Any]
        } else {
            entry = icons["CFBundlePrimaryIcon"] as? [String: Any]
        }
        guard let files = entry?["CFBundleIconFiles"] as? [String] else { return nil }
        for file in files.reversed() {
            if let image = UIImage(named: file) { return image }
        }
        return nil
    }
}

#Preview("App Icon") {
    NavigationStack {
        AppIconPickerView()
    }
    .fontDesign(.rounded)
    .preferredColorScheme(.dark)
}
