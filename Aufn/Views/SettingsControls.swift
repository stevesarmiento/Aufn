import SwiftUI
import UIKit

/// The settings design kit, ported from Lumo's settings: flat 7%-white cards
/// at radius 16, rounded bold type, soft haptics with a press-scale, and
/// accent check-circles for selection. Everything inside the workspace
/// settings sheet is built from these.

/// Imperative haptics for tap-driven feedback. Prefer
/// `.sensoryFeedback(_:trigger:)` when a state value already changes.
/// Generators are retained and re-prepared after each impact — a throwaway
/// generator deallocates before its player runs.
@MainActor
enum Haptics {
    private static let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)

    static func soft() {
        softGenerator.impactOccurred()
        softGenerator.prepare()
    }

    static func light() {
        lightGenerator.impactOccurred()
        lightGenerator.prepare()
    }
}

struct PressAnimation: ViewModifier {
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.90 : 1)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                withAnimation { isPressed = pressing }
            }, perform: {})
    }
}

extension View {
    func pressAnimation() -> some View {
        modifier(PressAnimation())
    }

    /// The settings card background shared by every row in the kit.
    func settingsCard(selected: Bool = false) -> some View {
        padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .foregroundStyle(Color.white.opacity(selected ? 0.1 : 0.07))
            )
    }
}

/// Rounded, brand-weight title for the settings navigation bars.
struct SettingsNavigationTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .bold()
            .font(.system(size: 20, design: .rounded))
            .foregroundStyle(.white.opacity(0.8))
    }
}

struct SettingsSectionHeader: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack {
            Text(text)
                .bold()
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 10)
    }
}

/// Navigation row: icon chip, bold rounded title, optional description,
/// chevron. Soft haptic on tap, press-scale while held.
struct SettingsLinkRow: View {
    var iconName: String
    var title: String
    var description: String = ""
    var chevronIconName: String = "chevron.forward"
    var navigateTo: () -> Void

    var body: some View {
        Button {
            Haptics.soft()
            navigateTo()
        } label: {
            HStack(alignment: .center) {
                HStack(alignment: description.isEmpty ? .center : .top) {
                    Image(systemName: iconName)
                        .font(.system(size: 16))
                        .bold()
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 28)
                        .padding(.trailing, 5)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .fontDesign(.rounded)
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                            .bold()

                        if !description.isEmpty {
                            Text(description)
                                .fontDesign(.rounded)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                                .multilineTextAlignment(.leading)
                        }
                    }
                }

                Spacer()

                Image(systemName: chevronIconName)
                    .font(.system(size: 16))
                    .bold()
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .foregroundStyle(Color.white.opacity(0.07))
            )
        }
        .buttonStyle(.plain)
        .pressAnimation()
        .accessibilityLabel(title)
    }
}

/// Toggle row: icon chip + title with an accent-tinted switch on a card.
struct SettingsToggle: View {
    let title: String
    let systemImageName: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Image(systemName: systemImageName)
                .font(.system(size: 16))
                .bold()
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 28)
                .padding(.trailing, 5)

            Text(title)
                .fontDesign(.rounded)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .bold()

            Spacer()

            Toggle("", isOn: $isOn)
                .tint(Color.accentColor)
                .accessibilityLabel(title)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .foregroundStyle(Color.white.opacity(0.07))
        )
    }
}

/// One selectable option: check-circle fills accent when chosen, dashed
/// circle otherwise, with the symbol morphing between the two. The selected
/// card sits slightly brighter.
struct SettingsOptionRow: View {
    var iconName: String? = nil
    var title: String
    var caption: String = ""
    var badge: String? = nil
    var selected: Bool
    var enabled: Bool = true
    var accessibilityLabelOverride: String? = nil
    var action: () -> Void

    var body: some View {
        Button {
            guard enabled else { return }
            Haptics.soft()
            action()
        } label: {
            HStack {
                if let iconName {
                    Image(systemName: iconName)
                        .font(.system(size: 16))
                        .bold()
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 28)
                        .padding(.trailing, 5)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .fontDesign(.rounded)
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                            .bold()
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: .capsule)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !caption.isEmpty {
                        Text(caption)
                            .fontDesign(.rounded)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace.offUp.byLayer))
            }
            .settingsCard(selected: selected)
        }
        .buttonStyle(.plain)
        .pressAnimation()
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .accessibilityLabel(accessibilityLabelOverride ?? title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Fine print under a section, in the kit's quiet rounded style.
struct SettingsFootnote: View {
    let text: String
    var systemImageName: String? = nil

    init(_ text: String, systemImageName: String? = nil) {
        self.text = text
        self.systemImageName = systemImageName
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let systemImageName {
                Image(systemName: systemImageName)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Text(text)
                .fontDesign(.rounded)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }
}

/// Chrome for a settings page: rounded title and the kit's padding. The
/// full-screen settings paints its black backdrop; a drawer floating over
/// another sheet skips it so the sheet's own glass shows through (the Lumo
/// SenkoSheet rule: never paint over the glass).
struct SettingsSubPage<Content: View>: View {
    let title: String
    var paintsBackdrop = true
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding()
            .padding(.horizontal, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background((paintsBackdrop ? Color.black : Color.clear).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                SettingsNavigationTitle(title)
            }
        }
    }
}
