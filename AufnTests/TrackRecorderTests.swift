import AVFAudio
import Testing
@testable import Aufn

/// The recorder's start gate and finalization: buffers without a host clock
/// must record (not vanish), the boundary buffer must be trimmed, and the
/// file must be readable at full length the moment finalize() returns.
struct TrackRecorderTests {
    private let sampleRate = 48_000.0

    private func makeRecorder(startInSeconds: Double) throws -> (TrackRecorder, URL) {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).caf")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let start = mach_absolute_time() + AVAudioTime.hostTicks(forSeconds: startInSeconds)
        return (try TrackRecorder(fileURL: url, format: format, startHostTime: start), url)
    }

    private func makeBuffer(seconds: Double) throws -> AVAudioPCMBuffer {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for frame in 0..<Int(frames) {
            buffer.floatChannelData![0][frame] = 0.25
        }
        return buffer
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
}
