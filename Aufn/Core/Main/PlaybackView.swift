//
//  PlaybackView.swift
//  Recordit
//
//  Created by Steven Sarmiento on 4/25/23.
//

import Foundation
import SwiftUI

struct PlaybackView: View {
    @StateObject private var audioPlayer = AudioPlayer()
    @StateObject private var audioFileViewModel = AudioFileViewModel()
    @State private var selectedFile: URL?
    @State private var showShareSheet = false
    @State private var fileToShare: URL?
    @State private var showRecordingDetails = false
    @State private var showClearAlert = false
    @State private var disableSwipe = false


    var body: some View {
        GeometryReader { geometry in 
            VStack{
                HStack {
                    Text("Playback")
                        .font(.largeTitle)
                        .bold()
                    
                    Spacer()
                    
                    Button(action: {
                        showClearAlert = true
                    }) {
                        Text("Clear All")
                    }
                    .alert(isPresented: $showClearAlert) {
                        Alert(title: Text("Clear Audio"), message: Text("Are you sure you want to delete the entire audio list?"), primaryButton: .destructive(Text("Delete All")) {
                            deleteAllFiles()
                        }, secondaryButton: .cancel())
                    }
                }
                .padding()
                
                ZStack {

                    if audioFileViewModel.audioFiles.isEmpty {
                        VStack {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 80))
                                .foregroundColor(.gray.opacity(0.5))
                            Text("No recordings found")
                                .foregroundColor(.gray.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        .padding()
                    } else {
                        ScrollView {
                            LazyVStack {
                            ForEach(audioFileViewModel.audioFiles, id: \.self) { fileURL in
                                HStack {
                                    Image(systemName: fileURL.pathExtension.lowercased() == "wav" ? "w.square.fill" : "m.square.fill")
                                        .foregroundColor(.gray.opacity(0.7))
                                    
                                    Text(fileURL.lastPathComponent)
                                        .font(.callout)
                                        .lineLimit(1)
                                    
                                    Spacer()

                                }
                                .frame(height: 30)
                                .font(.subheadline)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 18)
                                        .foregroundColor(Color.white.opacity(0.2))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 18)
                                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                                        )
                                    )
                                .listRowBackground(Color.clear)                        
                                .onTapGesture {
                                    selectedFile = fileURL
                                }
                                .onLongPressGesture {
                                    presentRecordingDetailsModal(for: fileURL)
                                    showRecordingDetails.toggle()
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button(action: {
                                        deleteAudioFile(at: [audioFileViewModel.audioFiles.firstIndex(of: fileURL)!])
                                    }) {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .tint(.red)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(action: {
                                        fileToShare = fileURL
                                        showShareSheet = true
                                    }) {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }
                                    .tint(.blue)
                                }
                            }
                            .onDelete(perform: deleteAudioFile)
                            }
                            .onAppear(perform: audioFileViewModel.fetchAudioFiles)
                            .padding()
                        }
                                    

                    }
                
                    VStack{
                        Spacer()

                        ZStack{

                            ContentBlurView(direction: .bottomBlur) {
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(maxWidth: .infinity)
                            }  

                            VStack{
                            // Selected file name
                            if let selectedFile = selectedFile {
                                Text(selectedFile.lastPathComponent)
                                    .font(.headline)
                                    .padding(.bottom)

                                // Slider to show and change the current playback position
                                Slider(value: $audioPlayer.currentTime, in: 0...audioPlayer.duration, onEditingChanged: { _ in
                                    audioPlayer.updateCurrentTime(to: audioPlayer.currentTime)
                                })
                                .padding(.horizontal)
                                }
                        
                                Button(action: {
                                    if audioPlayer.isPlaying {
                                        audioPlayer.pausePlaying()
                                    } else {
                                        if let fileURL = selectedFile {
                                            audioPlayer.startPlaying(fileURL: fileURL)
                                        } else {
                                            print("No file selected")
                                        }
                                    }
                                }) {
                                    Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "arrowtriangle.right.circle.fill")
                                        .font(.system(size: 80))
                                        .foregroundColor(audioPlayer.isPlaying ? .red : .blue)
                                }
                                .padding(.bottom)

                            }
                            // .frame(width: UIScreen.main.bounds.width / 1.2)
                            // .padding(.horizontal, 10)
                            // .padding(.vertical, 10)
                            // .background(
                            //     RoundedRectangle(cornerRadius: 30)
                            //         .fill(LinearGradient(gradient: Gradient(colors: [Color(red: 0.141, green: 0.141, blue: 0.141), Color(red: 0.141, green: 0.141, blue: 0.141)]), startPoint: .bottom, endPoint: .top))
                            //         .shadow(radius: 10)
                            // )
                            // .overlay(
                            //     RoundedRectangle(cornerRadius: 30)
                            //         .stroke(Color.white.opacity(0.4), lineWidth: 1)
                            // )         

                        }
                        .edgesIgnoringSafeArea(.bottom)
                        .frame(maxWidth: .infinity, maxHeight: 250, alignment: .bottom)                         
                    }


                }        
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.black, Color(red: 0.141, green: 0.141, blue: 0.141)]),
                        startPoint: .top,
                        endPoint: .bottom
                    ).edgesIgnoringSafeArea(.all)
                    
                )
                .foregroundColor(.white)
                .font(.system(size: 16))
                .onReceive(NotificationCenter.default.publisher(for: .newRecordingAdded)) { _ in
                    audioFileViewModel.fetchAudioFiles()
                }
                .sheet(isPresented: $showShareSheet) {
                    if let fileURL = fileToShare {
                        NavigationView {
                            ShareSheet(items: [fileURL])
                        }
                    }
                }
                .sheet(isPresented: $showRecordingDetails) {
                    if let selectedFile = selectedFile {
                        RecordingDetailsView(fileURL: selectedFile, onDelete: {
                            deleteAudioFile(at: [audioFileViewModel.audioFiles.firstIndex(of: selectedFile)!])
                        }, onRename: {
                            audioFileViewModel.fetchAudioFiles()
                        })
                    }
                }                
            }        
        }


        
    }
    
    private func presentRecordingDetailsModal(for fileURL: URL) {
        selectedFile = fileURL
    }

    private func deleteAllFiles() {
        for fileURL in audioFileViewModel.audioFiles {
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                print("Error deleting audio file: \(error)")
            }
        }
        audioFileViewModel.fetchAudioFiles()
    }

    private func deleteAudioFile(at offsets: IndexSet) {
        for index in offsets {
            let fileURL = audioFileViewModel.audioFiles[index]

            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                print("Error deleting audio file: \(error)")
            }
        }
        audioFileViewModel.fetchAudioFiles()
    }
    
}
