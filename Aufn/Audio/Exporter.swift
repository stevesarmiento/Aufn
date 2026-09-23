import AVFAudio
import Accelerate
import Foundation

/// Offline export: per-track 24-bit WAV stems (the primary deliverable),
/// zip packaging, and a stereo mixdown via manual offline rendering.
/// All functions run off the main actor; callers pass plain values/URLs.
enum Exporter {
    struct Stem: Sendable {
        let track: Track
        let audioURL: URL
    }

    private static let chunkFrames: AVAudioFrameCount = 65_536

    // MARK: - Stems

    /// Converts each track's Float32 CAF to a 24-bit WAV, skipping the stored
    /// latency-offset frames, into a fresh folder in tmp. Returns the folder.
    /// Stems are raw by default; `applyingVolume` bakes each track's volume in
    /// (pan is never baked into stems, mono or stereo; it only affects the mixdown).
    static func exportStems(_ stems: [Stem], projectName: String, applyingVolume: Bool = false) throws -> URL {
        let folder = try makeExportFolder(named: projectName)
        for (index, stem) in stems.enumerated() {
            let safeName = stem.track.name.replacingOccurrences(of: "/", with: "-")
            let destination = folder.appending(path: "\(String(format: "%02d", index + 1)) \(safeName).wav")
            try convertToWAV(
                source: stem.audioURL,
                destination: destination,
                skippingFrames: AVAudioFramePosition(stem.track.latencyOffsetSamples),
                gain: applyingVolume ? stem.track.volume : 1
            )
        }
        return folder
    }

    private static func convertToWAV(source: URL, destination: URL, skippingFrames offset: AVAudioFramePosition, gain: Float = 1) throws {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        // AVAudioFile converts Float32 -> int24 on write.
        let output = try AVAudioFile(forWriting: destination, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else { return }

        input.framePosition = min(offset, input.length)
        while input.framePosition < input.length {
            try input.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            if gain != 1, let channels = buffer.floatChannelData {
                var scalar = gain
                for channel in 0..<Int(format.channelCount) {
                    vDSP_vsmul(channels[channel], 1, &scalar, channels[channel], 1, vDSP_Length(buffer.frameLength))
                }
            }
            applyDither(buffer)
            try output.write(from: buffer)
        }
    }

    /// TPDF dither at the 24-bit LSB, added just before AVAudioFile quantizes
    /// Float32 -> int24. Decorrelates quantization error from the signal
    /// (removes low-level distortion on fades/quiet passages) at the cost of a
    /// vanishingly low noise floor. Applied to stems and the mixdown alike.
    private static func applyDither(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let lsb = Float(1) / Float(1 << 23) // 24-bit full-scale LSB in [-1, 1]
        let frames = Int(buffer.frameLength)
        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = channels[channel]
            for frame in 0..<frames {
                let triangular = Float.random(in: -0.5...0.5) + Float.random(in: -0.5...0.5)
                samples[frame] += triangular * lsb
            }
        }
    }

    // MARK: - Zip

    /// Zero-dependency zip: NSFileCoordinator's `.forUploading` option hands
    /// back a system-produced zip of the folder, which we copy out before the
    /// coordinated scope ends.
    static func zip(folder: URL) throws -> URL {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var copyResult: Result<URL, Error> = .failure(CocoaError(.fileNoSuchFile))
        coordinator.coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zipped in
            let destination = FileManager.default.temporaryDirectory
                .appending(path: "\(folder.lastPathComponent).zip")
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: zipped, to: destination)
                copyResult = .success(destination)
            } catch {
                copyResult = .failure(error)
            }
        }
        if let coordinationError { throw coordinationError }
        return try copyResult.get()
    }

    // MARK: - Mixdown

    /// Renders all stems into a stereo 24-bit WAV using a short-lived engine
    /// in offline manual-rendering mode.
    static func mixdown(_ stems: [Stem], projectName: String, sampleRate: Double, masterVolume: Float = 1) throws -> URL {
        let engine = AVAudioEngine()
        guard let renderFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false) else {
            throw CocoaError(.formatting)
        }
        try engine.enableManualRenderingMode(.offline, format: renderFormat, maximumFrameCount: 4096)

        var players: [(node: AVAudioPlayerNode, track: Track)] = []
        var longestSeconds: Double = 0
        for stem in stems {
            guard let file = try? AVAudioFile(forReading: stem.audioURL) else { continue }
            let offset = AVAudioFramePosition(stem.track.latencyOffsetSamples)
            let frameCount = AVAudioFrameCount(max(0, file.length - offset))
            guard frameCount > 0 else { continue }
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
            player.scheduleSegment(file, startingFrame: offset, frameCount: frameCount, at: nil)
            players.append((player, stem.track))
            longestSeconds = max(longestSeconds, Double(frameCount) / file.processingFormat.sampleRate)
        }
        guard !players.isEmpty else { throw CocoaError(.fileNoSuchFile) }

        engine.mainMixerNode.outputVolume = masterVolume
        try engine.start()
        // Mixing properties (pan especially) only take hold once the engine
        // has built the render graph — set them after start, before play.
        // Mixdown = what you hear, so mute/solo apply; stems stay raw/complete.
        // Solo state comes from the stems only: exports ignore the metronome
        // entirely, so a soloed click must not silence the mixdown.
        let anySoloed = stems.contains { $0.track.isSoloed }
        for (player, track) in players {
            player.volume = MixRules.effectiveVolume(for: track, anySoloed: anySoloed)
            player.pan = track.pan
            player.play()
        }

        let folder = try makeExportFolder(named: projectName)
        let destination = folder.appending(path: "\(projectName) Mixdown.wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = try AVAudioFile(forWriting: destination, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: renderFormat, frameCapacity: engine.manualRenderingMaximumFrameCount) else {
            throw CocoaError(.formatting)
        }

        let totalFrames = AVAudioFramePosition(longestSeconds * sampleRate)
        while engine.manualRenderingSampleTime < totalFrames {
            let remaining = AVAudioFrameCount(totalFrames - engine.manualRenderingSampleTime)
            let frames = min(remaining, engine.manualRenderingMaximumFrameCount)
            let status = try engine.renderOffline(frames, to: buffer)
            switch status {
            case .success:
                applyDither(buffer)
                try output.write(from: buffer)
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                continue
            case .error:
                throw CocoaError(.fileWriteUnknown)
            @unknown default:
                throw CocoaError(.fileWriteUnknown)
            }
        }
        engine.stop()
        return destination
    }

    // MARK: - Helpers

    static let exportFolderPrefix = "Aufn Export "

    /// One export set lives in tmp at a time: earlier folders (and their zip)
    /// are removed before the new one is created, so repeated exports don't
    /// pile up full-resolution WAVs.
    static func removeStaleExports() {
        let fileManager = FileManager.default
        let tmp = fileManager.temporaryDirectory
        let entries = (try? fileManager.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? []
        for url in entries where url.lastPathComponent.hasPrefix(exportFolderPrefix) {
            try? fileManager.removeItem(at: url)
        }
    }

    private static func makeExportFolder(named projectName: String) throws -> URL {
        removeStaleExports()
        let safeName = projectName.replacingOccurrences(of: "/", with: "-")
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "\(exportFolderPrefix)\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
            .appending(path: safeName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
