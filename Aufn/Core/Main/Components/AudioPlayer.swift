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
    @Published var errorMessage: String?

    func startPlaying(fileURL: URL) {
        setupAudioPlayer(fileURL: fileURL)
        print("Playing file at URL: \(fileURL)")

        // Check and set audio output route
        let audioSession = AVAudioSession.sharedInstance()
        do {
            let currentRoute = audioSession.currentRoute
            if currentRoute.outputs.contains(where: { $0.portType == AVAudioSession.Port.builtInSpeaker }) {
                print("Audio is playing through the device's speakers")
            } else {
                print("Audio is not playing through the device's speakers, setting to speakers")
                try audioSession.overrideOutputAudioPort(.speaker)
            }
        } catch {
            print("Failed to set audio output route: \(error)")
        }
        do {
                audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
                audioPlayer?.delegate = self
                duration = audioPlayer?.duration ?? 0
                audioPlayer?.play()
                isPlaying = audioPlayer?.isPlaying ?? false
                
                if isPlaying {
                    print("Audio player is playing")
                } else {
                    print("Audio player failed to start playing")
                }
                
                timer?.invalidate()
                timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    self?.currentTime = self?.audioPlayer?.currentTime ?? 0
                }
            } catch {
                print("Error playing audio file: \(error)")
                errorMessage = "Error playing audio file: \(error.localizedDescription)"
                isPlaying = false
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
    
     private func setupAudioSession() {
         do {
             try AVAudioSession.sharedInstance().setCategory(.playback)
             try AVAudioSession.sharedInstance().setActive(true)
         } catch {
             print("Failed to set up audio session: \(error)")
         }
     }

    private func setupAudioPlayer(fileURL: URL) {
            setupAudioSession()
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
