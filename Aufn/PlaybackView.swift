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
    @State private var selectionMode = false
    @State private var selectedFiles: Set<URL> = []
    @State private var showRecordingDetails = false

    
    var body: some View {
        VStack {
            HStack {
                Text("Playback")
                    .font(.largeTitle)
                
                Spacer()
                
                Button(action: {
                    selectionMode.toggle()
                    selectedFiles.removeAll()
                }) {
                    Text(selectionMode ? "Cancel" : "Select")
                }
            }
            .padding()
            
            
            List(selection: selectionMode ? $selectedFiles : nil) {
                ForEach(audioFileViewModel.audioFiles, id: \.self) { fileURL in
                    HStack {
                        if selectionMode && selectedFiles.contains(fileURL) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        }
                        
                        Text(fileURL.lastPathComponent)
                            .font(.callout)
                            .lineLimit(1)
                        
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !selectionMode {
                            selectedFile = fileURL
                        } else {
                            selectedFiles.update(with: fileURL)
                        }
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
                .onAppear(perform: audioFileViewModel.fetchAudioFiles)
            }

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
                    }
                }
            }) {
                Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "arrowtriangle.right.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(audioPlayer.isPlaying ? .red : .blue)
            }
            .padding(.bottom)
            if selectionMode && !selectedFiles.isEmpty {
                Button(action: {
                    deleteSelectedFiles()
                    selectedFiles.removeAll()
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete")
                    }
                    .foregroundColor(.red)
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                    .padding(.bottom)
                }
            }
        }
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
    
    private func presentRecordingDetailsModal(for fileURL: URL) {
        selectedFile = fileURL
    }
    private func deleteSelectedFiles() {
        for fileURL in selectedFiles {
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
