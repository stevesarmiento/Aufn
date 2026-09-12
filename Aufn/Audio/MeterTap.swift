import AVFAudio
import Accelerate
import os

/// Lock-protected level shared between the input tap thread and the UI.
/// The tap writes peak/RMS via vDSP; TimelineView-driven views poll `levels`.
final class MeterTap: Sendable {
    struct Levels {
        var peak: Float = 0
        var rms: Float = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: Levels())

    /// Called from the tap thread. No allocation, no logging, no actor hops.
    /// Peak is the loudest channel; RMS combines all channels (identical to
    /// the single-channel RMS for mono).
    func process(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let frames = vDSP_Length(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var peak: Float = 0
        var meanSquareSum: Float = 0
        for channel in 0..<channelCount {
            var channelPeak: Float = 0
            var channelRMS: Float = 0
            vDSP_maxmgv(channels[channel], 1, &channelPeak, frames)
            vDSP_rmsqv(channels[channel], 1, &channelRMS, frames)
            peak = max(peak, channelPeak)
            meanSquareSum += channelRMS * channelRMS
        }
        let newLevels = Levels(peak: peak, rms: (meanSquareSum / Float(channelCount)).squareRoot())
        state.withLock { $0 = newLevels }
    }

    var levels: Levels {
        state.withLock { $0 }
    }

    func reset() {
        state.withLock { $0 = Levels() }
    }
}
