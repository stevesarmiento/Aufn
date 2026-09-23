import Foundation
import SwiftUI

struct WaveformView: View {
    @Binding var audioLevels: [CGFloat]
    @Binding var isRecording: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Tape-like pattern
                RoundedRectangle(cornerRadius: 0)
                    .fill(Color.gray.opacity(0.2))
                    .mask(TapePatternView().opacity(0.5))

                // Central waveform
                CentralWaveformView(audioLevels: $audioLevels, isRecording: $isRecording)
            }
        }
    }
}

struct TapePatternView: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                let tapeSegmentHeight: CGFloat = 10

                for i in stride(from: 0, through: height, by: tapeSegmentHeight * 2) {
                    path.move(to: CGPoint(x: 0, y: i))
                    path.addRect(CGRect(x: 0, y: i, width: width, height: tapeSegmentHeight))
                }
            }.mask(LinearGradient(gradient: Gradient(colors: [.clear, .white, .clear]), startPoint: .leading, endPoint: .trailing))

        }
    }
}

struct CentralWaveformView: View {
    @Binding var audioLevels: [CGFloat]
    @Binding var isRecording: Bool

    var body: some View {
        GeometryReader { geometry in
            ForEach(0..<7) { lineIndex in
                Path { path in
                    let width = geometry.size.width / CGFloat(audioLevels.count)
                    let centerY = geometry.size.height / 2
                    let tapeGap = geometry.size.height / 6

                    for (index, level) in audioLevels.enumerated() {
                        let x = CGFloat(index) * width
                        let y1 = centerY - level * tapeGap * CGFloat(lineIndex + 1)
                        let y2 = centerY + level * tapeGap * CGFloat(lineIndex + 1)

                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y1))
                        } else {
                            path.addQuadCurve(
                                to: CGPoint(x: x, y: y1),
                                control: CGPoint(x: x - width / 2, y: (y1 + path.currentPoint!.y) / 2)
                            )
                        }
                        path.addQuadCurve(
                            to: CGPoint(x: x, y: y2),
                            control: CGPoint(x: x, y: centerY)
                        )
                    }
                }
                .stroke(isRecording ? Color.red : Color.blue, lineWidth: 2)
                .mask(LinearGradient(gradient: Gradient(colors: [.clear, .white, .clear]), startPoint: .leading, endPoint: .trailing))
            }
        }
    }
}



