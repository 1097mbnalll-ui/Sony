// SPDX-License-Identifier: AGPL-3.0-only
import AVFoundation

/// Reads Arabic translations aloud (on device).
final class ArabicSpeech {
    private let synth = AVSpeechSynthesizer()

    func speak(_ text: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "ar-SA") ?? AVSpeechSynthesisVoice(language: "ar")
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }
}
