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
    /// Position we last applied in this process, so Auto only clears a
    /// preference we set — same rule as appliedInputUID.
    private var appliedMicPosition: MicPosition?

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

    /// BT mics need the HFP option to be usable — only pay that cost (both
    /// directions drop to headset quality) when the user actually chose one.
    private var categoryOptions: AVAudioSession.CategoryOptions {
        var options: AVAudioSession.CategoryOptions = [.allowBluetoothA2DP]
        if preferredInputPortType == AVAudioSession.Port.bluetoothHFP.rawValue {
            options.insert(.allowBluetoothHFP)
        }
        return options
    }

    func configure(preferredSampleRate: Double = 48_000, output: OutputRoutingPolicy = .standard, recording: Bool = false) throws {
        // The capture mode's session mode only matters while recording; keep
        // playback on .default for normal output behavior.
        let mode: AVAudioSession.Mode = recording ? CaptureMode.current.sessionMode : .default
        try session.setCategory(.playAndRecord, mode: mode, options: categoryOptions)
        try? session.setPreferredSampleRate(preferredSampleRate)
        try? session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
        applyPreferredInput()
        // Only recording cares which capsule is live; playback shouldn't pay
        // the route rebuild.
        if recording {
            applyMicPosition()
        }
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

    /// Releases the session when the app has no use for it (left the project
    /// screen, went to the background while idle). A `.playAndRecord`
    /// session left active keeps other apps' audio interrupted; deactivating
    /// with the notify option lets them resume. `configure` reactivates.
    func deactivate() {
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        speakerOverrideActive = false
        appliedInputUID = nil
        appliedMicPosition = nil
        isConfigured = false
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

    // MARK: - Mic position

    /// What the route actually granted — the sheet's status line and the
    /// on-device check that a capture mode honors the requested pattern.
    struct MicStatus: Equatable {
        var isBuiltInMic: Bool
        var dataSourceName: String?
        var orientation: AVAudioSession.Orientation?
        var polarPattern: AVAudioSession.PolarPattern?
        var inputOrientation: AVAudioSession.StereoOrientation
        var inputChannels: Int
    }

    /// True when the active input is the built-in mic — the only case a
    /// mic position affects.
    var isBuiltInMicActive: Bool {
        session.currentRoute.inputs.first?.portType == .builtInMic
    }

    var micStatus: MicStatus {
        MicStatus(
            isBuiltInMic: isBuiltInMicActive,
            dataSourceName: session.inputDataSource?.dataSourceName,
            orientation: session.inputDataSource?.orientation,
            polarPattern: session.inputDataSource?.selectedPolarPattern,
            inputOrientation: session.inputOrientation,
            inputChannels: session.inputNumberOfChannels
        )
    }

    /// Persist and, while the session is live, apply immediately — so the one
    /// route rebuild happens in the sheet, never as a take starts.
    func selectMicPosition(_ position: MicPosition) {
        UserDefaults.standard.set(position.rawValue, forKey: MicPosition.storageKey)
        if isConfigured {
            applyMicPosition()
        }
    }

    enum MicPositionAvailability {
        case available
        /// Offered by the hardware, but not under RAW: iOS withholds the
        /// stereo beamform in `.measurement` mode (it is processing).
        case requiresTape
        case unavailable
    }

    /// What each position would get on this device. Probes under the real
    /// capture mode and, when that is RAW, under TAPE as well so the sheet
    /// can say "TAPE only" instead of a bare "Unavailable". Reads the
    /// built-in mic port from `availableInputs`, so it works even while an
    /// external mic is routed. Only call while idle — it reconfigures the
    /// session (and leaves it configured for recording, position applied).
    func micPositionAvailability() -> [MicPosition: MicPositionAvailability] {
        let mode = CaptureMode.current
        let underCurrent = positionsOffered(inMode: mode.sessionMode)
        let underTape = mode == .standard ? underCurrent : positionsOffered(inMode: CaptureMode.standard.sessionMode)
        try? configure(recording: true)

        var availability: [MicPosition: MicPositionAvailability] = [:]
        for position in MicPosition.allCases {
            availability[position] = if underCurrent.contains(position) {
                .available
            } else if underTape.contains(position) {
                .requiresTape
            } else {
                .unavailable
            }
        }
        return availability
    }

    private func positionsOffered(inMode mode: AVAudioSession.Mode) -> Set<MicPosition> {
        try? session.setCategory(.playAndRecord, mode: mode, options: categoryOptions)
        try? session.setActive(true)
        var offered: Set<MicPosition> = [.auto]
        let builtIn = session.availableInputs?.first { $0.portType == .builtInMic }
        let sources = builtIn?.dataSources ?? []
        for position in MicPosition.allCases where position != .auto {
            if position == .stereo {
                if sources.contains(where: { $0.supportedPolarPatterns?.contains(.stereo) == true }) {
                    offered.insert(position)
                }
            } else if sources.contains(where: { $0.orientation == position.orientation }) {
                // Capsule present is enough: an unsupported cardioid falls
                // back to omni on that capsule at apply time.
                offered.insert(position)
            }
        }
        return offered
    }

    /// Selects the capsule and pattern for the persisted position on the
    /// currently routed built-in mic. Inert for external inputs. Compares
    /// against live session state so a take start whose route already
    /// matches makes no route-changing calls at all.
    private func applyMicPosition() {
        let position = MicPosition.current
        guard isBuiltInMicActive, let sources = session.inputDataSources, !sources.isEmpty else { return }
        guard position != .auto else {
            clearMicPositionIfApplied(sources: sources)
            return
        }

        var target = sources.first { $0.orientation == position.orientation }
        if position == .stereo, target?.supportedPolarPatterns?.contains(.stereo) != true {
            target = sources.first { $0.supportedPolarPatterns?.contains(.stereo) == true }
        }
        guard let target else {
            // This device lacks the capsule: behave as Auto for the take.
            clearMicPositionIfApplied(sources: sources)
            return
        }
        let supported = target.supportedPolarPatterns ?? []
        let pattern: AVAudioSession.PolarPattern? = position.polarPattern.flatMap { supported.contains($0) ? $0 : nil }
            ?? (supported.contains(.omnidirectional) ? .omnidirectional : nil)

        let live = session.inputDataSource
        let sourceMatches = live?.dataSourceID == target.dataSourceID
        let patternMatches = pattern == nil || live?.selectedPolarPattern == pattern
        let orientationMatches = !position.requiresInputOrientation || session.preferredInputOrientation == .portrait
        if sourceMatches && patternMatches && orientationMatches {
            appliedMicPosition = position
            return
        }

        // Pattern on the (possibly inactive) source first, orientation next
        // (no route change), then the selection — the one call that rebuilds
        // the route.
        if let pattern, target.preferredPolarPattern != pattern {
            try? target.setPreferredPolarPattern(pattern)
        }
        if position.requiresInputOrientation {
            if session.preferredInputOrientation != .portrait {
                try? session.setPreferredInputOrientation(.portrait)
            }
            try? session.setPreferredInputNumberOfChannels(2)
        } else if appliedMicPosition == .stereo {
            try? session.setPreferredInputOrientation(.none)
            try? session.setPreferredInputNumberOfChannels(1)
        }
        try? session.setInputDataSource(target)
        appliedMicPosition = position
    }

    private func clearMicPositionIfApplied(sources: [AVAudioSessionDataSourceDescription]) {
        guard appliedMicPosition != nil else { return }
        for source in sources where source.preferredPolarPattern != nil {
            try? source.setPreferredPolarPattern(nil)
        }
        if session.preferredInputOrientation != .none {
            try? session.setPreferredInputOrientation(.none)
        }
        try? session.setPreferredInputNumberOfChannels(1)
        try? session.setInputDataSource(nil)
        appliedMicPosition = nil
    }
}
