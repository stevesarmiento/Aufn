import AVFAudio
import Observation

/// Single owner of the AVAudioSession. Nothing else in the app touches the session.
@MainActor
@Observable
final class AudioSessionController {
    static let shared = AudioSessionController()

    /// Loud-speaker override applies only when playing back with no external
    /// output; recording keeps the conservative receiver routing (less bleed).
    enum OutputRoutingPolicy {
        case loudspeakerIfBuiltIn
        case standard
    }

    private(set) var isConfigured = false
    /// Tracks whether we forced the loud speaker, so `.standard` only clears
    /// an override we actually set — gratuitous override/preferred-input calls
    /// rebuild the audio route and can stall the input right as a take starts.
    private var speakerOverrideActive = false
    private var appliedInputUID: String?

    private var session: AVAudioSession { .sharedInstance() }

    /// The rate the hardware actually granted — never assume the preferred rate.
    var sampleRate: Double { session.sampleRate }

    var inputLatency: TimeInterval { session.inputLatency }
    var outputLatency: TimeInterval { session.outputLatency }

    /// True when output is the built-in speaker — overdubs will bleed; suggest headphones.
    var isOutputBuiltInSpeaker: Bool {
        session.currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
    }

    private var hasExternalOutput: Bool {
        session.currentRoute.outputs.contains {
            $0.portType != .builtInSpeaker && $0.portType != .builtInReceiver
        }
    }

    func configure(preferredSampleRate: Double = 48_000, output: OutputRoutingPolicy = .standard, recording: Bool = false) throws {
        var options: AVAudioSession.CategoryOptions = [.allowBluetoothA2DP]
        // BT mics need the HFP option to be usable — only pay that cost (both
        // directions drop to headset quality) when the user actually chose one.
        if preferredInputPortType == AVAudioSession.Port.bluetoothHFP.rawValue {
            options.insert(.allowBluetoothHFP)
        }
        // The capture mode's session mode only matters while recording; keep
        // playback on .default for normal output behavior.
        let mode: AVAudioSession.Mode = recording ? CaptureMode.current.sessionMode : .default
        try session.setCategory(.playAndRecord, mode: mode, options: options)
        try? session.setPreferredSampleRate(preferredSampleRate)
        try? session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
        applyPreferredInput()
        switch output {
        case .loudspeakerIfBuiltIn where !hasExternalOutput:
            // .playAndRecord defaults built-in output to the quiet earpiece
            // receiver; route pure playback to the loud speaker instead.
            try? session.overrideOutputAudioPort(.speaker)
            speakerOverrideActive = true
        case .loudspeakerIfBuiltIn, .standard:
            if speakerOverrideActive {
                try? session.overrideOutputAudioPort(.none)
                speakerOverrideActive = false
            }
        }
        isConfigured = true
    }

    func requestRecordPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        default:
            return await AVAudioApplication.requestRecordPermission()
        }
    }

    /// Samples of input+output latency at the current rate, stored per track so
    /// playback/export can compensate without rewriting audio files.
    var latencyOffsetSamples: Int {
        Int(((inputLatency + outputLatency) * sampleRate).rounded())
    }

    // MARK: - Input selection

    /// Empty/nil = Auto (let iOS pick). The UID is kept even while the device
    /// is disconnected so the choice returns when it does.
    var preferredInputUID: String? {
        get { UserDefaults.standard.string(forKey: "preferredInputUID") }
        set {
            UserDefaults.standard.set(newValue, forKey: "preferredInputUID")
            applyPreferredInput()
        }
    }

    private(set) var preferredInputPortType: String? {
        get { UserDefaults.standard.string(forKey: "preferredInputPortType") }
        set { UserDefaults.standard.set(newValue, forKey: "preferredInputPortType") }
    }

    func selectInput(uid: String?, portType: String?) {
        preferredInputPortType = portType
        preferredInputUID = uid
    }

    /// Probes which capture rates the CURRENT input route actually grants:
    /// request each candidate and read back what the hardware gives. The
    /// preferred rate is restored afterwards; the next transport start
    /// re-applies the user's real preference anyway. Only call while idle —
    /// changing the preferred rate mid-transport reconfigures the route.
    func supportedSampleRates(from candidates: [Double]) -> Set<Double> {
        try? configure()
        var supported: Set<Double> = []
        for candidate in candidates {
            try? session.setPreferredSampleRate(candidate)
            if abs(session.sampleRate - candidate) < 1 {
                supported.insert(candidate)
            }
        }
        try? session.setPreferredSampleRate(UserDefaults.standard.preferredSampleRate)
        return supported
    }

    /// Inputs to show in the picker. Temporarily widens the category to
    /// include HFP so Bluetooth mics enumerate; the next transport start
    /// rebuilds options from the persisted choice.
    func inputsForPicker() -> [AVAudioSessionPortDescription] {
        try? session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothA2DP, .allowBluetoothHFP])
        return session.availableInputs ?? []
    }

    private func applyPreferredInput() {
        guard let uid = preferredInputUID, !uid.isEmpty else {
            // Auto: only clear if we previously applied a preference.
            if appliedInputUID != nil {
                try? session.setPreferredInput(nil)
                appliedInputUID = nil
            }
            return
        }
        // Absent device: silently fall back to Auto without clearing the choice.
        guard let port = session.availableInputs?.first(where: { $0.uid == uid }) else {
            if appliedInputUID != nil {
                try? session.setPreferredInput(nil)
                appliedInputUID = nil
            }
            return
        }
        guard appliedInputUID != uid else { return }
        try? session.setPreferredInput(port)
        appliedInputUID = uid
    }
}
