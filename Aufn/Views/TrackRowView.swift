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
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(track.name)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(track.durationSeconds.timecode)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    WaveformView(peaks: peaks, tint: project.isAudible(track) ? .accentColor : .secondary)
                        .frame(height: 36)
                        .opacity(project.isAudible(track) ? 1 : 0.4)
                }

                Button {
                    withAnimation(.snappy) { isMixerExpanded.toggle() }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(isMixerExpanded ? Color.accentColor : .primary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Mixer for \(track.name)")

                VStack(spacing: 4) {
                    muteSoloButton("M", isActive: track.isMuted, tint: .orange, label: "Mute \(track.name)") {
                        var updated = track
                        updated.isMuted.toggle()
                        persistAndUpdateMix(updated)
                    }
                    muteSoloButton("S", isActive: track.isSoloed, tint: .yellow, label: "Solo \(track.name)") {
                        var updated = track
                        updated.isSoloed.toggle()
                        persistAndUpdateMix(updated)
                    }
                }
            }

            if isMixerExpanded {
                mixerControls
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
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
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.1")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                .accessibilityLabel("Volume for \(track.name)")
                Image(systemName: "speaker.wave.3")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text("L")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { pan },
                        set: { pan = $0; engine.setTrackPan($0, trackID: track.id) }
                    ),
                    in: -1...1
                ) { editing in
                    if !editing { persistLevels() }
                }
                .accessibilityLabel("Pan for \(track.name)")
                .onTapGesture(count: 2) {
                    pan = 0
                    engine.setTrackPan(0, trackID: track.id)
                    persistLevels()
                }
                Text("R")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
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

    @ViewBuilder
    private func muteSoloButton(_ letter: String, isActive: Bool, tint: Color, label: String, action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            Text(letter)
                .font(.caption.weight(.bold))
                .frame(width: 30, height: 24)
        }
        .accessibilityLabel(label)
        if isActive {
            button.buttonStyle(.glassProminent).tint(tint)
        } else {
            button.buttonStyle(.glass).foregroundStyle(.primary)
        }
    }
}

/// The in-progress take: renders the engine's live peak bins as they arrive.
struct LiveTrackRowView: View {
    let engine: AudioEngineController

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Recording", systemImage: "record.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse)
                    Spacer()
                }
                WaveformView(peaks: engine.liveRecordingPeaks.suffix(600).map { $0 }, tint: .red)
                    .frame(height: 36)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

extension Double {
    /// "m:ss" timecode for track durations and the transport clock.
    var timecode: String {
        let total = Int(self.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
