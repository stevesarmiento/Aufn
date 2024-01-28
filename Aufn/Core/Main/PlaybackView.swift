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
            VStack{
                playbackHeader
                
                ZStack {

                    audioList
                
                    //playbackControls


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

extension PlaybackView {
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

    private var playbackHeader: some View {
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
    }

    private var audioList: some View {
        VStack {
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
                                // ForEach(audioFileViewModel.audioFiles, id: \.self) { fileURL in
                                //     VStack{
                                //         HStack {
                                //             Image(systemName: fileURL.pathExtension.lowercased() == "wav" ? "w.square.fill" : "m.square.fill")
                                //                 .foregroundColor(.gray.opacity(0.7))
                                            
                                //             Text(fileURL.lastPathComponent)
                                //                 .font(.callout)
                                //                 .lineLimit(1)
                                            
                                //             Spacer()

                                //         }
                                //         .font(.subheadline)
                                //         .padding()
                                //         if selectedFile == fileURL {
                                //             VStack{
                                //                 onlyPlaybackControls
                                //             }
                                //         }                                    
                                //     }
                                //     .padding(8)
                                //     .background(
                                //             RoundedRectangle(cornerRadius: 18)
                                //                 .foregroundColor(fileURL == selectedFile ? Color.white.opacity(0.2): Color.white.opacity(0.1))
                                //                 .overlay(
                                //                     RoundedRectangle(cornerRadius: 18)
                                //                         .stroke(fileURL == selectedFile ? Color.white.opacity(0.2): Color.white.opacity(0.1), lineWidth: 1)
                                //                 )
                                //             )                        
                                //         .onTapGesture {
                                //             if selectedFile == fileURL {
                                //                 selectedFile = nil
                                //             } else {
                                //                 selectedFile = fileURL
                                //             }
                                //         }
                                //         .onLongPressGesture {
                                //             presentRecordingDetailsModal(for: fileURL)
                                //             showRecordingDetails.toggle()
                                //         }
                                //         .transition(.move(edge: .bottom).combined(with: .opacity))
                                //         .animation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0), value: selectedFile)
                                // }
                                ForEach(audioFileViewModel.audioFiles, id: \.self) { fileURL in
                                    let isSelected = (fileURL == selectedFile)
                                    
                                    let fileRow = HStack {
                                        Image(systemName: fileURL.pathExtension.lowercased() == "wav" ? "w.square.fill" : "m.square.fill")
                                            .foregroundColor(.gray.opacity(0.7))
                                        
                                        Text(fileURL.lastPathComponent)
                                            .font(.callout)
                                            .lineLimit(1)
                                        
                                        Spacer()
                                    }
                                    .padding(8)
                                    VStack {
                                        fileRow
                                        if isSelected {
                                            onlyPlaybackControls(for: fileURL)
                                                .transition(.move(edge: .top).combined(with: .opacity))

                                        }
                                    }
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 20)
                                            .foregroundColor(isSelected ? Color.white.opacity(0.2): Color.white.opacity(0.1))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 20)
                                                    .stroke(isSelected ? Color.white.opacity(0.2): Color.white.opacity(0.1), lineWidth: 1)
                                            )
                                    )
                                    .onTapGesture {
                                        // withAnimation {
                                            if isSelected {
                                                selectedFile = nil
                                            } else {
                                                selectedFile = fileURL
                                            }
                                       // }
                                    }
                                    .onLongPressGesture {
                                        presentRecordingDetailsModal(for: fileURL)
                                        showRecordingDetails.toggle()
                                    }
                                    .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0), value: selectedFile)

                                }
                            }
                            .onAppear(perform: audioFileViewModel.fetchAudioFiles)
                        }.padding(.horizontal)
                    }            
                }
            }

    // private var playbackControls: some View {
    //                 VStack{
    //                     Spacer()

    //                     ZStack{

    //                         ContentBlurView(direction: .bottomBlur) {
    //                             Rectangle()
    //                                 .fill(Color.clear)
    //                                 .frame(maxWidth: .infinity)
    //                         }  

    //                         VStack{
    //                             // Selected file name
    //                             if let selectedFile = selectedFile {
    //                                 Text(selectedFile.lastPathComponent)
    //                                     .font(.headline)
    //                                     .padding(.bottom)

    //                                 Slider(value: $audioPlayer.currentTime, in: 0...audioPlayer.duration, onEditingChanged: { _ in
    //                                     audioPlayer.updateCurrentTime(to: audioPlayer.currentTime)
    //                                 })
    //                                 .padding(.horizontal)
    //                                 // WaveformSliderView(audioFile: $audioPlayer.audioFile, currentTime: $audioPlayer.currentTime)
    //                                 //     .padding(.horizontal)
    //                             }
                        
    //                             Button(action: {
    //                                 if audioPlayer.isPlaying {
    //                                     audioPlayer.pausePlaying()
    //                                 } else {
    //                                     if let fileURL = selectedFile {
    //                                         audioPlayer.startPlaying(fileURL: fileURL)
    //                                     } else {
    //                                         print("No file selected")
    //                                     }
    //                                 }
    //                             }) {
    //                                 Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "arrowtriangle.right.circle.fill")
    //                                     .font(.system(size: 80))
    //                                     .foregroundColor(audioPlayer.isPlaying ? .red : .blue)
    //                             }

    //                         }
    //                         .frame(width: UIScreen.main.bounds.width / 1.5) 
    //                         .padding(.horizontal, 20)
    //                         .padding(.vertical, 20)
    //                         .background(
    //                             RoundedRectangle(cornerRadius: 40)
    //                                 .fill(LinearGradient(gradient: Gradient(colors: [Color(red: 0.141, green: 0.141, blue: 0.141), Color(red: 0.141, green: 0.141, blue: 0.141)]), startPoint: .bottom, endPoint: .top))
    //                                 .shadow(radius: 10)
    //                         )
    //                         .overlay(
    //                             RoundedRectangle(cornerRadius: 40)
    //                                 .stroke(Color.white.opacity(0.1), lineWidth: 1)
    //                         )
    //                         .transition(.move(edge: .bottom).combined(with: .opacity))
    //                         .animation(.spring(response: 0.2, dampingFraction: 0.6, blendDuration: 0), value: selectedFile)
    //                     }
    //                     .edgesIgnoringSafeArea(.bottom)
    //                     .frame(maxWidth: .infinity, maxHeight: 250, alignment: .bottom)

    //                 }
  
    // }

        private func onlyPlaybackControls(for fileURL: URL) -> some View {
                        HStack{
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
                                        .font(.system(size: 40))
                                        .foregroundColor(audioPlayer.isPlaying ? .red : .blue)
                                }    

                                Slider(value: $audioPlayer.currentTime, in: 0...audioPlayer.duration, onEditingChanged: { _ in
                                    audioPlayer.updateCurrentTime(to: audioPlayer.currentTime)
                                })
                                .padding(.horizontal)
                                // WaveformSliderView(audioFile: $audioPlayer.audioFile, currentTime: $audioPlayer.currentTime)
                                //     .padding(.horizontal)  

                                Button(action: {
                                   deleteAudioFile(at: [audioFileViewModel.audioFiles.firstIndex(of: fileURL)!])
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 20))
                                        .foregroundColor(Color.red)
                                }             
                                Button(action: {
                                        fileToShare = fileURL
                                        showShareSheet = true 
                                        }) {
                                    Image(systemName: "circle")
                                        .font(.system(size: 20))
                                        .foregroundColor(Color.blue)
                                }  


                            }
    }

}
