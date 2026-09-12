import Foundation

enum ClickSound: String, Codable, CaseIterable {
    case click
    case beep
    case wood

    var label: String {
        switch self {
        case .click: "Click"
        case .beep: "Beep"
        case .wood: "Wood"
        }
    }
}

/// The project's metronome, stored on Project (nil = not added). Not a Track:
/// it has no audio file, peaks cache, or export presence — just click
/// parameters plus the same mute/solo flags the mix rules understand.
struct MetronomeSettings: Codable, Equatable, Hashable {
    /// Stable row identity for SwipeRow/ForEach — a project has at
    /// most one metronome.
    static let rowID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    static let bpmRange = 40...240
    static let beatsPerBarRange = 1...7
    static let countInBarsRange = 0...2

    var bpm: Int
    var beatsPerBar: Int
    var sound: ClickSound
    var countInBars: Int
    var volume: Float
    var isMuted: Bool
    var isSoloed: Bool

    var barDuration: Double { Double(beatsPerBar) * 60.0 / Double(bpm) }
    var countInSeconds: Double { Double(countInBars) * barDuration }

    init(
        bpm: Int = 120,
        beatsPerBar: Int = 4,
        sound: ClickSound = .click,
        countInBars: Int = 0,
        volume: Float = 0.8,
        isMuted: Bool = false,
        isSoloed: Bool = false
    ) {
        self.bpm = bpm
        self.beatsPerBar = beatsPerBar
        self.sound = sound
        self.countInBars = countInBars
        self.volume = volume
        self.isMuted = isMuted
        self.isSoloed = isSoloed
    }

    // Every field decodes with a default so project.json files written by any
    // earlier (or later) schema keep loading (ProjectStore decodes with try?,
    // so a throw would silently drop the whole project). Values are clamped
    // so hand-edited files can't drive the click synthesis out of range.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawBPM = try container.decodeIfPresent(Int.self, forKey: .bpm) ?? 120
        bpm = rawBPM.clamped(to: Self.bpmRange)
        let rawBeats = try container.decodeIfPresent(Int.self, forKey: .beatsPerBar) ?? 4
        beatsPerBar = rawBeats.clamped(to: Self.beatsPerBarRange)
        let rawSound = try container.decodeIfPresent(String.self, forKey: .sound)
        sound = rawSound.flatMap(ClickSound.init(rawValue:)) ?? .click
        let rawCountIn = try container.decodeIfPresent(Int.self, forKey: .countInBars) ?? 0
        countInBars = rawCountIn.clamped(to: Self.countInBarsRange)
        volume = try container.decodeIfPresent(Float.self, forKey: .volume) ?? 0.8
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        isSoloed = try container.decodeIfPresent(Bool.self, forKey: .isSoloed) ?? false
    }
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
