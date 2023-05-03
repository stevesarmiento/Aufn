//
//  RecordingDetailsView.swift
//  Recordit
//
//  Created by Steven Sarmiento on 4/27/23.
//

//
//  RecordingDetailsView.swift
//  Recordit
//
//  Created by Steven Sarmiento on 4/27/23.
//

import Foundation
import SwiftUI
import AVFoundation

struct RecordingDetailsView: View {
    let fileURL: URL
    let onDelete: () -> Void
    let onRename: () -> Void

    @State private var showDeleteConfirmation = false
    @State private var newName: String = ""
    @State private var isEditing = false
    @Environment(\.presentationMode) private var presentationMode

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var audioFile: AVAudioFile? {
        do {
            return try AVAudioFile(forReading: fileURL)
        } catch {
            print("Error reading audio file: \(error)")
            return nil
        }
    }
    
    private var fileSize: String {
        let resources = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = resources?.fileSize {
            let bcf = ByteCountFormatter()
            bcf.allowedUnits = [.useBytes, .useKB, .useMB]
            bcf.countStyle = .file
            return bcf.string(fromByteCount: Int64(fileSize))
        } else {
            return "Unknown size"
        }
    }
    
    private var creationDate: String {
        let resources = try? fileURL.resourceValues(forKeys: [.creationDateKey])
        if let creationDate = resources?.creationDate {
            return dateFormatter.string(from: creationDate)
        } else {
            return "Unknown date"
        }
    }
    
    private var fileFormat: String {
        return fileURL.pathExtension.uppercased()
    }
    
    private var sampleRate: String {
        if let audioFile = audioFile {
            return String(format: "%.0f Hz", audioFile.fileFormat.sampleRate)
        } else {
            return "Unknown"
        }
    }
    
    private var bitDepth: String {
        if let audioFile = audioFile {
            return "\(audioFile.fileFormat.streamDescription.pointee.mBitsPerChannel)-bit"
        } else {
            return "Unknown"
        }
    }

    
    private var numberOfChannels: String {
        if let audioFile = audioFile {
            return "\(audioFile.fileFormat.channelCount) channels"
        } else {
            return "Unknown"
        }
    }

    var body: some View {
            VStack {
                Text("Recording Details")
                    .font(.title2)
                    .padding()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("File Name:")
                        if isEditing {
                            TextField("New name", text: $newName, onCommit: {
                                renameFile()
                            })
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        } else {
                            Text(fileURL.lastPathComponent)
                        }
                    }
                    Text("File Size: \(fileSize)")
                    Text("File Format: \(fileFormat)")
                    Text("Sample Rate: \(sampleRate)")
                    Text("Bit Depth: \(bitDepth)")
                    Text("Channels: \(numberOfChannels)")
                    Text("Creation Date: \(creationDate)")
                }
                .padding()

                Button(action: {
                    if isEditing {
                        renameFile()
                    } else {
                        newName = fileURL.lastPathComponent
                    }
                    isEditing.toggle()
                }) {
                    Label(isEditing ? "Save" : "Rename", systemImage: "pencil")
                }
                .padding()

                Button(action: {
                    showDeleteConfirmation.toggle()
                }) {
                    Label("Delete", systemImage: "trash")
                        .foregroundColor(.red)
                }
                .alert(isPresented: $showDeleteConfirmation) {
                    Alert(
                        title: Text("Delete Recording"),
                        message: Text("Are you sure you want to delete this recording?"),
                        primaryButton: .destructive(Text("Delete"), action: {
                            presentationMode.wrappedValue.dismiss()
                            onDelete()
                        }),
                        secondaryButton: .cancel()
                    )
                }
                .padding()

                Spacer()
            }
            .padding()
        }

        private func renameFile() {
            if newName.isEmpty || newName == fileURL.lastPathComponent {
                isEditing = false
                return
            }

            let newFileURL = fileURL.deletingLastPathComponent().appendingPathComponent(newName)

            do {
                try FileManager.default.moveItem(at: fileURL, to: newFileURL)
                onRename()
                presentationMode.wrappedValue.dismiss()
            } catch {
                print("Error renaming file: \(error)")
            }
        }
    }
