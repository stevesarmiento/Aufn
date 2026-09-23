import AVFAudio
import Foundation
import Testing
@testable import Aufn

/// The primitives against their analytic responses: RBJ checkpoints for the
/// biquads, DC steady states for the compressor, and the soft clip's bounds.
struct GradeDSPTests {
    private typealias S = GradeTestSupport

    private func filter(_ band: EQBand, _ buffer: AVAudioPCMBuffer, channel: Int = 0) throws {
        let coefficients = try #require(BiquadCoefficients.make(band, sampleRate: S.sampleRate))
        var state = BiquadState(coefficients: coefficients)
        state.process(buffer.floatChannelData![channel], count: Int(buffer.frameLength))
    }

    private func dcGainDB(_ band: EQBand) throws -> Float {
        let buffer = try S.dc(0.5, seconds: 0.5)
        try filter(band, buffer)
        return S.dB(S.rms(buffer, from: 9_600, count: 9_600) / 0.5)
    }

    private func nyquistGainDB(_ band: EQBand) throws -> Float {
        let buffer = try S.nyquist(amplitude: 0.5, seconds: 0.5)
        try filter(band, buffer)
        return S.dB(S.rms(buffer, from: 9_600, count: 9_600) / 0.5)
    }

    private func sineGainDB(_ band: EQBand, frequency: Double) throws -> Float {
        let buffer = try S.sine(frequency: frequency, amplitude: 0.5, seconds: 3)
        try filter(band, buffer)
        return S.steadyGainDB(buffer, frequency: frequency, amplitude: 0.5, discard: 0.2)
    }

    // MARK: - Biquad

    @Test func lowShelfEndpoints() throws {
        let band = EQBand(kind: .lowShelf, frequency: 100, gainDB: 6, q: 0.7071)
        #expect(abs(try dcGainDB(band) - 6) < 0.05)
        #expect(abs(try nyquistGainDB(band)) < 0.05)
    }

    @Test func highShelfEndpoints() throws {
        let band = EQBand(kind: .highShelf, frequency: 8_000, gainDB: -6, q: 0.7071)
        #expect(abs(try nyquistGainDB(band) + 6) < 0.05)
        #expect(abs(try dcGainDB(band)) < 0.05)
    }

    @Test func shelfHasHalfGainAtCornerFrequency() throws {
        let band = EQBand(kind: .lowShelf, frequency: 100, gainDB: 6, q: 0.7071)
        #expect(abs(try sineGainDB(band, frequency: 100) - 3) < 0.1)
    }

    @Test func peakCenterAndSkirts() throws {
        let band = EQBand(kind: .peak, frequency: 1_000, gainDB: 6, q: 1)
        #expect(abs(try sineGainDB(band, frequency: 1_000) - 6) < 0.1)
        #expect(abs(try dcGainDB(band)) < 0.05)
        #expect(abs(try nyquistGainDB(band)) < 0.05)
    }

    @Test func highPassResponse() throws {
        let band = EQBand(kind: .highPass, frequency: 40, gainDB: 0, q: 0.7071)
        let dc = try S.dc(0.5, seconds: 0.5)
        try filter(band, dc)
        #expect(S.rms(dc, from: 9_600, count: 9_600) < 1e-4)
        #expect(abs(try sineGainDB(band, frequency: 40) + 3.01) < 0.15)
        #expect(abs(try sineGainDB(band, frequency: 1_000)) < 0.02)
        #expect(abs(try nyquistGainDB(band)) < 0.05)
    }

    @Test func zeroGainBandIsBypassed() throws {
        #expect(BiquadCoefficients.make(EQBand(kind: .lowShelf, frequency: 100, gainDB: 0, q: 0.7071), sampleRate: 48_000) == nil)
        #expect(BiquadCoefficients.make(EQBand(kind: .peak, frequency: 1_000, gainDB: 0, q: 1), sampleRate: 48_000) == nil)
        #expect(BiquadCoefficients.make(EQBand(kind: .highPass, frequency: 40, gainDB: 0, q: 0.7071), sampleRate: 48_000) != nil)
    }

    @Test func coefficientsAreNormalized() throws {
        let band = EQBand(kind: .lowShelf, frequency: 100, gainDB: 6, q: 0.7071)
        let coefficients = try #require(BiquadCoefficients.make(band, sampleRate: 48_000))
        // Low shelf DC gain is A² = 10^(6/20). Evaluated from the Float
        // coefficients, where 1 + a1 + a2 cancels to ~0.01, so allow ~1e-3
        // (0.005 dB); the audio-domain DC test above is the real check.
        #expect(abs(coefficients.dcGain - pow(10, 6.0 / 20)) < 2e-3)
    }

    @Test func stateIsPerChannel() throws {
        let band = EQBand(kind: .lowShelf, frequency: 100, gainDB: 6, q: 0.7071)
        let stereo = try S.sine(frequency: 100, amplitude: 0.5, seconds: 0.5, channels: 2)
        S.fill(stereo, channel: 1) { _ in 0 }
        let mono = try S.sine(frequency: 100, amplitude: 0.5, seconds: 0.5)
        try filter(band, stereo, channel: 0)
        try filter(band, stereo, channel: 1)
        try filter(band, mono)
        #expect(S.samples(of: stereo, channel: 1).allSatisfy { $0 == 0 })
        #expect(S.samples(of: stereo, channel: 0) == S.samples(of: mono))
    }

    // MARK: - Compressor

    private func compress(_ settings: CompressorSettings, _ buffer: AVAudioPCMBuffer) {
        let compressor = Compressor(settings: settings, sampleRate: S.sampleRate)
        compressor.process(channels: buffer.floatChannelData!, channelCount: Int(buffer.format.channelCount), frames: Int(buffer.frameLength))
    }

    private func tailGainDB(_ buffer: AVAudioPCMBuffer, channel: Int = 0, input: Float) -> Float {
        let frames = Int(buffer.frameLength)
        return S.dB(S.rms(buffer, channel: channel, from: frames - 4_800, count: 4_800) / input)
    }

    private let tapeComp = CompressorSettings(thresholdDB: -20, ratio: 1.5, kneeDB: 6, attackMs: 20, releaseMs: 200, makeupDB: 0)
    private let glueComp = CompressorSettings(thresholdDB: -18, ratio: 2, kneeDB: 6, attackMs: 10, releaseMs: 100, makeupDB: 0)

    @Test func unityBelowKnee() throws {
        // -26 dBFS sits below the knee start (-23 dB): no gain change, not even a transient.
        let buffer = try S.dc(0.05, seconds: 0.5)
        compress(tapeComp, buffer)
        #expect(S.samples(of: buffer).allSatisfy { abs($0 - 0.05) < 1e-6 })
    }

    @Test func steadyStateAboveKnee() throws {
        // DC 0.5 = -6.02 dBFS, 11.98 dB over -18 at 2:1 → 5.99 dB reduction.
        let buffer = try S.dc(0.5, seconds: 1)
        compress(glueComp, buffer)
        #expect(abs(tailGainDB(buffer, input: 0.5) + 5.99) < 0.05)
    }

    @Test func softKneeAtThreshold() throws {
        // Dead on threshold with a 6 dB knee: slope · 3² / 12 = 0.25 dB.
        let buffer = try S.dc(0.1, seconds: 1)
        compress(tapeComp, buffer)
        #expect(abs(tailGainDB(buffer, input: 0.1) + 0.25) < 0.02)
    }

    @Test func hardKnee() throws {
        let hard = CompressorSettings(thresholdDB: -18, ratio: 2, kneeDB: 0, attackMs: 10, releaseMs: 100, makeupDB: 0)
        let atThreshold = try S.dc(0.12589, seconds: 1)
        compress(hard, atThreshold)
        #expect(abs(tailGainDB(atThreshold, input: 0.12589)) < 0.01)
        let above = try S.dc(0.5, seconds: 1)
        compress(hard, above)
        #expect(abs(tailGainDB(above, input: 0.5) + 5.99) < 0.02)
    }

    @Test func makeupAddsAfterReduction() throws {
        var settings = glueComp
        settings.makeupDB = 1.5
        let buffer = try S.dc(0.5, seconds: 1)
        compress(settings, buffer)
        #expect(abs(tailGainDB(buffer, input: 0.5) + 4.49) < 0.05)
    }

    @Test func stereoLinkUsesLoudestChannel() throws {
        let buffer = try S.dc(0.5, seconds: 1, channels: 2)
        S.fill(buffer, channel: 1) { _ in 0.05 }
        compress(glueComp, buffer)
        let left = tailGainDB(buffer, channel: 0, input: 0.5)
        let right = tailGainDB(buffer, channel: 1, input: 0.05)
        #expect(right < -1)
        #expect(abs(left - right) < 0.01)
    }

    @Test func attackTimeConstant() throws {
        // One attack time constant (20 ms = 960 frames) into a step reaches
        // 63.2% of the steady-state reduction.
        let settings = CompressorSettings(thresholdDB: -18, ratio: 2, kneeDB: 6, attackMs: 20, releaseMs: 100, makeupDB: 0)
        let buffer = try S.dc(0.5, seconds: 0.5)
        compress(settings, buffer)
        let reduction = -S.dB(S.samples(of: buffer)[960] / 0.5)
        #expect(abs(reduction - 0.632 * 5.99) < 0.05 * 5.99)
    }

    @Test func releaseTimeConstant() throws {
        // Loud for 500 ms, then drop below the knee: 100 ms later the
        // reduction has decayed to 36.8% of steady state.
        let settings = CompressorSettings(thresholdDB: -18, ratio: 2, kneeDB: 6, attackMs: 10, releaseMs: 100, makeupDB: 0)
        let buffer = try S.dc(0.5, seconds: 1)
        S.fill(buffer, channel: 0) { frame in frame < 24_000 ? 0.5 : 0.05 }
        compress(settings, buffer)
        let reduction = -S.dB(S.samples(of: buffer)[24_000 + 4_800] / 0.05)
        #expect(abs(reduction - 0.368 * 5.99) < 0.05 * 5.99)
    }

    @Test func silenceStaysSilent() throws {
        var settings = glueComp
        settings.makeupDB = 3
        let buffer = try S.dc(0.5, seconds: 1)
        S.fill(buffer, channel: 0) { frame in frame < 24_000 ? 0.5 : 0 }
        compress(settings, buffer)
        #expect(S.samples(of: buffer)[24_000...].allSatisfy { $0 == 0 })
    }

    @Test func gainNeverExceedsMakeup() throws {
        var settings = glueComp
        settings.makeupDB = 1.5
        let buffer = try S.noise(seed: 7, peak: 1, seconds: 1)
        let input = S.samples(of: buffer)
        compress(settings, buffer)
        let makeup = pow(10, Float(1.5) / 20)
        for (out, inp) in zip(S.samples(of: buffer), input) {
            #expect(abs(out) <= abs(inp) * makeup * (1 + 1e-6))
        }
    }

    // MARK: - Soft clip

    @Test func softClipUnitySmallSignal() throws {
        let buffer = try S.dc(1e-3, seconds: 0.01)
        SoftClip.process(buffer.floatChannelData![0], count: Int(buffer.frameLength), drive: 1.2)
        #expect(abs(S.samples(of: buffer)[0] / 1e-3 - 1) < 1e-4)
    }

    @Test func softClipBoundedByInverseDrive() throws {
        let buffer = try S.dc(10, seconds: 0.01)
        S.fill(buffer, channel: 0) { frame in frame % 2 == 0 ? 10 : -10 }
        SoftClip.process(buffer.floatChannelData![0], count: Int(buffer.frameLength), drive: 1.2)
        for (index, sample) in S.samples(of: buffer).enumerated() {
            #expect(abs(sample) > 0.99 / 1.2 && abs(sample) <= 1 / 1.2 + 1e-6)
            #expect((sample > 0) == (index % 2 == 0))
        }
    }
}
