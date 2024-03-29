import Foundation
import SwiftUI

struct RecordingSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var appSettings: AppSettings

    var body: some View {
        NavigationView {
            VStack (alignment: .leading) {
                //header tag
                HStack {
                        Text("This is how your audio prints.")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Spacer()
                }
                .padding()
                
                //scrollview
                ScrollView {
                    VStack (alignment: .leading) {
                            channelToggle

                            fileTypeSelection

                            qualitySelection
                        }
                }
                .navigationTitle("Audio Settings")
                .foregroundColor(.white)
                // .toolbar {
                //         ToolbarItem(placement: .navigationBarTrailing) {
                //             Button(action: {
                //                 dismiss()
                //             }) {
                //                 Image(systemName: "chevron.down.circle.fill")
                //                     .font(.system(size: 20))
                //                     .foregroundColor(.white.opacity(0.2))
                //             }
                //         }
                //     }
            }
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [ Color(red: 0.141, green: 0.141, blue: 0.141), Color(red: 0.141, green: 0.141, blue: 0.141)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 40))
        .overlay(
            RoundedRectangle(cornerRadius: 40)
                .strokeBorder(LinearGradient(gradient: Gradient(colors: [.white.opacity(0.2), .white.opacity(0.2)]), startPoint: .leading, endPoint: .trailing), lineWidth: 1)
        )
        .edgesIgnoringSafeArea(.all)
    }
}

extension RecordingSettingsView {

    private var qualitySelection: some View {
                                // Audio quality (sample rate)
                        VStack(alignment: .leading) {
                            Text("Sample Rate")
                                .font(.headline)
                                .padding(.horizontal, 10)
                                
                            let iconNames = ["moonphase.waxing.gibbous.inverse", "moonphase.first.quarter.inverse", "moonphase.waxing.crescent.inverse", "moonphase.new.moon.inverse"]
                            let descriptions = ["G", "G+", "H", "H+"]
                            let explainers = [
                                "44.1 kHz: CD quality, smaller file size, suitable for most uses.",
                                "48 kHz: Higher quality, slightly larger file size, common for video.",
                                "88.2 kHz: Enhanced audio quality, larger file size, for high-fidelity music.",
                                "96 kHz: Studio-grade quality, largest file size, suitable for professional audio."
                            ]

                            VStack {
                                HStack {
                                    ForEach(appSettings.availableSampleRates.indices, id: \.self) { index in
                                        VStack {
                                            Button(action: {
                                                let impactMed = UIImpactFeedbackGenerator(style: .medium)
                                                impactMed.impactOccurred()
                                                if appSettings.audioFormats[appSettings.selectedAudioFormatIndex] == "WAV" || index < 2 {
                                                    appSettings.selectedSampleRateIndex = index
                                                }
                                            }) {
                                                VStack {
                                                    Image(systemName: iconNames[index])
                                                        .resizable()
                                                        .scaledToFit()
                                                        .frame(width: 30, height: 30)
                                                        .foregroundColor(
                                                            appSettings.selectedSampleRateIndex == index ?
                                                                .green :
                                                                (appSettings.audioFormats[appSettings.selectedAudioFormatIndex] == "WAV" || index < 2 ?
                                                                    Color.white.opacity(0.5):
                                                                    Color.white.opacity(0.3))
                                                        )
                                                        .padding()
                                                        .background(appSettings.selectedSampleRateIndex == index ? .white.opacity(0.2) : Color.clear)
                                                                                                            .overlay(
                                                        RoundedRectangle(cornerRadius: 16)
                                                        .strokeBorder(LinearGradient(gradient: Gradient(colors: [.white.opacity(0.1), .white.opacity(0)]), startPoint: .leading, endPoint: .trailing), lineWidth: 1)
                                                    )
                                                    .shadow(radius: 10) 
                                                    .cornerRadius(16)
                                                        .cornerRadius(16)
                                                }
                                            }
                                            .disabled(appSettings.audioFormats[appSettings.selectedAudioFormatIndex] != "WAV" && index >= 2)

                                            VStack(alignment: .center, spacing: 4) {
                                                Text(descriptions[index])
                                                    .font(.caption)
                                                    .bold()
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                                .padding(.horizontal, 10)
                                
                                ZStack {
                                    VStack {
                                        HStack() {
                                            Image(systemName: iconNames[appSettings.selectedSampleRateIndex])
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 30, height: 30)
                                                .foregroundColor(.white.opacity(0.8))


                                            Text(explainers[appSettings.selectedSampleRateIndex])
                                                .font(.system(size: 16))
                                                .foregroundColor(.white.opacity(0.5))
                                        }
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                    }
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
                                }
                                .padding(.horizontal, 10)
                            }
                        }
    }

    private var fileTypeSelection: some View {
                        // Audio file format
                        VStack(alignment: .leading) {

                            Text("File Format")
                                .font(.headline)
                                .padding(.horizontal, 10)

                            let iconNames = ["hifispeaker.2.fill", "hifispeaker.fill"]
                            let descriptions = ["WAV", "M4A"]
                            let explainers = [
                                "Uncompressed, highest quality audio. Access to H, and H+ quality, larger files.",
                                "Compressed audio format, limited to G, G+ quality, provides smaller file size."
                            ]
                            HStack {
                                ForEach(appSettings.audioFormats.indices, id: \.self) { index in
                                    VStack {
                                        Button(action: {
                                            let impactMed = UIImpactFeedbackGenerator(style: .medium)
                                            impactMed.impactOccurred()
                                            appSettings.selectedAudioFormatIndex = index
                                        }) {
                                            VStack {
                                                Image(systemName: iconNames[index])
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: 30, height: 30)
                                                    .foregroundColor(appSettings.selectedAudioFormatIndex == index ? .yellow : .white.opacity(0.5))
                                                    .padding()
                                                    .background(appSettings.selectedAudioFormatIndex == index ? Color.white.opacity(0.2) : Color.clear)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 16)
                                                        .strokeBorder(LinearGradient(gradient: Gradient(colors: [.white.opacity(0.1), .white.opacity(0)]), startPoint: .leading, endPoint: .trailing), lineWidth: 1)
                                                    )
                                                    .shadow(radius: 10) 
                                                    .cornerRadius(16)
                                            }
                                        }
                                        VStack(alignment: .center, spacing: 4) {
                                            Text(descriptions[index])
                                            .font(.caption)

                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 10)

                            ZStack {
                                VStack() {
                                    HStack(){
                                        Image(systemName: iconNames[appSettings.selectedAudioFormatIndex])
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 30, height: 30)
                                            .foregroundColor(.white.opacity(0.8))


                                        Text(explainers[appSettings.selectedAudioFormatIndex])
                                            .font(.system(size: 16))
                                            .foregroundColor(.white.opacity(0.5))
                                    }
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
                            }
                            .padding(.horizontal, 10)
                        }
    }

    private var channelToggle: some View {
                        // Mono/stereo toggle
                VStack {
                        HStack {
                            Image(systemName: "square.2.layers.3d.bottom.filled")
                                .foregroundColor(.blue)
                                .font(.system(size: 20))
                                .padding(.trailing, 8)
                            Toggle("Stereo Recording", isOn: $appSettings.isStereo)
                                .font(.headline)
                                .foregroundColor(.white)
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
                    .padding(.horizontal, 10)
    }
}
