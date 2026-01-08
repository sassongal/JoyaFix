import Cocoa

/// Simple sound manager for playing audio feedback
class SoundManager {
    static let shared = SoundManager()

    private init() {}

    /// Plays a sound file from the app bundle
    /// - Parameter filename: Name of the sound file (e.g., "success.wav")
    /// - Returns: True if sound was played successfully, false otherwise
    @discardableResult
    func playSound(_ filename: String) -> Bool {
        let nameWithoutExt = filename.replacingOccurrences(of: ".wav", with: "")
        
        // Priority 1: Try Bundle.main (final app bundle) - this is the primary method
        var soundURL: URL?
        soundURL = Bundle.main.url(forResource: nameWithoutExt, withExtension: "wav")
        
        // Priority 2: Try with the full filename as-is
        if soundURL == nil {
            soundURL = Bundle.main.url(forResource: filename, withExtension: nil)
        }
        
        guard let finalURL = soundURL else {
            print("⚠️ Sound file '\(filename)' not found")
            return false
        }
        
        return playSoundFile(at: finalURL)
    }

    /// Plays a sound file from a specific URL
    private func playSoundFile(at url: URL) -> Bool {
        guard let sound = NSSound(contentsOf: url, byReference: true) else {
            print("⚠️ Failed to load sound from: \(url.path)")
            return false
        }

        sound.play()
        return true
    }

    /// Plays the success sound (convenience method)
    func playSuccess() {
        playSound("success.wav")
    }

    /// Plays the system beep as fallback
    func playBeep() {
        NSSound.beep()
    }
}
