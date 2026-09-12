// MicrophonePreset.swift

import Foundation
import AVFoundation

struct GainRange {
    static let minValue: Float = 0.0
    static let maxValue: Float = 2.0
}

struct FrequencyRange {
    static let minValue: Float = 20.0
    static let maxValue: Float = 20000.0
}

struct MicrophoneSettings: Codable {
    var gain: Float {
        didSet {
            gain = max(GainRange.minValue, min(gain, GainRange.maxValue))
        }
    }
    var frequency: Float {
        didSet {
            frequency = max(FrequencyRange.minValue, min(frequency, FrequencyRange.maxValue))
        }
    }
    
    init(gain: Float, frequency: Float) {
        self.gain = max(GainRange.minValue, min(gain, GainRange.maxValue))
        self.frequency = max(FrequencyRange.minValue, min(frequency, FrequencyRange.maxValue))
    }
}

class MicrophonePreset: Codable {
    let name: String
    let icon: String
    var isToggled: Bool
    var settings: MicrophoneSettings
    var isEnabled: Bool
    private var eqNode: AVAudioUnitEQ?
    
    init(name: String, icon: String, isToggled: Bool, settings: MicrophoneSettings, isEnabled: Bool = true) {
        self.name = name
        self.icon = icon
        self.isToggled = isToggled
        self.settings = settings
        self.isEnabled = isEnabled
        self.eqNode = AVAudioUnitEQ(numberOfBands: 1) // Move eqNode initialization here
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decode(String.self, forKey: .icon)
        isToggled = try container.decode(Bool.self, forKey: .isToggled)
        settings = try container.decode(MicrophoneSettings.self, forKey: .settings)
        isEnabled = true // Assuming the isEnabled property should be true initially
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(icon, forKey: .icon)
        try container.encode(isToggled, forKey: .isToggled)
        try container.encode(settings, forKey: .settings)
    }
    
    func node(with engine: AVAudioEngine) -> AVAudioNode {
        if isEnabled {
            let mixerNode = AVAudioMixerNode()
            mixerNode.outputVolume = settings.gain

            eqNode = AVAudioUnitEQ(numberOfBands: 1)

            eqNode?.bands[0].filterType = .lowPass
            eqNode?.bands[0].frequency = settings.frequency

            if let eqNode = eqNode {
                connectNodes(inputNode: mixerNode, eqNode: eqNode, engine: engine)
            }

            return mixerNode
        } else {
            return AVAudioNode()
        }
    }

    
    private func connectNodes(inputNode: AVAudioNode, eqNode: AVAudioNode, engine: AVAudioEngine) {
        engine.attach(inputNode)
        engine.attach(eqNode)
        
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)
        engine.connect(inputNode, to: eqNode, format: format)
        engine.connect(eqNode, to: engine.mainMixerNode, format: format)
    }
    
    private enum CodingKeys: String, CodingKey {
        case name
        case icon
        case isToggled
        case settings
    }
}
