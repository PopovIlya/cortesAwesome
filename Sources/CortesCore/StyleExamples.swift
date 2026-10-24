import Foundation

/// Lines that set the tone of each voice: inner monologue, second person, pathos and drama.
/// They live in Resources/voices.json, so the voices can be tuned without touching code.
public enum StyleExamples {
    public struct Example: Sendable {
        public let difficulty: Difficulty
        public let lines: [String]
    }

    /// The difficulty a voice's own lines usually roll, for demo mode.
    static let typicalDifficulty: [Voice: Difficulty] = [
        .cautious: .trivial, .bold: .heroic, .accountant: .medium, .diplomat: .easy, .cynic: .hopeless,
        .mystic: .challenging, .hedonist: .trivial,
    ]

    public static func examples(_ voice: Voice, _ lang: AppLanguage) -> Example {
        Example(difficulty: typicalDifficulty[voice]!, lines: StyleCorpus.shared.lines(voice, lang))
    }

    /// One complete answer, so the model sees inner monologue and sendable replies side by side.
    public static func workedExample(_ lang: AppLanguage) -> String {
        switch lang {
        case .russian:
            return """
            {"situation": "Тебя зовут на вечерний звонок. Опять."}
            {"id": "cautious", "difficulty": "easy", "passed": true, "inner": "«Ненадолго». Ты знаешь это слово. Звонки в 19:00 не заканчиваются. Из них просто не возвращаются.", "reply": "А о чём звонок? Хочу подготовиться."}
            {"id": "cynic", "difficulty": "trivial", "passed": true, "inner": "«Это ненадолго» — самая длинная фраза в бизнесе. Попрощайся с вечером.", "reply": "Что случилось? Можно в двух словах тут?"}
            {"id": "hedonist", "difficulty": "easy", "passed": false, "inner": "Скажи, что у тебя в семь ужин. Ужина у тебя нет. Но он появится. Закажи прямо сейчас, это стратегия.", "reply": "Не могу, у меня ужин. Очень важный. С пиццей."}
            """
        case .english:
            return """
            {"situation": "An evening call. Again."}
            {"id": "cautious", "difficulty": "easy", "passed": true, "inner": "\\"Won't take long.\\" You know those words. Nobody comes back from a 7 pm call. Nobody.", "reply": "What's it about? Want to come prepared."}
            {"id": "cynic", "difficulty": "trivial", "passed": true, "inner": "\\"Won't take long\\" is the longest sentence in business. Say goodbye to your evening.", "reply": "What happened? Can you give me the short version here?"}
            {"id": "hedonist", "difficulty": "easy", "passed": false, "inner": "Say you have dinner at seven. You don't. But you will. Order it right now. That's strategy.", "reply": "Can't, I have dinner. A very important one. With pizza."}
            """
        }
    }

}

/// The voice corpus: each voice's signature moves and its lines in both languages.
public final class StyleCorpus: Sendable {
    public static let shared = StyleCorpus()

    struct File: Decodable {
        let moves: [String: [String]]
        let lines: [String: [String: [String]]]
    }

    private let file: File

    init() {
        let url = Self.resources.url(forResource: "voices", withExtension: "json")!
        file = try! JSONDecoder().decode(File.self, from: Data(contentsOf: url))
    }

    /// Inside Cortes.app the resource bundle sits in Contents/Resources; in tests and `swift run`, SwiftPM finds it.
    static let resources: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Cortes_CortesCore.bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return Bundle.module
    }()

    public func moves(_ voice: Voice) -> [String] { file.moves[voice.rawValue] ?? [] }

    public func lines(_ voice: Voice, _ language: AppLanguage) -> [String] {
        file.lines[language.rawValue]?[voice.rawValue] ?? []
    }

    public func allLines(_ language: AppLanguage) -> [String] {
        Voice.allCases.flatMap { lines($0, language) }
    }
}
