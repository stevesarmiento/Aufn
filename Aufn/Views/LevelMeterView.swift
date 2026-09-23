import SwiftUI

/// Input level bar with peak hold, polled from the MeterTap at display rate.
struct LevelMeterView: View {
    let meter: MeterTap

    @State private var peakHold: Float = 0
    @State private var peakHoldDate: Date = .distantPast

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let levels = meter.levels
                let level = CGFloat(min(1, levels.peak))
                let now = timeline.date

                let barRect = CGRect(x: 0, y: 0, width: size.width * level, height: size.height)
                let gradient = Gradient(colors: [.green, .green, .yellow, .red])
                context.fill(
                    Path(roundedRect: barRect, cornerRadius: size.height / 2),
                    with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
                )

                let hold = holdValue(current: levels.peak, at: now)
                if hold > 0.01 {
                    let x = size.width * CGFloat(min(1, hold))
                    context.fill(
                        Path(CGRect(x: max(0, x - 2), y: 0, width: 2, height: size.height)),
                        with: .color(.white.opacity(0.9))
                    )
                }
            }
        }
        .frame(height: 4)
        .background(.quaternary, in: .capsule)
    }

    private func holdValue(current: Float, at now: Date) -> Float {
        if current >= peakHold || now.timeIntervalSince(peakHoldDate) > 1.5 {
            // Canvas draw closures can't mutate @State directly mid-render;
            // schedule the update out-of-band.
            Task { @MainActor in
                peakHold = current
                peakHoldDate = now
            }
            return current
        }
        return peakHold
    }
}

#Preview("Levels", traits: .sizeThatFitsLayout) {
    VStack(spacing: 16) {
        LevelMeterView(meter: PreviewData.meter(level: 0.35))
        LevelMeterView(meter: PreviewData.meter(level: 0.7))
        LevelMeterView(meter: PreviewData.meter(level: 0.98))
    }
    .padding()
    .frame(width: 340)
    .preferredColorScheme(.dark)
}
