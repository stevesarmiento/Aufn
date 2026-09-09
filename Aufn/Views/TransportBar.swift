import SwiftUI

/// Floating tape-deck transport with no backing panel: the dot-matrix strip
/// runs full-width directly on the screen, the clear record head sits
/// centered on it, and the play/volume buttons are the only glass elements.
struct TransportBar: View {
    let engine: AudioEngineController
    let project: Project
    // AppStorage (not raw UserDefaults) so the readout re-renders when the
    // sample-rate picker changes the preference.
    @AppStorage("preferredSampleRate") private var preferredSampleRate: Double = 48_000
    @AppStorage(CaptureMode.storageKey) private var captureMode = CaptureMode.raw.rawValue
    @State private var dragStartIndex: Int?

    private var isRecording: Bool { engine.state == .recording }
    private var isPlaying: Bool { engine.state == .playing }

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
    }

    /// ZStack ordering matters: the strip is the bottom layer so the glass
    /// record head above it refracts the dots passing beneath.
    private var tapeDeck: some View {
        ZStack {
            MixWaveformView(project: project, engine: engine)
            HStack {
                playButton
                Spacer()
                if engine.state == .idle {
                    captureModeWheel
                } else {
                    timerReadout
                }
            }
            recordHeadButton
        }
        .frame(height: 96)
        .animation(.snappy, value: engine.state)
    }

    /// Camera-style capture-mode wheel: one mode shown at a time, dragged up
    /// or down like a date picker (with detent haptics), occupying the timer's
    /// spot while idle. Locked away during a take — the timer takes over,
    /// since mode can't change mid-record anyway.
    private var captureModeWheel: some View {
        let modes = CaptureMode.allCases
        let currentIndex = modes.firstIndex { $0.rawValue == captureMode } ?? 0
        return VStack(spacing: 1) {
            Image(systemName: "chevron.compact.up")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(modes[currentIndex].label)
                .font(.headline.weight(.heavy))
                .foregroundStyle(Color.accentColor)
                .id(captureMode)
                .transition(.push(from: .bottom).combined(with: .opacity))
                .frame(minWidth: 112, alignment: .trailing)
            Image(systemName: "chevron.compact.down")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .animation(.snappy, value: captureMode)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    let start = dragStartIndex ?? currentIndex
                    if dragStartIndex == nil { dragStartIndex = start }
                    // Drag up (negative height) advances to the next mode.
                    let steps = Int((value.translation.height / 30).rounded())
                    let target = min(max(start - steps, 0), modes.count - 1)
                    if modes[target].rawValue != captureMode {
                        captureMode = modes[target].rawValue
                    }
                }
                .onEnded { _ in dragStartIndex = nil }
        )
        .sensoryFeedback(.selection, trigger: captureMode)
        .accessibilityElement()
        .accessibilityLabel("Capture mode")
        .accessibilityValue(modes[currentIndex].label)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment where currentIndex < modes.count - 1:
                captureMode = modes[currentIndex + 1].rawValue
            case .decrement where currentIndex > 0:
                captureMode = modes[currentIndex - 1].rawValue
            default:
                break
            }
        }
    }

    /// Always-visible timecode + sample rate over a soft scrim that fades to
    /// transparent, so the tape dots stay visible around it.
    private var timerReadout: some View {
        VStack(alignment: .trailing, spacing: 2) {
            elapsedClock
            Text(sampleRateLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            EllipticalGradient(
                colors: [.black.opacity(0.75), .clear],
                center: .center,
                startRadiusFraction: 0.2,
                endRadiusFraction: 0.7
            )
        )
    }

    /// Locked project rate once the first take exists; the (reactive)
    /// preference before that. The hardware has the final say at record time.
    private var sampleRateLabel: String {
        let rate = project.sampleRate ?? preferredSampleRate
        let khz = rate / 1000
        return khz == khz.rounded() ? "\(Int(khz)) kHz" : String(format: "%.1f kHz", khz)
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
                .font(.title3.weight(.medium).monospacedDigit())
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
