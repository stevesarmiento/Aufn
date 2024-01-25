import Foundation
import SwiftUI

struct WaveformView: View {
    @Binding var audioLevels: [CGFloat]
    @Binding var isRecording: Bool
    @State private var orbScale: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            ZStack {

                if isRecording {
                    withAnimation(.easeInOut(duration: 1)) {
                        Image("backscreen")
                            .resizable()
                            .scaledToFit()
                            .opacity(1)
                            .transition(.opacity)
                    }
                } else {
                    withAnimation(.easeInOut(duration: 1)) {
                        Image("backscreenoff")
                            .resizable()
                            .scaledToFit()
                            .opacity(1)
                            .transition(.opacity)
                    }
                }

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
