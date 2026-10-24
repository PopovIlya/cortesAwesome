import AVFoundation
import CortesCore
import os
@preconcurrency import WhisperKit

/// Whisper on this Mac through WhisperKit: Russian and English, no servers, no quotas.
/// The model downloads once on first use into Application Support.
actor WhisperTranscriber {
    /// Multilingual "small": good Russian, fast enough on Apple Silicon. ~480 MB.
    static let defaultModel = "openai_whisper-small"

    let model: String
    private var kit: WhisperKit?
    private var loading: Task<WhisperKit, Error>?
    private let log = Logger(subsystem: "ai.cortes.parliament", category: "whisper")

    init(model: String = WhisperTranscriber.defaultModel) { self.model = model }

    static var modelsFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cortes/models")
    }

    /// Downloads (first time) and loads the model. Safe to call repeatedly.
    /// `progress` gets the download's completed fraction, 0…1; files already on disk are skipped.
    func load(progress: (@Sendable (Double) -> Void)? = nil) async throws -> WhisperKit {
        if let kit { return kit }
        if let loading { return try await loading.value }
        let model = model
        let task = Task {
            let folder = try await WhisperKit.download(variant: model, downloadBase: Self.modelsFolder) {
                progress?($0.fractionCompleted)
            }
            return try await WhisperKit(WhisperKitConfig(model: model, modelFolder: folder.path,
                                                         verbose: false, logLevel: .error, download: false))
        }
        loading = task
        defer { loading = nil }
        let start = Date()
        let kit = try await task.value
        log.info("whisper model \(model, privacy: .public) ready in \(Date().timeIntervalSince(start), format: .fixed(precision: 1)) s")
        self.kit = kit
        return kit
    }

    func transcribe(_ samples: [Float], language: AppLanguage) async throws -> String {
        let kit = try await load()
        let start = Date()
        let options = DecodingOptions(task: .transcribe, language: language.rawValue, temperature: 0,
                                      usePrefillPrompt: true, skipSpecialTokens: true, withoutTimestamps: true)
        let text = try await kit.transcribe(audioArray: samples, decodeOptions: options)
            .map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        log.info("transcribed \(Double(samples.count) / 16_000, format: .fixed(precision: 1)) s of audio in \(Date().timeIntervalSince(start), format: .fixed(precision: 1)) s, \(text.count) chars")
        return text
    }
}

/// Audio format plumbing: everything goes to Whisper as 16 kHz mono Float32.
enum AudioSamples {
    static let whisperFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                             channels: 1, interleaved: false)!

    /// Samples from a ScreenCaptureKit buffer, converted to 16 kHz mono when needed.
    static func floats(from sample: CMSampleBuffer) -> [Float] {
        guard let description = sample.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              let format = AVAudioFormat(streamDescription: [asbd]),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sample.numSamples))
        else { return [] }
        buffer.frameLength = buffer.frameCapacity
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(sample.numSamples),
                                                           into: buffer.mutableAudioBufferList) == noErr
        else { return [] }
        return floats(from: buffer)
    }

    /// Samples from any PCM buffer, resampled and mixed down to 16 kHz mono.
    static func floats(from buffer: AVAudioPCMBuffer) -> [Float] {
        let source = buffer.format
        if source.sampleRate == 16_000, source.channelCount == 1, source.commonFormat == .pcmFormatFloat32,
           let data = buffer.floatChannelData {
            return Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
        }
        guard let converter = AVAudioConverter(from: source, to: whisperFormat) else { return [] }
        let ratio = 16_000 / source.sampleRate
        guard let out = AVAudioPCMBuffer(pcmFormat: whisperFormat,
                                         frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32)
        else { return [] }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let data = out.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(out.frameLength)))
    }
}
