import SwiftUI

/// The transport's "tape" strip: the aggregated project waveform (every
/// track's cached peaks combined at its effective mute/solo-aware volume)
/// rendered as scrolling dot-matrix tape under the record head. During
/// recording it shows the live take's peaks emerging at the head instead.
/// Only ever reads the small peaks caches.
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
        TimelineView(.animation(minimumInterval: 0.05, paused: engine.state == .idle)) { _ in
            ZStack {
                TapeWaveformView(bins: currentBins, centerBin: currentCenterBin)
                // The record head's "refraction": the same tape, magnified
                // around the head's center and clipped to its capsule. Real
                // glassEffect can't sample siblings inside the transport's
                // GlassEffectContainer, so the lens is drawn by hand.
                TapeWaveformView(bins: currentBins, centerBin: currentCenterBin)
                    .scaleEffect(TapeHead.magnification, anchor: .center)
                    .mask(
                        Circle()
                            .frame(width: TapeHead.size.width, height: TapeHead.size.height)
                    )
            }
        }
        .frame(height: 48)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityIdentifier("MixWaveform")
        .accessibilityLabel("Project waveform")
        .task(id: peaksFingerprint) { await loadPeaks() }
        .task(id: mixFingerprint) { combine() }
    }

    /// State table: idle = mix cued at 0; playing = mix scrolling under the
    /// head; recording = the live take's bins with the newest bin at the head.
    private var currentBins: [Float] {
        engine.state == .recording ? engine.liveRecordingPeaks : combined
    }

    private var currentCenterBin: Double {
        switch engine.state {
        case .idle:
            0
        case .playing:
            engine.elapsedSeconds / PeakStore.binDuration
        case .recording:
            Double(engine.liveRecordingPeaks.count)
        }
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

}
