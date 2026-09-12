import Foundation

/// Tap tempo: a run of taps becomes a BPM. Pure value so the rules are
/// testable without a clock — the caller feeds in timestamps.
///
/// Taps are averaged over the last `window` intervals so a slightly uneven
/// hand still lands on a steady number; a pause longer than `resetGap`
/// forgets the old phrase so the next taps start clean instead of being
/// dragged by the gap.
struct TapTempo: Equatable {
    private(set) var taps: [TimeInterval] = []

    /// A pause this long ends the phrase; the next tap starts a new one.
    static let resetGap: TimeInterval = 2.0
    /// Number of most-recent intervals the tempo is averaged over.
    static let window = 8

    /// Records a tap and returns the tempo once there are at least two taps
    /// in the phrase; clamped to the metronome's range.
    @discardableResult
    mutating func register(at time: TimeInterval) -> Int? {
        if let last = taps.last, time - last > Self.resetGap {
            taps.removeAll()
        }
        taps.append(time)
        // window intervals need window + 1 taps.
        if taps.count > Self.window + 1 {
            taps.removeFirst(taps.count - (Self.window + 1))
        }
        guard taps.count >= 2 else { return nil }
        let intervals = zip(taps.dropFirst(), taps).map { $0 - $1 }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        guard mean > 0 else { return nil }
        return Int((60 / mean).rounded()).clamped(to: MetronomeSettings.bpmRange)
    }

    mutating func reset() {
        taps.removeAll()
    }
}
