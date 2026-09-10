import AVFAudio
import Observation

/// The only AVAudioEngine in the app. Owns transport state, per-track player
/// nodes, the input tap for recording, and the shared-start-time sync that
/// keeps overdubs aligned with playback.
@MainActor
@Observable
final class AudioEngineController {
    enum TransportState: Equatable {
        case idle
        case playing
        case recording
    }

    private(set) var state: TransportState = .idle
    private(set) var transportStartDate: Date?
    /// Live peak bins for the take currently being recorded (20 ms cadence,
    /// same bin duration as PeakStore caches).
    private(set) var liveRecordingPeaks: [Float] = []
    private(set) var lastError: String?

    let meter = MeterTap()

    // `var` only so a media-services reset can replace a dead engine.
    private var engine = AVAudioEngine()
    private let session = AudioSessionController.shared
    private let store: ProjectStore
    private var players: [UUID: AVAudioPlayerNode] = [:]
    private var activePlayerCount = 0
    /// Players stopped by a mid-transport delete. They stay attached until
    /// `stopTransport` so the graph is never mutated under a live input tap.
    private var retiredPlayers: [AVAudioPlayerNode] = []
    // The metronome's looping click. Deliberately outside `players`: it has
    // no completion handler and never counts toward activePlayerCount, so it
    // can't hold up or trigger the auto-stop.
    private var clickPlayer: AVAudioPlayerNode?
    private var clickFormat: AVAudioFormat?
    /// Wall-clock moment the click's beat 1 sounds — the pendulum visual's
    /// phase anchor. Unlike transportStartDate it is NOT future-dated by a
    /// count-in, so the pendulum swings through the count-in bars too.
    private(set) var clickStartDate: Date?
    private var recorder: TrackRecorder?
    private var pendingTrack: PendingTrack?
    private var livePeakTask: Task<Void, Never>?
    private var playbackGeneration = 0
    /// Re-entrancy guard across the permission `await` in startRecording.
    private var isStarting = false
    /// True from installTap until removeTap. Lets teardown remove a tap
    /// left by a failed start without touching `inputNode` at other times
    /// (first access before the session is configured for recording caches
    /// an empty input format; during playback it would enable input IO).
    private var tapInstalled = false
    // Only written on the main actor and read in deinit (which Swift 6
    // treats as nonisolated), hence the unsafe opt-out.
    nonisolated(unsafe) private var sessionObservers: [NSObjectProtocol] = []
    nonisolated(unsafe) private var engineObserver: NSObjectProtocol?

    /// Scheduled start is ~100 ms out so every node shares one anchor.
    private static let startLeadSeconds: TimeInterval = 0.1

    private struct PendingTrack {
        let id: UUID
        let fileURL: URL
        let sampleRate: Double
        let channelCount: Int
        let latencyOffsetSamples: Int
        let projectID: UUID
    }

    init(store: ProjectStore) {
        self.store = store
        observeSessionNotifications()
        observeEngineConfigurationChanges()
    }

    deinit {
        let center = NotificationCenter.default
        for observer in sessionObservers {
            center.removeObserver(observer)
        }
        if let engineObserver {
            center.removeObserver(engineObserver)
        }
    }

    // MARK: - Playback

    func startPlayback(of project: Project) {
        stopTransport()
        do {
            try session.configure(output: .loudspeakerIfBuiltIn)
            schedulePlayers(for: project)
            scheduleClick(for: project)
            guard !players.isEmpty || clickPlayer != nil else {
                if !project.tracks.isEmpty {
                    lastError = AufnError.missingAudio.localizedDescription
                }
                return
            }
            try engine.start()
        } catch {
            stopTransport()
            lastError = error.localizedDescription
            return
        }
        applyMixSettings(for: project)
        let startTime = sharedStartTime()
        for player in players.values {
            player.play(at: startTime)
        }
        // No count-in on playback: the click's beat 1 == transport t=0.
        // Metronome-only playback loops until the user stops (no completion
        // handlers, so the auto-stop never fires).
        clickPlayer?.play(at: startTime)
        clickStartDate = clickPlayer != nil ? .now.addingTimeInterval(Self.startLeadSeconds) : nil
        state = .playing
        transportStartDate = .now.addingTimeInterval(Self.startLeadSeconds)
    }

    // MARK: - Live mix controls

    func setTrackVolume(_ volume: Float, trackID: UUID) {
        players[trackID]?.volume = volume
    }

    func setTrackPan(_ pan: Float, trackID: UUID) {
        players[trackID]?.pan = pan
    }

    func setMasterVolume(_ volume: Float) {
        engine.mainMixerNode.outputVolume = volume
    }

    /// Live click level while dragging (the row passes EFFECTIVE volume,
    /// like tracks).
    func setMetronomeVolume(_ volume: Float) {
        clickPlayer?.volume = volume
    }

    /// Live tempo/meter/sound change: re-schedule a fresh bar loop on the
    /// existing node. stop/scheduleBuffer/play on an already-attached node
    /// never mutates the graph, so this is safe even mid-recording. The beat
    /// phase re-anchors to "now" (standard tempo-change behavior); the
    /// persisted settings govern the next transport start.
    func updateMetronome(_ settings: MetronomeSettings) {
        guard state != .idle, let clickPlayer, let clickFormat,
              let buffer = MetronomeClick.makeBarBuffer(settings: settings, format: clickFormat) else { return }
        clickPlayer.stop()
        clickPlayer.scheduleBuffer(buffer, at: nil, options: .loops)
        clickPlayer.play()
        clickStartDate = .now
    }

    /// Swipe-delete while the transport may be running: stop() silences the
    /// click immediately without detaching (no graph mutation while a
    /// recording tap is live); stopTransport() does the detach. Metronome-only
    /// playback has nothing left to hear, so it stops entirely.
    func removeMetronome() {
        clickPlayer?.stop()
        clickStartDate = nil
        if players.isEmpty && state == .playing { stopTransport() }
    }

    /// Stops a deleted track's player so its audio ceases immediately. The
    /// node stays attached until `stopTransport` — detaching would mutate
    /// the graph, which under a live recording tap can reset the tap and
    /// drop the rest of the take. Safe while idle, playing, or recording.
    func removeTrack(trackID: UUID) {
        guard let player = players.removeValue(forKey: trackID) else { return }
        player.stop()
        retiredPlayers.append(player)
        // Deleting the last track keeps a running click going (same as
        // metronome-only playback).
        if players.isEmpty && clickPlayer == nil && state == .playing { stopTransport() }
    }

    // MARK: - Recording

    func startRecording(into project: Project) async {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        stopTransport()
        guard await session.requestRecordPermission() else {
            lastError = AufnError.microphonePermissionDenied.localizedDescription
            return
        }
        var createdFileURL: URL?
        do {
            try session.configure(preferredSampleRate: project.sampleRate ?? UserDefaults.standard.preferredSampleRate, output: .standard, recording: true)

            schedulePlayers(for: project)
            scheduleClick(for: project)

            let inputFormat = engine.inputNode.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0 else { throw AufnError.noInput }

            let trackID = UUID()
            let fileURL = store.tracksDirectory(for: project).appending(path: "\(trackID.uuidString).caf")
            // Count-in: the click starts at clickStart; transport t=0 (the
            // recorder's frame gate and the overdub players) lands countIn
            // seconds later, so file frame 0 == the post-count-in downbeat.
            // Skipped when the click can't be heard — no silent dead air.
            let countIn = project.isMetronomeAudible ? (project.metronome?.countInSeconds ?? 0) : 0
            let clickStart = sharedStartTime()
            let startTime = clickStart.offset(bySeconds: countIn)
            let recorder = try TrackRecorder(fileURL: fileURL, format: inputFormat, startHostTime: startTime.hostTime)
            createdFileURL = fileURL
            self.recorder = recorder
            // Latency compensation only makes sense when the performer heard
            // something to play against (overdub players or an audible click).
            // A first take has no reference; trimming it would just cut its
            // head off — by 200 ms or more on Bluetooth headphones.
            let hasReference = !players.isEmpty || project.isMetronomeAudible
            self.pendingTrack = PendingTrack(
                id: trackID,
                fileURL: fileURL,
                sampleRate: inputFormat.sampleRate,
                channelCount: Int(inputFormat.channelCount),
                latencyOffsetSamples: hasReference ? session.latencyOffsetSamples : 0,
                projectID: project.id
            )

            let meter = self.meter
            engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { @Sendable buffer, when in
                recorder.append(buffer, at: when)
                meter.process(buffer)
            }
            tapInstalled = true

            engine.prepare()
            try engine.start()
            applyMixSettings(for: project)
            for player in players.values {
                player.play(at: startTime)
            }
            clickPlayer?.play(at: clickStart)
            clickStartDate = clickPlayer != nil ? .now.addingTimeInterval(Self.startLeadSeconds) : nil

            state = .recording
            // Future-dated by the start lead plus any count-in; elapsedSeconds
            // clamps to 0 so the clock sits at 0:00 until the take starts.
            transportStartDate = .now.addingTimeInterval(Self.startLeadSeconds + countIn)
            liveRecordingPeaks = []
            startLivePeakCollection()
        } catch {
            recorder = nil
            pendingTrack = nil
            // stopTransport() removes any installed tap regardless of state,
            // so a start that failed after installTap can't leak one onto
            // bus 0 (a second installTap there is an uncatchable exception).
            stopTransport()
            if let createdFileURL {
                try? FileManager.default.removeItem(at: createdFileURL)
            }
            lastError = error.localizedDescription
        }
    }

    /// Stops recording, finalizes the CAF, persists the track, and kicks off
    /// the waveform-peaks computation.
    func stopRecording() {
        guard state == .recording, let recorder = self.recorder, let pending = pendingTrack else {
            stopTransport()
            return
        }
        // Whether the record gate had opened (the count-in and start lead had
        // elapsed) — a zero-frame take after that point is a failure worth
        // telling the user about, not a cancelled count-in.
        let gateOpened = transportStartDate.map { Date.now.timeIntervalSince($0) > 0.25 } ?? false
        removeTapIfInstalled()
        let outcome = recorder.finalize()
        let provisionalPeaks = liveRecordingPeaks
        self.recorder = nil
        self.pendingTrack = nil
        stopTransport()

        if let writeError = outcome.writeError {
            lastError = AufnError.writeFailed(writeError.localizedDescription).localizedDescription
        }

        guard outcome.frames > 0, let project = store.project(id: pending.projectID) else {
            try? FileManager.default.removeItem(at: pending.fileURL)
            if gateOpened, outcome.writeError == nil {
                lastError = AufnError.nothingRecorded.localizedDescription
            }
            return
        }

        let track = Track(
            id: pending.id,
            name: "Track \(project.tracks.count + 1)",
            fileName: pending.fileURL.lastPathComponent,
            latencyOffsetSamples: pending.latencyOffsetSamples,
            durationSeconds: Double(outcome.frames) / pending.sampleRate,
            sampleRate: pending.sampleRate,
            channelCount: pending.channelCount
        )

        // Provisional cache from the live meter so the row and tape show a
        // waveform the instant the track appears; the accurate file-derived
        // peaks replace it below.
        let peaksURL = store.peaksURL(for: track, in: project)
        try? PeakStore.writePeaks(provisionalPeaks, to: peaksURL)
        store.addTrack(track, to: project)

        let audioURL = store.audioURL(for: track, in: project)
        let store = self.store
        Task.detached(priority: .utility) {
            try? PeakStore.computePeaks(audioURL: audioURL, peaksURL: peaksURL)
            await store.notePeaksUpdated()
        }
    }

    // MARK: - Transport

    /// Idempotent teardown. A recording in progress is finalized through
    /// `stopRecording` by callers; reaching here mid-record (interruption
    /// fallback) discards the partial file.
    func stopTransport() {
        // Keyed on the flag, not on `state`: a start that failed between
        // installTap and `state = .recording` must not leave a tap behind.
        removeTapIfInstalled()
        if state == .recording {
            if let recorder, let pending = pendingTrack {
                _ = recorder.finalize()
                try? FileManager.default.removeItem(at: pending.fileURL)
            }
            recorder = nil
            pendingTrack = nil
        }
        livePeakTask?.cancel()
        livePeakTask = nil
        playbackGeneration += 1
        for player in players.values {
            player.stop()
            engine.detach(player)
        }
        players = [:]
        activePlayerCount = 0
        for player in retiredPlayers {
            engine.detach(player)
        }
        retiredPlayers = []
        if let clickPlayer {
            clickPlayer.stop()
            engine.detach(clickPlayer)
        }
        clickPlayer = nil
        clickFormat = nil
        clickStartDate = nil
        if engine.isRunning {
            engine.stop()
        }
        engine.reset()
        state = .idle
        transportStartDate = nil
        meter.reset()
    }

    private func removeTapIfInstalled() {
        guard tapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    /// Lifecycle stop: keep a take in progress (finalize + persist), just
    /// stop playback. Used for interruptions, route/config changes, and
    /// leaving the project screen.
    func stopForLifecycle() {
        switch state {
        case .recording:
            stopRecording()
        case .playing:
            stopTransport()
        case .idle:
            break
        }
    }

    var elapsedSeconds: TimeInterval {
        guard let transportStartDate else { return 0 }
        // Never negative: during a recording count-in the start date sits in
        // the future and the clock holds at 0:00.
        return max(0, Date.now.timeIntervalSince(transportStartDate))
    }

    func clearError() {
        lastError = nil
    }

    // MARK: - Session events

    private func observeSessionNotifications() {
        let center = NotificationCenter.default
        sessionObservers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init) == .began
            guard began else { return }
            Task { @MainActor [weak self] in
                self?.stopForLifecycle()
            }
        })
        sessionObservers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init)
            Task { @MainActor [weak self] in
                self?.handleRouteChange(reason: reason)
            }
        })
        sessionObservers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMediaServicesReset()
            }
        })
    }

    /// The engine stops itself when the IO hardware's sample rate or channel
    /// count changes (headphones in, USB/Bluetooth connect, rate switch) and
    /// posts this per-engine notification. Without handling it the transport
    /// would sit "running" with a dead engine.
    private func observeEngineConfigurationChanges() {
        engineObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleConfigurationChange()
            }
        }
    }

    /// Headphones yanked stops everything (the user lost their monitor).
    /// A new device mid-take is about to reconfigure the engine; stop
    /// cleanly and keep the take rather than let it truncate silently.
    private func handleRouteChange(reason: AVAudioSession.RouteChangeReason?) {
        switch reason {
        case .oldDeviceUnavailable:
            stopForLifecycle()
        case .newDeviceAvailable where state == .recording:
            stopForLifecycle()
            lastError = AufnError.deviceChanged.localizedDescription
        default:
            break
        }
    }

    private func handleConfigurationChange() {
        guard state != .idle else { return }
        let wasRecording = state == .recording
        stopForLifecycle()
        if wasRecording {
            lastError = AufnError.deviceChanged.localizedDescription
        }
    }

    /// After a media-server reset every node is invalid; the only recovery
    /// is a fresh engine.
    private func handleMediaServicesReset() {
        stopForLifecycle()
        if let engineObserver {
            NotificationCenter.default.removeObserver(engineObserver)
        }
        engine = AVAudioEngine()
        tapInstalled = false
        observeEngineConfigurationChanges()
        lastError = AufnError.audioSystemReset.localizedDescription
    }

    // MARK: - Helpers

    /// Attaches and schedules a player for EVERY track — muted/solo-silenced
    /// tracks play at effective volume 0 so mute/solo toggles work live during
    /// playback. Player start frame skips the stored latency offset so what
    /// you hear lines up with t=0.
    private func schedulePlayers(for project: Project) {
        let generation = playbackGeneration
        var scheduled: [UUID: AVAudioPlayerNode] = [:]

        for track in project.tracks {
            let url = store.audioURL(for: track, in: project)
            guard let file = try? AVAudioFile(forReading: url) else { continue }
            let offset = AVAudioFramePosition(track.latencyOffsetSamples)
            let frameCount = AVAudioFrameCount(max(0, file.length - offset))
            guard frameCount > 0 else { continue }

            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
            player.scheduleSegment(file, startingFrame: offset, frameCount: frameCount, at: nil, completionCallbackType: .dataPlayedBack) { @Sendable [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.playerFinished(generation: generation)
                }
            }
            scheduled[track.id] = player
        }
        players = scheduled
        activePlayerCount = scheduled.count
    }

    /// Attaches, connects, and schedules the metronome's looping bar buffer.
    /// Must run BEFORE engine.start(), like schedulePlayers — the click node
    /// is what instantiates the mixer graph on a first take, and attaching it
    /// later would rebuild the graph under a live input tap. No completion
    /// handler: the click never counts toward activePlayerCount.
    private func scheduleClick(for project: Project) {
        guard let settings = project.metronome else { return }
        let rate = project.sampleRate ?? UserDefaults.standard.preferredSampleRate
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = MetronomeClick.makeBarBuffer(settings: settings, format: format) else { return }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        clickPlayer = player
        clickFormat = format
    }

    /// Mixing properties (pan especially) only take hold once the engine has
    /// built its render graph — apply them after engine.start(). Skipped when
    /// NOTHING is connected to the mixer: on a first take with no metronome
    /// the input tap is live but the mixer isn't instantiated yet, and touching
    /// mainMixerNode here would rebuild the graph mid-capture and reset the tap
    /// (every frame then reads as pre-start and gets dropped). With any player
    /// or the click node present the mixer is already connected before start,
    /// so setting properties is safe.
    private func applyMixSettings(for project: Project) {
        guard !players.isEmpty || clickPlayer != nil else { return }
        engine.mainMixerNode.outputVolume = project.masterVolume
        for track in project.tracks {
            guard let player = players[track.id] else { continue }
            player.volume = project.effectiveVolume(for: track)
            player.pan = track.pan
        }
        clickPlayer?.volume = project.metronomeEffectiveVolume
    }

    /// Re-derives effective per-track volumes (mute/solo) and master volume,
    /// live. Inherits applyMixSettings' players-empty guard, so it's a safe
    /// no-op when idle or during a first take (input-tap protection intact).
    func updateMix(for project: Project) {
        applyMixSettings(for: project)
    }

    /// Auto-stop playback when the last track finishes (recording keeps going).
    private func playerFinished(generation: Int) {
        guard playbackGeneration == generation, state == .playing else { return }
        activePlayerCount -= 1
        if activePlayerCount <= 0 {
            stopTransport()
        }
    }

    /// Common start ~100 ms out; all players and the record gate share it
    /// (the record gate offset further by any count-in).
    private func sharedStartTime() -> AVAudioTime {
        AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTicks(forSeconds: Self.startLeadSeconds))
    }

    /// Live bins start when the record gate opens, not when the button was
    /// tapped: audio from the count-in isn't in the file, so it shouldn't be
    /// on the tape either.
    private func startLivePeakCollection() {
        livePeakTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(20))
                guard let self, self.state == .recording else { return }
                guard let start = self.transportStartDate, Date.now >= start else { continue }
                self.liveRecordingPeaks.append(self.meter.levels.peak)
            }
        }
    }
}

enum AufnError: LocalizedError {
    case microphonePermissionDenied
    case noInput
    case nothingRecorded
    case writeFailed(String)
    case deviceChanged
    case audioSystemReset
    case missingAudio

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "Microphone access is off. Enable it for Aufn in Settings to record."
        case .noInput:
            "No audio input is available."
        case .nothingRecorded:
            "Nothing was recorded. Check the microphone and try again."
        case .writeFailed(let reason):
            "The take could not be saved completely: \(reason)"
        case .deviceChanged:
            "The audio device changed. The take so far was saved."
        case .audioSystemReset:
            "The audio system was reset. Please try again."
        case .missingAudio:
            "The audio files for this project could not be opened."
        }
    }
}

extension AVAudioTime {
    static func hostTicks(forSeconds seconds: TimeInterval) -> UInt64 {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let ticksPerSecond = Double(timebase.denom) / Double(timebase.numer) * 1_000_000_000
        return UInt64(seconds * ticksPerSecond)
    }

    /// The same host-time anchor shifted later by `seconds`.
    func offset(bySeconds seconds: TimeInterval) -> AVAudioTime {
        guard seconds > 0 else { return self }
        return AVAudioTime(hostTime: hostTime + Self.hostTicks(forSeconds: seconds))
    }
}

extension UserDefaults {
    var preferredSampleRate: Double {
        let rate = double(forKey: "preferredSampleRate")
        return rate > 0 ? rate : 48_000
    }
}
