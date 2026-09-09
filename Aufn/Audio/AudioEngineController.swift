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
            guard !players.isEmpty else { return }
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

    // MARK: - Recording

    func startRecording(into project: Project) async {
        stopTransport()
        guard await session.requestRecordPermission() else {
            lastError = AufnError.microphonePermissionDenied.localizedDescription
            return
        }
        do {
            try session.configure(preferredSampleRate: project.sampleRate ?? UserDefaults.standard.preferredSampleRate, output: .standard, recording: true)

            schedulePlayers(for: project)

            let inputFormat = engine.inputNode.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0 else { throw AufnError.noInput }

            let trackID = UUID()
            let fileURL = store.tracksDirectory(for: project).appending(path: "\(trackID.uuidString).caf")
            let startTime = sharedStartTime()
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

            state = .recording
            transportStartDate = .now
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
        return Date.now.timeIntervalSince(transportStartDate)
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

    /// Mixing properties (pan especially) only take hold once the engine has
    /// built its render graph — apply them after engine.start(). Skipped when
    /// there's no playback: on a first take the input tap is live but the mixer
    /// isn't instantiated yet, and touching mainMixerNode here would rebuild the
    /// graph mid-capture and reset the tap (every frame then reads as pre-start
    /// and gets dropped). With players present the mixer is already connected
    /// before start, so setting properties is safe.
    private func applyMixSettings(for project: Project) {
        guard !players.isEmpty else { return }
        engine.mainMixerNode.outputVolume = project.masterVolume
        for track in project.tracks {
            guard let player = players[track.id] else { continue }
            player.volume = project.effectiveVolume(for: track)
            player.pan = track.pan
        }
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

    /// Common start ~100 ms out; all players and the record gate share it.
    private func sharedStartTime() -> AVAudioTime {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let ticksPerSecond = Double(timebase.denom) / Double(timebase.numer) * 1_000_000_000
        let delayTicks = UInt64(0.1 * ticksPerSecond)
        return AVAudioTime(hostTime: mach_absolute_time() + delayTicks)
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

extension UserDefaults {
    var preferredSampleRate: Double {
        let rate = double(forKey: "preferredSampleRate")
        return rate > 0 ? rate : 48_000
    }
}
