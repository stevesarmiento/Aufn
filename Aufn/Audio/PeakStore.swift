import AVFAudio
import Accelerate
import Foundation

/// Precomputes and caches waveform peak data so views never read audio files.
/// Cache format: raw little-endian Float32 peak magnitudes, one per 20 ms bin.
enum PeakStore {
    static let binDuration: Double = 0.02
    private static let chunkFrames: AVAudioFrameCount = 65_536

    /// Reads the CAF in chunks and writes the peaks cache. Runs off the main
    /// actor (called from a detached task after a take finalizes).
    static func computePeaks(audioURL: URL, peaksURL: URL) throws {
        let file = try AVAudioFile(forReading: audioURL)
        let format = file.processingFormat
        let binFrames = max(1, Int(binDuration * format.sampleRate))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else { return }

        var peaks: [Float] = []
        peaks.reserveCapacity(Int(file.length) / binFrames + 1)
        var currentPeak: Float = 0
        var framesInBin = 0

        let channelCount = Int(format.channelCount)
        while file.framePosition < file.length {
            try file.read(into: buffer)
            guard let channels = buffer.floatChannelData else { break }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { break }

            var index = 0
            while index < frameCount {
                let take = min(binFrames - framesInBin, frameCount - index)
                // A bin's peak is the loudest sample on any channel.
                for channel in 0..<channelCount {
                    var chunkPeak: Float = 0
                    vDSP_maxmgv(channels[channel] + index, 1, &chunkPeak, vDSP_Length(take))
                    currentPeak = max(currentPeak, chunkPeak)
                }
                framesInBin += take
                index += take
                if framesInBin >= binFrames {
                    peaks.append(currentPeak)
                    currentPeak = 0
                    framesInBin = 0
                }
            }
        }
        if framesInBin > 0 {
            peaks.append(currentPeak)
        }

        try writePeaks(peaks, to: peaksURL)
    }

    /// Writes a peaks cache in the same layout `loadPeaks` reads. Also used
    /// for the provisional live-meter cache written the instant a take ends.
    static func writePeaks(_ peaks: [Float], to peaksURL: URL) throws {
        let data = peaks.withUnsafeBufferPointer { Data(buffer: $0) }
        try FileManager.default.createDirectory(at: peaksURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: peaksURL, options: .atomic)
    }

    static func loadPeaks(from url: URL) -> [Float]? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        let count = data.count / MemoryLayout<Float>.size
        return data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self).prefix(count))
        }
    }
}
