//
//  Plugin.swift
//  Recordit
//
//  Created by Steven Sarmiento on 4/29/23.
//

import Foundation
import AVFoundation
import AudioToolbox

struct Plugin: Identifiable, Codable {
    var id = UUID()
    let name: String
    let icon: String
    var isToggled: Bool
    var isEnabled: Bool
    
    init(name: String, icon: String, isToggled: Bool, isEnabled: Bool = true) {
        self.name = name
        self.icon = icon
        self.isToggled = isToggled
        self.isEnabled = isEnabled
    }
    
    var node: AVAudioNode? {
        if isEnabled {
            if let audioUnit = createAudioUnit() {
                return audioUnit
            } else {
                print("Failed to create audio unit for plugin \(name).")
                return nil
            }
        } else {
            return AVAudioNode()
        }
    }

    func createAudioUnit() -> AVAudioUnit? {
        switch name.lowercased() {
        case "compressor":
            return compressorEffect()
        case "equalizer":
            return equalizerEffect()
        case "reverb":
            return reverbEffect()
        default:
            print("Unknown plugin name: \(name)")
            return nil
        }
    }

    private func compressorEffect() -> AVAudioUnit {
        let audioComponentDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0)
        
        let audioUnit = AVAudioUnitEffect(audioComponentDescription: audioComponentDescription)
        
        if let parameterTree = audioUnit.auAudioUnit.parameterTree {
            parameterTree.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_Threshold))?.value = -24
            parameterTree.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_HeadRoom))?.value = 5
            parameterTree.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_ExpansionRatio))?.value = 2
            parameterTree.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_ExpansionThreshold))?.value = -40
            parameterTree.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_AttackTime))?.value = 0.01
            parameterTree.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_ReleaseTime))?.value = 0.5
        }
        
        return audioUnit
    }

    private func equalizerEffect() -> AVAudioUnit? {
        let audioEngine = AVAudioEngine()
        let _ = AVAudioUnitEQ(numberOfBands: 3)
        
        guard let audioUnitEQ = audioEngine.avAudioUnitEQ else {
            return nil
        }
        
        audioEngine.attach(audioUnitEQ)
        audioEngine.connect(audioUnitEQ, to: audioEngine.mainMixerNode, format: nil)
        
        audioUnitEQ.bands[0].filterType = AVAudioUnitEQFilterType.lowShelf
        audioUnitEQ.bands[0].frequency = 110.0
        audioUnitEQ.bands[0].gain = 4.0

        // Mid frequency peak filter
        audioUnitEQ.bands[1].filterType = AVAudioUnitEQFilterType.parametric
        audioUnitEQ.bands[1].frequency = 1100.0
        audioUnitEQ.bands[1].bandwidth = 0.71
        audioUnitEQ.bands[1].gain = -3.0

        // High frequency shelf filter
        audioUnitEQ.bands[2].filterType = AVAudioUnitEQFilterType.highShelf
        audioUnitEQ.bands[2].frequency = 10000.0
        audioUnitEQ.bands[2].gain = -2.0

        return audioUnitEQ
    }

private func reverbEffect() -> AVAudioUnit {
    let reverb = AVAudioUnitReverb()

    // Configure plate reverb properties
    reverb.loadFactoryPreset(.plate)
    reverb.wetDryMix = 30.0

    return reverb
}


}

extension AVAudioEngine {
    var avAudioUnitEQ: AVAudioUnitEQ? {
        return self.attachedNodes.compactMap { $0 as? AVAudioUnitEQ }.first
    }
}


