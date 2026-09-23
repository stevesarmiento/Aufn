import Foundation

/// The tuning for one printed grade: a short EQ chain, an optional
/// compressor, an optional tape-style soft clip, and a trim. Every number
/// that shapes a grade lives here so presets can be adjusted in one place and
/// checked by the level-match and ceiling tests.
struct GradeSettings: Sendable, Equatable {
    var eq: [EQBand] = []
    var compressor: CompressorSettings? = nil
    /// tanh drive; nil = no saturation stage. Small-signal gain stays unity.
    var saturationDrive: Float? = nil
    var trimDB: Float = 0

    /// True when the settings would leave audio untouched, so no processor
    /// needs to exist for the take.
    var isIdentity: Bool {
        eq.allSatisfy(\.isIdentity) && compressor == nil && saturationDrive == nil && trimDB == 0
    }

    /// Untouched input.
    static let raw = GradeSettings()

    /// Rounded top, a touch of low weight, slow gentle compression, and a
    /// soft clip on peaks. The take you keep.
    static let tape = GradeSettings(
        eq: [
            EQBand(kind: .highPass, frequency: 40, gainDB: 0, q: 0.7071),
            EQBand(kind: .lowShelf, frequency: 100, gainDB: 1.5, q: 0.7071),
            EQBand(kind: .highShelf, frequency: 10_000, gainDB: -2.5, q: 0.7071),
        ],
        compressor: CompressorSettings(thresholdDB: -20, ratio: 1.8, kneeDB: 6, attackMs: 20, releaseMs: 200, makeupDB: 2.5),
        saturationDrive: 1.6
    )

    /// Shelves only: more body, less air. No dynamics.
    static let warm = GradeSettings(
        eq: [
            EQBand(kind: .highPass, frequency: 50, gainDB: 0, q: 0.7071),
            EQBand(kind: .lowShelf, frequency: 150, gainDB: 2.5, q: 0.7071),
            EQBand(kind: .highShelf, frequency: 7_000, gainDB: -3, q: 0.7071),
        ]
    )

    /// Flat EQ, 2.5:1 glue. Makeup is set so a -18 dBFS RMS signal comes
    /// out where it went in.
    static let glue = GradeSettings(
        eq: [EQBand(kind: .highPass, frequency: 40, gainDB: 0, q: 0.7071)],
        compressor: CompressorSettings(thresholdDB: -20, ratio: 2.5, kneeDB: 6, attackMs: 15, releaseMs: 120, makeupDB: 3)
    )

    static let allGrades: [GradeSettings] = [.raw, .tape, .warm, .glue]
}

struct EQBand: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case lowShelf
        case highShelf
        case peak
        case highPass
    }

    var kind: Kind
    var frequency: Double
    var gainDB: Double
    var q: Double

    /// A 0 dB shelf or peak passes audio unchanged; a high-pass never does.
    var isIdentity: Bool {
        kind != .highPass && gainDB == 0
    }
}

struct CompressorSettings: Sendable, Equatable {
    var thresholdDB: Float
    var ratio: Float
    /// Knee width in dB centered on the threshold; 0 = hard knee.
    var kneeDB: Float
    var attackMs: Float
    var releaseMs: Float
    var makeupDB: Float

    /// Steady-state gain reduction at 0 dBFS. Makeup must not exceed this or
    /// a full-scale input would print above full scale.
    var reductionAtFullScaleDB: Float {
        (1 - 1 / ratio) * (0 - thresholdDB)
    }
}
