import AVFAudio
import Foundation

/// How much processing iOS applies to the mic before Aufn writes it. These are
/// discrete presets, not a continuum — each is a bundle Apple tuned for a use
/// case. Persisted under "captureMode"; defaults to raw.
enum CaptureMode: String, CaseIterable, Identifiable {
    case raw
    case standard
    case voice

    var id: String { rawValue }

    static let storageKey = "captureMode"

    static var current: CaptureMode {
        UserDefaults.standard.string(forKey: storageKey).flatMap(CaptureMode.init) ?? .raw
    }

    /// Short all-caps label for the transport wheel.
    var label: String {
        switch self {
        case .raw: "RAW"
        case .standard: "TAPE"
        case .voice: "VOICE"
        }
    }

    var caption: String {
        switch self {
        case .raw: "Raw, no processing"
        case .standard: "Light, dynamics applied"
        case .voice: "Heavy, processing added"
        }
    }

    var sessionMode: AVAudioSession.Mode {
        switch self {
        case .raw: .measurement
        case .standard: .default
        case .voice: .voiceChat
        }
    }

    /// The AEC + noise-suppression + AGC stack (`inputNode.setVoiceProcessingEnabled`).
    var usesVoiceProcessing: Bool { self == .voice }
}
