import SwiftUI

/// The metronome row's live element, sized for the header slot where an icon
/// would sit: a small dot cluster (columns of 2·4·4·2 dots, same 3 pt dot
/// idiom as the waveforms) that pulses on every beat — accent-tinted on the
/// downbeat, white on the rest. `clickStartDate` anchors the beat phase to
/// the moment the click's beat 1 sounds; nil rests the cluster as a dim,
/// static glyph.
struct MetronomeBeatGridView: View {
    let settings: MetronomeSettings
    let clickStartDate: Date?

    private static let columnDots = [2, 4, 4, 2]
    private static let dotDiameter: CGFloat = 3
    private static let dotPitch: CGFloat = 6
    /// Pulse decay constant: bright at the tick, faded well before the next
    /// beat even at 240 BPM (period 250 ms).
    private static let decay = 0.08

    var body: some View {
        TimelineView(.animation(paused: clickStartDate == nil)) { context in
            Canvas { graphics, size in
                var pulse = 0.0
                var isDownbeat = false
                if let clickStartDate {
                    let beatDuration = 60.0 / Double(settings.bpm)
                    let elapsed = max(0, context.date.timeIntervalSince(clickStartDate))
                    let beatIndex = Int(elapsed / beatDuration)
                    let beatPhase = elapsed - Double(beatIndex) * beatDuration
                    pulse = exp(-beatPhase / Self.decay)
                    isDownbeat = beatIndex % settings.beatsPerBar == 0
                }

                let color: Color
                if clickStartDate == nil {
                    color = Color.gray.opacity(0.45)
                } else {
                    let tint: Color = isDownbeat ? .accentColor : .white
                    color = tint.opacity(0.4 + 0.6 * pulse)
                }
                let radius = Self.dotDiameter / 2 + 0.7 * pulse

                var path = Path()
                let midX = size.width / 2
                let midY = size.height / 2
                let columns = Self.columnDots.count
                for (column, dots) in Self.columnDots.enumerated() {
                    let x = midX + (CGFloat(column) - CGFloat(columns - 1) / 2) * Self.dotPitch
                    for index in 0..<dots {
                        let y = midY + (CGFloat(index) - CGFloat(dots - 1) / 2) * Self.dotPitch
                        path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                    }
                }
                graphics.fill(path, with: .color(color))
            }
        }
        .frame(width: 28, height: 26)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Beat grid states", traits: .sizeThatFitsLayout) {
    HStack(spacing: 24) {
        MetronomeBeatGridView(settings: MetronomeSettings(), clickStartDate: nil)
        MetronomeBeatGridView(settings: MetronomeSettings(), clickStartDate: .now)
        MetronomeBeatGridView(settings: MetronomeSettings(bpm: 60, beatsPerBar: 1), clickStartDate: .now)
    }
    .padding()
    .preferredColorScheme(.dark)
}
