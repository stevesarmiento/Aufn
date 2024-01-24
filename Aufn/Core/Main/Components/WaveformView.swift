import Foundation
import SwiftUI

struct WaveformView: View {
    @Binding var audioLevels: [CGFloat]
    @Binding var isRecording: Bool
    @State private var orbScale: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                 // Glowing horizontal oval
                Ellipse()
                    .fill(RadialGradient(gradient: Gradient(colors: [isRecording ? Color.red.opacity(0.1) : Color.yellow.opacity(0.1), Color.clear]), center: .center, startRadius: 0, endRadius: geometry.size.height / 2))
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(x: orbScale, y: 1)
                    .onAppear {
                        withAnimation(Animation.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                            orbScale = 2
                        }
                    }
                // Microphone image
                Image("backscreen")
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .opacity(1)
//                    .mask(
//                        RadialGradient(
//                            gradient: Gradient(colors: [.white, .clear]),
//                            center: .center,
//                            startRadius: 0,
//                            endRadius: min(geometry.size.width, geometry.size.height) / 2
//                        )
//                    )                
                
                // Tape-like pattern
                // RoundedRectangle(cornerRadius: 0)
                //     .fill(Color.gray.opacity(1))
                //     .frame(height: geometry.size.height)
                //     .mask(TapePatternView().opacity(0.5))

                // Central waveform
                CentralWaveformView(audioLevels: $audioLevels, isRecording: $isRecording)
            }
        }
    }
}

// struct TapePatternView: View {
//     var body: some View {
//         GeometryReader { geometry in
//             Path { path in
//                 let width = geometry.size.width
//                 let height = geometry.size.height
//                 let tapeSegmentHeight: CGFloat = 10

//                 for i in stride(from: 0, through: height, by: tapeSegmentHeight * 2) {
//                     path.move(to: CGPoint(x: 0, y: i))
//                     path.addRect(CGRect(x: 0, y: i, width: width, height: tapeSegmentHeight))
//                 }
//             }
//             .mask(
//                 RadialGradient(
//                     gradient: Gradient(colors: [.white, .clear]),
//                     center: .center,
//                     startRadius: 0,
//                     endRadius: min(geometry.size.width, geometry.size.height) / 2
//                 )
//             )
//         }
//     }
// }


struct CentralWaveformView: View {
    @Binding var audioLevels: [CGFloat]
    @Binding var isRecording: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                waveformPath(audioLevels: audioLevels, centerY: geometry.size.height / 2, tapeGap: geometry.size.height / 6, lineWidth: 5, opacity: 0.1)
                waveformPath(audioLevels: audioLevels, centerY: geometry.size.height / 2, tapeGap: geometry.size.height / 6, lineWidth: 3, opacity: 0.3)
                waveformPath(audioLevels: audioLevels, centerY: geometry.size.height / 2, tapeGap: geometry.size.height / 6, lineWidth: 1, opacity: 1)
            }
        }
    }
    
    func waveformPath(audioLevels: [CGFloat], centerY: CGFloat, tapeGap: CGFloat, lineWidth: CGFloat, opacity: Double) -> some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width / CGFloat(audioLevels.count)

                for (index, level) in audioLevels.enumerated() {
                    let x = CGFloat(index) * width
                    let y1 = centerY - level * tapeGap
                    let y2 = centerY + level * tapeGap

                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y1))
                    } else {
                        path.addCurve(
                            to: CGPoint(x: x, y: y1),
                            control1: CGPoint(x: x - width / 2, y: path.currentPoint!.y),
                            control2: CGPoint(x: x - width / 2, y: y1)
                        )
                    }
                    path.addCurve(
                        to: CGPoint(x: x, y: y2),
                        control1: CGPoint(x: x, y: centerY),
                        control2: CGPoint(x: x, y: centerY)
                    )
                }
            }
            .stroke(isRecording ? Color.red.opacity(opacity) : Color.orange.opacity(opacity), lineWidth: lineWidth)
            .mask(
                RadialGradient(
                    gradient: Gradient(colors: [.white, .clear]),
                    center: .center,
                    startRadius: 0,
                    endRadius: min(geometry.size.width, geometry.size.height) / 2
                )
            )
        }
    }
}
