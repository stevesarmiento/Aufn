import Foundation

/// Single source of truth for transport position math: loop length, the
/// per-pass schedule repeat playback queues on each player, the wrapped
/// clock, click phase, and the waveform tap-to-seek mapping. Pure and
/// stateless, like MixRules — the engine and views share it, and it is the
/// testable surface for timing the engine itself can't offer.
enum TransportRules {
    /// Seek targets clamp just short of the end so a seek can never land on
    /// (or past) the auto-stop boundary.
    static let endGuardSeconds: TimeInterval = 0.05

    static func loopLength(tracks: [TrackSegment], bar: (frames: Int, rate: Double)?) -> LoopLength? {
        guard let longest = tracks.map(\.seconds).max(), longest > 0 else { return nil }
        guard let bar, bar.frames > 0, bar.rate > 0 else {
            let track = tracks.max { $0.seconds < $1.seconds }!
            return LoopLength(frames: track.frames, rate: track.rate)
        }
        // Nearest whole bar, not up: hand-stopped takes overshoot the last
        // downbeat, and rounding up would put most of a silent bar on every
        // wrap. Nearest drops the overshoot instead. Never less than one bar.
        let barSeconds = Double(bar.frames) / bar.rate
        let bars = max(1, Int((longest / barSeconds).rounded()))
        return LoopLength(frames: Int64(bars) * Int64(bar.frames), rate: bar.rate)
    }

    /// The schedule for pass `n` of a track: pass n covers loop-timeline
    /// span [n·L, (n+1)·L), and player sample time 0 is position `position`.
    /// Only pass 0 can start mid-file. nil = this pass has no audio (the
    /// position is past the track's end, or a later pass with no loop).
    static func pass(_ n: Int, track: TrackSegment, from position: TimeInterval, loop: LoopLength?) -> PassSchedule? {
        guard let loop else {
            guard n == 0 else { return nil }
            let skip = Int64((position * track.rate).rounded())
            guard skip < track.frames else { return nil }
            return PassSchedule(startingFrame: track.offsetFrames + skip, frameCount: track.frames - skip, playerSampleTime: 0)
        }
        let loopSeconds = loop.seconds
        let skipSeconds = max(0, position - Double(n) * loopSeconds)
        let skip = Int64((skipSeconds * track.rate).rounded())
        // Clamp the pass to the loop so passes can never overlap (a track
        // longer than L loses its tail).
        let passFrames = min(track.frames, Int64((loopSeconds * track.rate).rounded()))
        guard skip < passFrames else { return nil }
        // Anchor computed per pass from the exact product, so rounding never
        // accumulates across passes.
        let anchor = max(0, Int64(((Double(n) * loopSeconds - position) * track.rate).rounded()))
        return PassSchedule(startingFrame: track.offsetFrames + skip, frameCount: passFrames - skip, playerSampleTime: anchor)
    }

    /// Passes to keep queued ahead: at least two, and at least one second of
    /// audio regardless of how short the loop is.
    static func queueDepth(loopSeconds: TimeInterval) -> Int {
        guard loopSeconds > 0 else { return 2 }
        return max(2, Int((1.0 / loopSeconds).rounded(.up)))
    }

    /// The transport clock: schedule start position plus wall-clock elapsed,
    /// floored at zero (recording count-in holds at 0:00), wrapped into the
    /// loop while repeating.
    static func wrappedPosition(start: TimeInterval, elapsed: TimeInterval, loop: TimeInterval?) -> TimeInterval {
        let position = start + max(0, elapsed)
        guard let loop, loop > 0 else { return position }
        return position.truncatingRemainder(dividingBy: loop)
    }

    /// Frames into the current bar at `position` — the click's phase.
    static func clickPhaseFrames(position: TimeInterval, barFrames: Int, rate: Double) -> Int {
        guard barFrames > 0 else { return 0 }
        return Int((position * rate).rounded()) % barFrames
    }

    /// Inverts the tape geometry (head fixed at midX, tape scrolls at
    /// pointsPerSecond) into a clamped seek target.
    static func seekTarget(tapX: Double, midX: Double, position: TimeInterval, pointsPerSecond: Double, duration: TimeInterval) -> TimeInterval {
        let target = position + (tapX - midX) / pointsPerSecond
        return min(max(0, target), max(0, duration - endGuardSeconds))
    }
}

/// A loop length held as exact frames at a reference rate (the click bar's
/// rate when there is a metronome), so wraps stay sample-accurate across
/// mixed track rates instead of drifting through seconds arithmetic.
struct LoopLength: Equatable {
    var frames: Int64
    var rate: Double

    var seconds: TimeInterval { Double(frames) / rate }

    /// Player-timeline start of pass n at another rate. Rounded per pass
    /// from the exact product — never `n · round(...)` — so the error stays
    /// within half a frame no matter how many passes have elapsed.
    func passStart(_ n: Int, atRate playerRate: Double) -> Int64 {
        Int64((Double(n) * Double(frames) * playerRate / rate).rounded())
    }
}

/// What schedulePlayers learned about one track's file: the latency-offset
/// start, the playable frame count, and the file's rate.
struct TrackSegment: Equatable {
    var offsetFrames: Int64
    var frames: Int64
    var rate: Double

    var seconds: TimeInterval { Double(frames) / rate }
}

/// One scheduleSegment call: file start frame, length, and the player-time
/// anchor (0 = at play start).
struct PassSchedule: Equatable {
    var startingFrame: Int64
    var frameCount: Int64
    var playerSampleTime: Int64
}
