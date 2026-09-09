import AVFAudio

/// Writes input-tap buffers to a 32-bit float CAF file, dropping frames that
/// arrive before the shared transport start time so file frame 0 lines up with
/// playback t=0. Created on the main actor; after that only the tap thread
/// touches it until `finalize()` (guarded by a lock — the tap runs on an
/// AVFoundation worker thread, not the realtime render thread, so a brief
/// uncontended lock is safe there).
final class TrackRecorder: @unchecked Sendable {
    /// What `finalize()` hands back: frames on disk plus the first write
    /// error, if any (a disk-full take is truncated, not silently "fine").
    struct Outcome {
        let frames: AVAudioFramePosition
        let writeError: Error?
    }

    private let file: AVAudioFile
    private let startHostTime: UInt64
    private let sampleRate: Double
    private let hostTicksToSeconds: Double

    private let lock = NSLock()
    private var passedStart = false
    private var finished = false
    private var framesWritten: AVAudioFramePosition = 0
    private var writeError: Error?

    let fileURL: URL

    init(fileURL: URL, format: AVAudioFormat, startHostTime: UInt64) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]
        self.fileURL = fileURL
        self.file = try AVAudioFile(forWriting: fileURL, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        self.startHostTime = startHostTime
        self.sampleRate = format.sampleRate

        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        self.hostTicksToSeconds = Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }

    /// Tap-thread entry point.
    func append(_ buffer: AVAudioPCMBuffer, at when: AVAudioTime) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }

        if passedStart {
            write(buffer)
            return
        }

        // No host clock on this buffer (seen after IO-unit rebuilds): there
        // is nothing to gate against, so record rather than silently drop
        // the whole take.
        guard when.isHostTimeValid else {
            passedStart = true
            write(buffer)
            return
        }

        guard when.hostTime < startHostTime else {
            passedStart = true
            write(buffer)
            return
        }

        let secondsUntilStart = Double(startHostTime - when.hostTime) * hostTicksToSeconds
        // Clamp before converting: a bogus timestamp far in the past would
        // otherwise overflow the UInt32 conversion and trap the tap thread.
        let framesToSkip = AVAudioFrameCount(min(secondsUntilStart * sampleRate, Double(UInt32.max)))
        guard framesToSkip < buffer.frameLength else { return }

        passedStart = true
        if let trimmed = Self.trimmingHead(of: buffer, frames: framesToSkip) {
            write(trimmed)
        }
    }

    /// Main-actor entry point after `removeTap`. Closes the file so the CAF
    /// header is final before anyone reads it (peaks, playback, export).
    func finalize() -> Outcome {
        lock.lock()
        defer { lock.unlock() }
        if !finished {
            finished = true
            file.close()
        }
        return Outcome(frames: framesWritten, writeError: writeError)
    }

    private func write(_ buffer: AVAudioPCMBuffer) {
        do {
            try file.write(from: buffer)
            framesWritten += AVAudioFramePosition(buffer.frameLength)
        } catch {
            writeError = error
            finished = true
            file.close()
        }
    }

    /// One-time copy for the buffer that straddles the start boundary.
    private static func trimmingHead(of buffer: AVAudioPCMBuffer, frames: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        let remaining = buffer.frameLength - frames
        guard remaining > 0,
              let source = buffer.floatChannelData,
              let trimmed = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: remaining),
              let destination = trimmed.floatChannelData else { return nil }
        for channel in 0..<Int(buffer.format.channelCount) {
            destination[channel].update(from: source[channel] + Int(frames), count: Int(remaining))
        }
        trimmed.frameLength = remaining
        return trimmed
    }
}
