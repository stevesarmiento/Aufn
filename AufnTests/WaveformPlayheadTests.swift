import Testing
@testable import Aufn

struct WaveformPlayheadTests {
    // MARK: - playbackProgress

    @Test func progressIsTheElapsedFractionWhileActive() {
        #expect(WaveformView.playbackProgress(elapsed: 30, duration: 120, isActive: true) == 0.25)
        #expect(WaveformView.playbackProgress(elapsed: 0, duration: 120, isActive: true) == 0)
        #expect(WaveformView.playbackProgress(elapsed: 120, duration: 120, isActive: true) == 1)
    }

    @Test func inactiveTransportShowsNoPlayhead() {
        #expect(WaveformView.playbackProgress(elapsed: 30, duration: 120, isActive: false) == nil)
    }

    @Test func finishedShortTrackShowsNoPlayheadWhileLongerOnesPlay() {
        #expect(WaveformView.playbackProgress(elapsed: 45, duration: 30, isActive: true) == nil)
    }

    @Test func zeroLengthWaveformShowsNoPlayhead() {
        #expect(WaveformView.playbackProgress(elapsed: 5, duration: 0, isActive: true) == nil)
    }

    @Test func countInHoldsThePlayheadAtZero() {
        // A future-dated start can read slightly negative; the playhead parks at 0.
        #expect(WaveformView.playbackProgress(elapsed: -0.2, duration: 120, isActive: true) == 0)
    }

    // MARK: - playheadColumn

    @Test func playheadColumnMapsThroughTheSameDownsampling() {
        // 600 bins over 100 columns (6 bins each): halfway lands on column 50.
        #expect(WaveformView.playheadColumn(progress: 0.5, peakCount: 600, binsPerColumn: 6) == 50)
        #expect(WaveformView.playheadColumn(progress: 0, peakCount: 600, binsPerColumn: 6) == 0)
    }

    @Test func endOfMixLandsOnTheLastDrawnColumn() {
        #expect(WaveformView.playheadColumn(progress: 1, peakCount: 600, binsPerColumn: 6) == 99)
    }

    @Test func noProgressOrNoPeaksMeansNoColumn() {
        #expect(WaveformView.playheadColumn(progress: nil, peakCount: 600, binsPerColumn: 6) == nil)
        #expect(WaveformView.playheadColumn(progress: 0.5, peakCount: 0, binsPerColumn: 6) == nil)
    }
}
