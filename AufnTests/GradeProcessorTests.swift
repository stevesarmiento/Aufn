import AVFAudio
import Foundation
import Testing
@testable import Aufn

/// The whole chain as the tap sees it: RAW costs nothing, block boundaries
/// are invisible, every grade is level-matched and never prints above full
/// scale.
struct GradeProcessorTests {
    private typealias S = GradeTestSupport

    private let gradedModes: [CaptureMode] = [.tape, .warm, .glue]

    /// Trim off by default so each test measures the grade itself.
    private func processor(_ mode: CaptureMode, channels: Int = 1, trimDB: Float = 0) throws -> GradeProcessor {
        try #require(GradeProcessor(settings: mode.grade, inputTrimDB: trimDB, sampleRate: S.sampleRate, channelCount: channels))
    }

    @Test func rawWithoutTrimYieldsNoProcessor() {
        #expect(GradeSettings.raw.isIdentity)
        #expect(CaptureMode.raw.grade.isIdentity)
        #expect(GradeProcessor(settings: .raw, inputTrimDB: 0, sampleRate: 48_000, channelCount: 1) == nil)
        for mode in gradedModes {
            #expect(!mode.grade.isIdentity)
        }
    }

    @Test func inputTrimIsCleanGainOnRaw() throws {
        // The default trim applies to RAW too: a -30 dBFS sine comes out
        // exactly the trim louder, and a full-scale input meets the ceiling.
        let amplitude: Float = pow(10, -30.0 / 20)
        let buffer = try S.sine(frequency: 1_000, amplitude: amplitude, seconds: 0.5)
        try processor(.raw, trimDB: GradeProcessor.inputTrimDB).process(buffer)
        let gain = S.steadyGainDB(buffer, frequency: 1_000, amplitude: amplitude, discard: 0, cycles: 400)
        #expect(abs(gain - GradeProcessor.inputTrimDB) < 0.01)

        let loud = try S.noise(seed: 21, peak: 1, seconds: 0.5)
        try processor(.raw, trimDB: GradeProcessor.inputTrimDB).process(loud)
        #expect(S.peak(loud) <= 1 + 1e-6)
        #expect(S.peak(loud) > 0.999)
    }

    @Test(arguments: [CaptureMode.tape, .warm, .glue])
    func chunkInvariance(mode: CaptureMode) throws {
        let source = try S.noise(seed: 11, peak: 0.25, seconds: 2, channels: 2)
        let whole = try S.copy(source)
        try processor(mode, channels: 2).process(whole)
        let chunked = try S.processInChunks(try processor(mode, channels: 2), source, lengths: [1, 7, 64, 1000, 4096, 333])
        for channel in 0..<2 {
            let difference = zip(S.samples(of: whole, channel: channel), S.samples(of: chunked, channel: channel)).map { abs($0 - $1) }.max() ?? 1
            #expect(difference < 1e-5)
        }
    }

    @Test(arguments: [CaptureMode.tape, .warm, .glue], [1, 2])
    func levelMatchAtMinus18dBFS(mode: CaptureMode, channels: Int) throws {
        // -18 dBFS RMS sine: amplitude 10^(-18/20) · √2.
        let amplitude = Float(pow(10, -18.0 / 20) * 2.0.squareRoot())
        let buffer = try S.sine(frequency: 1_000, amplitude: amplitude, seconds: 1.5, channels: channels)
        try processor(mode, channels: channels).process(buffer)
        for channel in 0..<channels {
            let gain = S.steadyGainDB(buffer, channel: channel, frequency: 1_000, amplitude: amplitude, discard: 0.5, cycles: 1_000)
            #expect(abs(gain) <= 1, "\(mode.label) channel \(channel) moved \(gain) dB")
        }
    }

    @Test(arguments: CaptureMode.allCases)
    func ceilingHolds(mode: CaptureMode) throws {
        // Full-scale square toggling every 100 ms with full-scale noise on
        // top: the worst case for compressor attack overshoot.
        let buffer = try S.noise(seed: 3, peak: 1, seconds: 1)
        let noise = S.samples(of: buffer)
        S.fill(buffer, channel: 0) { frame in
            let square: Float = (frame / 4_800) % 2 == 0 ? 1 : -1
            return max(-1, min(1, square + noise[frame]))
        }
        try processor(mode, trimDB: GradeProcessor.inputTrimDB).process(buffer)
        #expect(S.peak(buffer) <= 1 + 1e-6)
    }

    @Test(arguments: [CaptureMode.tape, .warm, .glue])
    func silentInputIsSilent(mode: CaptureMode) throws {
        let buffer = try S.dc(0, seconds: 0.5, channels: 2)
        try processor(mode, channels: 2).process(buffer)
        #expect(S.samples(of: buffer, channel: 0).allSatisfy { $0 == 0 })
        #expect(S.samples(of: buffer, channel: 1).allSatisfy { $0 == 0 })
    }

    @Test(arguments: [CaptureMode.tape, .warm, .glue])
    func monoMatchesStereoLeft(mode: CaptureMode) throws {
        let mono = try S.noise(seed: 5, peak: 0.5, seconds: 0.5)
        let stereo = try S.makeBuffer(channels: 2, frames: Int(mono.frameLength))
        for channel in 0..<2 {
            stereo.floatChannelData![channel].update(from: mono.floatChannelData![0], count: Int(mono.frameLength))
        }
        try processor(mode).process(mono)
        try processor(mode, channels: 2).process(stereo)
        let difference = zip(S.samples(of: mono), S.samples(of: stereo, channel: 0)).map { abs($0 - $1) }.max() ?? 1
        #expect(difference < 1e-6)
    }

    /// One gain for both channels. GLUE is purely linked; TAPE's soft clip
    /// is per channel by design and rounds the loud side a little more, so
    /// its allowance is the most tanh could round a full-amplitude peak
    /// (an upper bound, since the compressor has already pulled it down),
    /// and the loud channel must be the lower one.
    @Test(arguments: [CaptureMode.glue, .tape])
    func stereoLinkThroughGrade(mode: CaptureMode) throws {
        let drive = mode.grade.saturationDrive ?? 0
        let rounding: Float = drive > 0 ? -S.dB(tanh(drive * 0.5) / (drive * 0.5)) : 0
        let tolerance = 0.1 + rounding
        let buffer = try S.sine(frequency: 1_000, amplitude: 0.5, seconds: 1.5, channels: 2)
        let quiet: Float = 0.5 * pow(10, -24.0 / 20)
        S.fill(buffer, channel: 1) { frame in quiet * Float(sin(2 * Double.pi * 1_000 * Double(frame) / S.sampleRate)) }
        try processor(mode, channels: 2).process(buffer)
        let left = S.steadyGainDB(buffer, channel: 0, frequency: 1_000, amplitude: 0.5, discard: 0.5, cycles: 500)
        let right = S.steadyGainDB(buffer, channel: 1, frequency: 1_000, amplitude: quiet, discard: 0.5, cycles: 500)
        #expect(right < 0, "\(mode.label): quiet channel was not pulled down with the loud one")
        #expect(left <= right + 1e-3 && right - left < tolerance, "\(mode.label): L \(left) dB, R \(right) dB")
    }

    @Test func channelCountMismatchIsNoOp() throws {
        let buffer = try S.noise(seed: 9, peak: 0.5, seconds: 0.1, channels: 2)
        let before = S.samples(of: buffer)
        try processor(.tape, channels: 1).process(buffer)
        #expect(S.samples(of: buffer) == before)
    }

    @Test func presetsRespectTheCeilingRule() {
        for grade in GradeSettings.allGrades {
            guard let compressor = grade.compressor else { continue }
            #expect(compressor.reductionAtFullScaleDB >= compressor.makeupDB)
        }
    }
}
