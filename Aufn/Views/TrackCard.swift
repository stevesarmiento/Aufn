import SwiftUI

/// Flat container for track rows (glass proved heavy with many rows). Clips
/// full-bleed content (the dot-matrix waveform) to the card shape.
struct TrackCard<Content: View>: View {
    var selected = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            // One notch brighter when selected — the same ratio the settings
            // kit uses for a chosen option row.
            .background(.white.opacity(selected ? 0.10 : 0.06), in: .rect(cornerRadius: 16))
            .clipShape(.rect(cornerRadius: 16))
            .animation(.snappy, value: selected)
    }
}

/// Leading check in a card header while the list is in selection mode: a
/// filled accent check when selected, a dashed ring otherwise, morphing the
/// same way the settings option rows do. The row carries the accessibility
/// trait, so this is decorative.
struct SelectionCheck: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle.dashed")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))
            .contentTransition(.symbolEffect(.replace.offUp.byLayer))
            .animation(.snappy, value: isSelected)
            .accessibilityHidden(true)
    }
}

/// Compact custom toggle for the track header (M / S / mixer disclosure).
/// Filled with its tint when on; quiet outline when off.
struct RoundToggle: View {
    var letter: String? = nil
    var systemImage: String? = nil
    let isOn: Bool
    let tint: Color
    let label: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isOn ? AnyShapeStyle(tint) : AnyShapeStyle(.white.opacity(0.06)))
                Circle()
                    .strokeBorder(.white.opacity(isOn ? 0 : 0.12), lineWidth: 1)
                Group {
                    if let letter {
                        Text(letter).font(.caption2.bold())
                    } else if let systemImage {
                        Image(systemName: systemImage).font(.system(size: 11, weight: .bold))
                    }
                }
                .foregroundStyle(isOn ? AnyShapeStyle(.black) : AnyShapeStyle(.secondary))
            }
            .frame(width: 26, height: 26)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // Quiet while the row is in selection mode (the card is disabled).
        .opacity(isEnabled ? 1 : 0.4)
        .animation(.snappy, value: isOn)
        .animation(.snappy, value: isEnabled)
        .sensoryFeedback(.impact(weight: .medium), trigger: isOn)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

#Preview("Track card", traits: .sizeThatFitsLayout) {
    VStack(spacing: 12) {
        TrackCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Track 1").font(.subheadline.weight(.semibold))
                    Spacer()
                    RoundToggle(letter: "M", isOn: false, tint: .orange, label: "Mute") {}
                    RoundToggle(letter: "S", isOn: true, tint: .yellow, label: "Solo") {}
                    RoundToggle(systemImage: "slider.horizontal.3", isOn: false, tint: .accentColor, label: "Mixer") {}
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                WaveformView(peaks: PreviewData.peaks(), tint: .gray.opacity(0.45))
                    .frame(height: 48)
                    .padding(.bottom, 12)
            }
        }
    }
    .padding()
    .frame(width: 360)
    .fontDesign(.rounded)
    .preferredColorScheme(.dark)
}
