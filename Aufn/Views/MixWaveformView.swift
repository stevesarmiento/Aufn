import SwiftUI

/// Aggregated project waveform for the transport bar: every track's cached
/// peaks combined at its effective (mute/solo-aware) volume, with a playhead
/// while the transport runs. Only ever reads the small peaks caches.
///
/// Known simplification (shared with TrackRowView): peaks start at file frame
/// 0 while playback skips `latencyOffsetSamples`, so the picture can lead the
/// audio by a few milliseconds.
struct MixWaveformView: View {
    @Environment(ProjectStore.self) private var store

    let project: Project
    let engine: AudioEngineController

    @State private var trackPeaks: [UUID: [Float]] = [:]
    @State private var combined: [Float] = []

    var body: some View {
        WaveformView(peaks: combined, tint: .secondary)
            .frame(height: 28)
            .overlay(playhead)
            .accessibilityElement()
            .accessibilityIdentifier("MixWaveform")
            .accessibilityLabel("Project waveform")
            .task(id: peaksFingerprint) { await loadPeaks() }
            .task(id: mixFingerprint) { combine() }
    }

    /// Reload peak caches when the track set changes; durations included so a
    /// just-finished take's late-arriving cache gets picked up.
    private var peaksFingerprint: Int {
        var hasher = Hasher()
        for track in project.tracks {
            hasher.combine(track.id)
            hasher.combine(track.durationSeconds)
        }
        return hasher.finalize()
    }

    /// Recombine (cheap, in-memory) when audibility or levels change.
    private var mixFingerprint: Int {
        var hasher = Hasher()
        for track in project.tracks {
            hasher.combine(track.id)
            hasher.combine(track.volume)
            hasher.combine(track.isMuted)
            hasher.combine(track.isSoloed)
        }
        return hasher.finalize()
    }

    private func loadPeaks() async {
        var loaded: [UUID: [Float]] = [:]
        for track in project.tracks {
            let url = store.peaksURL(for: track, in: project)
            loaded[track.id] = await Task.detached(priority: .utility) {
                PeakStore.loadPeaks(from: url) ?? []
            }.value
        }
        trackPeaks = loaded
        combine()
    }

    private func combine() {
        let anySoloed = project.isAnyTrackSoloed
        let maxBins = project.tracks.compactMap { trackPeaks[$0.id]?.count }.max() ?? 0
        guard maxBins > 0 else {
            combined = []
            return
        }
        var mix = [Float](repeating: 0, count: maxBins)
        for track in project.tracks {
            let gain = MixRules.effectiveVolume(for: track, anySoloed: anySoloed)
            guard gain > 0, let peaks = trackPeaks[track.id] else { continue }
            for index in peaks.indices {
                mix[index] += peaks[index] * gain
            }
        }
        combined = mix.map { min($0, 1) }
    }

    private var playhead: some View {
        GeometryReader { geometry in
            TimelineView(.periodic(from: .now, by: 0.05)) { _ in
                if engine.state != .idle, longestPlayableSeconds > 0 {
                    let fraction = min(1, engine.elapsedSeconds / longestPlayableSeconds)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 2)
                        .offset(x: geometry.size.width * fraction - 1)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var longestPlayableSeconds: Double {
        project.tracks
            .map { $0.durationSeconds - Double($0.latencyOffsetSamples) / $0.sampleRate }
            .max() ?? 0
    }
}
