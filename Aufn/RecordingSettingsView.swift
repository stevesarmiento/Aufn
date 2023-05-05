import Foundation
import SwiftUI

struct RecordingSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var appSettings: AppSettings

    var body: some View {
        NavigationView {
            VStack {
                HStack {
                    Text("This is how your audio prints.")
                        .font(.headline)
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding()
                ScrollView {
                    // Audio file format
                    VStack(alignment: .leading, spacing: 10) {
                        Text("File Format")
                            .font(.headline)
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
                                                .foregroundColor(appSettings.selectedAudioFormatIndex == index ? .white : .gray)
                                                .padding()
                                                .background(appSettings.selectedAudioFormatIndex == index ? Color.blue : Color.clear)
                                                .cornerRadius(16)
                                        }
                                    }.padding(.horizontal)
                                    VStack(alignment: .center, spacing: 4) {
                                        Text(descriptions[index])
                                        .font(.caption)

                                    }
                                }


                            }
                            
                        }
                        ZStack {
                            VStack() {
                                HStack(){
                                    Image(systemName: iconNames[appSettings.selectedAudioFormatIndex])
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 30, height: 30)
                                        .foregroundColor(.blue)


                                    Text(explainers[appSettings.selectedAudioFormatIndex])
                                        .font(.system(size: 16))
                                        .foregroundColor(.gray)
                                }
                            .frame(maxWidth: .infinity)
                            } 
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 15).fill(Color(.systemGroupedBackground)))
                        }

                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                    
                    // Audio quality (sample rate)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sample Rate")
                            .font(.headline)
                            .padding(.horizontal)
                            
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
                                                    .foregroundColor(appSettings.selectedSampleRateIndex == index ? .white : (appSettings.audioFormats[appSettings.selectedAudioFormatIndex] == "WAV" || index < 2 ? .gray : .gray))
                                                    .padding()
                                                    .background(appSettings.selectedSampleRateIndex == index ? Color.blue : Color.clear)
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
                            
                            ZStack {
                                VStack {
                                    HStack() {
                                        Image(systemName: iconNames[appSettings.selectedSampleRateIndex])
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 30, height: 30)
                                            .foregroundColor(.blue)


                                        Text(explainers[appSettings.selectedSampleRateIndex])
                                            .font(.system(size: 16))
                                            .foregroundColor(.gray)
                                    }
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                }
                                .background(RoundedRectangle(cornerRadius: 15).fill(Color(.systemGroupedBackground)))
                            }.padding(.horizontal)




                        }
                  // Mono/stereo toggle
                    VStack {
                        HStack {
                            Image(systemName: "square.2.layers.3d.bottom.filled") // Placeholder image
                                .foregroundColor(.blue)
                                .font(.system(size: 20))
                                .padding(.trailing, 8)
                            Toggle("Stereo Recording", isOn: $appSettings.isStereo)
                                .font(.headline)
                                .foregroundColor(Color(.label))
                            Spacer()
                        }
                        .padding()
                        .background(Color(.systemGroupedBackground))
                        .cornerRadius(16)
                    }.padding(.horizontal)
                }
            }.padding()

         }
            .navigationTitle("Audio Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Color(.systemGray4))
                    }
                }
            }
        }
    }
}
