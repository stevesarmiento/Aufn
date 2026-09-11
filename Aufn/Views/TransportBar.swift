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
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
        .onChange(of: engine.state) { _, state in
            if state != .idle { setChoosingMode(false) }
        }
    }

    private func setChoosingMode(_ choosing: Bool) {
        withAnimation(choosing ? .discloseOpen : .discloseClose) {
            choosingMode = choosing
        }
    }

    /// The wheel and its trigger swap through the trailing edge so one appears
    /// to become the other; play and the mode label do the same on the left.
    private var trailingSwap: AnyTransition { .disclose(anchor: .trailing) }
    private var leadingSwap: AnyTransition { .disclose(anchor: .leading) }

    /// ZStack ordering matters: the strip is the bottom layer so the glass
    /// record head above it refracts the dots passing beneath. While choosing
    /// a mode, a clear catcher behind the controls collapses on an outside tap.
    private var tapeDeck: some View {
        ZStack {
            MixWaveformView(project: project, engine: engine)
            if choosingMode {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture { setChoosingMode(false) }
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
                .transition(leadingSwap)
        } else if isPlaying {
            skipBackButton
                .transition(leadingSwap)
        } else {
            playButton
                .transition(leadingSwap)
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

    /// While playing, the play slot becomes skip-back — the record head is
    /// the stop button — so the layout never changes shape.
    private var skipBackButton: some View {
        Button {
            Haptics.tap()
            engine.skipBack()
        } label: {
            Image(systemName: "gobackward.10")
                .font(.title2)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Skip back 10 seconds")
    }

    /// Collapsed trigger: just the mode name in a glass capsule.
    private var captureModeTrigger: some View {
        Button {
            Haptics.tap()
            setChoosingMode(true)
        } label: {
            Text(currentMode.label)
                .font(.footnote.weight(.heavy))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glass)
        .transition(trailingSwap)
        .accessibilityLabel("Capture mode, \(currentMode.label)")
    }

    /// Custom UIPickerView wheel over a black panel that fades to transparent
    /// on the left into the tape dots; the selected row sits on black (no gray
    /// bubble) like the timer.
    private var captureModeWheel: some View {
        CaptureWheel(modes: CaptureMode.allCases, selection: $captureMode) {
            setChoosingMode(false)
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
            .transition(trailingSwap)
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
            Haptics.tap()
            engine.startPlayback(of: project)
        } label: {
            Image(systemName: "play.fill")
                .font(.title2)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.glass)
        .disabled(isRecording || (project.tracks.isEmpty && project.metronome == nil))
        .accessibilityLabel("Play")
    }

    /// Tall clear "lens" capsule with a pill inside; the pill morphs into a
    /// stop square while the transport runs — red for recording, white for
    /// playback (the head IS the stop button while playing). The magnified
    /// tape showing through it is drawn by MixWaveformView (glassEffect
    /// can't sample siblings inside the transport's GlassEffectContainer,
    /// and .regular glass would frost the dots away) — this button only
    /// supplies the rim chrome and the pill.
    private var recordHeadButton: some View {
        Button {
            switch engine.state {
            case .recording:
                Haptics.tap()
                engine.stopRecording()
            case .playing:
                Haptics.tap()
                engine.stopTransport()
            case .idle:
                // Heavier than a tap: starting a take is the app's defining action.
                Haptics.heavy()
                Task { await engine.startRecording(into: project) }
            }
        } label: {
            pillShape
                .frame(width: TapeHead.size.width, height: TapeHead.size.height)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: engine.state)
        .accessibilityLabel(headLabel)
    }

    private var headLabel: String {
        switch engine.state {
        case .recording: "Stop recording"
        case .playing: "Stop"
        case .idle: "Record"
        }
    }

    /// Camera-style morph: red circle at rest, rounded stop square while the
    /// transport runs — red-tinted glass for a take, white for playback.
    private var pillShape: some View {
        let running = engine.state != .idle
        return Color.clear
            .frame(width: running ? 28 : 34, height: running ? 28 : 34)
            .glassEffect(
                .regular.tint(isPlaying ? .white : Color(red: 1.0, green: 0.20, blue: 0.22)),
                in: .rect(cornerRadius: running ? 9 : 17)
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
