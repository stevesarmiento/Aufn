import Foundation

/// Single source of truth for mute/solo audibility, shared by the live engine,
/// the offline mixdown, and the UI. Pure and stateless so the non-main-actor
/// Exporter can use it under strict concurrency.
enum MixRules {
    /// Mute wins over solo on the same track (M+S both lit = silent, matching
    /// Logic/Pro Tools). When any track is soloed, only soloed tracks play.
    static func isAudible(_ track: Track, anySoloed: Bool) -> Bool {
        if track.isMuted { return false }
        if anySoloed { return track.isSoloed }
        return true
    }

    static func effectiveVolume(for track: Track, anySoloed: Bool) -> Float {
        isAudible(track, anySoloed: anySoloed) ? track.volume : 0
    }
}

extension Project {
    var isAnyTrackSoloed: Bool {
        tracks.contains { $0.isSoloed }
    }

    func isAudible(_ track: Track) -> Bool {
        MixRules.isAudible(track, anySoloed: isAnyTrackSoloed)
    }

    func effectiveVolume(for track: Track) -> Float {
        MixRules.effectiveVolume(for: track, anySoloed: isAnyTrackSoloed)
    }
}
