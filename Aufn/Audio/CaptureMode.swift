import AVFAudio
import Foundation

/// The grade printed onto a take: RAW leaves the mic untouched, the others
/// run Aufn's own light processing on top of the raw input before the file is
/// written. Persisted under "captureMode"; the retired "standard" value (the
/// old TAPE, which was Apple's `.default` input chain) maps to our tape, and
/// anything else unknown falls back to raw.
enum CaptureMode: String, CaseIterable, Identifiable, Codable {
    case raw
    case tape
    case warm
    case glue

    var id: String { rawValue }

    static let storageKey = "captureMode"

    static var current: CaptureMode {
        from(stored: UserDefaults.standard.string(forKey: storageKey))
    }

    static func from(stored raw: String?) -> CaptureMode {
        if raw == "standard" { return .tape }
        return raw.flatMap(CaptureMode.init) ?? .raw
    }

    /// Short all-caps label for the transport wheel.
    var label: String {
        switch self {
        case .raw: "RAW"
        case .tape: "TAPE"
        case .warm: "WARM"
        case .glue: "GLUE"
        }
    }

    var caption: String {
        switch self {
        case .raw: "Untouched input"
        case .tape: "Rounded top, gentle compression, soft peaks"
        case .warm: "More body, less air"
        case .glue: "Light 2:1 compression"
        }
    }

    /// Single letter for the track-row seal; nil for RAW, which is the
    /// absence of a grade.
    var badgeLetter: String? {
        switch self {
        case .raw: nil
        case .tape: "T"
        case .warm: "W"
        case .glue: "G"
        }
    }

    var grade: GradeSettings {
        switch self {
        case .raw: .raw
        case .tape: .tape
        case .warm: .warm
        case .glue: .glue
        }
    }
}
