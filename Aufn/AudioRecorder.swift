//
//  AudioRecorder.swift
//  Recordit
//
//  Created by Steven Sarmiento on 4/24/23.
//

import Foundation
import AVFoundation
import Accelerate


extension Notification.Name {
    static let newRecordingAdded = Notification.Name("newRecordingAdded")
}

class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    var audioRecorder: AVAudioRecorder!
    private var outputFile: AVAudioFile?
    @Published var isRecording = false
    @Published var audioLevels: [CGFloat] = Array(repeating: 0, count: 30)
    private var audioEngine: AVAudioEngine!
    private var attachedNodes: [AVAudioNode] = []
    private var audioProcessingManager: AudioProcessingManager!
    var appSettings: AppSettings
    var finalURL: URL
    var temporaryAudioFilename: URL

    init(appSettings: AppSettings) {
        self.appSettings = appSettings
        let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMddHHmmss"
        let recordingName = "recording_\(dateFormatter.string(from: Date())).\(appSettings.audioFormats[appSettings.selectedAudioFormatIndex].lowercased())"
        finalURL = documentPath.appendingPathComponent(recordingName)
        temporaryAudioFilename = documentPath.appendingPathComponent("temp_recording.\(appSettings.audioFormats[appSettings.selectedAudioFormatIndex].lowercased())")
        super.init()
        self.audioProcessingManager = AudioProcessingManager(appSettings: appSettings)
    }


    func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth, .allowAirPlay, .mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            try AVAudioSession.sharedInstance().setMode(.measurement)
            
            // Set the preferred sample rate
            let preferredSampleRate = appSettings.availableSampleRates[appSettings.selectedSampleRateIndex]
            try AVAudioSession.sharedInstance().setPreferredSampleRate(Double(preferredSampleRate))
            
            // Set preferred IO buffer duration
            let ioBufferDuration: TimeInterval = appSettings.limitAlertEnabled ? 0.005 : 0.01
            try AVAudioSession.sharedInstance().setPreferredIOBufferDuration(ioBufferDuration)
            
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }

    func checkFileSavedSuccessfully(url: URL) -> Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: url.path)
    }
    
    private func setupAudioRecorder() {
    let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let temporaryAudioFilename = documentPath.appendingPathComponent("temp_recording.\(appSettings.audioFormats[appSettings.selectedAudioFormatIndex].lowercased())")
    
    let numberOfChannels = appSettings.isStereo ? 2 : 1
    let settings: [String: Any] = [
        AVFormatIDKey: appSettings.audioFormats[appSettings.selectedAudioFormatIndex] == "WAV" ? kAudioFormatLinearPCM : kAudioFormatMPEG4AAC,
        AVSampleRateKey: appSettings.availableSampleRates[appSettings.selectedSampleRateIndex],
        AVNumberOfChannelsKey: numberOfChannels,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]
    
        do {
            let audioRecorder = try AVAudioRecorder(url: temporaryAudioFilename, settings: settings)
            audioRecorder.delegate = self
            audioRecorder.isMeteringEnabled = true
            audioRecorder.prepareToRecord()
            audioRecorder.record()
            
            // Set the NSFileProtectionComplete attribute
            try (temporaryAudioFilename as NSURL).setResourceValue(URLFileProtection.complete, forKey: .fileProtectionKey)
        } catch {
            print("Failed to initialize audio recorder: \(error)")
        }
    }

    private func createAudioFileOutputNode() -> AVAudioFile? {
        let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let temporaryAudioFilename = documentPath.appendingPathComponent("temp_recording.\(appSettings.audioFormats[appSettings.selectedAudioFormatIndex].lowercased())")
        
        let audioFileFormat = appSettings.audioFormats[appSettings.selectedAudioFormatIndex]
        let audioFileSettings: [String: Any] = [
            AVFormatIDKey: audioFileFormat == "WAV" ? kAudioFormatLinearPCM : kAudioFormatMPEG4AAC,
            AVSampleRateKey: Float(appSettings.sampleRates[appSettings.selectedSampleRateIndex]),
            AVNumberOfChannelsKey: appSettings.isStereo ? 2 : 1,
            AVLinearPCMBitDepthKey: 16,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        
        do {
            let outputFile = try AVAudioFile(forWriting: temporaryAudioFilename, settings: audioFileSettings)
            return outputFile
        } catch {
            print("Failed to create AVAudioFile: \(error)")
            return nil
        }
    }
    
    
    func startRecording() {
        print("startRecording called")
        if audioEngine == nil {
            setupAudioEngine()
            setupAudioProcessingNodes()
        }
        
        do {
            print("Setting audio session active")
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
            
            // Remove the tap on the mainMixerNode if it exists
            if isRecording {
                audioEngine.inputNode.removeTap(onBus: 0)
                audioEngine.mainMixerNode.removeTap(onBus: 0)
                isRecording = false
            }
            
            setupTapOnInputNode()
            audioEngine.prepare()
            print("Starting audio engine")
            try audioEngine.start()
            
            // Start the AudioProcessingManager engine
            audioProcessingManager.start()
            
            isRecording = true
            
            // Add a tap on the mainMixerNode output
            let format = audioEngine.mainMixerNode.outputFormat(forBus: 0)
            outputFile = createAudioFileOutputNode()
            
            audioEngine.mainMixerNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                do {
                    try self?.outputFile?.write(from: buffer)
                } catch {
                    print("Failed to write to the output file: \(error)")
                }
            }
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    func stopRecording() {
        print("stopRecording called")
        isRecording = false
        
        // Remove the tap from the inputNode and mainMixerNode
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.mainMixerNode.removeTap(onBus: 0)
        
        // Stop the AudioProcessingManager engine
        audioProcessingManager.stop()
        
        // Close the output file and set the outputFile to nil
        outputFile = nil
        
         if checkFileSavedSuccessfully(url: finalURL) {
        print("File saved successfully")
        } else {
            print("Failed to save the recorded audio file")
        }
        // Reset audio session
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to reset audio session: \(error)")
        }
        
        // Move the temporary recording to its final location
        let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMddHHmmss"
        let recordingName = "recording_\(dateFormatter.string(from: Date())).\(appSettings.audioFormats[appSettings.selectedAudioFormatIndex].lowercased())"
        let finalURL = documentPath.appendingPathComponent(recordingName)
        let temporaryAudioFilename = documentPath.appendingPathComponent("temp_recording.\(appSettings.audioFormats[appSettings.selectedAudioFormatIndex].lowercased())")
        
        do {
            try FileManager.default.moveItem(at: temporaryAudioFilename, to: finalURL)
            NotificationCenter.default.post(name: .newRecordingAdded, object: nil)
            print("File moved successfully")
        } catch {
            print("Failed to move the recorded audio file: \(error)")
        }
        
        // Stop the audio engine
        audioEngine.stop()
    } 

    private func setupAudioProcessingNodes() {
        print("Setting up audio processing nodes...")
        guard let microphonePreset = appSettings.selectedMicrophonePreset,
            let selectedPlugins = appSettings.selectedPlugins else {
            print("Microphone preset or plugins not selected.")
            return
        }

        // Detach all nodes from the audio engine
        for node in attachedNodes {
            audioEngine.detach(node)
        }
        attachedNodes.removeAll()
        
        // Set up the nodes for the selected microphone preset
        let microphoneNode = microphonePreset.node(with: audioEngine)
        attachedNodes.append(microphoneNode)
        
        // Set up the nodes for the selected plugins
        var lastNode: AVAudioNode = microphoneNode
        for plugin in selectedPlugins {
            if let pluginNode = plugin.createAudioUnit() {
                audioEngine.attach(pluginNode)
                audioEngine.connect(lastNode, to: pluginNode, format: audioEngine.mainMixerNode.outputFormat(forBus: 0))
                lastNode = pluginNode
                attachedNodes.append(pluginNode)
                print("Plugin \(plugin.name) successfully attached to audio processing chain.")
            } else {
                print("Failed to create audio unit for plugin \(plugin.name).")
            }
        }
        
        // Connect the last plugin node to the main mixer node
        audioEngine.connect(lastNode, to: audioEngine.mainMixerNode, format: audioEngine.mainMixerNode.outputFormat(forBus: 0))
        print("Audio processing nodes set up successfully.")
    }


        
        
        
        
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
    }
    
    private func setupTapOnInputNode() {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            let channelData = buffer.floatChannelData?[0]
            let bufferSize = buffer.frameLength
            var rms: Float = 0
            
            if let data = channelData {
                for i in 0..<Int(bufferSize) {
                    rms += data[i] * data[i]
                }
                rms = sqrtf(rms / Float(bufferSize))
            }
            
            DispatchQueue.main.async {
                if let strongSelf = self {
                    if strongSelf.audioLevels.count < 30 {
                        strongSelf.audioLevels.append(CGFloat(rms))
                    } else {
                        strongSelf.audioLevels.remove(at: 0)
                        strongSelf.audioLevels.append(CGFloat(rms))
                    }
                }
            }
        }
        
        // Initialize the audioRecorder
        let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let temporaryAudioFilename = documentPath.appendingPathComponent("temp_recording.\(appSettings.audioFormats[appSettings.selectedAudioFormatIndex].lowercased())")
        
        let numberOfChannels = appSettings.isStereo ? 2 : 1
        let settings: [String: Any] = [
            AVFormatIDKey: appSettings.audioFormats[appSettings.selectedAudioFormatIndex] == "WAV" ? kAudioFormatLinearPCM : kAudioFormatMPEG4AAC,
            AVSampleRateKey: appSettings.availableSampleRates[appSettings.selectedSampleRateIndex],
            AVNumberOfChannelsKey: numberOfChannels,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            let audioRecorder = try AVAudioRecorder(url: temporaryAudioFilename, settings: settings)
            audioRecorder.delegate = self
            audioRecorder.isMeteringEnabled = true
            audioRecorder.prepareToRecord()
            audioRecorder.record()
            
            // Set the NSFileProtectionComplete attribute
            try (temporaryAudioFilename as NSURL).setResourceValue(URLFileProtection.complete, forKey: .fileProtectionKey)
        } catch {
            print("Failed to initialize audio recorder: \(error)")
        }
    }
}
