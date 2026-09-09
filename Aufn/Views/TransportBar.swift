import SwiftUI

/// Floating glass transport: play/stop, record, elapsed time, live meter.
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
                    MixWaveformView(project: project, engine: engine)
                        .padding(.horizontal, 4)
                    masterVolumeRow
                }
                HStack(spacing: 16) {
                    playButton
                    recordButton
                    elapsedClock
                }
            }
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
        }
        .padding(.horizontal)
        .task(id: project.id) {
            masterVolume = project.masterVolume
        }
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

    private var recordButton: some View {
        Button {
            if isRecording {
                engine.stopRecording()
            } else {
                Task { await engine.startRecording(into: project) }
            }
        } label: {
            Image(systemName: isRecording ? "stop.fill" : "record.circle.fill")
                .font(.title)
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.glassProminent)
        .tint(.red)
        .glassEffectID("record", in: glassNamespace)
        .disabled(isPlaying)
        .accessibilityLabel(isRecording ? "Stop recording" : "Record")
    }

    private var elapsedClock: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            Text(engine.state == .idle ? "0:00" : engine.elapsedSeconds.timecode)
                .font(.title3.monospacedDigit())
                .foregroundStyle(engine.state == .idle ? .secondary : .primary)
                .frame(minWidth: 56, alignment: .trailing)
        }
    }
}
