import AVFAudio
import Testing
@testable import Aufn

/// End-to-end coverage of the offline pipeline: synthesize a Float32 CAF the
/// way TrackRecorder writes one, then verify peaks computation, stem export
/// to 24-bit WAV (with latency-offset trimming), zip, and mixdown.
struct ExportPipelineTests {
    private func makeCAF(seconds: Double, sampleRate: Double = 48_000, frequency: Double = 440) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).caf")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        for frame in 0..<Int(frames) {
            buffer.floatChannelData![0][frame] = Float(sin(2 * .pi * frequency * Double(frame) / sampleRate)) * 0.5
        }
        buffer.frameLength = frames
        try file.write(from: buffer)
        return url
    }

    @Test func peaksComputeAndLoad() throws {
        let caf = try makeCAF(seconds: 1.0)
        let peaksURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).peaks")
        try PeakStore.computePeaks(audioURL: caf, peaksURL: peaksURL)
        let peaks = try #require(PeakStore.loadPeaks(from: peaksURL))
        // 1 s at 20 ms bins = 50 bins; sine at amplitude 0.5 peaks near 0.5.
        #expect(peaks.count == 50)
        #expect(peaks.allSatisfy { $0 > 0.4 && $0 <= 0.51 })
    }

    @Test func stemExportProduces24BitWAVWithOffsetTrimmed() throws {
        let sampleRate = 48_000.0
        let caf = try makeCAF(seconds: 2.0, sampleRate: sampleRate)
        let offsetSamples = Int(sampleRate * 0.5)
        let track = Track(name: "Track 1", fileName: caf.lastPathComponent, latencyOffsetSamples: offsetSamples, durationSeconds: 2.0, sampleRate: sampleRate)
        let folder = try Exporter.exportStems([.init(track: track, audioURL: caf)], projectName: "Test")

        let wavs = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        #expect(wavs.count == 1)
        let wav = try AVAudioFile(forReading: wavs[0])
        #expect(wav.fileFormat.sampleRate == sampleRate)
        let bitDepth = wav.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int
        #expect(bitDepth == 24)
        // 2 s minus the 0.5 s latency offset.
        #expect(abs(Double(wav.length) / sampleRate - 1.5) < 0.01)
    }

    @Test func zipProducesArchive() throws {
        let caf = try makeCAF(seconds: 0.5)
        let track = Track(name: "Track 1", fileName: caf.lastPathComponent, durationSeconds: 0.5, sampleRate: 48_000)
        let folder = try Exporter.exportStems([.init(track: track, audioURL: caf)], projectName: "ZipTest")
        let zip = try Exporter.zip(folder: folder)
        let size = try #require(try zip.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        #expect(zip.pathExtension == "zip")
        #expect(size > 1_000)
    }

    @Test func mixdownRendersStereoWAV() throws {
        let sampleRate = 48_000.0
        let cafA = try makeCAF(seconds: 1.0, sampleRate: sampleRate, frequency: 440)
        let cafB = try makeCAF(seconds: 1.5, sampleRate: sampleRate, frequency: 220)
        let stems: [Exporter.Stem] = [
            .init(track: Track(name: "Track 1", fileName: cafA.lastPathComponent, durationSeconds: 1.0, sampleRate: sampleRate), audioURL: cafA),
            .init(track: Track(name: "Track 2", fileName: cafB.lastPathComponent, durationSeconds: 1.5, sampleRate: sampleRate), audioURL: cafB),
        ]
        let url = try Exporter.mixdown(stems, projectName: "Mix", sampleRate: sampleRate)
        let wav = try AVAudioFile(forReading: url)
        #expect(wav.fileFormat.channelCount == 2)
        #expect((wav.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int) == 24)
        // Length matches the longest stem.
        #expect(abs(Double(wav.length) / sampleRate - 1.5) < 0.05)

        // The render actually contains signal, not silence.
        let buffer = AVAudioPCMBuffer(pcmFormat: wav.processingFormat, frameCapacity: AVAudioFrameCount(wav.length))!
        try wav.read(into: buffer)
        var peak: Float = 0
        for frame in 0..<Int(buffer.frameLength) {
            peak = max(peak, abs(buffer.floatChannelData![0][frame]))
        }
        #expect(peak > 0.2)
    }

    // MARK: - Mix levels

    private func channelPeaks(of url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        return (0..<Int(file.processingFormat.channelCount)).map { channel in
            var peak: Float = 0
            for frame in 0..<Int(buffer.frameLength) {
                peak = max(peak, abs(buffer.floatChannelData![channel][frame]))
            }
            return peak
        }
    }

    private func mixdownPeaks(volume: Float = 1, pan: Float = 0, masterVolume: Float = 1) throws -> [Float] {
        let sampleRate = 48_000.0
        let caf = try makeCAF(seconds: 0.5, sampleRate: sampleRate)
        let track = Track(name: "T", fileName: caf.lastPathComponent, durationSeconds: 0.5, sampleRate: sampleRate, volume: volume, pan: pan)
        let url = try Exporter.mixdown([.init(track: track, audioURL: caf)], projectName: "Levels", sampleRate: sampleRate, masterVolume: masterVolume)
        return try channelPeaks(of: url)
    }

    @Test func mixdownRespectsTrackVolume() throws {
        let full = try mixdownPeaks(volume: 1.0)
        let half = try mixdownPeaks(volume: 0.5)
        // Ratio-based so the mixer's mono->stereo pan law doesn't matter.
        #expect(abs(half[0] / full[0] - 0.5) < 0.05)
    }

    @Test func mixdownRespectsPan() throws {
        let hardLeft = try mixdownPeaks(pan: -1)
        #expect(hardLeft[0] > 0.2)
        #expect(hardLeft[1] < 0.02)
    }

    @Test func mixdownRespectsMasterVolume() throws {
        let full = try mixdownPeaks()
        let half = try mixdownPeaks(masterVolume: 0.5)
        #expect(abs(half[0] / full[0] - 0.5) < 0.05)
    }

    @Test func mixdownExcludesMutedTrack() throws {
        let sampleRate = 48_000.0
        let caf = try makeCAF(seconds: 0.5, sampleRate: sampleRate)
        let track = Track(name: "T", fileName: caf.lastPathComponent, isMuted: true, durationSeconds: 0.5, sampleRate: sampleRate)
        let url = try Exporter.mixdown([.init(track: track, audioURL: caf)], projectName: "Muted", sampleRate: sampleRate)
        let peaks = try channelPeaks(of: url)
        #expect(peaks[0] < 0.02)
        #expect(peaks[1] < 0.02)
    }

    @Test func mixdownHonorsSolo() throws {
        let sampleRate = 48_000.0
        let cafA = try makeCAF(seconds: 0.5, sampleRate: sampleRate, frequency: 440)
        let cafB = try makeCAF(seconds: 0.5, sampleRate: sampleRate, frequency: 220)
        let soloed = Track(name: "A", fileName: cafA.lastPathComponent, isSoloed: true, durationSeconds: 0.5, sampleRate: sampleRate)
        let other = Track(name: "B", fileName: cafB.lastPathComponent, durationSeconds: 0.5, sampleRate: sampleRate)

        let soloMix = try Exporter.mixdown(
            [.init(track: soloed, audioURL: cafA), .init(track: other, audioURL: cafB)],
            projectName: "Solo", sampleRate: sampleRate
        )
        let soloAlone = try Exporter.mixdown(
            [.init(track: soloed, audioURL: cafA)],
            projectName: "SoloAlone", sampleRate: sampleRate
        )
        let mixPeak = try channelPeaks(of: soloMix)[0]
        let alonePeak = try channelPeaks(of: soloAlone)[0]
        // Non-soloed track contributes nothing: mix matches the solo-only render.
        #expect(abs(mixPeak / alonePeak - 1) < 0.05)
    }

    @Test func mixdownMuteBeatsSolo() throws {
        let sampleRate = 48_000.0
        let caf = try makeCAF(seconds: 0.5, sampleRate: sampleRate)
        let track = Track(name: "T", fileName: caf.lastPathComponent, isMuted: true, isSoloed: true, durationSeconds: 0.5, sampleRate: sampleRate)
        let url = try Exporter.mixdown([.init(track: track, audioURL: caf)], projectName: "MS", sampleRate: sampleRate)
        #expect(try channelPeaks(of: url)[0] < 0.02)
    }

    @Test func stemExportBakesVolumeWhenAsked() throws {
        let sampleRate = 48_000.0
        let caf = try makeCAF(seconds: 0.5, sampleRate: sampleRate)
        let track = Track(name: "T", fileName: caf.lastPathComponent, durationSeconds: 0.5, sampleRate: sampleRate, volume: 0.5)
        let stem = Exporter.Stem(track: track, audioURL: caf)

        let rawFolder = try Exporter.exportStems([stem], projectName: "Raw")
        let bakedFolder = try Exporter.exportStems([stem], projectName: "Baked", applyingVolume: true)
        let rawPeak = try channelPeaks(of: FileManager.default.contentsOfDirectory(at: rawFolder, includingPropertiesForKeys: nil)[0])[0]
        let bakedPeak = try channelPeaks(of: FileManager.default.contentsOfDirectory(at: bakedFolder, includingPropertiesForKeys: nil)[0])[0]
        #expect(abs(bakedPeak / rawPeak - 0.5) < 0.05)
    }
}
