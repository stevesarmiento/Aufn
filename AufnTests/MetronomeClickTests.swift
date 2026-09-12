import AVFAudio
import Testing
@testable import Aufn

/// The click buffer's exact length defines the beat grid (it loops), so the
/// frame math and the silence between ticks are load-bearing.
struct MetronomeClickTests {
    private func makeBuffer(bpm: Int = 120, beatsPerBar: Int = 4, sound: ClickSound = .click, sampleRate: Double = 48_000) throws -> AVAudioPCMBuffer {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let settings = MetronomeSettings(bpm: bpm, beatsPerBar: beatsPerBar, sound: sound)
        return try #require(MetronomeClick.makeBarBuffer(settings: settings, format: format))
    }

    private func samples(of buffer: AVAudioPCMBuffer) throws -> [Float] {
        let channel = try #require(buffer.floatChannelData?[0])
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    @Test(arguments: [(40, 1), (120, 4), (240, 7)])
    func barLengthMatchesTempoAndMeter(bpm: Int, beatsPerBar: Int) throws {
        let buffer = try makeBuffer(bpm: bpm, beatsPerBar: beatsPerBar)
        let beatFrames = Int(48_000 * 60.0 / Double(bpm))
        #expect(Int(buffer.frameLength) == beatsPerBar * beatFrames)
    }

    @Test func ticksAtEveryBeatWithSilentSeam() throws {
        let buffer = try makeBuffer(bpm: 120, beatsPerBar: 4)
        let all = try samples(of: buffer)
        let beatFrames = all.count / 4
        for beat in 0..<4 {
            let head = all[(beat * beatFrames)..<(beat * beatFrames + 100)]
            #expect(head.contains { abs($0) > 0.05 }, "beat \(beat) has a tick")
            // The back half of every beat is true silence, so the loop seam
            // (and the gap before the next tick) can't hiss or pop.
            let tail = all[(beat * beatFrames + beatFrames / 2)..<((beat + 1) * beatFrames)]
            #expect(tail.allSatisfy { $0 == 0 }, "beat \(beat) decays to silence")
        }
    }

    @Test func downbeatIsAccented() throws {
        let buffer = try makeBuffer(bpm: 120, beatsPerBar: 4)
        let all = try samples(of: buffer)
        let beatFrames = all.count / 4
        let accentPeak = all[0..<beatFrames].map(abs).max() ?? 0
        let regularPeak = all[beatFrames..<(2 * beatFrames)].map(abs).max() ?? 0
        #expect(accentPeak > regularPeak)

        // A 1-beat bar has no accent to distinguish.
        let single = try makeBuffer(bpm: 120, beatsPerBar: 1)
        #expect(Int(single.frameLength) == 24_000)
    }

    @Test(arguments: ClickSound.allCases)
    func everySoundRendersWithinFullScale(sound: ClickSound) throws {
        let buffer = try makeBuffer(sound: sound)
        let peaks = try samples(of: buffer).map(abs)
        let peak = peaks.max() ?? 0
        #expect(peak > 0.1)
        #expect(peak <= 1)
    }

    @Test func leadInResumesOnTheNextBeat() throws {
        let bar = try makeBuffer(bpm: 120, beatsPerBar: 4)   // 96 000 frames, 24 000 per beat
        let barSamples = try samples(of: bar)
        let lead = try #require(MetronomeClick.leadIn(bar: bar, phaseFrames: 30_000, beatFrames: 24_000))
        let leadSamples = try samples(of: lead)
        #expect(leadSamples.count == 66_000)
        #expect(leadSamples[..<18_000].allSatisfy { $0 == 0 })
        #expect(Array(leadSamples[18_000...]) == Array(barSamples[48_000...]))
    }

    @Test func leadInEdges() throws {
        let bar = try makeBuffer(bpm: 120, beatsPerBar: 4)
        #expect(MetronomeClick.leadIn(bar: bar, phaseFrames: 0, beatFrames: 24_000) == nil)
        // Past the last beat: the remainder is pure silence to the bar line.
        let tail = try #require(MetronomeClick.leadIn(bar: bar, phaseFrames: 95_000, beatFrames: 24_000))
        let tailSamples = try samples(of: tail)
        #expect(tailSamples.count == 1_000)
        #expect(tailSamples.allSatisfy { $0 == 0 })
    }

    @Test func countInMath() {
        let settings = MetronomeSettings(bpm: 120, beatsPerBar: 4, countInBars: 2)
        #expect(settings.barDuration == 2.0)
        #expect(settings.countInSeconds == 4.0)
        #expect(MetronomeSettings().countInSeconds == 0)
    }
}
