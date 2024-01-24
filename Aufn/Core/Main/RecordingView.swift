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
            Spacer()

            if audioRecorder.isRecording {
                Text("Recording...")
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.red)
            } else {
                Text("Ready?")
                    .foregroundColor(.white)
                    .font(.largeTitle)
                    .bold()
            }

            Spacer()

            WaveformView(audioLevels: $audioRecorder.audioLevels, isRecording: $audioRecorder.isRecording)
                .frame(height: UIScreen.main.bounds.height * 0.5) // Adjust the height here

            Spacer()

            Button(action: {
                let impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
                impactFeedbackGenerator.prepare()
                impactFeedbackGenerator.impactOccurred()

                if audioRecorder.isRecording {
                    audioRecorder.stopRecording()
                } else {
                    audioRecorder.startRecording()
                }
                
            }) {
                Image(systemName: audioRecorder.isRecording ? "square.circle.fill" : "circle.circle.fill")
                    .font(.system(size: 99))//i got 99 problems but a bitch ain't one.
                    .foregroundColor(audioRecorder.isRecording ? .red : .blue)
            }.padding(.bottom)



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
                            .foregroundColor(.white.opacity(0.6))

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
                            .foregroundColor(.white.opacity(0.6))

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
                            .foregroundColor(.white.opacity(0.6))


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
                            .foregroundColor(.white.opacity(0.6))

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
                            isSecondaryNavVisible = value.translation.height < 100
                        }
                    })
                    .onEnded({ value in
                        withAnimation {
                            isSecondaryNavVisible = value.translation.height < -100
                        }
                    })
                    // .simultaneously(with: TapGesture().onEnded {
                    //     withAnimation {
                    //         isSecondaryNavVisible.toggle()
                    //     }
                    // })
            )
        .background(
            LinearGradient(
                gradient: Gradient(colors: [ Color(red: 0.047, green: 0.039, blue: 0.055), Color.black.opacity(1)]),
                startPoint: .top,
                endPoint: .bottom
            ).edgesIgnoringSafeArea(.all)
            
        )
        }

}
