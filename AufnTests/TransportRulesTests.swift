import Foundation
import Testing
@testable import Aufn

/// The transport math the engine schedules from: exact-frame loop lengths,
/// per-pass anchors that never accumulate rounding, the wrapped clock, and
/// the tape's tap-to-seek mapping.
struct TransportRulesTests {
    private func track(offset: Int64 = 0, frames: Int64, rate: Double = 48_000) -> TrackSegment {
        TrackSegment(offsetFrames: offset, frames: frames, rate: rate)
    }

    // MARK: - Loop length

    @Test func loopLengthWithoutBarIsLongestTrack() {
        let loop = TransportRules.loopLength(tracks: [track(frames: 480_000), track(frames: 96_000)], bar: nil)
        #expect(loop == LoopLength(frames: 480_000, rate: 48_000))
        #expect(loop?.seconds == 10)
    }

    @Test func loopLengthComparesMixedRatesInSeconds() {
        // 44.1k track is longer in seconds despite fewer frames than 9 s @ 48k.
        let loop = TransportRules.loopLength(tracks: [track(frames: 432_000), track(frames: 441_000, rate: 44_100)], bar: nil)
        #expect(loop == LoopLength(frames: 441_000, rate: 44_100))
        #expect(loop?.seconds == 10)
    }

    @Test func loopLengthSnapsToNearestBar() {
        // 10.1 s against 2 s bars → 5 bars, dropping the overshoot.
        #expect(TransportRules.loopLength(tracks: [track(frames: 484_800)], bar: (96_000, 48_000)) == LoopLength(frames: 480_000, rate: 48_000))
        // 8.7 s against 113 bpm bars (truncated to 101 944 frames) → 4 bars.
        #expect(TransportRules.loopLength(tracks: [track(frames: 417_600)], bar: (101_944, 48_000)) == LoopLength(frames: 407_776, rate: 48_000))
        // A take shorter than a bar still loops one whole bar.
        #expect(TransportRules.loopLength(tracks: [track(frames: 48_000)], bar: (96_000, 48_000)) == LoopLength(frames: 96_000, rate: 48_000))
    }

    @Test func loopLengthNeedsTracks() {
        #expect(TransportRules.loopLength(tracks: [], bar: (96_000, 48_000)) == nil)
    }

    // MARK: - Pass starts across rates

    @Test func passStartRoundsPerPassNotCumulatively() {
        #expect(LoopLength(frames: 576_000, rate: 48_000).passStart(1, atRate: 44_100) == 529_200)
        // 101 944 @ 48k → exact spacing 93 661.05 frames @ 44.1k; successive
        // anchors differ by 93 661 or 93 662, never drifting.
        let loop = LoopLength(frames: 101_944, rate: 48_000)
        #expect(loop.passStart(2, atRate: 44_100) == 187_322)
        #expect(loop.passStart(3, atRate: 44_100) == 280_983)
        let exact = 101_944.0 * 44_100 / 48_000
        for n in 1..<500 {
            let spacing = loop.passStart(n + 1, atRate: 44_100) - loop.passStart(n, atRate: 44_100)
            #expect(spacing == Int64(exact.rounded(.down)) || spacing == Int64(exact.rounded(.up)))
        }
    }

    // MARK: - Passes

    @Test func passZeroFromZeroPlaysTheWholeTrack() {
        let t = track(offset: 960, frames: 480_000)
        let loop = LoopLength(frames: 480_000, rate: 48_000)
        #expect(TransportRules.pass(0, track: t, from: 0, loop: loop) == PassSchedule(startingFrame: 960, frameCount: 480_000, playerSampleTime: 0))
        #expect(TransportRules.pass(1, track: t, from: 0, loop: loop) == PassSchedule(startingFrame: 960, frameCount: 480_000, playerSampleTime: 480_000))
    }

    @Test func passZeroFromMidPositionSkipsIntoTheFile() {
        let t = track(offset: 960, frames: 480_000)
        let loop = LoopLength(frames: 480_000, rate: 48_000)
        #expect(TransportRules.pass(0, track: t, from: 2.5, loop: loop) == PassSchedule(startingFrame: 120_960, frameCount: 360_000, playerSampleTime: 0))
        #expect(TransportRules.pass(1, track: t, from: 2.5, loop: loop) == PassSchedule(startingFrame: 960, frameCount: 480_000, playerSampleTime: 360_000))
    }

    @Test func passPastTheTrackEndIsNil() {
        // A 10 s track inside a 12 s loop has no audio at position 11.
        let t = track(frames: 480_000)
        let loop = LoopLength(frames: 576_000, rate: 48_000)
        #expect(TransportRules.pass(0, track: t, from: 11, loop: loop) == nil)
        // The next pass carries it again, anchored at the wrap.
        #expect(TransportRules.pass(1, track: t, from: 11, loop: loop) == PassSchedule(startingFrame: 0, frameCount: 480_000, playerSampleTime: 48_000))
    }

    @Test func passClampsTracksLongerThanTheLoop() {
        // Nearest-bar truncation: the 8.7 s take loses its tail past 4 bars.
        let t = track(frames: 417_600)
        let loop = LoopLength(frames: 407_776, rate: 48_000)
        #expect(TransportRules.pass(0, track: t, from: 0, loop: loop) == PassSchedule(startingFrame: 0, frameCount: 407_776, playerSampleTime: 0))
    }

    @Test func withoutLoopOnlyPassZeroExists() {
        let t = track(offset: 960, frames: 480_000)
        #expect(TransportRules.pass(0, track: t, from: 0, loop: nil) == PassSchedule(startingFrame: 960, frameCount: 480_000, playerSampleTime: 0))
        #expect(TransportRules.pass(0, track: t, from: 2.5, loop: nil) == PassSchedule(startingFrame: 120_960, frameCount: 360_000, playerSampleTime: 0))
        #expect(TransportRules.pass(0, track: t, from: 10.5, loop: nil) == nil)
        #expect(TransportRules.pass(1, track: t, from: 0, loop: nil) == nil)
    }

    @Test func mixedRatesAgreeInSeconds() throws {
        // Pass 1 of a 44.1k track in a 48k-referenced 10 s loop anchors at
        // 10 s in its own rate.
        let t = track(frames: 441_000, rate: 44_100)
        let loop = LoopLength(frames: 480_000, rate: 48_000)
        let pass = try #require(TransportRules.pass(1, track: t, from: 0, loop: loop))
        #expect(pass.playerSampleTime == 441_000)
    }

    // MARK: - Queue depth, clock, click phase

    @Test func queueDepthKeepsASecondQueued() {
        #expect(TransportRules.queueDepth(loopSeconds: 10) == 2)
        #expect(TransportRules.queueDepth(loopSeconds: 0.3) == 4)
    }

    @Test func wrappedPositionClock() {
        #expect(TransportRules.wrappedPosition(start: 2.5, elapsed: 9.0, loop: 10) == 1.5)
        #expect(TransportRules.wrappedPosition(start: 2.5, elapsed: 9.0, loop: nil) == 11.5)
        // Count-in: a future-dated start reads as the start position.
        #expect(TransportRules.wrappedPosition(start: 0, elapsed: -0.8, loop: nil) == 0)
    }

    @Test func clickPhase() {
        #expect(TransportRules.clickPhaseFrames(position: 2.5, barFrames: 96_000, rate: 48_000) == 24_000)
        #expect(TransportRules.clickPhaseFrames(position: 4, barFrames: 96_000, rate: 48_000) == 0)
    }

    // MARK: - Tap-to-seek

    @Test func seekTargetInvertsTheTapeGeometry() {
        #expect(TransportRules.seekTarget(tapX: 196.5, midX: 196.5, position: 5, pointsPerSecond: 60, duration: 20) == 5)
        #expect(TransportRules.seekTarget(tapX: 256.5, midX: 196.5, position: 5, pointsPerSecond: 60, duration: 20) == 6)
        #expect(TransportRules.seekTarget(tapX: 0, midX: 196.5, position: 1, pointsPerSecond: 60, duration: 20) == 0)
        #expect(TransportRules.seekTarget(tapX: 380, midX: 196.5, position: 19, pointsPerSecond: 60, duration: 20) == 19.95)
    }
}
