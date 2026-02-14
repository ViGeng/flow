//
//  SoundManager.swift
//  Flow
//
//  Manages audio feedback for user interactions.
//  Uses system sounds (NSSound) which are lightweight and native.
//

import AppKit

@MainActor
final class SoundManager {
    static let shared = SoundManager()
    
    // Cache sounds to prevent I/O lag
    private let clickSound: NSSound?
    private let successSound: NSSound?
    private let enterSound: NSSound?
    private let deleteSound: NSSound?
    
    private init() {
        // Preload sounds
        self.clickSound = NSSound(named: "Tink")
        self.successSound = NSSound(named: "Pop")
        self.enterSound = NSSound(named: "Morse")
        self.deleteSound = NSSound(named: "Basso")
    }
    
    /// Play a cached click sound (Bottle)
    func playClick() {
        if let sound = clickSound, !sound.isPlaying {
            sound.stop() // rewind if needed
            sound.play()
        } else {
            clickSound?.play()
        }
    }
    
    /// Play a cached success sound (Glass)
    func playSuccess() {
        if let sound = successSound, !sound.isPlaying {
            sound.stop()
            sound.play()
        } else {
            successSound?.play()
        }
    }
    
    /// Play a cached confirmation sound (Ping)
    func playEnter() {
        if let sound = enterSound, !sound.isPlaying {
            sound.stop()
            sound.play()
        } else {
            enterSound?.play()
        }
    }
    
    /// Play a cached delete sound (Basso)
    func playDelete() {
        if let sound = deleteSound, !sound.isPlaying {
            sound.stop()
            sound.play()
        } else {
            deleteSound?.play()
        }
    }
}
