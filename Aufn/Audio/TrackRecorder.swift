import AVFAudio

/// Writes input-tap buffers to a 32-bit float CAF file, dropping frames that
/// arrive before the shared transport start time so file frame 0 lines up with
/// playback t=0. Created on the main actor; after that only the tap thread
/// touches it until `finalize()` (guarded by a lock — the tap runs on an
/// AVFoundation worker thread, not the realtime render thread, so a brief
/// uncontended lock is safe there).
final class TrackRecorder: @unchecked Sendable {
    private let file: AVAudioFile
    private let startHostTime: UInt64
    private let sampleRate: Double
    private let hostTicksToSeconds: Double

    private let lock = NSLock()
    private var passedStart = false
    private var finished = false
    private var framesWritten: AVAudioFramePosition = 0

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

        guard when.hostTime < startHostTime else {
            passedStart = true
            write(buffer)
            return
        }

        let secondsUntilStart = Double(startHostTime - when.hostTime) * hostTicksToSeconds
        let framesToSkip = AVAudioFrameCount(secondsUntilStart * sampleRate)
        guard framesToSkip < buffer.frameLength else { return }

        passedStart = true
        if let trimmed = Self.trimmingHead(of: buffer, frames: framesToSkip) {
            write(trimmed)
        }
    }

    /// Main-actor entry point after `removeTap`. Returns duration in frames.
    func finalize() -> AVAudioFramePosition {
        lock.lock()
        defer { lock.unlock() }
        finished = true
        return framesWritten
    }

    private func write(_ buffer: AVAudioPCMBuffer) {
        do {
            try file.write(from: buffer)
            framesWritten += AVAudioFramePosition(buffer.frameLength)
        } catch {
            finished = true
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
