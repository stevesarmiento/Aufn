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
    func process(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let frames = vDSP_Length(buffer.frameLength)
        var peak: Float = 0
        var rms: Float = 0
        vDSP_maxmgv(channels[0], 1, &peak, frames)
        vDSP_rmsqv(channels[0], 1, &rms, frames)
        let newLevels = Levels(peak: peak, rms: rms)
        state.withLock { $0 = newLevels }
    }

    var levels: Levels {
        state.withLock { $0 }
    }

    func reset() {
        state.withLock { $0 = Levels() }
    }
}
