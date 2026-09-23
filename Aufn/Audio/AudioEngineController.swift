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
    private var players: [UUID: PlayerSlot] = [:]
    private var activePlayerCount = 0
    /// One playback pass of a track: the node stays attached and the file
    /// stays open across reschedules (seek, repeat toggling), so mid-play
    /// restarts never touch the graph or the filesystem.
    private struct PlayerSlot {
        let node: AVAudioPlayerNode
        let file: AVAudioFile
        let segment: TrackSegment
        var nextPass = 0
    }
    /// Whether playback wraps; mirrors project.repeatPlayback at play start.
    private var isRepeating = false
    /// Non-nil only while playing with repeat on and at least one track.
    private var loop: LoopLength?
    /// Longest scheduled track, unquantized — the seek range without repeat.
    private var mixDurationSeconds: TimeInterval = 0
    /// Where the current schedule began; elapsedSeconds counts from here.
    private var startPositionSeconds: TimeInterval = 0
    /// The click's bar buffer and beat length, kept so a seek can rebuild
    /// the lead-in without re-deriving from settings.
    private var clickBar: AVAudioPCMBuffer?
    private var clickBeatFrames = 0
    /// The project playback started from, kept for a one-shot restart.
    private var playbackProject: Project?
    /// When startPlayback last reconfigured the session. Under a live IO
    /// unit that can make the engine report a configuration change and stop
    /// itself right after starting; a change arriving inside this window is
    /// treated as self-inflicted and playback restarts once instead of
    /// surfacing "device changed" and leaving the play button blinking.
    private var selfReconfigureDate: Date?
    /// One restart per user-initiated play, so a device that really does
    /// reconfigure on every start can't loop.
    private var playbackRetried = false
    /// One-shot retry for a take whose start was stopped by our own session
    /// reconfigure (mirror of `playbackRetried`).
    private var recordingRetried = false
    private var recordingProject: Project?
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
        let captureMode: CaptureMode
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

    /// The project whose mix is playing, or nil when the transport isn't
    /// playing. Lets the projects grid show which card owns the transport.
    var playingProjectID: UUID? {
        state == .playing ? playbackProject?.id : nil
    }

    func startPlayback(of project: Project) {
        playbackRetried = false
        beginPlayback(of: project)
    }

    private func beginPlayback(of project: Project) {
        stopTransport()
        do {
            try session.configure(output: .loudspeakerIfBuiltIn)
            selfReconfigureDate = .now
            playbackProject = project
            schedulePlayers(for: project)
            scheduleClick(for: project)
            guard !players.isEmpty || clickPlayer != nil else {
                if !project.tracks.isEmpty {
                    lastError = AufnError.missingAudio.localizedDescription
                }
                return
            }
            isRepeating = project.repeatPlayback
            schedulePasses(from: 0, repeating: isRepeating)
            scheduleClickPasses(from: 0)
            try engine.start()
        } catch {
            stopTransport()
            lastError = error.localizedDescription
            return
        }
        applyMixSettings(for: project)
        let startTime = sharedStartTime()
        for slot in players.values {
            slot.node.play(at: startTime)
        }
        // No count-in on playback: the click's beat 1 == transport t=0.
        // Metronome-only playback loops until the user stops (no completion
        // handlers, so the auto-stop never fires).
        clickPlayer?.play(at: startTime)
        clickStartDate = clickPlayer != nil ? .now.addingTimeInterval(Self.startLeadSeconds) : nil
        state = .playing
        transportStartDate = .now.addingTimeInterval(Self.startLeadSeconds)
        startPositionSeconds = 0
    }

    // MARK: - Seek & repeat

    /// The seek range: the loop while repeating, else the longest track.
    var durationSeconds: TimeInterval { loop?.seconds ?? mixDurationSeconds }

    /// Jump playback to `seconds`. Playback-only; recording is linear.
    func seek(to seconds: TimeInterval) {
        guard state == .playing else { return }
        let clamped = min(max(0, seconds), max(0, durationSeconds - TransportRules.endGuardSeconds))
        reschedule(from: clamped)
    }

    func skipBack(_ seconds: TimeInterval = 10) {
        seek(to: elapsedSeconds - seconds)
    }

    /// Repeat is playback-only; toggling mid-play reschedules from the
    /// current position (accepting the ~100 ms restart seam) so queued or
    /// missing passes match the new setting.
    func setRepeat(_ repeating: Bool) {
        guard isRepeating != repeating else { return }
        isRepeating = repeating
        if state == .playing {
            reschedule(from: elapsedSeconds)
        }
    }

    /// Restart playback from `position` on the existing nodes. Generation
    /// bumps BEFORE the first stop(): completion handlers may fire on
    /// stop(), possibly synchronously, and must all be stale by then.
    private func reschedule(from position: TimeInterval) {
        guard state == .playing else { return }
        playbackGeneration += 1
        for slot in players.values {
            slot.node.stop()
        }
        clickPlayer?.stop()
        schedulePasses(from: position, repeating: isRepeating)
        scheduleClickPasses(from: position)
        // A seek past every track's end with nothing to wrap into and no
        // click leaves nothing audible.
        let anyAudio = activePlayerCount > 0 || (loop != nil && !players.isEmpty) || clickPlayer != nil
        guard anyAudio else {
            stopTransport()
            return
        }
        let startTime = sharedStartTime()
        for slot in players.values {
            slot.node.play(at: startTime)
        }
        clickPlayer?.play(at: startTime)
        transportStartDate = .now.addingTimeInterval(Self.startLeadSeconds)
        startPositionSeconds = position
        if let clickBar {
            let phase = TransportRules.clickPhaseFrames(position: position, barFrames: Int(clickBar.frameLength), rate: clickBar.format.sampleRate)
            clickStartDate = .now.addingTimeInterval(Self.startLeadSeconds - Double(phase) / clickBar.format.sampleRate)
        }
    }

    // MARK: - Live mix controls

    func setTrackVolume(_ volume: Float, trackID: UUID) {
        players[trackID]?.node.volume = volume
    }

    func setTrackPan(_ pan: Float, trackID: UUID) {
        players[trackID]?.node.pan = pan
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
        clickBar = buffer
        clickBeatFrames = Int(buffer.frameLength) / settings.beatsPerBar.clamped(to: MetronomeSettings.beatsPerBarRange)
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
        guard let slot = players.removeValue(forKey: trackID) else { return }
        slot.node.stop()
        retiredPlayers.append(slot.node)
        // Deleting the last track keeps a running click going (same as
        // metronome-only playback).
        if players.isEmpty && clickPlayer == nil && state == .playing { stopTransport() }
    }

    // MARK: - Recording

    func startRecording(into project: Project) async {
        recordingRetried = false
        await beginRecording(into: project)
    }

    private func beginRecording(into project: Project) async {
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
            // The mode flip (.default → .measurement) can stop the engine
            // after start; handleConfigurationChange uses this to tell that
            // self-inflicted change from a real device change.
            selfReconfigureDate = .now
            recordingProject = project

            schedulePlayers(for: project)
            scheduleClick(for: project)
            // Recording is linear: no loop regardless of the repeat flag.
            schedulePasses(from: 0, repeating: false)
            scheduleClickPasses(from: 0)

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
            // Read once at start: the wheel can change while the take runs,
            // and the file carries whatever grade it was printed with.
            let captureMode = CaptureMode.current
            self.pendingTrack = PendingTrack(
                id: trackID,
                fileURL: fileURL,
                sampleRate: inputFormat.sampleRate,
                channelCount: Int(inputFormat.channelCount),
                latencyOffsetSamples: hasReference ? session.latencyOffsetSamples : 0,
                projectID: project.id,
                captureMode: captureMode
            )

            // The grade is printed: it runs on the tap buffer before the
            // recorder writes it. Nil for RAW. Its state warms up on count-in
            // audio the recorder's gate drops. Metered post-grade so the
            // meter and provisional waveform show what lands on disk.
            let processor = GradeProcessor(settings: captureMode.grade, sampleRate: inputFormat.sampleRate, channelCount: Int(inputFormat.channelCount))
            let meter = self.meter
            engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { @Sendable buffer, when in
                processor?.process(buffer)
                recorder.append(buffer, at: when)
                meter.process(buffer)
            }
            tapInstalled = true

            engine.prepare()
            try engine.start()
            applyMixSettings(for: project)
            for slot in players.values {
                slot.node.play(at: startTime)
            }
            clickPlayer?.play(at: clickStart)
            clickStartDate = clickPlayer != nil ? .now.addingTimeInterval(Self.startLeadSeconds) : nil

            state = .recording
            // Future-dated by the start lead plus any count-in; elapsedSeconds
            // clamps to 0 so the clock sits at 0:00 until the take starts.
            transportStartDate = .now.addingTimeInterval(Self.startLeadSeconds + countIn)
            startPositionSeconds = 0
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
        // Settle the session into the full playback configuration now, while
        // idle — mode AND the loudspeaker override — so the next play's
        // configure changes nothing. Whatever configuration change this
        // causes lands on an idle transport and is ignored, instead of
        // under a freshly started engine.
        try? session.configure(output: .loudspeakerIfBuiltIn)

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
            channelCount: pending.channelCount,
            captureMode: pending.captureMode
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
        for slot in players.values {
            slot.node.stop()
            engine.detach(slot.node)
        }
        players = [:]
        activePlayerCount = 0
        loop = nil
        mixDurationSeconds = 0
        startPositionSeconds = 0
        playbackProject = nil
        selfReconfigureDate = nil
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
        clickBar = nil
        clickBeatFrames = 0
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
        // Floored at 0 (a recording count-in future-dates the start, holding
        // the clock at 0:00) and wrapped into the loop while repeating.
        return TransportRules.wrappedPosition(
            start: startPositionSeconds,
            elapsed: Date.now.timeIntervalSince(transportStartDate),
            loop: state == .playing ? loop?.seconds : nil
        )
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

    /// A real hardware change stops the engine before this notification is
    /// posted, so a running engine means the notification is stale: it was
    /// raised by our own session reconfigure at transport start (playback
    /// runs the session in `.default`, takes in `.measurement`, and the IO
    /// unit reports the mode flip as a configuration change), queued on the
    /// main queue, and delivered after `engine.start()` already absorbed it.
    ///
    /// When our own flip DID stop the engine (it can, when the IO format
    /// changes with the mode), playback restarts once: the mode is settled
    /// by then, so the second start doesn't flip and sticks.
    private func handleConfigurationChange() {
        guard state != .idle, !engine.isRunning else { return }
        if state == .playing, !playbackRetried, let project = playbackProject,
           let configured = selfReconfigureDate, Date.now.timeIntervalSince(configured) < 2 {
            playbackRetried = true
            beginPlayback(of: project)
            return
        }
        if state == .recording, !recordingRetried, let project = recordingProject,
           let configured = selfReconfigureDate, Date.now.timeIntervalSince(configured) < 2 {
            // Our own mode flip stopped the engine right as the take began.
            // The recorder's gate hasn't opened yet (start lead), so nothing
            // is lost: drop the empty file and start once more with the mode
            // already settled, instead of blaming a device change.
            recordingRetried = true
            discardStartingTake()
            Task { @MainActor [weak self] in
                await self?.beginRecording(into: project)
            }
            return
        }
        let wasRecording = state == .recording
        stopForLifecycle()
        if wasRecording {
            lastError = AufnError.deviceChanged.localizedDescription
        }
    }

    /// Throws away a take that never got going (no track, no file).
    private func discardStartingTake() {
        let fileURL = pendingTrack?.fileURL
        removeTapIfInstalled()
        _ = recorder?.finalize()
        recorder = nil
        pendingTrack = nil
        stopTransport()
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
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

    /// Attaches and connects a player for EVERY track — muted/solo-silenced
    /// tracks play at effective volume 0 so mute/solo toggles work live
    /// during playback. Opens each file once and keeps it on the slot; all
    /// scheduling happens in schedulePasses so a mid-play reschedule never
    /// reopens a file or touches the graph. Segment start frames skip the
    /// stored latency offset so what you hear lines up with t=0.
    private func schedulePlayers(for project: Project) {
        var scheduled: [UUID: PlayerSlot] = [:]
        var longest: TimeInterval = 0
        for track in project.tracks {
            let url = store.audioURL(for: track, in: project)
            guard let file = try? AVAudioFile(forReading: url) else { continue }
            let offset = Int64(track.latencyOffsetSamples)
            let frames = file.length - offset
            guard frames > 0 else { continue }

            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
            let segment = TrackSegment(offsetFrames: offset, frames: frames, rate: file.processingFormat.sampleRate)
            scheduled[track.id] = PlayerSlot(node: player, file: file, segment: segment)
            longest = max(longest, segment.seconds)
        }
        players = scheduled
        mixDurationSeconds = longest
    }

    /// Queues segments on every slot from `position`. Without repeat: one
    /// final pass per track with the `.dataPlayedBack` auto-stop handler
    /// (fires at the true audible end, even over Bluetooth latency). With
    /// repeat: `queueDepth` passes per track with `.dataConsumed` refill
    /// handlers — the earliest completion signal, so the queue is topped up
    /// long before the render reaches the wrap, making it gapless.
    private func schedulePasses(from position: TimeInterval, repeating: Bool) {
        let bar = clickBar.map { (frames: Int($0.frameLength), rate: $0.format.sampleRate) }
        loop = repeating ? TransportRules.loopLength(tracks: players.values.map(\.segment), bar: bar) : nil
        activePlayerCount = 0
        let generation = playbackGeneration
        for trackID in players.keys {
            players[trackID]?.nextPass = 0
            if let loop {
                for _ in 0..<TransportRules.queueDepth(loopSeconds: loop.seconds) {
                    enqueueLoopPass(trackID: trackID, from: position, generation: generation)
                }
            } else if let slot = players[trackID],
                      let pass = TransportRules.pass(0, track: slot.segment, from: position, loop: nil) {
                activePlayerCount += 1
                slot.node.scheduleSegment(slot.file, startingFrame: pass.startingFrame, frameCount: AVAudioFrameCount(pass.frameCount), at: nil, completionCallbackType: .dataPlayedBack) { @Sendable [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.playerFinished(generation: generation)
                    }
                }
            }
        }
    }

    /// Queues the slot's next audible pass. Player sample time 0 is pinned
    /// to `position` by the play(at:) that follows scheduling, so every
    /// anchor is absolute in the player timeline and rounding never
    /// accumulates. Only pass 0 can be silent (a seek past a short track's
    /// end); it is skipped without consuming a queue slot's callback.
    private func enqueueLoopPass(trackID: UUID, from position: TimeInterval, generation: Int) {
        guard let loop, let slot = players[trackID] else { return }
        var n = slot.nextPass
        var schedule = TransportRules.pass(n, track: slot.segment, from: position, loop: loop)
        if schedule == nil {
            n += 1
            schedule = TransportRules.pass(n, track: slot.segment, from: position, loop: loop)
        }
        players[trackID]?.nextPass = n + 1
        guard let schedule else { return }
        slot.node.scheduleSegment(slot.file, startingFrame: schedule.startingFrame, frameCount: AVAudioFrameCount(schedule.frameCount), at: AVAudioTime(sampleTime: schedule.playerSampleTime, atRate: slot.segment.rate), completionCallbackType: .dataConsumed) { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in
                self?.loopPassConsumed(trackID: trackID, generation: generation)
            }
        }
    }

    /// Refill: one consumed pass queues one more, keeping the depth
    /// constant. Guarded against stale generations (reschedules and stop()
    /// both fire handlers), a transport that left playing, and a track
    /// removed mid-play.
    private func loopPassConsumed(trackID: UUID, generation: Int) {
        guard playbackGeneration == generation, state == .playing, players[trackID] != nil else { return }
        enqueueLoopPass(trackID: trackID, from: startPositionSeconds, generation: generation)
    }

    /// Attaches and connects the metronome node and keeps its bar buffer.
    /// Must run BEFORE engine.start(), like schedulePlayers — the click node
    /// is what instantiates the mixer graph on a first take, and attaching it
    /// later would rebuild the graph under a live input tap. No completion
    /// handler: the click never counts toward activePlayerCount. Scheduling
    /// happens in scheduleClickPasses.
    private func scheduleClick(for project: Project) {
        guard let settings = project.metronome else { return }
        let rate = project.sampleRate ?? UserDefaults.standard.preferredSampleRate
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = MetronomeClick.makeBarBuffer(settings: settings, format: format) else { return }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        clickPlayer = player
        clickFormat = format
        clickBar = buffer
        clickBeatFrames = Int(buffer.frameLength) / settings.beatsPerBar.clamped(to: MetronomeSettings.beatsPerBarRange)
    }

    /// Queues the click from `position`: mid-bar, a one-shot lead-in
    /// (silence to the next beat, then the rest of the bar) followed by the
    /// looping bar — so a seek rejoins the grid on the next beat. At a bar
    /// boundary the loop alone is already in phase.
    private func scheduleClickPasses(from position: TimeInterval) {
        guard let clickPlayer, let clickBar else { return }
        let phase = TransportRules.clickPhaseFrames(position: position, barFrames: Int(clickBar.frameLength), rate: clickBar.format.sampleRate)
        if let lead = MetronomeClick.leadIn(bar: clickBar, phaseFrames: phase, beatFrames: clickBeatFrames) {
            clickPlayer.scheduleBuffer(lead)
        }
        clickPlayer.scheduleBuffer(clickBar, at: nil, options: .loops)
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
            guard let slot = players[track.id] else { continue }
            slot.node.volume = project.effectiveVolume(for: track)
            slot.node.pan = track.pan
        }
        clickPlayer?.volume = project.metronomeEffectiveVolume
    }

    /// Re-derives effective per-track volumes (mute/solo) and master volume,
    /// live. Inherits applyMixSettings' players-empty guard, so it's a safe
    /// no-op when idle or during a first take (input-tap protection intact).
    func updateMix(for project: Project) {
        applyMixSettings(for: project)
        setRepeat(project.repeatPlayback)
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
