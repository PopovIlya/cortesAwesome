import CortesCore
import SwiftUI

extension Voice {
    var color: Color {
        switch self {
        case .cautious: return Color(red: 0.55, green: 0.70, blue: 0.95)
        case .bold: return Color(red: 0.95, green: 0.45, blue: 0.30)
        case .accountant: return Color(red: 0.55, green: 0.85, blue: 0.55)
        case .diplomat: return Color(red: 0.90, green: 0.70, blue: 0.95)
        case .cynic: return Color(red: 0.85, green: 0.80, blue: 0.45)
        case .mystic: return Color(red: 0.40, green: 0.82, blue: 0.80)
        case .hedonist: return Color(red: 1.00, green: 0.48, blue: 0.66)
        }
    }
}

struct ParliamentView: View {
    @ObservedObject var state: AppState
    @ObservedObject var whisperer: Whisperer
    @ObservedObject var listener: Listener

    init(state: AppState) {
        self.state = state
        whisperer = state.whisperer
        listener = state.listener
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            // Everything between the header and the footer scrolls as one, so a tall stats screen never hides the top.
            ScrollView {
                VStack(alignment: .leading, spacing: 10) { scrollingContent }
                    .padding(.vertical, 6)
            }
            footer
        }
        .padding(14)
        .frame(width: 400)
        .frame(minHeight: 200, maxHeight: 760)
        .background(Color(red: 0.08, green: 0.08, blue: 0.09).opacity(0.96))
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.2), value: state.voices.count)
    }

    @ViewBuilder
    private var scrollingContent: some View {
        let leaders = state.todayLeaders
        if !leaders.isEmpty {
            Button { state.showStats.toggle() } label: {
                HStack(alignment: .center, spacing: 14) {
                    Sticker(voices: leaders, language: state.language)
                    VStack(alignment: .leading, spacing: 4) {
                        Text((leaders.count == 1 ? state.ui.todayRules : state.ui.todayRuleTogether).uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(.secondary)
                        if leaders.count == 1 {
                            Text(leaders[0].name(state.language))
                                .font(.system(size: 18, weight: .black, design: .serif))
                                .foregroundStyle(leaders[0].color)
                            Text(leaders[0].tagline(state.language))
                                .font(.system(size: 12, design: .serif).italic())
                                .foregroundStyle(.secondary)
                        } else {
                            // "Осторожный и Авантюрист", each name in its own color.
                            leaders.enumerated().reduce(Text("")) { text, item in
                                let separator = item.offset == 0 ? "" : item.offset == leaders.count - 1
                                    ? (state.language == .russian ? " и " : " and ") : ", "
                                return text + Text(separator).foregroundColor(.secondary)
                                    + Text(item.element.name(state.language)).foregroundColor(item.element.color)
                            }
                            .font(.system(size: 16, weight: .black, design: .serif))
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
            .help(state.ui.stats)
        }
        if state.showSettings { SettingsView(state: state) }
        if state.showStats { StatsView(state: state) }
        if state.isDemo {
            Text(state.ui.demoMode)
                .font(.caption)
                .foregroundStyle(.orange)
        }
        if listener.isListening { listening }
        content
    }

    private var header: some View {
        HStack(spacing: 10) {
            // A short title, so the five controls on the right always fit.
            Text("CORTES")
                .font(.system(size: 12, weight: .bold, design: .serif))
                .tracking(1.5)
                .foregroundStyle(.secondary)
                .help(state.ui.appTitle)
            Spacer()
            iconButton("chart.bar.fill", active: state.showStats, tint: .primary, help: state.ui.stats) {
                state.showStats.toggle()
                if state.showStats { state.showSettings = false }
            }
            iconButton("gearshape.fill", active: state.showSettings, tint: .primary, help: state.ui.settings) {
                state.showSettings.toggle()
                if state.showSettings { state.showStats = false }
            }
            iconButton(listener.isListening ? "mic.fill" : "mic",
                       active: listener.isListening, tint: .red,
                       help: listener.isListening ? state.ui.stopListening : state.ui.listen) {
                state.toggleListening()
            }
            iconButton(state.whisperEnabled ? "speaker.wave.2.fill" : "speaker.slash",
                       active: state.whisperEnabled, tint: .primary, help: state.ui.whisper) {
                state.whisperEnabled.toggle()
            }
            Picker("", selection: $state.language) {
                ForEach(AppLanguage.allCases, id: \.self) { lang in
                    Text(lang == .english ? "EN" : "RU").tag(lang)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 90)
            .labelsHidden()
            .help(state.ui.language)
            .onChange(of: state.language) { _, _ in state.rerunInCurrentLanguage() }
        }
    }

    private func iconButton(_ symbol: String, active: Bool, tint: Color, help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 18)
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? tint : .secondary)
        .help(help)
    }

    private var listening: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Circle().fill(.red).frame(width: 6, height: 6).padding(.top, 5)
                    .opacity(listener.hearsSpeech ? 1 : 0.5)
                if let last = state.heard.last {
                    (Text(state.ui.speakerLabel(last.speaker) + ": ").bold() + Text(last.text))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                } else {
                    Text(state.ui.listeningHint)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Group {
                switch listener.model {
                case .downloading(let fraction):
                    VStack(alignment: .leading, spacing: 3) {
                        Text(state.ui.whisperDownloading(Int(fraction * 100)))
                        ProgressView(value: fraction).controlSize(.small)
                    }
                case .loading: Text(state.ui.whisperLoading)
                case .failed(let error): Text(state.ui.whisperFailed + " " + error).foregroundStyle(.red)
                default:
                    if listener.hearsSpeech { Text(state.ui.otherSideSpeaking) }
                    else if listener.transcribing { Text(state.ui.transcribing) }
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            if let next = state.nextAnswerAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(state.ui.nextAnswerIn(max(1, Int(next.timeIntervalSince(context.date).rounded(.up)))))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            if !listener.hearsOtherSide {
                Text(state.ui.micOnly)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if case .error(let message) = state.phase {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.ui.errorPrefix.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.red)
                Text(message)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        } else if state.phase == .idle {
            Text(state.ui.hotkeyHint)
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(.secondary)
                .padding(.vertical, 20)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if state.servedLocally {
                    Label(state.ui.servedLocally, systemImage: "laptopcomputer")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if let situation = state.situation {
                    Text(situation)
                        .font(.system(size: 13, design: .serif).italic())
                        .foregroundStyle(.secondary)
                }
                ForEach(state.voices, id: \.id) { voice in
                    VoiceCard(voice: voice, state: state, speaking: whisperer.speaking == voice.id,
                              loading: whisperer.loading == voice.id)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if state.phase == .thinking {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(state.ui.thinking)
                            .font(.system(size: 14, design: .serif).italic())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if whisperer.hasElevenLabs, whisperer.lastSource == .system, let error = whisperer.lastError {
                Text(state.ui.whisperFallback)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help(error)
            }
            Spacer()
            Text(state.chosen == nil ? state.ui.clickToCopy : state.pasteIntoChat ? state.ui.pasted : state.ui.copied)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

struct VoiceCard: View {
    let voice: VoiceReply
    @ObservedObject var state: AppState
    let speaking: Bool
    let loading: Bool
    @State private var hovering = false

    private var isChosen: Bool { state.chosen == voice.id }
    private var isDimmed: Bool { state.chosen != nil && !isChosen }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(voice.id.color)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(voice.id.name(state.language).uppercased())
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(1)
                            .foregroundStyle(voice.id.color)
                        Text(voice.checkLabel(state.language))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(voice.passed ? voice.id.color.opacity(0.8) : .red.opacity(0.8))
                        Spacer()
                        if isChosen {
                            Text(state.ui.chosen.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(voice.id.color.opacity(0.25), in: Capsule())
                        }
                        // Listening never picks: this button sits outside the card's pick gesture.
                        Button { state.replay(voice) } label: {
                            Group {
                                if loading {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: speaking ? "waveform" : "play.circle")
                                        .font(.system(size: 16))
                                        .foregroundStyle(speaking ? voice.id.color : .secondary)
                                        .symbolEffect(.variableColor, isActive: speaking)
                                }
                            }
                            .frame(width: 24, height: 20)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(state.ui.replayWhisper)
                    }
                    Text(state.language == .russian ? "«\(voice.inner)»" : "“\(voice.inner)”")
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top, spacing: 4) {
                        // A failed check means a wrong move: flag it before it lands in the chat box.
                        Image(systemName: isChosen ? "checkmark" : voice.passed ? "arrow.turn.down.right" : "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(voice.passed || isChosen ? Color.secondary : Color.orange)
                            .help(voice.passed ? "" : state.ui.failedReplyWarning)
                        Text(voice.reply)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(hovering || speaking ? 0.09 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isChosen ? voice.id.color.opacity(0.8) : .clear, lineWidth: 1.5)
            )
            .opacity(isDimmed ? 0.45 : (voice.passed ? 1 : 0.7))
            .contentShape(Rectangle())
            .onTapGesture { state.choose(voice) }
            .onHover { hovering = $0 }
    }
}
