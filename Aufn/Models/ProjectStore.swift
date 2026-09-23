import AVFAudio
import Foundation
import Observation

/// Owns the on-disk project library: Documents/Projects/<uuid>/ with
/// project.json metadata, tracks/*.caf audio, peaks/*.peaks caches, and
/// trash/ holding deleted takes (audio + peaks keyed by track id) until they
/// are restored or expire.
@MainActor
@Observable
final class ProjectStore {
    /// How long a deleted take stays restorable.
    nonisolated static let trashRetention: TimeInterval = 30 * 24 * 60 * 60

    private(set) var projects: [Project] = []
    /// Bumped whenever a peaks cache lands on disk after its track already
    /// exists (post-take recompute, recovered takes). Views key their cache
    /// loads on it so a late-arriving waveform still shows up.
    private(set) var peaksRevision = 0

    private let fileManager = FileManager.default

    let rootDirectory: URL

    init(rootDirectory: URL = URL.documentsDirectory.appending(path: "Projects", directoryHint: .isDirectory)) {
        self.rootDirectory = rootDirectory
        loadProjects()
    }

    // MARK: - Paths

    func directory(for project: Project) -> URL {
        rootDirectory.appending(path: project.id.uuidString, directoryHint: .isDirectory)
    }

    func tracksDirectory(for project: Project) -> URL {
        directory(for: project).appending(path: "tracks", directoryHint: .isDirectory)
    }

    func peaksDirectory(for project: Project) -> URL {
        directory(for: project).appending(path: "peaks", directoryHint: .isDirectory)
    }

    func audioURL(for track: Track, in project: Project) -> URL {
        tracksDirectory(for: project).appending(path: track.fileName)
    }

    func peaksURL(for track: Track, in project: Project) -> URL {
        peaksDirectory(for: project).appending(path: "\(track.id.uuidString).peaks")
    }

    /// Deleted takes wait here, keyed by track id (not file name) so two
    /// trashed takes can never collide.
    func trashDirectory(for project: Project) -> URL {
        directory(for: project).appending(path: "trash", directoryHint: .isDirectory)
    }

    func trashedAudioURL(forTrackID id: UUID, in project: Project) -> URL {
        trashDirectory(for: project).appending(path: "\(id.uuidString).caf")
    }

    func trashedPeaksURL(forTrackID id: UUID, in project: Project) -> URL {
        trashDirectory(for: project).appending(path: "\(id.uuidString).peaks")
    }

    // MARK: - Loading

    private func loadProjects() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let contents = (try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []
        projects = contents
            .compactMap { dir -> Project? in
                let metadata = dir.appending(path: "project.json")
                guard let data = try? Data(contentsOf: metadata) else { return nil }
                return try? decoder.decode(Project.self, from: data)
            }
            .map(recoveringOrphanTakes)
            .map { purgingExpiredTrash($0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// A take's CAF is written incrementally but its Track entry only lands
    /// when the take stops. A crash or kill mid-take leaves a complete,
    /// playable file with no entry: adopt it as a track. Unreadable or empty
    /// leftovers (a start that failed) and peaks caches with no track are
    /// deleted. Only tracks/ and peaks/ are scanned — trash/ belongs to
    /// `purgingExpiredTrash`, so a deleted take is never re-adopted here.
    private func recoveringOrphanTakes(_ project: Project) -> Project {
        var project = project
        let known = Set(project.tracks.map(\.fileName))
        let audioFiles = (try? fileManager.contentsOfDirectory(
            at: tracksDirectory(for: project),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        )) ?? []
        var recovered: [Track] = []
        for url in audioFiles where url.pathExtension == "caf" && !known.contains(url.lastPathComponent) {
            guard let file = try? AVAudioFile(forReading: url), file.length > 0 else {
                try? fileManager.removeItem(at: url)
                continue
            }
            let rate = file.processingFormat.sampleRate
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
            let track = Track(
                id: UUID(uuidString: url.deletingPathExtension().lastPathComponent) ?? UUID(),
                name: "Track \(project.tracks.count + recovered.count + 1) (recovered)",
                fileName: url.lastPathComponent,
                createdAt: modified,
                durationSeconds: Double(file.length) / rate,
                sampleRate: rate,
                channelCount: Int(file.processingFormat.channelCount)
            )
            recovered.append(track)
        }
        if !recovered.isEmpty {
            project.tracks.append(contentsOf: recovered)
            if project.sampleRate == nil {
                project.sampleRate = recovered.first?.sampleRate
            }
            try? persist(project)
            for track in recovered {
                let audioURL = audioURL(for: track, in: project)
                let peaksURL = peaksURL(for: track, in: project)
                Task.detached(priority: .utility) { [weak self] in
                    try? PeakStore.computePeaks(audioURL: audioURL, peaksURL: peaksURL)
                    await self?.notePeaksUpdated()
                }
            }
        }

        let wantedPeaks = Set(project.tracks.map { "\($0.id.uuidString).peaks" })
        let peaksFiles = (try? fileManager.contentsOfDirectory(
            at: peaksDirectory(for: project),
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []
        for url in peaksFiles where !wantedPeaks.contains(url.lastPathComponent) {
            try? fileManager.removeItem(at: url)
        }
        return project
    }

    /// Trash past the retention window is removed for good, and any file in
    /// trash/ with no entry (a crash between the move and the persist) is
    /// swept. Persists only when an entry was dropped.
    private func purgingExpiredTrash(_ project: Project, now: Date = .now) -> Project {
        var project = project
        let cutoff = now.addingTimeInterval(-Self.trashRetention)
        let expired = project.deletedTracks.filter { $0.deletedAt < cutoff }
        if !expired.isEmpty {
            project.deletedTracks.removeAll { $0.deletedAt < cutoff }
            for entry in expired {
                try? fileManager.removeItem(at: trashedAudioURL(forTrackID: entry.id, in: project))
                try? fileManager.removeItem(at: trashedPeaksURL(forTrackID: entry.id, in: project))
            }
            try? persist(project)
        }

        let wanted = Set(project.deletedTracks.map { $0.id.uuidString })
        let trashed = (try? fileManager.contentsOfDirectory(
            at: trashDirectory(for: project),
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []
        for url in trashed where !wanted.contains(url.deletingPathExtension().lastPathComponent) {
            try? fileManager.removeItem(at: url)
        }
        return project
    }

    /// Call after writing a peaks cache for a track that is already listed.
    func notePeaksUpdated() {
        peaksRevision += 1
    }

    // MARK: - Mutations

    @discardableResult
    func createProject(named name: String) throws -> Project {
        let project = Project(name: name, tint: .rotating(index: projects.count))
        try fileManager.createDirectory(at: tracksDirectory(for: project), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: peaksDirectory(for: project), withIntermediateDirectories: true)
        try persist(project)
        projects.insert(project, at: 0)
        return project
    }

    func renameProject(_ project: Project, to name: String) {
        var updated = project
        updated.name = name
        update(updated)
    }

    func deleteProject(_ project: Project) {
        try? fileManager.removeItem(at: directory(for: project))
        projects.removeAll { $0.id == project.id }
    }

    /// Replaces the in-memory copy and persists metadata to disk.
    func update(_ project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index] = project
        try? persist(project)
    }

    func addTrack(_ track: Track, to project: Project) {
        guard var current = self.project(id: project.id) else { return }
        current.tracks.append(track)
        if current.sampleRate == nil {
            current.sampleRate = track.sampleRate
        }
        update(current)
    }

    func updateTrack(_ track: Track, in project: Project) {
        guard var current = self.project(id: project.id),
              let index = current.tracks.firstIndex(where: { $0.id == track.id }) else { return }
        current.tracks[index] = track
        update(current)
    }

    func deleteTrack(_ track: Track, from project: Project) {
        deleteTracks(ids: [track.id], from: project)
    }

    /// Batched removal with ONE metadata write. Unknown ids are ignored; each
    /// removed track's CAF and peaks cache move to trash/ and the track is
    /// recorded in `deletedTracks` so it can be restored. `removingMetronome`
    /// rides along so a mixed selection is still a single persist.
    ///
    /// Files move before the persist: a crash in between leaves trash files
    /// with no entry, which the launch sweep removes — never a listed take
    /// sitting in tracks/ for orphan recovery to re-adopt under a new name.
    func deleteTracks(ids: Set<UUID>, removingMetronome: Bool = false, from project: Project) {
        guard var current = self.project(id: project.id) else { return }
        // Derived from the fresh copy, not the caller's snapshot.
        let doomed = current.tracks.filter { ids.contains($0.id) }
        guard !doomed.isEmpty || (removingMetronome && current.metronome != nil) else { return }
        current.tracks.removeAll { ids.contains($0.id) }
        if removingMetronome { current.metronome = nil }
        if !doomed.isEmpty {
            try? fileManager.createDirectory(at: trashDirectory(for: current), withIntermediateDirectories: true)
        }
        let now = Date.now
        for track in doomed {
            // Best effort: a take whose file was already missing is recorded
            // anyway — restoring it just returns it to that state.
            move(audioURL(for: track, in: current), to: trashedAudioURL(forTrackID: track.id, in: current))
            move(peaksURL(for: track, in: current), to: trashedPeaksURL(forTrackID: track.id, in: current))
            current.deletedTracks.append(DeletedTrack(track: track, deletedAt: now))
        }
        update(current)
    }

    /// Puts a trashed take back where it was: files return to tracks/ and
    /// peaks/, the track re-enters the list in creation order (the list is
    /// append-only, so that is its original spot), and its levels, grade and
    /// flags come back untouched. Returns the restored track, or nil for an
    /// unknown id.
    @discardableResult
    func restoreTrack(id: UUID, in project: Project) -> Track? {
        guard var current = self.project(id: project.id),
              let index = current.deletedTracks.firstIndex(where: { $0.id == id }) else { return nil }
        var track = current.deletedTracks.remove(at: index).track
        let trashedAudio = trashedAudioURL(forTrackID: id, in: current)
        let trashedPeaks = trashedPeaksURL(forTrackID: id, in: current)
        if current.tracks.contains(where: { $0.id == track.id }) {
            // Only reachable when a duplicated file was adopted by orphan
            // recovery under this id; give the restored take its own identity.
            track.id = UUID()
            track.fileName = "\(track.id.uuidString).caf"
        }
        move(trashedAudio, to: audioURL(for: track, in: current))
        move(trashedPeaks, to: peaksURL(for: track, in: current))

        let insertAt = current.tracks.firstIndex { $0.createdAt > track.createdAt } ?? current.tracks.endIndex
        current.tracks.insert(track, at: insertAt)
        if current.sampleRate == nil {
            current.sampleRate = track.sampleRate
        }
        update(current)

        // A take deleted before its post-take peaks landed has no cache to
        // bring back; rebuild it so the row gets a waveform.
        let audioURL = audioURL(for: track, in: current)
        let peaksURL = peaksURL(for: track, in: current)
        if fileManager.fileExists(atPath: peaksURL.path) {
            notePeaksUpdated()
        } else if fileManager.fileExists(atPath: audioURL.path) {
            Task.detached(priority: .utility) { [weak self] in
                try? PeakStore.computePeaks(audioURL: audioURL, peaksURL: peaksURL)
                await self?.notePeaksUpdated()
            }
        }
        return track
    }

    /// Removes trashed takes for good — entries and files — in one persist.
    func permanentlyDeleteTrashedTracks(ids: Set<UUID>, from project: Project) {
        guard var current = self.project(id: project.id) else { return }
        let doomed = current.deletedTracks.filter { ids.contains($0.id) }
        guard !doomed.isEmpty else { return }
        current.deletedTracks.removeAll { ids.contains($0.id) }
        for entry in doomed {
            try? fileManager.removeItem(at: trashedAudioURL(forTrackID: entry.id, in: current))
            try? fileManager.removeItem(at: trashedPeaksURL(forTrackID: entry.id, in: current))
        }
        update(current)
    }

    func emptyTrash(for project: Project) {
        guard let current = self.project(id: project.id) else { return }
        permanentlyDeleteTrashedTracks(ids: Set(current.deletedTracks.map(\.id)), from: current)
    }

    /// Best-effort move that replaces anything stale at the destination.
    private func move(_ source: URL, to destination: URL) {
        guard fileManager.fileExists(atPath: source.path) else { return }
        try? fileManager.removeItem(at: destination)
        try? fileManager.moveItem(at: source, to: destination)
    }

    func project(id: UUID) -> Project? {
        projects.first { $0.id == id }
    }

    // MARK: - Persistence

    private func persist(_ project: Project) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        let destination = directory(for: project).appending(path: "project.json")
        let temp = destination.appendingPathExtension("tmp")
        try data.write(to: temp, options: .atomic)
        _ = try fileManager.replaceItemAt(destination, withItemAt: temp)
    }
}
