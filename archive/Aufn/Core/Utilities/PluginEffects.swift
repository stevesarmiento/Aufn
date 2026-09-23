//
//  PluginEffects.swift
//  Recordit
//
//  Created by Steven Sarmiento on 4/29/23.
//

import Foundation
import AVFoundation
import AudioToolbox

extension Plugin {
    func createPluginAudioUnit() -> AVAudioUnit? {
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

        // Configure Teletronix LA-2A compressor properties
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



    private func equalizerEffect() -> AVAudioUnit {
        let equalizer = AVAudioUnitEQ(numberOfBands: 3)

        // Configure Neve 1073 preamp equalizer properties
        // Low frequency shelf filter
        equalizer.bands[0].filterType = .lowShelf
        equalizer.bands[0].frequency = 110.0
        equalizer.bands[0].gain = 4.0

        // Mid frequency peak filter
        equalizer.bands[1].filterType = .parametric
        equalizer.bands[1].frequency = 1100.0
        equalizer.bands[1].bandwidth = 0.71
        equalizer.bands[1].gain = -3.0

        // High frequency shelf filter
        equalizer.bands[2].filterType = .highShelf
        equalizer.bands[2].frequency = 10000.0
        equalizer.bands[2].gain = -2.0

        return equalizer
    }



    private func reverbEffect() -> AVAudioUnit {
        let reverb = AVAudioUnitReverb()

        // Configure plate reverb properties
        reverb.loadFactoryPreset(.plate)
        reverb.wetDryMix = 30.0

        return reverb
    }

}
