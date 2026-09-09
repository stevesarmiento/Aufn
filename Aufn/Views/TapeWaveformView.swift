import SwiftUI

/// Shared geometry for the record head "lens" so the strip's magnified copy
/// (in MixWaveformView) and the button chrome (in TransportBar) stay aligned.
enum TapeHead {
    static let size = CGSize(width: 72, height: 100)
    static let magnification: CGFloat = 1.35
}

/// Stateless dot-matrix "tape" renderer. The strip is a timeline of 20 ms
/// bins flowing right-to-left under a fixed center point (the record head).
/// Bins left of center render in `playedTint` (committed to tape); bins right
/// of center render gray (upcoming). Columns outside the audio range — before
/// bin 0 or past the last bin — render as dim blank-tape placeholder dots, so
/// idle shows blank tape behind the head and recording shows blank tape ahead.
/// The caller animates by changing `centerBin` — no timers or engine here.
struct TapeWaveformView: View {
    let bins: [Float]
    let centerBin: Double
    var playedTint: Color = .accentColor

    // One column per 100 ms of tape; 6 pt pitch -> 60 pt/s scroll speed.
    private static let columnPitch: CGFloat = 6
    private static let dotDiameter: CGFloat = 3
    private static let dotPitch: CGFloat = 6
    private static let maxDots = 7
    private static let binsPerColumn = 5
    private static let silenceFloor: Float = 0.015

    var body: some View {
        Canvas { context, size in
            let pitch = Self.columnPitch
            let pointsPerBin = pitch / CGFloat(Self.binsPerColumn)
            let midX = size.width / 2
            let midY = size.height / 2

            // Column k covers bins [k*5, k*5+5); its center x under the head:
            // x = midX + (k*5 + 2.5 - centerBin) * pointsPerBin
            let minK = Int(floor((CGFloat(centerBin) * pointsPerBin - midX - pitch) / pitch))
            let maxK = Int(ceil((CGFloat(centerBin) * pointsPerBin + size.width - midX + pitch) / pitch))
            let audioColumns = (bins.count + Self.binsPerColumn - 1) / Self.binsPerColumn

            var playedPath = Path()
            var upcomingPath = Path()
            var blankPath = Path()

            for k in minK...maxK {
                let binStart = k * Self.binsPerColumn
                let x = midX + (CGFloat(binStart) + 2.5 - CGFloat(centerBin)) * pointsPerBin

                if k >= 0 && k < audioColumns {
                    let binEnd = min(binStart + Self.binsPerColumn, bins.count)
                    guard binStart < binEnd else { continue }
                    var amplitude: Float = 0
                    for index in binStart..<binEnd {
                        amplitude = max(amplitude, bins[index])
                    }
                    let dotCount = amplitude <= Self.silenceFloor
                        ? 1
                        : min(Self.maxDots, max(1, Int((amplitude * Float(Self.maxDots)).rounded(.up))))
                    if x < midX {
                        addColumn(dots: dotCount, x: x, midY: midY, to: &playedPath)
                    } else {
                        addColumn(dots: dotCount, x: x, midY: midY, to: &upcomingPath)
                    }
                } else {
                    // Deterministic 1-2 dot pattern keyed on the absolute column
                    // index so blank tape scrolls without shimmering.
                    let hashed = UInt64(bitPattern: Int64(k)) &* 2_654_435_761
                    let dots = 1 + Int((hashed >> 30) & 1)
                    addColumn(dots: dots, x: x, midY: midY, to: &blankPath)
                }
            }

            context.fill(playedPath, with: .color(playedTint))
            context.fill(upcomingPath, with: .color(.gray.opacity(0.45)))
            context.fill(blankPath, with: .color(.gray.opacity(0.22)))
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.07),
                    .init(color: .black, location: 0.93),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    private func addColumn(dots: Int, x: CGFloat, midY: CGFloat, to path: inout Path) {
        let radius = Self.dotDiameter / 2
        for index in 0..<dots {
            let y = midY + (CGFloat(index) - CGFloat(dots - 1) / 2) * Self.dotPitch
            path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: Self.dotDiameter, height: Self.dotDiameter))
        }
    }
}

#Preview("Tape states", traits: .sizeThatFitsLayout) {
    let synthetic: [Float] = (0..<600).map { index in
        abs(sin(Double(index) * 0.09)) > 0.3 ? Float(abs(sin(Double(index) * 0.21))) : 0.05
    }
    return VStack(spacing: 20) {
        TapeWaveformView(bins: [], centerBin: 0)
            .frame(height: 48)
        TapeWaveformView(bins: synthetic, centerBin: 0)
            .frame(height: 48)
        TapeWaveformView(bins: synthetic, centerBin: 300)
            .frame(height: 48)
        TapeWaveformView(bins: synthetic, centerBin: Double(synthetic.count))
            .frame(height: 48)
    }
    .padding()
    .background(.black)
}
