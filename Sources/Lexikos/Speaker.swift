import AVFoundation
import NaturalLanguage

/// Text-to-speech played through a time-stretch unit, because system voices largely ignore
/// `AVSpeechUtterance.rate`: slowing the rendered audio is the only reliable "slow" mode.
final class Speaker {
    private let synth = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let stretch = AVAudioUnitTimePitch()
    private var format: AVAudioFormat?
    private var token = 0

    init() {
        engine.attach(player)
        engine.attach(stretch)
    }

    func say(_ text: String, language: String? = nil, slow: Bool = false) {
        guard !text.isEmpty else { return }
        stop()
        token += 1
        let mine = token
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: language ?? Self.language(of: text))
        u.rate = slow ? 0.42 : AVSpeechUtteranceDefaultSpeechRate
        stretch.rate = slow ? 0.5 : 1
        synth.write(u) { [weak self] buffer in
            guard let self, mine == self.token, let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0,
                  let floats = self.toFloat(pcm) else { return }
            self.connect(floats.format)
            self.player.scheduleBuffer(floats)
            if !self.player.isPlaying { self.player.play() }
        }
    }

    func stop() {
        token += 1
        synth.stopSpeaking(at: .immediate)
        player.stop()
    }

    static func language(of text: String) -> String {
        let r = NLLanguageRecognizer()
        r.processString(text)
        return r.dominantLanguage?.rawValue ?? "fr"
    }

    private func connect(_ f: AVAudioFormat) {
        if format != f {
            engine.stop()
            engine.connect(player, to: stretch, format: f)
            engine.connect(stretch, to: engine.mainMixerNode, format: f)
            format = f
        }
        if !engine.isRunning { try? engine.start() }
    }

    private func toFloat(_ b: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if b.format.commonFormat == .pcmFormatFloat32 { return b }
        guard let f = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: b.format.sampleRate,
                                    channels: b.format.channelCount, interleaved: false),
              let out = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: b.frameLength),
              let conv = AVAudioConverter(from: b.format, to: f) else { return nil }
        try? conv.convert(to: out, from: b)
        return out
    }
}
