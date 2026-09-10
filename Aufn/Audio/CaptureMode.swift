import AVFAudio
import Foundation

/// How much processing iOS applies to the mic before Aufn writes it. These are
/// discrete presets, not a continuum — each is a bundle Apple tuned for a use
/// case. Persisted under "captureMode"; unknown or retired values (the old
/// "voice" mode) fall back to raw.
enum CaptureMode: String, CaseIterable, Identifiable {
    case raw
    case standard

    var id: String { rawValue }

    static let storageKey = "captureMode"

    static var current: CaptureMode {
        from(stored: UserDefaults.standard.string(forKey: storageKey))
    }

    static func from(stored raw: String?) -> CaptureMode {
        raw.flatMap(CaptureMode.init) ?? .raw
    }

    /// Short all-caps label for the transport wheel.
    var label: String {
        switch self {
        case .raw: "RAW"
        case .standard: "TAPE"
        }
    }

    var caption: String {
        switch self {
        case .raw: "Raw, no processing"
        case .standard: "Light, dynamics applied"
        }
    }

    var sessionMode: AVAudioSession.Mode {
        switch self {
        case .raw: .measurement
        case .standard: .default
        }
    }
}
