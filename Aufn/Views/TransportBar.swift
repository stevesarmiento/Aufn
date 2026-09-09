import SwiftUI

/// Floating glass transport styled as a tape deck: the dot-matrix tape strip
/// runs full-width behind a centered glass "record head" (which refracts it),
/// with the play button and clock flanking at the strip's faded edges.
struct TransportBar: View {
    @Environment(ProjectStore.self) private var store

    let engine: AudioEngineController
    let project: Project
    @State private var masterVolume: Float = 1

    private var isRecording: Bool { engine.state == .recording }
    private var isPlaying: Bool { engine.state == .playing }

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 10) {
                if isRecording {
                    LevelMeterView(meter: engine.meter)
                        .padding(.horizontal, 4)
                }
                if !project.tracks.isEmpty {
                    masterVolumeRow
                }
                tapeDeck
            }
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
        }
        .padding(.horizontal)
        .task(id: project.id) {
            masterVolume = project.masterVolume
        }
    }

    /// ZStack ordering matters: the strip is the bottom layer so the glass
    /// record head above it refracts the dots passing beneath.
    private var tapeDeck: some View {
        ZStack {
            MixWaveformView(project: project, engine: engine)
            HStack {
                playButton
                Spacer()
                elapsedClock
            }
            recordHeadButton
        }
        .frame(height: 80)
    }

    private var masterVolumeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.wave.1")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { masterVolume },
                    set: { masterVolume = $0; engine.setMasterVolume($0) }
                ),
                in: 0...1
            ) { editing in
                if !editing {
                    var updated = project
                    updated.masterVolume = masterVolume
                    store.update(updated)
                }
            }
            .accessibilityLabel("Master volume")
        }
        .padding(.horizontal, 4)
    }

    private var playButton: some View {
        Button {
            if isPlaying {
                engine.stopTransport()
            } else {
                engine.startPlayback(of: project)
            }
        } label: {
            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                .font(.title2)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .disabled(isRecording || project.tracks.isEmpty)
        .accessibilityLabel(isPlaying ? "Stop" : "Play")
    }

    /// Tall clear "lens" capsule with a red pill inside; the pill morphs into
    /// a stop square while recording. The magnified tape showing through it is
    /// drawn by MixWaveformView (glassEffect can't sample siblings inside the
    /// transport's GlassEffectContainer, and .regular glass would frost the
    /// dots away) — this button only supplies the rim chrome and the pill.
    private var recordHeadButton: some View {
        Button {
            if isRecording {
                engine.stopRecording()
            } else {
                Task { await engine.startRecording(into: project) }
            }
        } label: {
            ZStack {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.10), .white.opacity(0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.45), .white.opacity(0.08), .white.opacity(0.30)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                RoundedRectangle(cornerRadius: isRecording ? 7 : 13, style: .continuous)
                    .fill(.red)
                    .frame(width: isRecording ? 24 : 26, height: isRecording ? 24 : 46)
                    .shadow(color: .red.opacity(0.5), radius: 6)
            }
            .frame(width: TapeHead.size.width, height: TapeHead.size.height)
            .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: isRecording)
        .disabled(isPlaying)
        .accessibilityLabel(isRecording ? "Stop recording" : "Record")
    }

    private var elapsedClock: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            Text(engine.state == .idle ? "0:00" : engine.elapsedSeconds.timecode)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(engine.state == .idle ? .secondary : .primary)
                .frame(minWidth: 56, alignment: .trailing)
        }
    }
}
