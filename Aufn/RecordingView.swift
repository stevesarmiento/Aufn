import SwiftUI

struct RecordingView: View {
    @EnvironmentObject var appSettings: AppSettings
    @StateObject private var audioRecorder: AudioRecorder
    
    init(appSettings: AppSettings) {
        _audioRecorder = StateObject(wrappedValue: AudioRecorder(appSettings: appSettings))
    }
    
    
    @State private var usePluginManagement = true
    @State private var showGeneralSettings = false
    @State private var showMetronomeSettings = false
    @State private var showRecordingSettings = false
    @State private var showPluginManagement = false
    @State private var isSecondaryNavVisible = true
    
    private var audioChain: AudioChain {
        if usePluginManagement, let selectedPlugins = appSettings.selectedPlugins {
            return AudioChain(microphonePreset: appSettings.selectedMicrophonePreset, plugins: selectedPlugins)
        } else {
            return AudioChain(microphonePreset: AppSettings.defaultMicrophonePresets().first(where: { $0.name == "Dynamic" }), plugins: [])
        }
    }

    var body: some View {
        
        VStack {
            Spacer()

            if audioRecorder.isRecording {
                Text("Recording...")
                    .font(.largeTitle)
                    .foregroundColor(.red)
            } else {
                Text("Ready?")
                    .font(.largeTitle)
            }

            Spacer()

            WaveformView(audioLevels: $audioRecorder.audioLevels)
                .frame(height: 100)

            Spacer()

            Button(action: {
                if audioRecorder.isRecording {
                    audioRecorder.stopRecording()
                } else {
                    audioRecorder.startRecording()
                }
            }) {
                Image(systemName: audioRecorder.isRecording ? "square.circle.fill" : "circle.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(audioRecorder.isRecording ? .red : .blue)
            }

            if isSecondaryNavVisible {
                HStack {
                    // Plugin management button
                    Button(action: {
                        showPluginManagement.toggle()
                        let impactMed = UIImpactFeedbackGenerator(style: .medium)
                        impactMed.impactOccurred()
                    }) {
                        Image(systemName: "wand.and.rays")
                            .font(.system(size: 23))
                            .padding()
                            .foregroundColor(.gray)

                    }
                    .sheet(isPresented: $showPluginManagement) {
                        PluginManagementView()
                    }

                    // Settings button
                    Button(action: {
                        showRecordingSettings.toggle()
                        let impactMed = UIImpactFeedbackGenerator(style: .medium)
                        impactMed.impactOccurred()
                    }) {
                        Image(systemName: "waveform")
                            .font(.system(size: 23))
                            .padding()
                            .foregroundColor(.gray)

                    }
                    .sheet(isPresented: $showRecordingSettings) {
                        RecordingSettingsView(appSettings: appSettings)
                    }

                    // Placeholder button 1
                    Button(action: {
                        showMetronomeSettings.toggle()
                        let impactMed = UIImpactFeedbackGenerator(style: .medium)
                        impactMed.impactOccurred()
                    }) {
                        Image(systemName: "metronome")
                            .font(.system(size: 23))
                            .padding()
                            .foregroundColor(.gray)


                    }.sheet(isPresented: $showMetronomeSettings) {
                        MetronomeSettingsView()
                    }

                    // Placeholder button 2
                    Button(action: {
                        showGeneralSettings.toggle()
                        let impactMed = UIImpactFeedbackGenerator(style: .medium)
                        impactMed.impactOccurred()
                    })  {
                        Image(systemName: "gear")
                            .font(.system(size: 23))
                            .padding()
                            .foregroundColor(.gray)

                    }.sheet(isPresented: $showGeneralSettings) {
                        GeneralSettingsView()
                    }
                }
            }
        }
        .padding()
        .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged({ value in
                        withAnimation {
                            isSecondaryNavVisible = value.translation.height < 0
                        }
                    })
                    .onEnded({ value in
                        withAnimation {
                            isSecondaryNavVisible = value.translation.height < -50
                        }
                    })
                    .simultaneously(with: TapGesture().onEnded {
                        withAnimation {
                            isSecondaryNavVisible.toggle()
                        }
                    })
            )
        }

}
