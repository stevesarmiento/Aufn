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

    private var audioChain: AudioChain {
        if usePluginManagement, let selectedPlugins = appSettings.selectedPlugins {
            return AudioChain(microphonePreset: appSettings.selectedMicrophonePreset, plugins: selectedPlugins)
        } else {
            return AudioChain(microphonePreset: AppSettings.defaultMicrophonePresets().first(where: { $0.name == "Dynamic" }), plugins: [])
        }
    }

    var body: some View {
        VStack{
            VStack {
                ZStack{

                    WaveformView(audioLevels: $audioRecorder.audioLevels, isRecording: $audioRecorder.isRecording)
                        .frame(height: UIScreen.main.bounds.height * 0.4)

                    VStack {
                        Spacer()
                            .frame(height: 140)

                        HStack {
                            VStack {
                                if audioRecorder.isRecording {
                                    HStack {
                                        Image(systemName: "circle.fill")
                                            .foregroundColor(.red)
                                        Text("REC")
                                            .foregroundColor(.white.opacity(0.8))
                                            .font(.system(size: 20, design: .monospaced))
                                            .bold()
                                    }
                                    .padding(5)

                                } else {
                                    HStack {
                                        Image(systemName: "circle.fill")
                                            .foregroundColor(.yellow)
                                        Text("REC")
                                            .foregroundColor(.white.opacity(0.4))
                                            .font(.system(size: 20, design: .monospaced))
                                            .bold()
                                    }
                                    .padding(5)
                                }
                            }
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.1)]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(LinearGradient(gradient: Gradient(colors: [.white.opacity(0.1), .white.opacity(0.1)]), startPoint: .leading, endPoint: .trailing), lineWidth: 1)
                            )
                            .padding(.leading, 20)
                            .shadow(radius: 5)

                            Spacer() 

                            HStack {

                                // metronome
                                Button(action: {
                                    showMetronomeSettings.toggle()
                                    let impactMed = UIImpactFeedbackGenerator(style: .medium)
                                    impactMed.impactOccurred()
                                }) {
                                    Image(systemName: "metronome")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white.opacity(0.4))


                                }
                                .padding(5)
                                .shadow(radius: 5)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.1)]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(LinearGradient(gradient: Gradient(colors: [.white.opacity(0.1), .white.opacity(0.1)]), startPoint: .leading, endPoint: .trailing), lineWidth: 1)
                                )
                                .sheet(isPresented: $showMetronomeSettings) {
                                    MetronomeSettingsView()
                                }

                                // app settings
                                Button(action: {
                                    showGeneralSettings.toggle()
                                    let impactMed = UIImpactFeedbackGenerator(style: .medium)
                                    impactMed.impactOccurred()
                                })  {
                                    Image(systemName: "gear")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white.opacity(0.4))

                                }
                                .padding(5)
                                .shadow(radius: 5)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.1)]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(LinearGradient(gradient: Gradient(colors: [.white.opacity(0.1), .white.opacity(0.1)]), startPoint: .leading, endPoint: .trailing), lineWidth: 1)
                                )                               
                                .sheet(isPresented: $showGeneralSettings) {
                                    GeneralSettingsView()
                                }
                            }
                            .padding(.trailing, 20)

                        }
                    }
                }


                // Button(action: {
                //     let impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
                //     impactFeedbackGenerator.prepare()
                //     impactFeedbackGenerator.impactOccurred()

                //     if audioRecorder.isRecording {
                //         audioRecorder.stopRecording()
                //     } else {
                //         audioRecorder.startRecording()
                //     }
                    
                // }) {
                //     Image(systemName: audioRecorder.isRecording ? "square.circle.fill" : "circle.circle.fill")
                //         .font(.system(size: 99))//i got 99 problems but a bitch ain't one.
                //         .foregroundColor(audioRecorder.isRecording ? .red : .blue)
                // }
                // .padding(.bottom)

                        HStack {

                            ZStack {
                                Image("triangle")
                                    .rotationEffect(.degrees(0))                           
                               
                                Image("tape")
                                    .rotationEffect(.degrees(audioRecorder.isRecording ? 360 : 0))
                                    .offset(x: -70, y: -70)
                                    .animation(audioRecorder.isRecording ? Animation.linear(duration: 10).repeatForever(autoreverses: false) : .default, value: audioRecorder.isRecording)

                                // Plugin management
                                Button(action: {
                                    showPluginManagement.toggle()
                                    let impactMed = UIImpactFeedbackGenerator(style: .medium)
                                    impactMed.impactOccurred()
                                }) {
                                    Image(systemName: "wand.and.rays")
                                        .font(.system(size: 23))
                                        .padding()
                                        .foregroundColor(.black.opacity(0.8))
                                        .background(Color.black.opacity(0.1))
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .strokeBorder(LinearGradient(gradient: Gradient(colors: [.white.opacity(0.4), .black.opacity(0.1)]), startPoint: .top, endPoint: .bottom), lineWidth: 1)
                                        )
                                }
                                .offset(x: 120, y: -40)

                                // Audio Settings
                                Button(action: {
                                    showRecordingSettings.toggle()
                                    let impactMed = UIImpactFeedbackGenerator(style: .medium)
                                    impactMed.impactOccurred()
                                }) {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 23))
                                        .padding()
                                        .foregroundColor(.black.opacity(0.6))
                                                    .background(Color.black.opacity(0.1))
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .strokeBorder(LinearGradient(gradient: Gradient(colors: [.white.opacity(0.4), .black.opacity(0.1)]), startPoint: .top, endPoint: .bottom), lineWidth: 1)
                                        )                                

                                    }
                                    .offset(x: -40, y: 120)

                                
                                // Recording Button
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
                                        .font(.system(size: 120))
                                        .foregroundColor(audioRecorder.isRecording ? .red : .blue)
                                }
                                .offset(x: 70, y: 70)
                            } 
                        }  
                    
                    //grills
                    ZStack {
                        HStack(spacing: 10) {
                            ForEach(0..<4) { _ in
                                Rectangle()
                                    .fill(Color(red: 0.141, green: 0.141, blue: 0.141))
                                    .frame(width: 12, height: 40)
                                    .cornerRadius(50)
                            }
                            Spacer() 
                        }
                        .padding(.leading, 15) 

                        HStack(spacing: 10) {
                            Spacer() 
                            ForEach(0..<4) { _ in
                                Rectangle()
                                    .fill(Color(red: 0.141, green: 0.141, blue: 0.141))
                                    .frame(width: 12, height: 40)
                                    .cornerRadius(50)
                            }
                        }
                        .padding(.trailing, 15)
                    }
                    .padding(.bottom) 

                }
                .padding(.horizontal)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color(red: 0.878, green: 0.878, blue: 0.878), Color(red: 0.722, green: 0.722, blue: 0.722)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )   
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 40)
                        .strokeBorder(LinearGradient(gradient: Gradient(colors: [.white.opacity(1), .white.opacity(1)]), startPoint: .leading, endPoint: .trailing), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 40))
                .overlay(
                        Group {
                            if showPluginManagement {
                                        HalfModalView(isShown: $showPluginManagement, onDismiss: {
                                            print("Dismissed")
                                    }) {
                                    PluginManagementView()
                                    }
                                }
                            }
                        )
                .overlay(
                        Group {
                            if showRecordingSettings {
                                        HalfModalView(isShown: $showRecordingSettings, onDismiss: {
                                            print("Dismissed")
                                    }) {
                                        RecordingSettingsView(appSettings: appSettings)
                                    }
                                }
                            }
                        )
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color(red: 0.141, green: 0.141, blue: 0.141)]),
                startPoint: .top,
                endPoint: .bottom
            )   
        )
    }
}

