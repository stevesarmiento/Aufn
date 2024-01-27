//
//  WaveformSliderView.swift
//  Aufn
//
//  Created by Steven Sarmiento on 1/26/24.
//

import SwiftUI
import AVFoundation

struct WaveformSliderView: View {
    @Binding var audioFile: AVAudioFile?
    @Binding var currentTime: TimeInterval

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let audioLevels = self.getAudioLevels()
                let width = geometry.size.width / CGFloat(audioLevels.count * 2)

                for (index, level) in audioLevels.enumerated() {
                    let x = CGFloat(index) * width
                    let y = CGFloat(level * 2) * geometry.size.height
                    path.addRect(CGRect(x: x, y: geometry.size.height - y, width: width, height: y))
                }
            }
            .fill(LinearGradient(gradient: Gradient(colors: [Color.red, Color.blue]), startPoint: .leading, endPoint: .trailing))
            .gesture(DragGesture(minimumDistance: 0).onChanged({ value in
                let duration = Double(audioFile?.length ?? 0) / Double(audioFile?.fileFormat.sampleRate ?? 1)
                self.currentTime = Double(value.location.x / geometry.size.width) * duration
            }))
        }
    }

    private func getAudioLevels() -> [Float] {
        guard let audioFile = audioFile else {
            return [Float]()
        }

       // let sampleRate = Int(audioFile.fileFormat.sampleRate)
        let length = Int(audioFile.length)
        let numberOfSamples = 1024
        let strideLength = max(length / numberOfSamples, 1)
        

        var audioLevels = [Float]()
        do {
            let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: AVAudioFrameCount(length))!
            try audioFile.read(into: buffer)

            let channelData = buffer.floatChannelData![0]
            for index in stride(from: 0, to: length, by: strideLength) {
                let sample = channelData[index]
                let level = abs(sample)
                audioLevels.append(level)
            }

        } catch {
            print("Error reading audio file: \(error)")
        }

        return audioLevels
    }
}
