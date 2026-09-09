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

    private let engine = AVAudioEngine()
    private let session = AudioSessionController.shared
    private let store: ProjectStore
    private var players: [UUID: AVAudioPlayerNode] = [:]
    private var activePlayerCount = 0
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

    private struct PendingTrack {
        let id: UUID
        let fileURL: URL
        let sampleRate: Double
        let latencyOffsetSamples: Int
        let projectID: UUID
    }

    init(store: ProjectStore) {
        self.store = store
        observeSessionNotifications()
    }

    // MARK: - Playback

    func startPlayback(of project: Project) {
        stopTransport()
        do {
            try session.configure(output: .loudspeakerIfBuiltIn)
            schedulePlayers(for: project)
            scheduleClick(for: project)
            guard !players.isEmpty || clickPlayer != nil else { return }
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
        clickStartDate = clickPlayer != nil ? .now.addingTimeInterval(0.1) : nil
        state = .playing
        transportStartDate = .now
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

    /// Stops and detaches a deleted track's player so its audio ceases
    /// immediately. Safe while idle (no player exists), playing, or recording.
    func removeTrack(trackID: UUID) {
        guard let player = players.removeValue(forKey: trackID) else { return }
        player.stop()
        engine.detach(player)
        // Deleting the last track keeps a running click going (same as
        // metronome-only playback).
        if players.isEmpty && clickPlayer == nil && state == .playing { stopTransport() }
    }

    // MARK: - Recording

    func startRecording(into project: Project) async {
        stopTransport()
        guard await session.requestRecordPermission() else {
            lastError = AufnError.microphonePermissionDenied.localizedDescription
            return
        }
        do {
            try session.configure(preferredSampleRate: project.sampleRate ?? UserDefaults.standard.preferredSampleRate, output: .standard, recording: true)

            // Toggle the AEC/noise-suppression/AGC stack to match the capture
            // mode. Must happen while the engine is stopped and before we read
            // the input format (it can change the format).
            try? engine.inputNode.setVoiceProcessingEnabled(CaptureMode.current.usesVoiceProcessing)

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
            self.recorder = recorder
            self.pendingTrack = PendingTrack(
                id: trackID,
                fileURL: fileURL,
                sampleRate: inputFormat.sampleRate,
                latencyOffsetSamples: session.latencyOffsetSamples,
                projectID: project.id
            )

            let meter = self.meter
            engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { @Sendable buffer, when in
                recorder.append(buffer, at: when)
                meter.process(buffer)
            }

            engine.prepare()
            try engine.start()
            applyMixSettings(for: project)
            for player in players.values {
                player.play(at: startTime)
            }
            clickPlayer?.play(at: clickStart)
            clickStartDate = clickPlayer != nil ? .now.addingTimeInterval(0.1) : nil

            state = .recording
            // Future-dated by the count-in; elapsedSeconds clamps to 0 so the
            // clock sits at 0:00 until the take actually starts.
            transportStartDate = .now.addingTimeInterval(countIn)
            liveRecordingPeaks = []
            startLivePeakCollection()
        } catch {
            recorder = nil
            pendingTrack = nil
            stopTransport()
            lastError = error.localizedDescription
        }
    }

    /// Stops recording, finalizes the CAF, persists the track, and kicks off
    /// the waveform-peaks computation.
    func stopRecording() {
        guard state == .recording, let recorder, let pending = pendingTrack else {
            stopTransport()
            return
        }
        engine.inputNode.removeTap(onBus: 0)
        let frames = recorder.finalize()
        self.recorder = nil
        self.pendingTrack = nil
        stopTransport()

        guard frames > 0, let project = store.project(id: pending.projectID) else {
            try? FileManager.default.removeItem(at: pending.fileURL)
            return
        }

        let track = Track(
            id: pending.id,
            name: "Track \(project.tracks.count + 1)",
            fileName: pending.fileURL.lastPathComponent,
            latencyOffsetSamples: pending.latencyOffsetSamples,
            durationSeconds: Double(frames) / pending.sampleRate,
            sampleRate: pending.sampleRate
        )
        store.addTrack(track, to: project)

        if let updated = store.project(id: pending.projectID) {
            let audioURL = store.audioURL(for: track, in: updated)
            let peaksURL = store.peaksURL(for: track, in: updated)
            Task.detached(priority: .utility) {
                try? PeakStore.computePeaks(audioURL: audioURL, peaksURL: peaksURL)
            }
        }
    }

    // MARK: - Transport

    /// Idempotent teardown. A recording in progress is finalized through
    /// `stopRecording` by callers; reaching here mid-record (interruption
    /// fallback) discards the partial file.
    func stopTransport() {
        if state == .recording {
            engine.inputNode.removeTap(onBus: 0)
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
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
            let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init) == .began
            guard began else { return }
            Task { @MainActor [weak self] in
                self?.handleTransportLoss()
            }
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init)
            guard reason == .oldDeviceUnavailable else { return }
            Task { @MainActor [weak self] in
                self?.handleTransportLoss()
            }
        }
    }

    /// Phone call or headphones yanked: keep the partial take, stop cleanly.
    private func handleTransportLoss() {
        switch state {
        case .recording:
            stopRecording()
        case .playing:
            stopTransport()
        case .idle:
            break
        }
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
        AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTicks(forSeconds: 0.1))
    }

    private func startLivePeakCollection() {
        livePeakTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(20))
                guard let self, self.state == .recording else { return }
                self.liveRecordingPeaks.append(self.meter.levels.peak)
            }
        }
    }
}

enum AufnError: LocalizedError {
    case microphonePermissionDenied
    case noInput

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "Microphone access is off. Enable it for Aufn in Settings to record."
        case .noInput:
            "No audio input is available."
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
