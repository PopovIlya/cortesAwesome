import Foundation

/// Language of the interface and of the inner voices.
public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case english = "en"
    case russian = "ru"

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .russian: return "Русский"
        }
    }

    /// Name the model understands when asked to write in this language.
    public var promptName: String {
        switch self {
        case .english: return "English"
        case .russian: return "Russian"
        }
    }
}

/// The members of the parliament. Skill names are our own, not from Disco Elysium.
/// The last two are wild voices: absurd, rare, never the sensible choice.
public enum Voice: String, CaseIterable, Codable, Sendable {
    case cautious, bold, accountant, diplomat, cynic, mystic, hedonist

    /// Wild voices speak rarely and only when it would be funny.
    public var isWild: Bool { self == .mystic || self == .hedonist }

    public func name(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.cautious, .english): return "The Cautious"
        case (.bold, .english): return "The Adventurer"
        case (.accountant, .english): return "The Accountant"
        case (.diplomat, .english): return "The Diplomat"
        case (.cynic, .english): return "The Cynic"
        case (.cautious, .russian): return "Осторожный"
        case (.bold, .russian): return "Авантюрист"
        case (.accountant, .russian): return "Бухгалтер"
        case (.diplomat, .russian): return "Дипломат"
        case (.cynic, .russian): return "Циник"
        case (.mystic, .english): return "The Mystic"
        case (.hedonist, .english): return "The Hedonist"
        case (.mystic, .russian): return "Мистик"
        case (.hedonist, .russian): return "Гедонист"
        }
    }

    public func tagline(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.cautious, .english): return "a paranoid in a tinfoil hat"
        case (.bold, .english): return "sure he is the main character"
        case (.accountant, .english): return "sees the world in Excel"
        case (.diplomat, .english): return "would hug a cactus"
        case (.cynic, .english): return "has seen too many sprints"
        case (.cautious, .russian): return "параноик в шапочке из фольги"
        case (.bold, .russian): return "уверен, что он главный герой"
        case (.accountant, .russian): return "видит мир в Excel"
        case (.diplomat, .russian): return "обнимет даже кактус"
        case (.cynic, .russian): return "видел слишком много спринтов"
        case (.mystic, .english): return "takes advice from the stapler"
        case (.hedonist, .english): return "lives from coffee to Friday"
        case (.mystic, .russian): return "советуется со степлером"
        case (.hedonist, .russian): return "живёт от кофе до пятницы"
        }
    }

    /// The face on the voice's sticker.
    public var sticker: String {
        switch self {
        case .cautious: return "🫣"
        case .bold: return "🦸"
        case .accountant: return "🧮"
        case .diplomat: return "🤗"
        case .cynic: return "🥱"
        case .mystic: return "🔮"
        case .hedonist: return "🍕"
        }
    }

    /// The skill rolled in the check shown at the top of the card.
    public func skill(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.cautious, .english): return "Anxiety"
        case (.bold, .english): return "Audacity"
        case (.accountant, .english): return "Arithmetic"
        case (.diplomat, .english): return "Empathy"
        case (.cynic, .english): return "Weariness"
        case (.cautious, .russian): return "Тревожность"
        case (.bold, .russian): return "Наглость"
        case (.accountant, .russian): return "Счёт"
        case (.diplomat, .russian): return "Эмпатия"
        case (.cynic, .russian): return "Усталость"
        case (.mystic, .english): return "Premonition"
        case (.hedonist, .english): return "Appetite"
        case (.mystic, .russian): return "Предчувствие"
        case (.hedonist, .russian): return "Аппетит"
        }
    }
}

/// Lets `[Voice: Int]` encode as a JSON object keyed by the voice id.
extension Voice: CodingKeyRepresentable {}

/// Difficulty of the skill check, as the model picks it.
public enum Difficulty: String, CaseIterable, Codable, Sendable {
    case trivial, easy, medium, challenging, heroic, hopeless

    public func label(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.trivial, .english): return "Trivial"
        case (.easy, .english): return "Easy"
        case (.medium, .english): return "Medium"
        case (.challenging, .english): return "Challenging"
        case (.heroic, .english): return "Heroic"
        case (.hopeless, .english): return "Hopeless"
        case (.trivial, .russian): return "Тривиально"
        case (.easy, .russian): return "Легко"
        case (.medium, .russian): return "Средне"
        case (.challenging, .russian): return "Сложно"
        case (.heroic, .russian): return "Героически"
        case (.hopeless, .russian): return "Безнадёжно"
        }
    }
}

/// Interface strings.
public struct UIStrings: Sendable {
    public let lang: AppLanguage

    public init(_ lang: AppLanguage) { self.lang = lang }

    private func t(_ en: String, _ ru: String) -> String { lang == .english ? en : ru }

    public var appTitle: String { t("Parliament in your head", "Парламент в голове") }
    public var success: String { t("Success", "Успех") }
    public var failedReplyWarning: String {
        t("Failed check: this reply is a mistake. Funny to read, risky to send.",
          "Проверка провалена: эта реплика — ошибка. Смешно читать, рискованно отправлять.")
    }
    public var failure: String { t("Failure", "Провал") }
    public var thinking: String { t("The parliament is in session…", "Парламент заседает…") }
    public var chosen: String { t("Your pick", "Твой выбор") }
    public var copied: String { t("Copied · click another card to change, the same one to undo", "Скопировано · другая карточка — сменить, та же — отменить") }
    public var pasted: String { t("In the chat box, press Enter to send · another card replaces it, the same one removes it", "В поле чата, отправь Enter · другая карточка заменит, та же — уберёт") }
    public var clickToCopy: String { t("Click a card to pick it · ▶ to listen", "Клик по карточке — выбрать · ▶ — прослушать") }
    public var demoMode: String {
        t("Demo mode: no GEMINI_API_KEY, showing canned voices",
          "Демо-режим: нет GEMINI_API_KEY, показываю заготовленные голоса")
    }
    public var noSelection: String {
        t("Nothing selected. Select a message, or turn on ⚙ Settings → Chats → “Read the last messages” to answer the open chat without selecting.",
          "Ничего не выделено. Выдели сообщение или включи ⚙ Настройки → «Чаты» → «Читать последние сообщения», чтобы отвечать на открытый чат без выделения.")
    }
    public var accessibilityNeeded: String {
        t("Allow Cortes in System Settings → Privacy & Security → Accessibility so it can copy the selection.",
          "Разреши Cortes в Системных настройках → Конфиденциальность и безопасность → Универсальный доступ, чтобы копировать выделенное.")
    }
    public var language: String { t("Language", "Язык") }
    public var askAbout: String { t("Ask the parliament about the clipboard", "Спросить парламент про буфер обмена") }
    public var showPanel: String { t("Show panel", "Показать панель") }
    public var quit: String { t("Quit Cortes", "Выйти из Cortes") }
    public var hotkeyHint: String { t("Hotkey: ⌃⌥Space on selected text", "Хоткей: ⌃⌥Пробел на выделенном тексте") }
    public var errorPrefix: String { t("The parliament is silent", "Парламент молчит") }
    public var whisper: String { t("Whisper in headphones", "Шёпот в наушники") }
    public var servedLocally: String {
        t("The cloud is unavailable, local Gemma answered", "Облако недоступно, ответила локальная Gemma")
    }
    public var stats: String { t("Who wins", "Кто побеждает") }
    public var todayRules: String { t("Rules today", "Сегодня правит") }
    public var todayRuleTogether: String { t("Rule today together", "Сегодня правят вместе") }
    /// "A and B", "A, B and C".
    public func and(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + t(" and ", " и ") + names.last!
    }
    public var today: String { t("Today", "Сегодня") }
    public var allTime: String { t("All time", "За всё время") }
    public var recentDays: String { t("Recent days", "Последние дни") }
    public var noPicksYet: String { t("No picks yet. Pick a card to give a voice the win.", "Пока никого не выбирали. Выбери карточку, и голос получит победу.") }
    public func picks(_ n: Int) -> String {
        if lang == .english { return n == 1 ? "1 pick" : "\(n) picks" }
        let mod10 = n % 10, mod100 = n % 100
        let word = mod10 == 1 && mod100 != 11 ? "выбор" : (2...4).contains(mod10) && !(12...14).contains(mod100) ? "выбора" : "выборов"
        return "\(n) \(word)"
    }
    public var replayWhisper: String { t("Listen without picking", "Прослушать, не выбирая") }
    public var listen: String { t("Listen to the call", "Слушать созвон") }
    public var stopListening: String { t("Stop listening", "Перестать слушать") }
    /// Label for a call line: "ME", "THEM" or "SPEAKER".
    public func speakerLabel(_ speaker: String) -> String {
        switch speaker {
        case "THEM": return t("Them", "Собеседник")
        default: return t("Heard", "Слышу")
        }
    }
    public var settings: String { t("Settings", "Настройки") }
    public var settingsModel: String { t("Who answers", "Кто отвечает") }
    public var backendAuto: String { t("Auto", "Авто") }
    public var backendCloud: String { t("Cloud", "Облако") }
    public var backendLocal: String { t("This Mac", "Этот Mac") }
    public var geminiKey: String { t("Gemini API key (cloud Gemma 4 26B)", "Ключ Gemini API (облачная Gemma 4 26B)") }
    public var localModel: String { t("Local Gemma 4 E4B in Ollama", "Локальная Gemma 4 E4B в Ollama") }
    public var settingsChat: String { t("Chats", "Чаты") }
    public var pasteIntoChat: String {
        t("Paste the picked reply into the chat (you press Enter)", "Вставлять выбранный ответ в чат (Enter жмёшь ты)")
    }
    public var readChatHistory: String {
        t("Read the last messages of the chat window", "Читать последние сообщения окна чата")
    }
    public var chatHistoryCount: String { t("Messages to read", "Сколько сообщений читать") }
    public var readChatHistoryHint: String {
        t("On ⌃⌥Space Cortes reads the open chat (Slack, Telegram, Messages) through Accessibility and sends that text to the model. Select a message to answer it, or select nothing to answer the last one.",
          "По ⌃⌥Пробел Cortes читает открытый чат (Slack, Telegram, Сообщения) через Универсальный доступ и отправляет этот текст модели. Выдели сообщение, чтобы ответить на него, или ничего не выделяй, чтобы ответить на последнее.")
    }
    public var settingsCall: String { t("Calls", "Созвон") }
    public var phrasePause: String { t("Pause that ends their phrase", "Пауза, после которой фраза закончена") }
    public var callCooldown: String { t("Answer at most every", "Отвечать не чаще чем раз в") }
    public var seconds: String { t("s", "с") }
    public var speechModel: String { t("Speech recognition", "Распознавание речи") }
    public var whisperBase: String { t("Whisper base: faster, weaker Russian", "Whisper base: быстрее, русский хуже") }
    public var whisperSmall: String { t("Whisper small: better Russian", "Whisper small: русский лучше") }
    public var settingsWhisper: String { t("Whisper", "Шёпот") }
    public var autoWhisperOnCalls: String {
        t("On calls, today's leader whispers by itself", "На созвоне лидер дня шепчет сам")
    }
    public var elevenLabsKey: String { t("ElevenLabs key (whispering voices)", "Ключ ElevenLabs (шёпот голосами)") }
    public var keysHint: String {
        t("Keys live in the .env file next to the app; restart Cortes after changing them.",
          "Ключи хранятся в файле .env рядом с приложением; после изменения перезапусти Cortes.")
    }
    public var whisperLoading: String { t("Loading the speech model…", "Загружаю модель распознавания…") }
    public func whisperDownloading(_ percent: Int) -> String {
        t("Downloading the speech model, once: \(percent)%", "Скачиваю модель распознавания, один раз: \(percent)%")
    }
    public var whisperFailed: String { t("Speech model failed:", "Модель распознавания не загрузилась:") }
    public var otherSideSpeaking: String { t("Listening to the phrase…", "Слушаю фразу…") }
    public var transcribing: String { t("Recognising…", "Распознаю…") }
    public func nextAnswerIn(_ seconds: Int) -> String {
        t("The parliament answers in \(seconds) s", "Парламент ответит через \(seconds) с")
    }
    public var micOnly: String {
        t("No system audio, so the mic is listening and hears you too. Allow Cortes in Settings → Privacy & Security → Screen & System Audio Recording, then restart Cortes.",
          "Нет системного звука: слушаю микрофон, а он слышит и тебя. Разреши Cortes в Настройках → Конфиденциальность и безопасность → Запись экрана и системного звука, затем перезапусти Cortes.")
    }
    public var listeningHint: String {
        t("Listening… Speak, and the parliament answers after a pause.", "Слушаю… Говорите, парламент ответит после паузы.")
    }
    public var microphoneNeeded: String {
        t("Allow Cortes to use the microphone in System Settings → Privacy & Security → Microphone.",
          "Разреши Cortes микрофон в Системных настройках → Конфиденциальность и безопасность → Микрофон.")
    }
    public var listeningUnavailable: String {
        t("Speech recognition is not available for this language right now.",
          "Распознавание речи для этого языка сейчас недоступно.")
    }
    public var whisperFallback: String {
        t("ElevenLabs unavailable, the macOS voice is speaking", "ElevenLabs недоступен, говорит голос macOS")
    }
}
