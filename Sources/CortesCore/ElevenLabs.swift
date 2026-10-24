import Foundation

public enum ElevenLabsError: LocalizedError {
    case http(Int, String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .http(401, _): return "ElevenLabs rejected the key (401)."
        case .http(let code, let body): return "ElevenLabs error \(code): \(body.prefix(200))"
        case .network(let detail): return "No connection to ElevenLabs: \(detail)"
        }
    }
}

/// Whispers each voice's inner line through the ElevenLabs text-to-speech API, every voice with its own timbre.
public struct ElevenLabsClient: Sendable {
    public let apiKey: String
    public let voiceIDs: [Voice: String]
    public let model: String
    public let session: URLSession

    /// Premade voices available on every account. Override with ELEVENLABS_VOICE_<ID>, e.g. ELEVENLABS_VOICE_CYNIC.
    public static let defaultVoiceIDs: [Voice: String] = [
        .cautious: "N2lVS1w4EtoT3dr4eOWO",   // Callum: hoarse, intense
        .bold: "TX3LPaxmHKxFdv7VOQHJ",       // Liam: energetic
        .accountant: "onwK4e9ZLuTAKqWW03F9", // Daniel: steady newsreader
        .diplomat: "pFZP5JQG7iQjIQuC4Bku",   // Lily: warm
        .cynic: "CwhRBWXzGAHq8TQ4Fs17",      // Roger: laid-back, tired
        .mystic: "XB0fDUnXU5powFXDhCwa",     // Charlotte: mysterious
        .hedonist: "IKne3meq5aSn9XLyUdCD",   // Charlie: easy-going
    ]
    /// The v3 model understands the [whispers] audio tag. eleven_flash_v2_5 is ~5x faster but cannot whisper.
    public static let defaultModel = "eleven_v3"

    public init(apiKey: String, voiceIDs: [Voice: String] = ElevenLabsClient.defaultVoiceIDs,
                model: String = ElevenLabsClient.defaultModel, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.voiceIDs = ElevenLabsClient.defaultVoiceIDs.merging(voiceIDs) { _, custom in custom }
        self.model = model
        self.session = session
    }

    public init(env: Env) {
        var ids: [Voice: String] = [:]
        for voice in Voice.allCases {
            if let id = env["ELEVENLABS_VOICE_\(voice.rawValue.uppercased())"] { ids[voice] = id }
        }
        self.init(apiKey: env["ELEVENLABS_API_KEY"] ?? "", voiceIDs: ids,
                  model: env["ELEVENLABS_MODEL"] ?? ElevenLabsClient.defaultModel)
    }

    var canWhisper: Bool { model.contains("v3") }

    public func request(for text: String, voice: Voice, language: AppLanguage) throws -> URLRequest {
        var request = URLRequest(url: URL(string:
            "https://api.elevenlabs.io/v1/text-to-speech/\(voiceIDs[voice]!)?output_format=mp3_44100_128")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        let body: [String: Any] = [
            "text": canWhisper ? "[whispers] " + text : text,
            "model_id": model,
            "language_code": language.rawValue,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Returns MP3 audio.
    public func speech(for text: String, voice: Voice, language: AppLanguage) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request(for: text, voice: voice, language: language))
        } catch {
            throw ElevenLabsError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw ElevenLabsError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}
