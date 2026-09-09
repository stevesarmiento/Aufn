import SwiftUI

/// Floating glass transport styled as a tape deck: the dot-matrix tape strip
/// runs full-width behind a centered glass "record head" (which refracts it),
/// with the play button and clock flanking at the strip's faded edges.
struct TransportBar: View {
    @Environment(ProjectStore.self) private var store

    let engine: AudioEngineController
    let project: Project
    @Namespace private var glassNamespace
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

    /// Tall glass capsule with a red pill inside; the pill morphs into a stop
    /// square while recording. Clear glass (not prominent) so the tape strip
    /// stays visible, refracted, behind it.
    private var recordHeadButton: some View {
        Button {
            if isRecording {
                engine.stopRecording()
            } else {
                Task { await engine.startRecording(into: project) }
            }
        } label: {
            RoundedRectangle(cornerRadius: isRecording ? 7 : 13, style: .continuous)
                .fill(.red)
                .frame(width: isRecording ? 24 : 26, height: isRecording ? 24 : 46)
                .frame(width: 56, height: 76)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .glassEffectID("record", in: glassNamespace)
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
