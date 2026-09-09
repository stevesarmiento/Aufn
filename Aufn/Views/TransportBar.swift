import SwiftUI

/// Floating tape-deck transport with no backing panel: the dot-matrix strip
/// runs full-width directly on the screen, the clear record head sits
/// centered on it, and the play/volume buttons are the only glass elements.
struct TransportBar: View {
    let engine: AudioEngineController
    let project: Project
    // AppStorage (not raw UserDefaults) so the readout re-renders when the
    // sample-rate picker changes the preference.
    @AppStorage(CaptureMode.storageKey) private var captureMode = CaptureMode.raw.rawValue
    @State private var choosingMode = false

    private var isRecording: Bool { engine.state == .recording }
    private var isPlaying: Bool { engine.state == .playing }
    private var currentMode: CaptureMode { CaptureMode(rawValue: captureMode) ?? .raw }

    var body: some View {
        VStack(spacing: 12) {
            if isRecording {
                LevelMeterView(meter: engine.meter)
                    .padding(.horizontal, 4)
            }
            tapeDeck
        }
        .animation(.snappy, value: engine.state)
        .animation(.snappy, value: choosingMode)
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
        .onChange(of: engine.state) { _, state in
            if state != .idle { choosingMode = false }
        }
    }

    /// ZStack ordering matters: the strip is the bottom layer so the glass
    /// record head above it refracts the dots passing beneath. While choosing
    /// a mode, a clear catcher behind the controls collapses on an outside tap.
    private var tapeDeck: some View {
        ZStack {
            MixWaveformView(project: project, engine: engine)
            if choosingMode {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture { choosingMode = false }
            }
            HStack {
                leftControl
                Spacer()
                rightControl
            }
            recordHeadButton
        }
        .frame(height: 96)
        .animation(.snappy, value: engine.state)
    }

    /// Play at rest; the selected mode's description while choosing (in the
    /// play slot). Play is unavailable mid-record anyway.
    @ViewBuilder
    private var leftControl: some View {
        if engine.state == .idle && choosingMode {
            Text("INPUT PROCESSING")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .trailing)
                .transition(.opacity)
        } else {
            playButton
        }
    }

    @ViewBuilder
    private var rightControl: some View {
        if engine.state != .idle {
            timerReadout
        } else if choosingMode {
            captureModeWheel
        } else {
            captureModeTrigger
        }
    }

    /// Collapsed trigger: just the mode name in a glass capsule.
    private var captureModeTrigger: some View {
        Button {
            choosingMode = true
        } label: {
            Text(currentMode.label)
                .font(.footnote.weight(.heavy))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Capture mode, \(currentMode.label)")
    }

    /// Custom UIPickerView wheel over a black panel that fades to transparent
    /// on the left into the tape dots; the selected row sits on black (no gray
    /// bubble) like the timer.
    private var captureModeWheel: some View {
        CaptureWheel(modes: CaptureMode.allCases, selection: $captureMode) {
            choosingMode = false
        }
            .frame(width: 130, height: 96)
            .clipped()
            .background(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.5),
                        .init(color: .black, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .transition(.opacity)
    }

    /// Just the elapsed time now — larger — over a soft scrim that fades to
    /// transparent so the tape dots stay visible around it.
    private var timerReadout: some View {
        elapsedClock
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                EllipticalGradient(
                    colors: [.black.opacity(0.75), .clear],
                    center: .center,
                    startRadiusFraction: 0.2,
                    endRadiusFraction: 0.7
                )
            )
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
                .frame(width: 40, height: 40)
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
            pillShape
                .frame(width: TapeHead.size.width, height: TapeHead.size.height)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: isRecording)
        .accessibilityLabel(isRecording ? "Stop recording" : "Record")
    }

    /// Camera-style morph: red circle at rest, rounded stop square recording.
    /// Rendered as red-tinted glass sitting on the head's glass.
    private var pillShape: some View {
        Color.clear
            .frame(width: isRecording ? 28 : 34, height: isRecording ? 28 : 34)
            .glassEffect(
                .regular.tint(Color(red: 1.0, green: 0.20, blue: 0.22)),
                in: .rect(cornerRadius: isRecording ? 9 : 17)
            )
    }

    private var elapsedClock: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            Text(engine.state == .idle ? "0:00" : engine.elapsedSeconds.timecode)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(engine.state == .idle ? .secondary : .primary)
        }
    }
}

#Preview("Idle") {
    let store = PreviewData.store()
    VStack {
        Spacer()
        TransportBar(engine: AudioEngineController(store: store), project: PreviewData.demoProject(in: store))
    }
    .fontDesign(.rounded)
    .environment(store)
    .preferredColorScheme(.dark)
}
