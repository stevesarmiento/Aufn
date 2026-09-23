import AVFAudio
import Testing
@testable import Aufn

/// The live meter must hear every channel of a stereo take: peak is the
/// loudest channel, RMS combines them.
struct MeterTapTests {
    private func makeBuffer(channelLevels: [Float], frames: AVAudioFrameCount = 480) throws -> AVAudioPCMBuffer {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: AVAudioChannelCount(channelLevels.count)))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for (channel, level) in channelLevels.enumerated() {
            for frame in 0..<Int(frames) {
                buffer.floatChannelData![channel][frame] = level
            }
        }
        return buffer
    }

    @Test func monoBufferMetersPeakAndRMS() throws {
        let meter = MeterTap()
        meter.process(try makeBuffer(channelLevels: [0.25]))
        #expect(abs(meter.levels.peak - 0.25) < 0.001)
        #expect(abs(meter.levels.rms - 0.25) < 0.001)
    }

    @Test func stereoBufferMetersEveryChannel() throws {
        let meter = MeterTap()
        meter.process(try makeBuffer(channelLevels: [0, 0.5]))
        #expect(abs(meter.levels.peak - 0.5) < 0.001)
        // Combined RMS of a silent and a 0.5 channel: sqrt((0 + 0.25) / 2).
        #expect(abs(meter.levels.rms - (0.125 as Float).squareRoot()) < 0.001)

        meter.process(try makeBuffer(channelLevels: [0.5, 0]))
        #expect(abs(meter.levels.peak - 0.5) < 0.001)
        #expect(abs(meter.levels.rms - (0.125 as Float).squareRoot()) < 0.001)
    }

    @Test func resetClearsLevels() throws {
        let meter = MeterTap()
        meter.process(try makeBuffer(channelLevels: [0.5]))
        meter.reset()
        #expect(meter.levels.peak == 0)
        #expect(meter.levels.rms == 0)
    }
}
