//  PluginManagementView.swift
//  Recordit
//
//  Created by Steven Sarmiento on 4/27/23.
//

import Foundation
import SwiftUI
import AVFAudio

struct AudioChain {
    let microphonePreset: MicrophonePreset?
    let plugins: [Plugin]
}

struct ToggleableButton: View {
    let name: String
    let icon: String
    @Binding var isToggled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            let impactMed = UIImpactFeedbackGenerator(style: .medium)
            impactMed.impactOccurred()
            action()
        }) {
            Image(systemName: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .foregroundColor(isToggled ? .green : .white.opacity(0.3))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isToggled ? Color.white.opacity(0.2) : Color.clear)
                .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(LinearGradient(gradient: Gradient(colors: [.white.opacity(0.1), .white.opacity(0)]), startPoint: .leading, endPoint: .trailing), lineWidth: 1)
                        )
                        .shadow(radius: 10)
        )
    }
}

struct PluginManagementView: View {
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dismiss) var dismiss
    @State private var hasLoadedSettings = false
    @State private var chainConnectionEnabled = false
    @State private var microphones: [MicrophonePreset] = []
    @State private var plugins = [
        Plugin(name: "Compressor", icon: "rectangle.compress.vertical", isToggled: false),
        Plugin(name: "Equalizer", icon: "dial.medium", isToggled: false),
        Plugin(name: "Reverb", icon: "drop", isToggled: false)
    ]

    // Helper functions to handle selection changes
    func microphonePresetSelected(at index: Int) {
        if microphones[index].isToggled {
            microphones[index].isToggled = false
            appSettings.selectedMicrophonePreset = nil
        } else {
            for i in 0..<microphones.count {
                if i == index {
                    microphones[i].isToggled = true
                    appSettings.selectedMicrophonePreset = microphones[i]
                } else {
                    microphones[i].isToggled = false
                }
            }
        }
    }
    
    func pluginSelected(at index: Int) {
        plugins[index].isToggled.toggle()
        let selectedPlugins = plugins.filter { $0.isToggled }.map { Plugin(name: $0.name, icon: $0.icon, isToggled: true) }
        appSettings.selectedPlugins = selectedPlugins
        
        // Remove all connections from the audio engine
        AudioProcessingManager.shared.resetAudioEngine()
        
        // Reconnect nodes based on the updated list of selected plugins
        let audioChain = AudioChain(microphonePreset: appSettings.selectedMicrophonePreset, plugins: selectedPlugins)
        AudioProcessingManager.shared.updateAudioChain(audioChain)
    }
    
    func loadMicrophoneAndPluginSettings() {
        if let selectedMicrophonePreset = appSettings.selectedMicrophonePreset {
            microphones = AppSettings.defaultMicrophonePresets().map { preset in
                if preset.name == selectedMicrophonePreset.name {
                    return selectedMicrophonePreset
                } else {
                    return preset
                }
            }
        } else {
            microphones = AppSettings.defaultMicrophonePresets()
        }
        
        if let selectedPlugins = appSettings.selectedPlugins {
            plugins = plugins.map { plugin in
                if let foundPlugin = selectedPlugins.first(where: { $0.name == plugin.name }) {
                    return Plugin(name: foundPlugin.name, icon: foundPlugin.icon, isToggled: true)
                } else {
                    return plugin
                }
            }
        } else {
            appSettings.selectedPlugins = []
        }
    }
    
    func saveSettings() {
        appSettings.saveSelectedMicrophonePreset()
        appSettings.saveSelectedPlugins()
    }
    
    var body: some View {
        NavigationView {
            VStack (alignment: .leading) {
                HStack {
                    Text("Whats in your audio-chain?")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                }
                .padding()
                ScrollView {
                    VStack (alignment: .leading) {
                        // connect audiochain toggle
                            VStack {
                                HStack {
                                    Image(systemName: "bolt.heart.fill") // Placeholder image
                                        .foregroundColor(chainConnectionEnabled ? .green : .yellow)
                                        .font(.system(size: 20))
                                        .padding(.trailing, 8)
                                    Toggle("Connect Audio-chain", isOn: $chainConnectionEnabled)
                                        .font(.headline)
                                        .foregroundColor(Color(.white))
                                    Spacer()
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.1)]),
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(LinearGradient(gradient: Gradient(colors: [.white.opacity(0.1), .white.opacity(0.2)]), startPoint: .leading, endPoint: .trailing), lineWidth: 1)
                        )
                        .shadow(radius: 10)     
                )
                                .cornerRadius(16)
                            }
                            .padding(.horizontal)
                            .padding(.bottom)
                        Text("Microphone Type")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        let micExplainers = [
                            "The versatile microphone, suitable for a wide range of applications.",
                            "A Sensitive microphone, capturing detailed and accurate sound.",
                            "Delivers a smooth and warm sound, ideal for capturing vintage tones.",
                            "You decide the levels you need to work with to get your sound."
                        ]
                        
                        HStack {
                             ForEach(microphones.indices, id: \.self) { index in
                                 VStack {
                                     ToggleableButton(name: microphones[index].name, icon: microphones[index].icon, isToggled: $microphones[index].isToggled) {
                                         microphonePresetSelected(at: index)
                                     }
                                     Text(microphones[index].name)
                                         .font(.caption)
                                 }
                                 .padding(.horizontal)
                             }
                         }
                        
                        CardView(title: "", iconName: microphones.first(where: { $0.isToggled })?.icon ?? "waveform.badge.plus", description: microphones.first(where: { $0.isToggled }) != nil ? micExplainers[microphones.firstIndex(where: { $0.isToggled })!] : "Aufn offers high-quality built-in custom microphone pre-amps incasse you want to try something new.")
                            .padding(.horizontal)
                        
                        if let customMicIndex = microphones.firstIndex(where: { $0.name == "Custom" }), microphones[customMicIndex].isToggled {
                            VStack {
                                Text("Custom Microphone Settings")
                                    .font(.headline)
                                // Add UI components to adjust custom microphone settings
                                // Example: Gain slider
                                HStack {
                                    Text("Gain")
                                    Slider(value: $microphones[customMicIndex].settings.gain, in: 0...1)
                                }
                                // Example: Frequency slider
                                HStack {
                                    Text("Frequency")
                                    Slider(value: $microphones[customMicIndex].settings.frequency, in: 100...2000)
                                }
                                // Add other UI components for other settings
                            }
                            .padding(.horizontal)
                        }
                        
                        
                        Text("Processing")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        let pluginExplainers = [
                            "Dynamic range control of your audio, loud parts are quieter and quiet parts are louder.",
                            "A general frequency boost that helps add clarity to your audio recording.",
                            "Add some depth and space to your audio, this is a hall reverb."
                        ]
                        
                        HStack {
                            ForEach(plugins.indices, id: \.self) { index in
                                VStack {
                                    ToggleableButton(name: plugins[index].name, icon: plugins[index].icon, isToggled: $plugins[index].isToggled) {
                                        pluginSelected(at: index)
                                        
                                    }
                                    Text(plugins[index].name)
                                        .font(.caption)
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        CardView(title: "", iconName: plugins.first(where: { $0.isToggled })?.icon ?? "wand.and.stars", description: plugins.first(where: { $0.isToggled }) != nil ? pluginExplainers[plugins.firstIndex(where: { $0.isToggled })!] : "Add some magic to your chain. Print it directly to tape.")
                            .padding(.horizontal)
                    }
                }
                .navigationTitle("Chain Manager")
                .foregroundColor(.white)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "chevron.down.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(Color.white.opacity(0.2))
                        }
                    }
                }
            }
            .background(
            LinearGradient(
                gradient: Gradient(colors: [ Color(red: 0, green: 0.122, blue: 0.137), Color.black.opacity(1)]),
                startPoint: .top,
                endPoint: .bottom
            )
            
        ) 
            .onAppear {
                loadMicrophoneAndPluginSettings()
            }
            .onDisappear {
                saveSettings()
            }
        }.clipShape(RoundedRectangle(cornerRadius: 30))
         .edgesIgnoringSafeArea(.all)
    }
    
    struct CardView: View {
        let title: String
        let iconName: String
        let description: String
        
        var body: some View {
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                    .padding(.horizontal)
                
                ZStack {
                    RoundedRectangle(cornerRadius: 15)
                          .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.1)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(LinearGradient(gradient: Gradient(colors: [.white.opacity(0.1), .white.opacity(0.2)]), startPoint: .leading, endPoint: .trailing), lineWidth: 1)
                        )
                        .shadow(radius: 10)

                    HStack {
                        Image(systemName: iconName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .foregroundColor(.white.opacity(0.8))
                            .padding()

                        Text(description)
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding()
                }

            }
        }
    }
}
