import Foundation

/// Single source of truth for mute/solo audibility, shared by the live engine,
/// the offline mixdown, and the UI. Pure and stateless so the non-main-actor
/// Exporter can use it under strict concurrency.
enum MixRules {
    /// Mute wins over solo on the same channel (M+S both lit = silent,
    /// matching Logic/Pro Tools). When any channel is soloed, only soloed
    /// channels play. Core rule on plain flags so tracks and the metronome
    /// share one truth.
    static func isAudible(muted: Bool, soloed: Bool, anySoloed: Bool) -> Bool {
        if muted { return false }
        if anySoloed { return soloed }
        return true
    }

    static func isAudible(_ track: Track, anySoloed: Bool) -> Bool {
        isAudible(muted: track.isMuted, soloed: track.isSoloed, anySoloed: anySoloed)
    }

    static func effectiveVolume(for track: Track, anySoloed: Bool) -> Float {
        isAudible(track, anySoloed: anySoloed) ? track.volume : 0
    }
}

extension Project {
    /// Any solo active anywhere — tracks or the metronome.
    var isAnySoloed: Bool {
        tracks.contains { $0.isSoloed } || (metronome?.isSoloed ?? false)
    }

    func isAudible(_ track: Track) -> Bool {
        MixRules.isAudible(track, anySoloed: isAnySoloed)
    }

    func effectiveVolume(for track: Track) -> Float {
        MixRules.effectiveVolume(for: track, anySoloed: isAnySoloed)
    }

    var isMetronomeAudible: Bool {
        guard let metronome else { return false }
        return MixRules.isAudible(muted: metronome.isMuted, soloed: metronome.isSoloed, anySoloed: isAnySoloed)
    }

    var metronomeEffectiveVolume: Float {
        guard let metronome, isMetronomeAudible else { return 0 }
        return metronome.volume
    }

    /// The aggregate mix picture: every track's peak bins summed at its
    /// mute/solo-aware effective volume, clipped to full scale. Pure math on
    /// already-loaded caches, shared by the transport tape and the grid
    /// card's thumbnail.
    func combinedMixPeaks(from trackPeaks: [UUID: [Float]]) -> [Float] {
        let anySoloed = isAnySoloed
        let maxBins = tracks.compactMap { trackPeaks[$0.id]?.count }.max() ?? 0
        guard maxBins > 0 else { return [] }
        var mix = [Float](repeating: 0, count: maxBins)
        for track in tracks {
            let gain = MixRules.effectiveVolume(for: track, anySoloed: anySoloed)
            guard gain > 0, let peaks = trackPeaks[track.id] else { continue }
            for index in peaks.indices {
                mix[index] += peaks[index] * gain
            }
        }
        return mix.map { min($0, 1) }
    }
}
