import Testing
@testable import Aufn

struct AppIconCatalogTests {
    private func info(alternates: [String]) -> [String: Any] {
        var alt: [String: Any] = [:]
        for name in alternates {
            alt[name] = ["CFBundleIconFiles": ["\(name)60x60"]]
        }
        return [
            "CFBundleIcons": [
                "CFBundlePrimaryIcon": ["CFBundleIconFiles": ["AppIcon60x60"]],
                "CFBundleAlternateIcons": alt,
            ],
        ]
    }

    @Test func emptyInfoYieldsOnlyDefault() {
        let options = AppIconCatalog.options(from: [:])
        #expect(options.map(\.displayName) == ["Default"])
        #expect(options[0].name == nil)
        #expect(options[0].storageKey == "AppIcon")
    }

    @Test func preferredOrderFirstThenAlphabeticalWithFallbackNames() {
        let options = AppIconCatalog.options(
            from: info(alternates: ["zed", "aufn-dark", "mono", "aufn_gold"]),
            preferredOrder: ["mono", "missing", "zed"],
            displayNames: ["mono": "Mono"]
        )
        #expect(options.map(\.name) == [nil, "mono", "zed", "aufn-dark", "aufn_gold"])
        #expect(options.map(\.displayName) == ["Default", "Mono", "Zed", "Aufn Dark", "Aufn Gold"])
    }

    /// A typo in `preferredOrder` would silently drop the icon back into the
    /// alphabetical tail with a fallback name instead of failing loudly.
    @Test func everyPreferredIconHasADisplayName() {
        for name in AppIconCatalog.preferredOrder {
            #expect(AppIconCatalog.displayNames[name] != nil, "\(name) is ordered but unnamed")
        }
    }

    /// The names shipped in the catalog must match real appiconset folders,
    /// which is what the built plist lists.
    @Test func shippedIconsResolveInOrderWithTheirNames() {
        let options = AppIconCatalog.options(
            from: info(alternates: ["aufn-blueprint", "aufn-retro"])
        )
        #expect(options.map(\.name) == [nil, "aufn-retro", "aufn-blueprint"])
        #expect(options.map(\.displayName) == ["Default", "Retro", "Blueprint"])
    }
}
