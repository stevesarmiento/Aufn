import Testing
@testable import Aufn

struct TapTempoRulesTests {
    @Test func singleTapHasNoTempo() {
        var tempo = TapTempo()
        #expect(tempo.register(at: 10) == nil)
    }

    @Test func evenTapsAtHalfSecondRead120() {
        var tempo = TapTempo()
        var bpm: Int?
        for i in 0..<4 {
            bpm = tempo.register(at: Double(i) * 0.5)
        }
        #expect(bpm == 120)
    }

    @Test func unevenTapsAreAveraged() {
        var tempo = TapTempo()
        tempo.register(at: 0)
        tempo.register(at: 0.45)
        let bpm = tempo.register(at: 1.05) // intervals 0.45 + 0.60 → mean 0.525
        #expect(bpm == 114)
    }

    @Test func longPauseStartsANewPhrase() {
        var tempo = TapTempo()
        tempo.register(at: 0)
        tempo.register(at: 0.5)
        // Past the reset gap: the phrase forgets the earlier taps, so this
        // single tap has no tempo yet …
        #expect(tempo.register(at: 5) == nil)
        // … and the next one is derived from the new phrase alone.
        #expect(tempo.register(at: 6) == 60)
    }

    @Test func clampsToTheMetronomeRange() {
        var fast = TapTempo()
        fast.register(at: 0)
        #expect(fast.register(at: 0.05) == MetronomeSettings.bpmRange.upperBound)

        var slow = TapTempo()
        slow.register(at: 0)
        #expect(slow.register(at: 1.9) == MetronomeSettings.bpmRange.lowerBound)
    }

    @Test func averagesOverTheLastEightIntervalsOnly() {
        var tempo = TapTempo()
        // Two slow intervals at 60 BPM …
        tempo.register(at: 0)
        tempo.register(at: 1)
        tempo.register(at: 2)
        // … then eight at 120 BPM push them out of the window.
        var bpm: Int?
        for i in 1...8 {
            bpm = tempo.register(at: 2 + Double(i) * 0.5)
        }
        #expect(bpm == 120)
        #expect(tempo.taps.count == TapTempo.window + 1)
    }

    @Test func resetForgetsEverything() {
        var tempo = TapTempo()
        tempo.register(at: 0)
        tempo.register(at: 0.5)
        tempo.reset()
        #expect(tempo.taps.isEmpty)
        #expect(tempo.register(at: 1) == nil)
    }
}
