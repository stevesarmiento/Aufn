//
//  MetronomeSettingsView.swift
//  Recordit
//
//  Created by YourName on 4/28/23.
//

import SwiftUI

struct MetronomeIconButton: View {
    let name: String
    let icon: String
    @Binding var selected: Int
    let index: Int

    var body: some View {
        Button(action: {
            let impactMed = UIImpactFeedbackGenerator(style: .medium)
            impactMed.impactOccurred()
            selected = index
        }) {
            VStack {
                Image(systemName: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .foregroundColor(selected == index ? .white : .gray)
                Text(name)
                    .font(.caption)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selected == index ? Color.blue : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(selected == index ? Color.blue : Color.gray.opacity(0.2), lineWidth: 2)
                    )
            )
        }
    }
}

struct MetronomeSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var metronomeEnabled = false
    @State private var bpm: String = "120"
    @State private var timeSignature = 0
    @State private var metronomeSound = 0
    @State private var metronomeVolume: Double = 0.5

    let timeSignatures = ["4/4 ", "3/4", "6/8", "5/4"]
    let metronomeSounds = [("Click", "hand.thumbsup"), ("Beep", "bell"), ("Wood", "leaf")]

    var body: some View {
        NavigationView {
            VStack {
                HStack {
                    Text("Metronome Settings")
                        .font(.headline)
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding()

                ScrollView {
                    VStack(alignment: .leading) {
                    // metronome toggle
                        VStack {
                            HStack {
                                Image(systemName: "metronome.fill") // Placeholder image
                                    .foregroundColor(.yellow)
                                    .font(.system(size: 20))
                                    .padding(.trailing, 8)
                                    Toggle("Metronome", isOn: $metronomeEnabled)
                                    .font(.headline)
                                    .foregroundColor(Color(.label))
                                Spacer()
                            }
                            .padding()
                            .background(Color(.systemGroupedBackground))
                            .cornerRadius(16)
                        }


                        Text("BPM")
                            .font(.headline)
                            .padding(.top)
                        
                        TextField("120", text: $bpm)
                                .keyboardType(.numberPad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 80, alignment: .center)

                        Text("Time Signature")
                            .font(.headline)
                            .padding(.top)
                        Picker("", selection: $timeSignature) {
                            ForEach((0..<timeSignatures.count), id: \.self) { index in
                                Text(timeSignatures[index])
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())

                        Text("Metronome Sound")
                            .font(.headline)
                            .padding(.top)
                        HStack {
                            ForEach(metronomeSounds.indices, id: \.self) { index in
                                MetronomeIconButton(name: metronomeSounds[index].0, icon: metronomeSounds[index].1, selected: $metronomeSound, index: index)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)

                        Text("Volume (\(Int(metronomeVolume * 100)))")
                            .font(.headline)
                            .padding(.top)
                        Slider(value: $metronomeVolume)
                            .padding(.vertical)
                    }
                    .padding()
                }
                .navigationTitle("Metrono")
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
}
