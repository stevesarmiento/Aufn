import SwiftUI

/// Floating tape-deck transport with no backing panel: the dot-matrix strip
/// runs full-width directly on the screen, the clear record head sits
/// centered on it, and the play/volume buttons are the only glass elements.
struct TransportBar: View {
    @Environment(ProjectStore.self) private var store

    let engine: AudioEngineController
    let project: Project
    @State private var masterVolume: Float = 1
    @State private var showsMasterVolume = false

    private var isRecording: Bool { engine.state == .recording }
    private var isPlaying: Bool { engine.state == .playing }

    var body: some View {
        VStack(spacing: 12) {
            if isRecording {
                LevelMeterView(meter: engine.meter)
                    .padding(.horizontal, 4)
            }
            if showsMasterVolume && !project.tracks.isEmpty {
                masterVolumeRow
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            tapeDeck
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
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
                VStack(alignment: .trailing, spacing: 8) {
                    elapsedClock
                    volumeToggleButton
                }
            }
            recordHeadButton
        }
        .frame(height: 108)
    }

    private var volumeToggleButton: some View {
        Button {
            withAnimation(.snappy) { showsMasterVolume.toggle() }
        } label: {
            Image(systemName: showsMasterVolume ? "speaker.wave.2.fill" : "speaker.wave.2")
                .font(.subheadline)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.glass)
        .disabled(project.tracks.isEmpty)
        .accessibilityLabel(showsMasterVolume ? "Hide master volume" : "Show master volume")
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
            RoundedRectangle(cornerRadius: isRecording ? 9 : 15, style: .continuous)
                .fill(Color(red: 1.0, green: 0.20, blue: 0.22))
                .frame(width: isRecording ? 28 : 30, height: isRecording ? 28 : 58)
                .frame(width: TapeHead.size.width, height: TapeHead.size.height)
                .glassEffect(.regular.interactive(), in: .capsule)
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
