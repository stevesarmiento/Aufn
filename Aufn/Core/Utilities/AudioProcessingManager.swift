import Foundation
import AVFoundation
import Combine

class AudioEngine {
        static let shared = AudioEngine()
        private(set) var audioEngine = AVAudioEngine()
        private var audioChain: AudioChain?

        func updateAudioChain(_ audioChain: AudioChain) {
            // Remove the current audio chain from the audio engine
            disconnectCurrentAudioChain()

            // Set the new audio chain
            self.audioChain = audioChain

            // Connect the new audio chain
            connectNewAudioChain()

            // Start the audio engine
            startAudioEngine()
        }

        func reset() {
            audioEngine.stop()
            audioEngine.reset()
            audioChain = nil
        }

        private func disconnectCurrentAudioChain() {
            if let chain = self.audioChain {
                audioEngine.disconnectNodeInput(audioEngine.inputNode)
                
                if let presetNode = chain.microphonePreset?.node(with: audioEngine) {
                    audioEngine.disconnectNodeOutput(presetNode)
                } else {
                    audioEngine.disconnectNodeOutput(audioEngine.outputNode)
                }
                
                chain.plugins.forEach { plugin in
                    if let pluginNode = plugin.node {
                        audioEngine.disconnectNodeInput(pluginNode)
                    }
                }
            }
        }

        private func connectNewAudioChain() {
            guard let audioChain = self.audioChain else { return }

            var lastConnectedNode: AVAudioNode

            if let presetNode = audioChain.microphonePreset?.node(with: audioEngine) {
                print("Connecting preset node")
                connectNodes(audioEngine.inputNode, presetNode)
                lastConnectedNode = presetNode
            } else {
                print("Connecting input to output directly")
                lastConnectedNode = audioEngine.inputNode
            }

            for plugin in audioChain.plugins {
                print("Processing plugin: \(plugin.name)")
                
                if let pluginNode = plugin.node {
                    audioEngine.attach(pluginNode)
                    connectNodes(lastConnectedNode, pluginNode)
                    lastConnectedNode = pluginNode
                }
            }

            connectNodes(lastConnectedNode, audioEngine.outputNode)
        }

        private func connectNodes(_ sourceNode: AVAudioNode, _ destinationNode: AVAudioNode, format: AVAudioFormat? = nil) {
            let connectionFormat = format ?? sourceNode.inputFormat(forBus: 0)
            print("Connecting \(sourceNode) to \(destinationNode)")
            print("Input format: \(sourceNode.inputFormat(forBus: 0))")
            print("Output format: \(sourceNode.outputFormat(forBus: 0))")
            print("Connection format: \(connectionFormat)")
            audioEngine.connect(sourceNode, to: destinationNode, format: connectionFormat)
        }

        private func startAudioEngine() {
            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setCategory(.playback, mode: .default, options: [])
                try audioSession.setActive(true)
            } catch {
                print("Failed to set audio session category and options: \(error)")
            }

            do {
                try audioEngine.start()
            } catch {
                print("Failed to start audio engine: \(error)")
            }
        }

    }
    
class AudioProcessingManager {
    
    let engine = AVAudioEngine()
    var audioProcessingChain: [AVAudioUnit] = []
    let appSettings: AppSettings
    private var cancellables = Set<AnyCancellable>()
    private var activePlugins: [Plugin] = []
    private var activeMicrophonePreset: MicrophonePreset?
    private let audioEngine: AudioEngine
    
    static let shared = AudioProcessingManager(appSettings: AppSettings())
    
    init(appSettings: AppSettings) {
        self.appSettings = appSettings
        self.audioEngine = AudioEngine()
        observeAppSettings()
        setupAudioProcessingChain()
    }
    
    func resetAudioEngine() {
        audioEngine.reset()
    }

    func updateAudioChain(_ audioChain: AudioChain) {
        audioEngine.updateAudioChain(audioChain)
    }
    func start() {
        do {
            try engine.start()
        } catch {
            print("Error starting the audio engine: \(error.localizedDescription)")
        }
    }

    func stop() {
        engine.stop()
    }

    private func addAudioUnit(_ audioUnit: AVAudioUnit?) {
        guard let audioUnit = audioUnit else { return }
        
        // Get the format for connecting the audio units
        let format = engine.inputNode.outputFormat(forBus: 0)

        // Attach the audio unit to the engine
        engine.attach(audioUnit)

        // Connect the audio unit into the audio processing chain
        if let lastUnit = audioProcessingChain.last {
            engine.disconnectNodeInput(engine.outputNode)
            engine.connect(lastUnit, to: audioUnit, format: format)
            engine.connect(audioUnit, to: engine.outputNode, format: format)
        } else {
            engine.connect(engine.inputNode, to: audioUnit, format: format)
            engine.connect(audioUnit, to: engine.outputNode, format: format)
        }

        // Add the audio unit to the audio processing chain array
        audioProcessingChain.append(audioUnit)
    }
    private func outputFormat(sampleRate: Double, channels: UInt32) -> AVAudioFormat {
        return AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
    }

    private func removeAudioUnit(_ audioUnit: AVAudioUnit?) {
        guard let audioUnit = audioUnit, let index = audioProcessingChain.firstIndex(of: audioUnit) else { return }

        // Get the format for connecting the audio units
        let format = engine.inputNode.outputFormat(forBus: 0)

        // Disconnect the audio unit from the audio processing chain
        if index == 0 {
            if audioProcessingChain.count > 1 {
                let nextUnit = audioProcessingChain[index + 1]
                engine.disconnectNodeInput(nextUnit)
                engine.connect(engine.inputNode, to: nextUnit, format: format)
            } else {
                engine.disconnectNodeInput(engine.outputNode)
                engine.connect(engine.inputNode, to: engine.outputNode, format: format)
            }
        } else {
            let prevUnit = audioProcessingChain[index - 1]
            if index < audioProcessingChain.count - 1 {
                let nextUnit = audioProcessingChain[index + 1]
                engine.disconnectNodeInput(nextUnit)
                engine.connect(prevUnit, to: nextUnit, format: format)
            } else {
                engine.disconnectNodeInput(engine.outputNode)
                engine.connect(prevUnit, to: engine.outputNode, format: format)
            }
        }

        // Remove the audio unit from the audio processing chain array
        audioProcessingChain.remove(at: index)

        // Detach the audio unit from the engine
        engine.detach(audioUnit)
    }

    
func togglePlugin(plugin: Plugin) {
    if plugin.isToggled {
        if let audioUnit = plugin.createAudioUnit() {
            activePlugins.append(plugin)
            addAudioUnit(audioUnit)
        } else {
            print("Failed to create audio unit for plugin \(plugin.name).")
        }
    } else {
        if let index = activePlugins.firstIndex(where: { $0.name == plugin.name }) {
            activePlugins.remove(at: index)
            if let audioUnit = plugin.createAudioUnit() {
                removeAudioUnit(audioUnit)
            }
        }
    }
}


    func toggleMicrophonePreset(preset: MicrophonePreset) {
        if preset.isToggled {
            activeMicrophonePreset = preset
            
            // Apply the microphone preset to the audio processing chain
            preset.audioUnits.forEach { audioUnit in
                addAudioUnit(audioUnit)
            }
        } else {
            // Remove the microphone preset from the audio processing chain
            activeMicrophonePreset?.audioUnits.forEach { audioUnit in
                removeAudioUnit(audioUnit)
            }
            
            activeMicrophonePreset = nil
        }
        
        // Update the audio processing chain to reflect the changes
        updateAudioProcessingChain()
    }

    private func setupAudioProcessingChain() {
        // Remove any existing nodes from the audio processing chain
        audioProcessingChain.forEach { engine.disconnectNodeInput($0) }

        // Set up microphone preset
        if let microphonePreset = appSettings.selectedMicrophonePreset {
            audioProcessingChain.append(contentsOf: microphonePreset.audioUnits)
            print("Microphone preset successfully added to audio processing chain.")
        } else {
            print("No microphone preset selected.")
        }

        // Set up plugins
        if let selectedPlugins = appSettings.selectedPlugins {
            for plugin in selectedPlugins {
                if let audioUnit = plugin.createAudioUnit() {
                    audioProcessingChain.append(audioUnit)
                    print("Plugin \(plugin.name) successfully added to audio processing chain.")
                } else {
                    print("Failed to create audio unit for plugin \(plugin.name).")
                }
            }
        } else {
            print("No plugins selected.")
        }

        // Connect audio processing chain nodes
        let inputNode = engine.inputNode
        let outputNode = engine.outputNode
        let hardwareSampleRate = inputNode.inputFormat(forBus: 0).sampleRate
        let format = outputFormat(sampleRate: hardwareSampleRate, channels: 1)

        if !audioProcessingChain.isEmpty {
            for i in 0..<(audioProcessingChain.count - 1) {
                let currentUnit = audioProcessingChain[i]
                let nextUnit = audioProcessingChain[i + 1]
                engine.attach(currentUnit)
                engine.attach(nextUnit)
                print("Attached nodes \(currentUnit) and \(nextUnit).")

                engine.connect(currentUnit, to: nextUnit, format: format)
                print("Connected nodes \(currentUnit) and \(nextUnit).")
            }

            if let firstUnit = audioProcessingChain.first, let lastUnit = audioProcessingChain.last {
                engine.attach(firstUnit)
                engine.attach(lastUnit)
                print("Attached nodes \(firstUnit) and \(lastUnit).")

                engine.connect(inputNode, to: firstUnit, format: format)
                engine.connect(lastUnit, to: outputNode, format: format)
                print("Connected input node to \(firstUnit) and \(lastUnit) to output node.")
            }
        } else {
            print("Audio processing chain is empty. Connecting input node directly to output node.")
            engine.connect(inputNode, to: outputNode, format: format)
        }
    }

    
private func observeAppSettings() {
    appSettings.$selectedMicrophonePreset.sink { [weak self] preset in
        if let preset = preset {
            self?.toggleMicrophonePreset(preset: preset)
        }
    }.store(in: &cancellables)
    
    appSettings.$selectedPlugins.sink { [weak self] plugins in
        if let plugins = plugins {
            plugins.forEach { plugin in
                self?.togglePlugin(plugin: plugin)
            }
        }
    }.store(in: &cancellables)
}


    func updateAudioProcessingChain() {
        let isRunning = engine.isRunning
        if isRunning { stop() }
        setupAudioProcessingChain()
        if isRunning { start() }
    }
}
