import SwiftUI

/// Symmetric waveform rendered from cached peak bins. Downsamples bins to
/// pixel columns in a Canvas — never touches audio files.
struct WaveformView: View {
    let peaks: [Float]
    var tint: Color = .accentColor

    var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty else { return }
            let columnWidth: CGFloat = 3
            let gap: CGFloat = 1
            let columns = max(1, Int(size.width / (columnWidth + gap)))
            let binsPerColumn = max(1, peaks.count / columns)
            let midY = size.height / 2

            var path = Path()
            for column in 0..<columns {
                let start = column * binsPerColumn
                guard start < peaks.count else { break }
                let end = min(start + binsPerColumn, peaks.count)
                let peak = peaks[start..<end].max() ?? 0
                let height = max(2, CGFloat(peak) * size.height)
                let x = CGFloat(column) * (columnWidth + gap)
                path.addRoundedRect(
                    in: CGRect(x: x, y: midY - height / 2, width: columnWidth, height: height),
                    cornerSize: CGSize(width: 1.5, height: 1.5)
                )
            }
            context.fill(path, with: .color(tint))
        }
    }
}
