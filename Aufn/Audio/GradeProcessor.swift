import AVFAudio
import Accelerate
import Foundation

/// Prints a grade onto tap buffers, in place, before they reach the recorder.
/// Built on the main actor once per take; after that only the tap thread
/// touches it, and nothing else reads it, so no lock is needed (the tap
/// closure owns the last reference and may release it on its own thread —
/// keep deinit trivial). Sample rate and channel count cannot change under a
/// live tap, so every coefficient is fixed at init.
final class GradeProcessor: @unchecked Sendable {
    /// Clean gain ahead of every grade, RAW included. `.measurement` input
    /// has no automatic gain and the built-in mic lands well below where
    /// Apple's chain used to put it; this recovers a little of that without
    /// coloring anything. The ceiling clip below keeps a shout in range.
    static let inputTrimDB: Float = 2.5

    private let channelCount: Int
    private let inputTrimLinear: Float?
    /// bands[band][channel]
    private var bands: [[BiquadState]]
    private let compressor: Compressor?
    private let saturationDrive: Float?
    private let trimLinear: Float?

    /// nil when neither the trim nor the settings would touch the audio, so
    /// the tap pays nothing and the buffer is bit-identical to the input.
    init?(settings: GradeSettings, inputTrimDB: Float = GradeProcessor.inputTrimDB, sampleRate: Double, channelCount: Int) {
        guard !settings.isIdentity || inputTrimDB != 0, channelCount > 0 else { return nil }
        self.channelCount = channelCount
        inputTrimLinear = inputTrimDB == 0 ? nil : pow(10, inputTrimDB / 20)
        bands = settings.eq.compactMap { band in
            BiquadCoefficients.make(band, sampleRate: sampleRate).map { coefficients in
                (0..<channelCount).map { _ in BiquadState(coefficients: coefficients) }
            }
        }
        compressor = settings.compressor.map { Compressor(settings: $0, sampleRate: sampleRate) }
        saturationDrive = settings.saturationDrive
        trimLinear = settings.trimDB == 0 ? nil : pow(10, settings.trimDB / 20)
    }

    /// Input trim → EQ → compressor → soft clip → trim → hard ceiling. The ceiling is
    /// bit-transparent unless exceeded: a feed-forward compressor passes the
    /// first attack-time of a transient at makeup gain, and playback/export
    /// would clip anything over full scale.
    func process(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData,
              Int(buffer.format.channelCount) == channelCount,
              buffer.frameLength > 0 else { return }
        let frames = Int(buffer.frameLength)

        if var inputTrimLinear {
            for channel in 0..<channelCount {
                vDSP_vsmul(channels[channel], 1, &inputTrimLinear, channels[channel], 1, vDSP_Length(frames))
            }
        }
        for band in bands.indices {
            for channel in 0..<channelCount {
                bands[band][channel].process(channels[channel], count: frames)
            }
        }
        compressor?.process(channels: channels, channelCount: channelCount, frames: frames)

        var low: Float = -1
        var high: Float = 1
        for channel in 0..<channelCount {
            let samples = channels[channel]
            if let saturationDrive {
                SoftClip.process(samples, count: frames, drive: saturationDrive)
            }
            if var trimLinear {
                vDSP_vsmul(samples, 1, &trimLinear, samples, 1, vDSP_Length(frames))
            }
            vDSP_vclip(samples, 1, &low, &high, samples, 1, vDSP_Length(frames))
        }
    }
}
