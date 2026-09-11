import AVFAudio
import Foundation
import Testing
@testable import Aufn

/// Startup recovery: a take whose file landed but whose Track entry never
/// did (crash mid-recording) is adopted; junk is swept.
@MainActor
struct ProjectStoreTests {
    private func makeRoot() -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "ProjectStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeCAF(at url: URL, seconds: Double, sampleRate: Double = 48_000) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
        buffer.frameLength = frames
        try file.write(from: buffer)
        file.close()
    }

    @Test func orphanTakeIsRecoveredAndJunkSwept() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let first = ProjectStore(rootDirectory: root)
        let project = try first.createProject(named: "Crashy")
        let listed = Track(name: "Track 1", fileName: "listed.caf", durationSeconds: 1, sampleRate: 48_000)
        first.addTrack(listed, to: project)
        try writeCAF(at: first.tracksDirectory(for: project).appending(path: "listed.caf"), seconds: 1)

        // The orphan: a complete CAF named by a UUID, no Track entry.
        let orphanID = UUID()
        try writeCAF(at: first.tracksDirectory(for: project).appending(path: "\(orphanID.uuidString).caf"), seconds: 2)
        // Junk: an empty CAF from a failed start, and a peaks cache for no track.
        let emptyURL = first.tracksDirectory(for: project).appending(path: "\(UUID().uuidString).caf")
        FileManager.default.createFile(atPath: emptyURL.path, contents: Data())
        let stalePeaks = first.peaksDirectory(for: project).appending(path: "\(UUID().uuidString).peaks")
        try Data([0, 0, 0, 0]).write(to: stalePeaks)

        let second = ProjectStore(rootDirectory: root)
        let reloaded = try #require(second.project(id: project.id))
        #expect(reloaded.tracks.count == 2)
        let recovered = try #require(reloaded.tracks.first { $0.id == orphanID })
        #expect(recovered.fileName == "\(orphanID.uuidString).caf")
        #expect(abs(recovered.durationSeconds - 2) < 0.01)
        #expect(recovered.latencyOffsetSamples == 0)
        #expect(recovered.name.contains("recovered"))
        #expect(!FileManager.default.fileExists(atPath: emptyURL.path))
        #expect(!FileManager.default.fileExists(atPath: stalePeaks.path))

        // Recovery is persisted: a third load sees the same two tracks.
        let third = ProjectStore(rootDirectory: root)
        #expect(third.project(id: project.id)?.tracks.count == 2)
    }

    @Test func peaksRevisionBumps() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootDirectory: root)
        let before = store.peaksRevision
        store.notePeaksUpdated()
        #expect(store.peaksRevision == before + 1)
    }

    @Test func consecutiveProjectsRotateTints() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootDirectory: root)
        let a = try store.createProject(named: "A")
        let b = try store.createProject(named: "B")
        let c = try store.createProject(named: "C")
        #expect(a.tint == ProjectTint.rotating(index: 0))
        #expect(b.tint == ProjectTint.rotating(index: 1))
        #expect(c.tint == ProjectTint.rotating(index: 2))
        #expect(Set([a.tint, b.tint, c.tint]).count == 3)
    }

    @Test func deleteTracksBatchRemovesFilesAndMetronomeInOnePersist() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootDirectory: root)
        var project = try store.createProject(named: "Batch")
        let keep = Track(name: "Keep", fileName: "keep.caf", durationSeconds: 0.1, sampleRate: 48_000)
        let a = Track(name: "A", fileName: "a.caf", durationSeconds: 0.1, sampleRate: 48_000)
        let b = Track(name: "B", fileName: "b.caf", durationSeconds: 0.1, sampleRate: 48_000)
        for track in [keep, a, b] {
            store.addTrack(track, to: project)
            try writeCAF(at: store.tracksDirectory(for: project).appending(path: track.fileName), seconds: 0.1)
            try Data([0, 0, 0, 0]).write(to: store.peaksURL(for: track, in: project))
        }
        project = try #require(store.project(id: project.id))
        project.metronome = MetronomeSettings()
        store.update(project)

        // A stale snapshot plus an unknown id: both must be harmless.
        store.deleteTracks(ids: [a.id, b.id, UUID()], removingMetronome: true, from: project)

        let after = try #require(store.project(id: project.id))
        #expect(after.tracks.map(\.id) == [keep.id])
        #expect(after.metronome == nil)
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: store.audioURL(for: keep, in: after).path))
        #expect(fm.fileExists(atPath: store.peaksURL(for: keep, in: after).path))
        for gone in [a, b] {
            #expect(!fm.fileExists(atPath: store.audioURL(for: gone, in: after).path))
            #expect(!fm.fileExists(atPath: store.peaksURL(for: gone, in: after).path))
        }

        // Persisted, not just in memory.
        let reloaded = ProjectStore(rootDirectory: root)
        #expect(reloaded.project(id: project.id)?.tracks.map(\.id) == [keep.id])
        #expect(reloaded.project(id: project.id)?.metronome == nil)
    }

    @Test func deleteTracksWithNothingToRemoveIsANoOp() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootDirectory: root)
        let project = try store.createProject(named: "Untouched")
        let track = Track(name: "Only", fileName: "only.caf", durationSeconds: 0.1, sampleRate: 48_000)
        store.addTrack(track, to: project)
        try writeCAF(at: store.tracksDirectory(for: project).appending(path: track.fileName), seconds: 0.1)

        store.deleteTracks(ids: [UUID()], from: project)

        let after = try #require(store.project(id: project.id))
        #expect(after.tracks.map(\.id) == [track.id])
        #expect(FileManager.default.fileExists(atPath: store.audioURL(for: track, in: after).path))
    }
}
