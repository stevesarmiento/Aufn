import SwiftUI

struct TrackRowView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(AudioEngineController.self) private var engine

    let track: Track
    let project: Project

    @State private var peaks: [Float] = []
    @State private var isMixerExpanded = false
    @State private var volume: Float = 1
    @State private var pan: Float = 0

    var body: some View {
        TrackCard {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text(track.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(-1)
                    Spacer(minLength: 8)
                    Text(track.durationSeconds.timecode)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                    RoundToggle(letter: "M", isOn: track.isMuted, tint: .orange, label: "Mute \(track.name)") {
                        var updated = track
                        updated.isMuted.toggle()
                        persistAndUpdateMix(updated)
                    }
                    RoundToggle(letter: "S", isOn: track.isSoloed, tint: .yellow, label: "Solo \(track.name)") {
                        var updated = track
                        updated.isSoloed.toggle()
                        persistAndUpdateMix(updated)
                    }
                    RoundToggle(systemImage: "slider.horizontal.3", isOn: isMixerExpanded, tint: .accentColor, label: "Mixer for \(track.name)") {
                        withAnimation(.snappy) { isMixerExpanded.toggle() }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                WaveformView(peaks: peaks, tint: .gray.opacity(0.45))
                    .frame(height: 48)
                    .opacity(project.isAudible(track) ? 1 : 0.4)
                    .padding(.bottom, isMixerExpanded ? 0 : 12)

                if isMixerExpanded {
                    mixerControls
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .transition(.blurReplace.combined(with: .move(edge: .top)))
                        // Below the header/waveform so the expand reveals from
                        // underneath instead of sliding over the track.
                        .zIndex(-1)
                }
            }
        }
        .task(id: track.id) {
            volume = track.volume
            pan = track.pan
            let url = store.peaksURL(for: track, in: project)
            peaks = await Task.detached(priority: .utility) {
                PeakStore.loadPeaks(from: url) ?? []
            }.value
        }
    }

    /// Slider ticks drive the live engine only; disk writes happen once per
    /// gesture, on release.
    private var mixerControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)
                Slider(
                    value: Binding(
                        get: { volume },
                        // Push EFFECTIVE volume so dragging a muted/solo-silenced
                        // track doesn't audibly unmute it; raw volume persists.
                        set: { volume = $0; engine.setTrackVolume(project.isAudible(track) ? $0 : 0, trackID: track.id) }
                    ),
                    in: 0...1
                ) { editing in
                    if !editing { persistLevels() }
                }
                .tint(.white.opacity(0.6))
                .accessibilityLabel("Volume for \(track.name)")
            }
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.and.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)
                Slider(
                    value: Binding(
                        get: { pan },
                        set: { pan = $0; engine.setTrackPan($0, trackID: track.id) }
                    ),
                    in: -1...1,
                    neutralValue: 0,
                    label: { Text("Pan") },
                    onEditingChanged: { editing in
                        if !editing { persistLevels() }
                    }
                )
                .labelsHidden()
                .tint(.white.opacity(0.6))
                .accessibilityLabel("Pan for \(track.name)")
                .onTapGesture(count: 2) {
                    pan = 0
                    engine.setTrackPan(0, trackID: track.id)
                    persistLevels()
                }
            }
        }
    }

    private func persistLevels() {
        var updated = track
        updated.volume = volume
        updated.pan = pan
        store.updateTrack(updated, in: project)
    }

    /// Persist, then live-update the engine mix from the FRESH project — solo
    /// audibility derives from the whole track list, and the row's `project`
    /// is a pre-toggle snapshot.
    private func persistAndUpdateMix(_ updated: Track) {
        store.updateTrack(updated, in: project)
        if let fresh = store.project(id: project.id) {
            engine.updateMix(for: fresh)
        }
    }
}

/// The in-progress take: renders the engine's live peak bins as they arrive.
struct LiveTrackRowView: View {
    let engine: AudioEngineController

    var body: some View {
        TrackCard {
            VStack(spacing: 8) {
                HStack {
                    Label("Recording", systemImage: "record.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                WaveformView(peaks: engine.liveRecordingPeaks.suffix(600).map { $0 }, tint: .red)
                    .frame(height: 48)
                    .padding(.bottom, 12)
            }
        }
    }
}

extension Double {
    /// "m:ss" timecode for track durations and the transport clock.
    var timecode: String {
        let total = Int(self.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

#Preview("Track rows") {
    @Previewable @State var openID: UUID?
    let store = PreviewData.store()
    let project = PreviewData.demoProject(in: store)
    let engine = AudioEngineController(store: store)
    ScrollView {
        LazyVStack(spacing: 12) {
            ForEach(project.tracks) { track in
                SwipeToDeleteRow(
                    id: track.id,
                    openRowID: $openID,
                    deleteTitle: "Delete \"\(track.name)\"?",
                    onDelete: {}
                ) {
                    TrackRowView(track: track, project: project)
                }
            }
            LiveTrackRowView(engine: engine)
        }
        .padding()
    }
    .fontDesign(.rounded)
    .environment(store)
    .environment(engine)
    .preferredColorScheme(.dark)
}
