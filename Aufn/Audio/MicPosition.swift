import AVFAudio
import Foundation

/// Which built-in capsule (and the pickup pattern it implies) Aufn asks iOS
/// for while recording. Orthogonal to CaptureMode: that is the printed grade,
/// this is the microphone. Inert unless the built-in mic is the active input.
/// Every position records under `.measurement`; the stereo beamform was
/// dropped because it only exists inside Apple's input chain.
/// Persisted under "micPosition"; defaults to auto.
enum MicPosition: String, CaseIterable, Identifiable {
    case auto
    case front
    case bottom
    case back

    var id: String { rawValue }

    static let storageKey = "micPosition"

    static var current: MicPosition {
        from(stored: UserDefaults.standard.string(forKey: storageKey))
    }

    static func from(stored raw: String?) -> MicPosition {
        raw.flatMap(MicPosition.init) ?? .auto
    }

    var name: String {
        switch self {
        case .auto: "Auto"
        case .front: "Front"
        case .bottom: "Bottom"
        case .back: "Back"
        }
    }

    var caption: String {
        switch self {
        case .auto: "Let iOS pick the capsule and pattern."
        case .front: "Screen-side capsule, cardioid — rejects sound from behind the phone."
        case .bottom: "Bottom capsule, omnidirectional — picks up the whole room."
        case .back: "Camera-side capsule, cardioid — point the back of the phone at the source."
        }
    }

    var symbol: String {
        switch self {
        case .auto: "wand.and.stars"
        case .front: "iphone"
        case .bottom: "arrow.down.to.line"
        case .back: "camera"
        }
    }

    /// Data source to select on the built-in mic; nil = leave iOS's choice.
    var orientation: AVAudioSession.Orientation? {
        switch self {
        case .auto: nil
        case .front: .front
        case .bottom: .bottom
        case .back: .back
        }
    }

    /// Pattern to request on that source; nil = leave iOS's choice.
    var polarPattern: AVAudioSession.PolarPattern? {
        switch self {
        case .auto: nil
        case .front, .back: .cardioid
        case .bottom: .omnidirectional
        }
    }
}
