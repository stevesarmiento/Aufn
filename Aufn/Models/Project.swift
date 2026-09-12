import Foundation

struct Project: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var createdAt: Date
    /// Locked to the hardware rate when the first track is recorded.
    var sampleRate: Double?
    var tracks: [Track]
    var masterVolume: Float
    /// nil until the user adds the metronome row.
    var metronome: MetronomeSettings?
    /// Playback wraps from the end back to the start until stopped.
    var repeatPlayback: Bool
    /// Grid card fill; cosmetic only.
    var tint: ProjectTint
    /// Deleted takes waiting in the trash, restorable until they expire.
    var deletedTracks: [DeletedTrack]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        sampleRate: Double? = nil,
        tracks: [Track] = [],
        masterVolume: Float = 1,
        metronome: MetronomeSettings? = nil,
        repeatPlayback: Bool = false,
        tint: ProjectTint = .graphite,
        deletedTracks: [DeletedTrack] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sampleRate = sampleRate
        self.tracks = tracks
        self.masterVolume = masterVolume
        self.metronome = metronome
        self.repeatPlayback = repeatPlayback
        self.tint = tint
        self.deletedTracks = deletedTracks
    }

    // Tolerates project.json files written before masterVolume existed.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        sampleRate = try container.decodeIfPresent(Double.self, forKey: .sampleRate)
        tracks = try container.decode([Track].self, forKey: .tracks)
        masterVolume = try container.decodeIfPresent(Float.self, forKey: .masterVolume) ?? 1
        metronome = try container.decodeIfPresent(MetronomeSettings.self, forKey: .metronome)
        repeatPlayback = try container.decodeIfPresent(Bool.self, forKey: .repeatPlayback) ?? false
        // Unknown tint names (a newer build's palette) fall back rather than
        // failing the decode.
        let tintName = try container.decodeIfPresent(String.self, forKey: .tint)
        tint = tintName.flatMap(ProjectTint.init(rawValue:)) ?? .graphite
        // A malformed trash list must never take the whole project with it.
        deletedTracks = (try? container.decodeIfPresent([DeletedTrack].self, forKey: .deletedTracks)) ?? []
    }
}

extension Project {
    /// The tracks a scoped operation (export of a selection) applies to:
    /// `nil` means the whole project. Project order is preserved and unknown
    /// ids are ignored.
    func tracks(limitedTo ids: Set<UUID>?) -> [Track] {
        guard let ids else { return tracks }
        return tracks.filter { ids.contains($0.id) }
    }
}
