//
//  AudioFileViewModal.swift
//  Recordit
//
//  Created by Steven Sarmiento on 4/26/23.
//

import Foundation
import Combine

class AudioFileViewModel: ObservableObject {
    @Published var audioFiles: [URL] = []

    private let fileManager = FileManager.default
    private let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    init() {
        fetchAudioFiles()
        NotificationCenter.default.addObserver(self, selector: #selector(fetchAudioFiles), name: .newRecordingAdded, object: nil)
    }

    @objc func fetchAudioFiles() {
        do {
            let contents = try fileManager.contentsOfDirectory(at: documentPath, includingPropertiesForKeys: nil, options: [])
            let audioFiles = contents.filter { $0.pathExtension.lowercased().hasPrefix("m4a") || $0.pathExtension.lowercased().hasPrefix("mp3") || $0.pathExtension.lowercased().hasPrefix("wav") || $0.pathExtension.lowercased().hasPrefix("caf")}
            self.audioFiles = audioFiles.sorted { $0.lastPathComponent > $1.lastPathComponent }
        } catch {
            print("Error fetching audio files: \(error)")
        }
    }
}

