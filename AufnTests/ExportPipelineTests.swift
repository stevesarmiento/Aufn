import AVFAudio
import Testing
@testable import Aufn

/// End-to-end coverage of the offline pipeline: synthesize a Float32 CAF the
/// way TrackRecorder writes one, then verify peaks computation, stem export
/// to 24-bit WAV (with latency-offset trimming), zip, and mixdown.
/// Serialized: every export sweeps earlier export folders out of tmp, so
/// parallel tests would delete each other's output.
@Suite(.serialized)
struct ExportPipelineTests {
    /// One entry per channel: the sine's amplitude on that channel.
    private func makeCAF(seconds: Double, sampleRate: Double = 48_000, frequency: Double = 440, channelGains: [Float] = [0.5]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).caf")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelGains.count,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        for frame in 0..<Int(frames) {
            let sample = Float(sin(2 * .pi * frequency * Double(frame) / sampleRate))
            for (channel, gain) in channelGains.enumerated() {
                buffer.floatChannelData![channel][frame] = sample * gain
            }
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

    @Test func newExportSweepsPreviousExportFolders() throws {
        let caf = try makeCAF(seconds: 0.2)
        let track = Track(name: "Track 1", fileName: caf.lastPathComponent, durationSeconds: 0.2, sampleRate: 48_000)
        let first = try Exporter.exportStems([.init(track: track, audioURL: caf)], projectName: "First")
        #expect(FileManager.default.fileExists(atPath: first.path))
        let second = try Exporter.exportStems([.init(track: track, audioURL: caf)], projectName: "Second")
        #expect(FileManager.default.fileExists(atPath: second.path))
        // The first export's top-level "Aufn Export <id>" folder is gone.
        #expect(!FileManager.default.fileExists(atPath: first.deletingLastPathComponent().path))
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

    private func mixdownPeaks(volume: Float = 1, pan: Float = 0, masterVolume: Float = 1, channelGains: [Float] = [0.5]) throws -> [Float] {
        let sampleRate = 48_000.0
        let caf = try makeCAF(seconds: 0.5, sampleRate: sampleRate, channelGains: channelGains)
        let track = Track(name: "T", fileName: caf.lastPathComponent, durationSeconds: 0.5, sampleRate: sampleRate, channelCount: channelGains.count, volume: volume, pan: pan)
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

        // Each export sweeps the previous one out of tmp, so read the first
        // render before producing the second.
        let soloMix = try Exporter.mixdown(
            [.init(track: soloed, audioURL: cafA), .init(track: other, audioURL: cafB)],
            projectName: "Solo", sampleRate: sampleRate
        )
        let mixPeak = try channelPeaks(of: soloMix)[0]
        let soloAlone = try Exporter.mixdown(
            [.init(track: soloed, audioURL: cafA)],
            projectName: "SoloAlone", sampleRate: sampleRate
        )
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

        // Read the raw stem before the baked export sweeps its folder.
        let rawFolder = try Exporter.exportStems([stem], projectName: "Raw")
        let rawPeak = try channelPeaks(of: FileManager.default.contentsOfDirectory(at: rawFolder, includingPropertiesForKeys: nil)[0])[0]
        let bakedFolder = try Exporter.exportStems([stem], projectName: "Baked", applyingVolume: true)
        let bakedPeak = try channelPeaks(of: FileManager.default.contentsOfDirectory(at: bakedFolder, includingPropertiesForKeys: nil)[0])[0]
        #expect(abs(bakedPeak / rawPeak - 0.5) < 0.05)
    }

    // MARK: - Stereo takes

    @Test func peaksUseAllChannels() throws {
        // Right-channel-only signal: peaks derived from channel 0 alone would be zero.
        let caf = try makeCAF(seconds: 1.0, channelGains: [0, 0.5])
        let peaksURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).peaks")
        try PeakStore.computePeaks(audioURL: caf, peaksURL: peaksURL)
        let peaks = try #require(PeakStore.loadPeaks(from: peaksURL))
        #expect(peaks.count == 50)
        #expect(peaks.allSatisfy { $0 > 0.4 && $0 <= 0.51 })
    }

    @Test func stemExportPreservesStereoChannels() throws {
        let sampleRate = 48_000.0
        let caf = try makeCAF(seconds: 1.0, sampleRate: sampleRate, channelGains: [0, 0.5])
        let track = Track(name: "Stereo", fileName: caf.lastPathComponent, durationSeconds: 1.0, sampleRate: sampleRate, channelCount: 2)
        let folder = try Exporter.exportStems([.init(track: track, audioURL: caf)], projectName: "Stereo")
        let wav = try #require(try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first)
        #expect(try AVAudioFile(forReading: wav).fileFormat.channelCount == 2)
        let peaks = try channelPeaks(of: wav)
        #expect(peaks[0] < 0.02)
        #expect(peaks[1] > 0.4)
    }

    @Test func mixdownPreservesStereoImage() throws {
        // A left-only stereo source at pan 0 must not be collapsed to mono.
        let peaks = try mixdownPeaks(pan: 0, channelGains: [0.5, 0])
        #expect(peaks[0] > 0.2)
        #expect(peaks[1] < 0.02)
    }

    @Test func mixdownPanActsAsBalanceOnStereoTrack() throws {
        let hardLeft = try mixdownPeaks(pan: -1, channelGains: [0.5, 0.5])
        #expect(hardLeft[0] > 0.2)
        #expect(hardLeft[1] < 0.02)
        let hardRight = try mixdownPeaks(pan: 1, channelGains: [0.5, 0.5])
        #expect(hardRight[0] < 0.02)
        #expect(hardRight[1] > 0.2)
    }

    @Test func mixdownMixesMonoAndStereoTracks() throws {
        let sampleRate = 48_000.0
        let mono = try makeCAF(seconds: 1.0, sampleRate: sampleRate)
        let stereo = try makeCAF(seconds: 1.5, sampleRate: sampleRate, channelGains: [0, 0.5])
        let stems: [Exporter.Stem] = [
            .init(track: Track(name: "Mono", fileName: mono.lastPathComponent, durationSeconds: 1.0, sampleRate: sampleRate), audioURL: mono),
            .init(track: Track(name: "Stereo", fileName: stereo.lastPathComponent, durationSeconds: 1.5, sampleRate: sampleRate, channelCount: 2), audioURL: stereo),
        ]
        let url = try Exporter.mixdown(stems, projectName: "Mixed", sampleRate: sampleRate)
        let file = try AVAudioFile(forReading: url)
        #expect(abs(Double(file.length) / sampleRate - 1.5) < 0.05)
        let peaks = try channelPeaks(of: url)
        #expect(peaks[0] > 0.2)
        #expect(peaks[1] > 0.2)
    }

    @Test func exportScopeKeepsProjectOrderAndIgnoresUnknownIDs() {
        let t1 = Track(name: "1", fileName: "1.caf", sampleRate: 48_000)
        let t2 = Track(name: "2", fileName: "2.caf", sampleRate: 48_000)
        let t3 = Track(name: "3", fileName: "3.caf", sampleRate: 48_000)
        let project = Project(name: "P", tracks: [t1, t2, t3])
        #expect(project.tracks(limitedTo: nil).map(\.id) == [t1.id, t2.id, t3.id])
        #expect(project.tracks(limitedTo: [t3.id, t1.id, UUID()]).map(\.id) == [t1.id, t3.id])
        #expect(project.tracks(limitedTo: []).isEmpty)
    }
}
