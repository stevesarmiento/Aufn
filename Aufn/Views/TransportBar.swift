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
            if engine.state == .idle && choosingMode {
                Text(currentMode.caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
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
    /// record head above it refracts the dots passing beneath.
    private var tapeDeck: some View {
        ZStack {
            MixWaveformView(project: project, engine: engine)
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

    /// Play at rest; a Done button while choosing the capture mode (which the
    /// wheel replaces on the right). Play is unavailable mid-record anyway.
    @ViewBuilder
    private var leftControl: some View {
        if engine.state == .idle && choosingMode {
            Button {
                choosingMode = false
            } label: {
                Image(systemName: "checkmark")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .transition(.opacity)
            .accessibilityLabel("Done choosing capture mode")
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

    /// Collapsed trigger showing the current mode; tap to reveal the wheel.
    private var captureModeTrigger: some View {
        Button {
            choosingMode = true
        } label: {
            HStack(spacing: 4) {
                Text(currentMode.label)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Color.accentColor)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Capture mode, \(currentMode.label)")
    }

    /// Standard SwiftUI wheel picker (UIPickerView) — native momentum, snap,
    /// haptics — over a vertical black-to-transparent scrim matching the tape.
    private var captureModeWheel: some View {
        Picker("Capture mode", selection: $captureMode) {
            ForEach(CaptureMode.allCases) { mode in
                Text(mode.label)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .tag(mode.rawValue)
            }
        }
        .pickerStyle(.wheel)
        .frame(width: 150, height: 100)
        .clipped()
        .background(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.85), location: 0.5),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
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
                .font(.title.weight(.semibold).monospacedDigit())
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
