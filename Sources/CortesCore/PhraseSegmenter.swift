import Foundation

/// Cuts a stream of 16 kHz mono samples into phrases. A phrase ends after a pause long enough to mean
/// "your turn" (1.5 s by default). Loudness is compared with an adaptive noise floor, so it works for
/// both clean system audio and a noisy microphone.
public struct PhraseSegmenter: Sendable {
    public static let sampleRate = 16_000
    /// 20 ms frames.
    static let frame = 320

    public var pause: TimeInterval
    /// Shorter bursts are clicks and coughs, not speech.
    public var minSpeech: TimeInterval = 0.4
    /// Whisper reads 30 s at a time; a monologue is cut before that.
    public var maxPhrase: TimeInterval = 28

    public private(set) var isSpeaking = false

    private var noiseFloor: Float = 0.002
    private var pending: [Float] = []
    private var phrase: [Float] = []
    /// The last 300 ms before speech starts, so the first syllable is not clipped.
    private var preroll: [Float] = []
    private var speechSamples = 0
    private var silenceSamples = 0

    public init(pause: TimeInterval = 1.5) { self.pause = pause }

    /// Feeds samples, returns the phrases that ended within them.
    public mutating func feed(_ samples: [Float]) -> [[Float]] {
        pending += samples
        var finished: [[Float]] = []
        while pending.count >= Self.frame {
            let frame = Array(pending.prefix(Self.frame))
            pending.removeFirst(Self.frame)
            if let done = process(frame) { finished.append(done) }
        }
        return finished
    }

    private mutating func process(_ frame: [Float]) -> [Float]? {
        let rms = (frame.reduce(0) { $0 + $1 * $1 } / Float(frame.count)).squareRoot()
        let loud = rms > max(0.01, noiseFloor * 3)
        let rate = Double(Self.sampleRate)

        if loud {
            if !isSpeaking {
                isSpeaking = true
                phrase = preroll
            }
            phrase += frame
            speechSamples += frame.count
            silenceSamples = 0
        } else if isSpeaking {
            phrase += frame
            silenceSamples += frame.count
            if Double(silenceSamples) >= pause * rate { return close() }
        } else {
            noiseFloor = noiseFloor * 0.95 + rms * 0.05
            preroll = Array((preroll + frame).suffix(Self.frame * 15))
        }
        if isSpeaking, Double(phrase.count) >= maxPhrase * rate { return close() }
        return nil
    }

    private mutating func close() -> [Float]? {
        let enough = Double(speechSamples) >= minSpeech * Double(Self.sampleRate)
        // Keep half a second of the trailing silence, drop the rest.
        let keep = max(0, phrase.count - max(0, silenceSamples - Self.sampleRate / 2))
        let result = Array(phrase.prefix(keep))
        isSpeaking = false
        phrase = []
        preroll = []
        speechSamples = 0
        silenceSamples = 0
        return enough ? result : nil
    }
}
