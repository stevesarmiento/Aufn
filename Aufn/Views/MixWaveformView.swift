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
        GeometryReader { geometry in
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
            // The head is fixed at center and the tape scrolls under it, so a
            // tap's distance from center IS its distance in time. Playback
            // only; the transport buttons above this layer keep winning their
            // own taps.
            .contentShape(.rect)
            .onTapGesture { location in
                seek(toTapAt: location.x, width: geometry.size.width)
            }
        }
        .frame(height: 48)
        .accessibilityElement()
        .accessibilityIdentifier("MixWaveform")
        .accessibilityLabel("Project waveform")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: engine.seek(to: engine.elapsedSeconds + 5)
            case .decrement: engine.seek(to: engine.elapsedSeconds - 5)
            @unknown default: break
            }
        }
        .task(id: peaksFingerprint) { await loadPeaks() }
        .task(id: mixFingerprint) { combine() }
    }

    private func seek(toTapAt x: CGFloat, width: CGFloat) {
        guard engine.state == .playing else { return }
        engine.seek(to: TransportRules.seekTarget(
            tapX: x,
            midX: width / 2,
            position: engine.elapsedSeconds,
            pointsPerSecond: TapeWaveformView.pointsPerSecond,
            duration: engine.durationSeconds
        ))
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

    /// Reload peak caches when the track set changes, and when the store
    /// reports a cache landing late (the accurate peaks after a take).
    private var peaksFingerprint: Int {
        var hasher = Hasher()
        for track in project.tracks {
            hasher.combine(track.id)
        }
        hasher.combine(store.peaksRevision)
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
        // Soloing the metronome silences every track, so the tape must
        // recombine when its solo flips.
        hasher.combine(project.metronome?.isSoloed ?? false)
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
        // A superseded load (track set changed mid-flight) must not overwrite
        // the newer result.
        guard !Task.isCancelled else { return }
        trackPeaks = loaded
        combine()
    }

    private func combine() {
        let anySoloed = project.isAnySoloed
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

#Preview("Cued mix", traits: .sizeThatFitsLayout) {
    let store = PreviewData.store()
    MixWaveformView(project: PreviewData.demoProject(in: store), engine: AudioEngineController(store: store))
        .padding(.vertical, 24)
        .frame(width: 380)
        .environment(store)
        .preferredColorScheme(.dark)
}
