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

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        sampleRate: Double? = nil,
        tracks: [Track] = [],
        masterVolume: Float = 1,
        metronome: MetronomeSettings? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sampleRate = sampleRate
        self.tracks = tracks
        self.masterVolume = masterVolume
        self.metronome = metronome
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
    }
}
