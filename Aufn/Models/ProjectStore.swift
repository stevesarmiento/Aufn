import AVFAudio
import Foundation
import Observation

/// Owns the on-disk project library: Documents/Projects/<uuid>/ with
/// project.json metadata, tracks/*.caf audio, and peaks/*.peaks caches.
@MainActor
@Observable
final class ProjectStore {
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
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// A take's CAF is written incrementally but its Track entry only lands
    /// when the take stops. A crash or kill mid-take leaves a complete,
    /// playable file with no entry: adopt it as a track. Unreadable or empty
    /// leftovers (a start that failed) and peaks caches with no track are
    /// deleted.
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
        guard var current = self.project(id: project.id) else { return }
        current.tracks.removeAll { $0.id == track.id }
        try? fileManager.removeItem(at: audioURL(for: track, in: project))
        try? fileManager.removeItem(at: peaksURL(for: track, in: project))
        update(current)
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
