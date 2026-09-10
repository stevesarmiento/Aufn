import AVFAudio
import Testing
@testable import Aufn

/// The recorder's start gate and finalization: buffers without a host clock
/// must record (not vanish), the boundary buffer must be trimmed, and the
/// file must be readable at full length the moment finalize() returns.
struct TrackRecorderTests {
    private let sampleRate = 48_000.0

    private func makeRecorder(startInSeconds: Double, channels: AVAudioChannelCount = 1) throws -> (TrackRecorder, URL) {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).caf")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels))
        let start = mach_absolute_time() + AVAudioTime.hostTicks(forSeconds: startInSeconds)
        return (try TrackRecorder(fileURL: url, format: format, startHostTime: start), url)
    }

    /// One level per channel (mono 0.25 by default).
    private func makeBuffer(seconds: Double, channelLevels: [Float] = [0.25]) throws -> AVAudioPCMBuffer {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channelLevels.count)))
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for (channel, level) in channelLevels.enumerated() {
            for frame in 0..<Int(frames) {
                buffer.floatChannelData![channel][frame] = level
            }
        }
        return buffer
    }

    private func channelPeaks(of url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        return (0..<Int(file.processingFormat.channelCount)).map { channel in
            (0..<Int(buffer.frameLength)).reduce(Float(0)) { max($0, abs(buffer.floatChannelData![channel][$1])) }
        }
    }

    @Test func invalidHostTimeRecordsInsteadOfDropping() throws {
        let (recorder, url) = try makeRecorder(startInSeconds: 10)
        // Sample-time-only timestamp: isHostTimeValid == false.
        recorder.append(try makeBuffer(seconds: 0.5), at: AVAudioTime(sampleTime: 0, atRate: sampleRate))
        let outcome = recorder.finalize()
        #expect(outcome.frames == AVAudioFramePosition(0.5 * sampleRate))
        #expect(outcome.writeError == nil)
        try? FileManager.default.removeItem(at: url)
    }

    @Test func boundaryBufferIsTrimmedToTheStart() throws {
        let (recorder, url) = try makeRecorder(startInSeconds: 1.0)
        // A 2 s buffer whose first frame is ~0.5 s before the gate: about
        // 0.5 s should be skipped and ~1.5 s written.
        let when = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTicks(forSeconds: 0.5))
        recorder.append(try makeBuffer(seconds: 2.0), at: when)
        let frames = recorder.finalize().frames
        let written = Double(frames) / sampleRate
        #expect(abs(written - 1.5) < 0.05)
        try? FileManager.default.removeItem(at: url)
    }

    @Test func wholeBufferBeforeStartIsDropped() throws {
        let (recorder, url) = try makeRecorder(startInSeconds: 5.0)
        recorder.append(try makeBuffer(seconds: 1.0), at: AVAudioTime(hostTime: mach_absolute_time()))
        #expect(recorder.finalize().frames == 0)
        try? FileManager.default.removeItem(at: url)
    }

    @Test func finalizeClosesFileForImmediateReaders() throws {
        let (recorder, url) = try makeRecorder(startInSeconds: 0)
        recorder.append(try makeBuffer(seconds: 1.0), at: AVAudioTime(hostTime: mach_absolute_time()))
        recorder.append(try makeBuffer(seconds: 1.0), at: AVAudioTime(hostTime: mach_absolute_time()))
        let outcome = recorder.finalize()
        let reader = try AVAudioFile(forReading: url)
        #expect(reader.length == outcome.frames)
        #expect(reader.length == AVAudioFramePosition(2 * sampleRate))
        // Appends after finalize are ignored, not written.
        recorder.append(try makeBuffer(seconds: 1.0), at: AVAudioTime(hostTime: mach_absolute_time()))
        #expect(recorder.finalize().frames == outcome.frames)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Stereo takes

    @Test func stereoBuffersWriteBothChannels() throws {
        let (recorder, url) = try makeRecorder(startInSeconds: 0, channels: 2)
        recorder.append(try makeBuffer(seconds: 0.5, channelLevels: [0, 0.25]), at: AVAudioTime(hostTime: mach_absolute_time()))
        recorder.append(try makeBuffer(seconds: 0.5, channelLevels: [0, 0.25]), at: AVAudioTime(hostTime: mach_absolute_time()))
        let outcome = recorder.finalize()
        #expect(outcome.frames == AVAudioFramePosition(sampleRate))
        let reader = try AVAudioFile(forReading: url)
        #expect(reader.processingFormat.channelCount == 2)
        let peaks = try channelPeaks(of: url)
        #expect(peaks[0] == 0)
        #expect(abs(peaks[1] - 0.25) < 0.001)
        try? FileManager.default.removeItem(at: url)
    }

    @Test func boundaryTrimKeepsBothChannels() throws {
        let (recorder, url) = try makeRecorder(startInSeconds: 1.0, channels: 2)
        let when = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTicks(forSeconds: 0.5))
        recorder.append(try makeBuffer(seconds: 2.0, channelLevels: [0.1, 0.25]), at: when)
        let frames = recorder.finalize().frames
        #expect(abs(Double(frames) / sampleRate - 1.5) < 0.05)
        let peaks = try channelPeaks(of: url)
        #expect(abs(peaks[0] - 0.1) < 0.001)
        #expect(abs(peaks[1] - 0.25) < 0.001)
        try? FileManager.default.removeItem(at: url)
    }
}
