import Foundation

struct Track: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var fileName: String
    var createdAt: Date
    var isMuted: Bool
    var isSoloed: Bool
    var latencyOffsetSamples: Int
    var durationSeconds: Double
    var sampleRate: Double
    var channelCount: Int
    var volume: Float
    var pan: Float
    /// The grade printed onto the file at record time.
    var captureMode: CaptureMode

    init(
        id: UUID = UUID(),
        name: String,
        fileName: String,
        createdAt: Date = .now,
        isMuted: Bool = false,
        isSoloed: Bool = false,
        latencyOffsetSamples: Int = 0,
        durationSeconds: Double = 0,
        sampleRate: Double,
        channelCount: Int = 1,
        volume: Float = 1,
        pan: Float = 0,
        captureMode: CaptureMode = .raw
    ) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.createdAt = createdAt
        self.isMuted = isMuted
        self.isSoloed = isSoloed
        self.latencyOffsetSamples = latencyOffsetSamples
        self.durationSeconds = durationSeconds
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.volume = volume
        self.pan = pan
        self.captureMode = captureMode
    }

    // Custom decoding so project.json files written before volume/pan existed
    // keep loading (ProjectStore decodes with try?, so a throw would silently
    // drop the whole project).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        fileName = try container.decode(String.self, forKey: .fileName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isMuted = try container.decode(Bool.self, forKey: .isMuted)
        isSoloed = try container.decodeIfPresent(Bool.self, forKey: .isSoloed) ?? false
        latencyOffsetSamples = try container.decode(Int.self, forKey: .latencyOffsetSamples)
        durationSeconds = try container.decode(Double.self, forKey: .durationSeconds)
        sampleRate = try container.decode(Double.self, forKey: .sampleRate)
        channelCount = try container.decodeIfPresent(Int.self, forKey: .channelCount) ?? 1
        volume = try container.decodeIfPresent(Float.self, forKey: .volume) ?? 1
        pan = try container.decodeIfPresent(Float.self, forKey: .pan) ?? 0
        captureMode = CaptureMode.from(stored: try container.decodeIfPresent(String.self, forKey: .captureMode))
    }
}
