import Foundation
import SwiftUI

class AppSettings: ObservableObject {
    
    @AppStorage("selectedSampleRateIndex") var selectedSampleRateIndex: Int = 0
    @AppStorage("limitAlertEnabled") var limitAlertEnabled: Bool = false
    @AppStorage("isStereo") var isStereo: Bool = true
    @Published var selectedMicrophonePreset: MicrophonePreset? {
        didSet {
            saveSelectedMicrophonePreset()
        }
    }
    @Published var selectedPlugins: [Plugin]? {
        didSet {
            saveSelectedPlugins()
        }
    }

    private let microphonePresetKey = "microphonePreset"
    private let pluginsKey = "plugins"
    
    let sampleRates = [44100, 48000, 88200, 96000]
    let audioFormats = ["WAV", "M4A"]
    
    @AppStorage("selectedAudioFormatIndex") var selectedAudioFormatIndex: Int = 0 {
        willSet {
            if newValue != 0 && selectedSampleRateIndex > 1 {
                selectedSampleRateIndex = 1 // Set to 48000
            }
        }
    }
    
    // Create the microphone presets
    static func defaultMicrophonePresets() -> [MicrophonePreset] {
        let dynamicPreset = MicrophonePreset(name: "Dynamic", icon: "circle.and.line.horizontal", isToggled: false, settings: MicrophoneSettings(gain: 0.5, frequency: 1000))
        let condenserPreset = MicrophonePreset(name: "Condenser", icon: "rotate.3d", isToggled: false, settings: MicrophoneSettings(gain: 0.7, frequency: 1500))
        let ribbonPreset = MicrophonePreset(name: "Ribbon", icon: "water.waves", isToggled: false, settings: MicrophoneSettings(gain: 0.4, frequency: 800))
        let customPreset = MicrophonePreset(name: "Custom", icon: "camera.filters", isToggled: false, settings: MicrophoneSettings(gain: 0.5, frequency: 1000))

        return [dynamicPreset, condenserPreset, ribbonPreset, customPreset]
    }

    var audioProcessingManager: AudioProcessingManager!
    
    init() {
        loadSelectedMicrophonePreset()
        loadSelectedPlugins()
        audioProcessingManager = AudioProcessingManager(appSettings: self)
    }
    
    var availableSampleRates: [Int] {
        return sampleRates
    }
    
    func saveSelectedMicrophonePreset() {
        if let preset = selectedMicrophonePreset {
            UserDefaults.standard.save(object: preset, forKey: microphonePresetKey)
        }
    }
    
    func loadSelectedMicrophonePreset() {
        selectedMicrophonePreset = UserDefaults.standard.fetch(forKey: microphonePresetKey, type: MicrophonePreset.self)
    }

    func saveSelectedPlugins() {
        if let plugins = selectedPlugins {
            UserDefaults.standard.save(object: plugins, forKey: pluginsKey)
        }
    }
    
    func loadSelectedPlugins() {
        selectedPlugins = UserDefaults.standard.fetch(forKey: pluginsKey, type: [Plugin].self)
    }
}
