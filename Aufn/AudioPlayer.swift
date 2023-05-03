//
//  AudioPlayer.swift
//  Recordit
//
//  Created by Steven Sarmiento on 4/25/23.
//

import Foundation
import AVFoundation

class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var audioPlayer: AVAudioPlayer?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    private var timer: Timer?

    func startPlaying(fileURL: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
            audioPlayer?.delegate = self
            duration = audioPlayer?.duration ?? 0
            audioPlayer?.play()
            isPlaying = true
            
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.currentTime = self?.audioPlayer?.currentTime ?? 0
            }
        } catch {
            print("Error playing audio file: \(error)")
        }
    }

    func pausePlaying() {
        audioPlayer?.pause()
        isPlaying = false
        timer?.invalidate()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        currentTime = 0
    }

    func updateCurrentTime(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        if !isPlaying {
            isPlaying = true
            audioPlayer?.play()

            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.currentTime = self?.audioPlayer?.currentTime ?? 0
            }
        }
    }
    
    private func setupAudioPlayer(fileURL: URL) {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
                audioPlayer?.delegate = self
                audioPlayer?.prepareToPlay()
            } catch {
                print("Failed to set up audio player: \(error)")
            }
        } else {
            print("Audio file not found at path: \(fileURL.path)")
        }
    }
}
