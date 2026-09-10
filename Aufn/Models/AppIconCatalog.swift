import Foundation

/// One entry in the App Icon picker. `name` is the alternate icon's asset
/// name; nil is the primary icon.
struct AppIconOption: Identifiable, Equatable, Hashable {
    let name: String?
    let displayName: String

    var id: String { storageKey }
    /// What `activeAppIcon` stores; the primary uses a sentinel.
    var storageKey: String { name ?? AppIconCatalog.primaryKey }
}

/// Discovers alternate icons from the built Info.plist so a new
/// `.appiconset` shows up in the picker without a code change (the catalog is
/// compiled with INCLUDE_ALL_APPICON_ASSETS). Names here only add polish.
enum AppIconCatalog {
    static let primaryKey = "AppIcon"
    static let primaryDisplayName = "Default"

    /// Optional pretty names, keyed by appiconset name.
    static let displayNames: [String: String] = [:]

    /// Icons listed here come first, in this order; the rest follow alphabetically.
    static let preferredOrder: [String] = []

    static var options: [AppIconOption] {
        options(from: Bundle.main.infoDictionary ?? [:])
    }

    static func options(
        from info: [String: Any],
        preferredOrder: [String] = preferredOrder,
        displayNames: [String: String] = displayNames
    ) -> [AppIconOption] {
        let icons = info["CFBundleIcons"] as? [String: Any]
        let alternates = (icons?["CFBundleAlternateIcons"] as? [String: Any])?.keys.map { $0 } ?? []
        let preferred = preferredOrder.filter { alternates.contains($0) }
        let rest = alternates.filter { !preferred.contains($0) }.sorted()
        let primary = AppIconOption(name: nil, displayName: primaryDisplayName)
        return [primary] + (preferred + rest).map { name in
            AppIconOption(name: name, displayName: displayNames[name] ?? fallbackDisplayName(for: name))
        }
    }

    /// "aufn-dark" → "Aufn Dark"
    static func fallbackDisplayName(for name: String) -> String {
        name.split { $0 == "-" || $0 == "_" }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    static func option(forStorageKey key: String) -> AppIconOption? {
        options.first { $0.storageKey == key }
    }
}
