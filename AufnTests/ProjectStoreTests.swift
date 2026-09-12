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
        // Deleted takes move to the trash rather than vanishing.
        #expect(after.deletedTracks.map(\.id) == [a.id, b.id])
        for gone in [a, b] {
            #expect(!fm.fileExists(atPath: store.audioURL(for: gone, in: after).path))
            #expect(!fm.fileExists(atPath: store.peaksURL(for: gone, in: after).path))
            #expect(fm.fileExists(atPath: store.trashedAudioURL(forTrackID: gone.id, in: after).path))
            #expect(fm.fileExists(atPath: store.trashedPeaksURL(forTrackID: gone.id, in: after).path))
        }

        // Persisted, not just in memory.
        let reloaded = ProjectStore(rootDirectory: root)
        #expect(reloaded.project(id: project.id)?.tracks.map(\.id) == [keep.id])
        #expect(reloaded.project(id: project.id)?.metronome == nil)
        #expect(reloaded.project(id: project.id)?.deletedTracks.map(\.id) == [a.id, b.id])
    }

    // MARK: - Trash

    /// Adds a listed track with a real CAF and a peaks cache on disk.
    private func seed(_ track: Track, in project: Project, store: ProjectStore) throws {
        store.addTrack(track, to: project)
        try writeCAF(at: store.tracksDirectory(for: project).appending(path: track.fileName), seconds: 0.1)
        try Data([0, 0, 0, 0]).write(to: store.peaksURL(for: track, in: project))
    }

    @Test func deleteTracksRecordsFullSnapshotAndTimestamp() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootDirectory: root)
        let project = try store.createProject(named: "Trash")
        let track = Track(name: "Vox", fileName: "vox.caf", isMuted: true, durationSeconds: 0.1, sampleRate: 48_000, volume: 0.4, pan: -0.5, captureMode: .warm)
        try seed(track, in: project, store: store)

        store.deleteTracks(ids: [track.id], from: project)

        let after = try #require(store.project(id: project.id))
        let entry = try #require(after.deletedTracks.first)
        #expect(entry.track == track)
        #expect(abs(entry.deletedAt.timeIntervalSinceNow) < 5)
        #expect(after.tracks.isEmpty)
    }

    @Test func restoreTrackReinsertsChronologicallyWithMetadataIntact() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootDirectory: root)
        let project = try store.createProject(named: "Restore")
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let a = Track(name: "A", fileName: "a.caf", createdAt: t0, durationSeconds: 0.1, sampleRate: 48_000)
        let b = Track(name: "B", fileName: "b.caf", createdAt: t0.addingTimeInterval(60), durationSeconds: 0.1, sampleRate: 48_000, volume: 0.4, pan: -0.5, captureMode: .warm)
        let c = Track(name: "C", fileName: "c.caf", createdAt: t0.addingTimeInterval(120), durationSeconds: 0.1, sampleRate: 48_000)
        for track in [a, b, c] {
            try seed(track, in: project, store: store)
        }

        store.deleteTracks(ids: [b.id], from: project)
        #expect(store.project(id: project.id)?.tracks.map(\.id) == [a.id, c.id])

        let restored = try #require(store.restoreTrack(id: b.id, in: project))
        let after = try #require(store.project(id: project.id))
        #expect(after.tracks.map(\.id) == [a.id, b.id, c.id])
        #expect(after.deletedTracks.isEmpty)
        #expect(restored == b)
        #expect(after.tracks[1].volume == 0.4)
        #expect(after.tracks[1].pan == -0.5)
        #expect(after.tracks[1].captureMode == .warm)
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: store.audioURL(for: b, in: after).path))
        #expect(fm.fileExists(atPath: store.peaksURL(for: b, in: after).path))
        #expect(!fm.fileExists(atPath: store.trashedAudioURL(forTrackID: b.id, in: after).path))
        #expect(!fm.fileExists(atPath: store.trashedPeaksURL(forTrackID: b.id, in: after).path))

        let reloaded = ProjectStore(rootDirectory: root)
        #expect(reloaded.project(id: project.id)?.tracks.map(\.id) == [a.id, b.id, c.id])
        #expect(reloaded.project(id: project.id)?.deletedTracks.isEmpty == true)
    }

    @Test func restoreAppendsAfterOlderTracks() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootDirectory: root)
        let project = try store.createProject(named: "Append")
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let a = Track(name: "A", fileName: "a.caf", createdAt: t0, durationSeconds: 0.1, sampleRate: 48_000)
        let b = Track(name: "B", fileName: "b.caf", createdAt: t0.addingTimeInterval(60), durationSeconds: 0.1, sampleRate: 48_000)
        let c = Track(name: "C", fileName: "c.caf", createdAt: t0.addingTimeInterval(120), durationSeconds: 0.1, sampleRate: 48_000)
        for track in [a, b, c] {
            try seed(track, in: project, store: store)
        }

        store.deleteTracks(ids: [c.id], from: project)
        store.restoreTrack(id: c.id, in: project)

        #expect(store.project(id: project.id)?.tracks.map(\.id) == [a.id, b.id, c.id])
    }

    @Test func restoreUnknownIDIsANoOp() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootDirectory: root)
        let project = try store.createProject(named: "Nothing")
        let track = Track(name: "Only", fileName: "only.caf", durationSeconds: 0.1, sampleRate: 48_000)
        try seed(track, in: project, store: store)

        #expect(store.restoreTrack(id: UUID(), in: project) == nil)
        #expect(store.project(id: project.id)?.tracks.map(\.id) == [track.id])
    }

    @Test func restoreRelocksSampleRateWhenProjectHasNone() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootDirectory: root)
        let project = try store.createProject(named: "Rate")
        let track = Track(name: "Only", fileName: "only.caf", durationSeconds: 0.1, sampleRate: 44_100)
        try seed(track, in: project, store: store)
        store.deleteTracks(ids: [track.id], from: project)

        var unlocked = try #require(store.project(id: project.id))
        unlocked.sampleRate = nil
        store.update(unlocked)

        store.restoreTrack(id: track.id, in: project)
        #expect(store.project(id: project.id)?.sampleRate == 44_100)
    }

    @Test func restoreWithCollidingIDMintsANewIdentity() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootDirectory: root)
        let project = try store.createProject(named: "Collide")
        let original = Track(name: "Take", fileName: "take.caf", durationSeconds: 0.1, sampleRate: 48_000)
        try seed(original, in: project, store: store)
        store.deleteTracks(ids: [original.id], from: project)

        // Something else now occupies the id (orphan recovery of a copy).
        let squatter = Track(id: original.id, name: "Copy", fileName: "copy.caf", durationSeconds: 0.1, sampleRate: 48_000)
        try seed(squatter, in: project, store: store)

        let restored = try #require(store.restoreTrack(id: original.id, in: project))
        let after = try #require(store.project(id: project.id))
        #expect(after.tracks.count == 2)
        #expect(restored.id != original.id)
        #expect(restored.fileName == "\(restored.id.uuidString).caf")
        #expect(Set(after.tracks.map(\.id)).count == 2)
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: store.audioURL(for: restored, in: after).path))
        #expect(fm.fileExists(atPath: store.audioURL(for: squatter, in: after).path))
        #expect(after.deletedTracks.isEmpty)
    }

    @Test func permanentlyDeleteRemovesTrashFilesAndEntry() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootDirectory: root)
        let project = try store.createProject(named: "Forever")
        let a = Track(name: "A", fileName: "a.caf", durationSeconds: 0.1, sampleRate: 48_000)
        let b = Track(name: "B", fileName: "b.caf", durationSeconds: 0.1, sampleRate: 48_000)
        for track in [a, b] {
            try seed(track, in: project, store: store)
        }
        store.deleteTracks(ids: [a.id, b.id], from: project)

        store.permanentlyDeleteTrashedTracks(ids: [a.id], from: project)

        let after = try #require(store.project(id: project.id))
        #expect(after.deletedTracks.map(\.id) == [b.id])
        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: store.trashedAudioURL(forTrackID: a.id, in: after).path))
        #expect(!fm.fileExists(atPath: store.trashedPeaksURL(forTrackID: a.id, in: after).path))
        #expect(fm.fileExists(atPath: store.trashedAudioURL(forTrackID: b.id, in: after).path))

        store.emptyTrash(for: project)
        let emptied = try #require(store.project(id: project.id))
        #expect(emptied.deletedTracks.isEmpty)
        #expect(!fm.fileExists(atPath: store.trashedAudioURL(forTrackID: b.id, in: emptied).path))
        #expect(ProjectStore(rootDirectory: root).project(id: project.id)?.deletedTracks.isEmpty == true)
    }

    @Test func expiredTrashIsPurgedOnLoadAndFreshEntriesSurvive() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootDirectory: root)
        let project = try store.createProject(named: "Expire")
        let old = Track(name: "Old", fileName: "old.caf", durationSeconds: 0.1, sampleRate: 48_000)
        let fresh = Track(name: "Fresh", fileName: "fresh.caf", durationSeconds: 0.1, sampleRate: 48_000)
        for track in [old, fresh] {
            try seed(track, in: project, store: store)
        }
        store.deleteTracks(ids: [old.id, fresh.id], from: project)

        var aged = try #require(store.project(id: project.id))
        let oldIndex = try #require(aged.deletedTracks.firstIndex { $0.id == old.id })
        aged.deletedTracks[oldIndex].deletedAt = Date.now.addingTimeInterval(-ProjectStore.trashRetention - 86_400)
        store.update(aged)

        let reloaded = ProjectStore(rootDirectory: root)
        let after = try #require(reloaded.project(id: project.id))
        #expect(after.deletedTracks.map(\.id) == [fresh.id])
        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: reloaded.trashedAudioURL(forTrackID: old.id, in: after).path))
        #expect(!fm.fileExists(atPath: reloaded.trashedPeaksURL(forTrackID: old.id, in: after).path))
        #expect(fm.fileExists(atPath: reloaded.trashedAudioURL(forTrackID: fresh.id, in: after).path))

        // The purge is persisted.
        #expect(ProjectStore(rootDirectory: root).project(id: project.id)?.deletedTracks.map(\.id) == [fresh.id])
    }

    @Test func orphanRecoveryIgnoresTrashAndSweepsUnlistedTrashFiles() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootDirectory: root)
        let project = try store.createProject(named: "Sweep")
        let listed = Track(name: "Listed", fileName: "listed.caf", durationSeconds: 0.1, sampleRate: 48_000)
        try seed(listed, in: project, store: store)

        // A complete CAF and a peaks cache in trash/ with no entry.
        let strayID = UUID()
        try FileManager.default.createDirectory(at: store.trashDirectory(for: project), withIntermediateDirectories: true)
        let strayAudio = store.trashedAudioURL(forTrackID: strayID, in: project)
        let strayPeaks = store.trashedPeaksURL(forTrackID: strayID, in: project)
        try writeCAF(at: strayAudio, seconds: 0.2)
        try Data([0, 0, 0, 0]).write(to: strayPeaks)

        let reloaded = ProjectStore(rootDirectory: root)
        let after = try #require(reloaded.project(id: project.id))
        #expect(after.tracks.map(\.id) == [listed.id])
        #expect(after.deletedTracks.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: strayAudio.path))
        #expect(!FileManager.default.fileExists(atPath: strayPeaks.path))
    }

    @Test func deleteTracksWithMissingAudioStillRecordsTheEntry() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootDirectory: root)
        let project = try store.createProject(named: "Missing")
        let ghost = Track(name: "Ghost", fileName: "ghost.caf", durationSeconds: 0.1, sampleRate: 48_000)
        store.addTrack(ghost, to: project)

        store.deleteTracks(ids: [ghost.id], from: project)

        let after = try #require(store.project(id: project.id))
        #expect(after.tracks.isEmpty)
        #expect(after.deletedTracks.map(\.id) == [ghost.id])
        // And it comes back the same way — listed, still fileless.
        #expect(store.restoreTrack(id: ghost.id, in: project)?.id == ghost.id)
        #expect(store.project(id: project.id)?.tracks.map(\.id) == [ghost.id])
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
