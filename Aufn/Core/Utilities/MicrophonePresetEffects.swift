//
//  MicrophonePresetEffects.swift
//  Recordit
//
//  Created by Steven Sarmiento on 4/29/23.
//

import Foundation
import AVFoundation

extension MicrophonePreset {
    var audioUnits: [AVAudioUnit] {
        switch name {
        case "Dynamic":
            return dynamicMicrophoneEffects()
        case "Condenser":
            return condenserMicrophoneEffects()
        case "Ribbon":
            return ribbonMicrophoneEffects()
        case "Custom":
            return customMicrophoneEffects(settings: settings)
        default:
            print("Unknown microphone preset name: \(name)")
            return []
        }
    }
    
    private func dynamicMicrophoneEffects() -> [AVAudioUnit] {
        // Shure SM7b Emulation
        let eq = AVAudioUnitEQ(numberOfBands: 3)

        // Low-frequency rolloff
        let highPassParams = eq.bands[0]
        highPassParams.filterType = .highPass
        highPassParams.frequency = 50.0
        highPassParams.gain = 0.0

        // Presence boost
        let presenceBoostParams = eq.bands[1]
        presenceBoostParams.filterType = .parametric
        presenceBoostParams.frequency = 5000.0
        presenceBoostParams.bandwidth = 1.0
        presenceBoostParams.gain = 4.0

        // Low-frequency boost
        let lowBoostParams = eq.bands[2]
        lowBoostParams.filterType = .lowShelf
        lowBoostParams.frequency = 200.0
        lowBoostParams.gain = 2.0

        return [eq]
    }

    private func condenserMicrophoneEffects() -> [AVAudioUnit] {
        // Neumann TLM49 Emulation
        let eq = AVAudioUnitEQ(numberOfBands: 3)

        // High-frequency boost
        let highBoostParams = eq.bands[0]
        highBoostParams.filterType = .highShelf
        highBoostParams.frequency = 2000.0
        highBoostParams.gain = 4.0

        // Presence boost
        let presenceBoostParams = eq.bands[1]
        presenceBoostParams.filterType = .parametric
        presenceBoostParams.frequency = 5000.0
        presenceBoostParams.bandwidth = 1.0
        presenceBoostParams.gain = 2.0

        // Low-frequency boost
        let lowBoostParams = eq.bands[2]
        lowBoostParams.filterType = .lowShelf
        lowBoostParams.frequency = 100.0
        lowBoostParams.gain = 2.0

        return [eq]
    }

    private func ribbonMicrophoneEffects() -> [AVAudioUnit] {
        // AEA A440 Emulation
        let eq = AVAudioUnitEQ(numberOfBands: 3)

        // High-frequency roll-off
        let highRollOffParams = eq.bands[0]
        highRollOffParams.filterType = .highPass
        highRollOffParams.frequency = 100.0
        highRollOffParams.gain = 0.0

        // Low-frequency boost
        let lowBoostParams = eq.bands[1]
        lowBoostParams.filterType = .lowShelf
        lowBoostParams.frequency = 200.0
        lowBoostParams.gain = 2.0

        // Presence boost
        let presenceBoostParams = eq.bands[2]
        presenceBoostParams.filterType = .parametric
        presenceBoostParams.frequency = 4000.0
        presenceBoostParams.bandwidth = 1.0
        presenceBoostParams.gain = 4.0

        return [eq]
    }

    
    private func customMicrophoneEffects(settings: MicrophoneSettings) -> [AVAudioUnit] {
        // Implement the audio units for the custom microphone preset using the provided settings
        // Example: Gain and frequency adjustments
        let highPassFilter = AVAudioUnitEQ(numberOfBands: 1)
        let highPassParams = highPassFilter.bands[0]
        highPassParams.filterType = .highPass
        highPassParams.frequency = Float(settings.frequency)
        highPassParams.gain = Float(settings.gain * 10) // Adjust the gain factor as needed
        
        return [highPassFilter]
    }
}
