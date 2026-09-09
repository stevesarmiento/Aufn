import SwiftUI

/// Dot-matrix waveform rendered from cached peak bins — same visual language
/// as the transport's tape strip (3 pt dots on a 6 pt pitch, amplitude = dot
/// count). Downsamples bins to columns in a Canvas — never touches audio files.
struct WaveformView: View {
    let peaks: [Float]
    var tint: Color = .gray.opacity(0.45)

    private static let columnPitch: CGFloat = 6
    private static let dotDiameter: CGFloat = 3
    private static let dotPitch: CGFloat = 6
    private static let silenceFloor: Float = 0.015

    var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty else { return }
            let maxDots = max(1, min(7, Int(size.height / Self.dotPitch)))
            let columns = max(1, Int(size.width / Self.columnPitch))
            let binsPerColumn = max(1, peaks.count / columns)
            let midY = size.height / 2
            let radius = Self.dotDiameter / 2

            var path = Path()
            for column in 0..<columns {
                let start = column * binsPerColumn
                guard start < peaks.count else { break }
                let end = min(start + binsPerColumn, peaks.count)
                let peak = peaks[start..<end].max() ?? 0
                let dotCount = peak <= Self.silenceFloor
                    ? 1
                    : min(maxDots, max(1, Int((peak * Float(maxDots)).rounded(.up))))
                let x = CGFloat(column) * Self.columnPitch + Self.columnPitch / 2
                for index in 0..<dotCount {
                    let y = midY + (CGFloat(index) - CGFloat(dotCount - 1) / 2) * Self.dotPitch
                    path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: Self.dotDiameter, height: Self.dotDiameter))
                }
            }
            context.fill(path, with: .color(tint))
        }
    }
}

#Preview("Waveforms", traits: .sizeThatFitsLayout) {
    VStack(spacing: 20) {
        WaveformView(peaks: PreviewData.peaks())
            .frame(height: 48)
        WaveformView(peaks: PreviewData.peaks(seed: 0.05))
            .frame(height: 48)
            .opacity(0.4)
        WaveformView(peaks: PreviewData.peaks(bins: 300), tint: .red)
            .frame(height: 48)
    }
    .padding()
    .frame(width: 340)
    .preferredColorScheme(.dark)
}
