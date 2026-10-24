import CortesCore
import SwiftUI

/// A die-cut sticker shaped like a skill card: pixel portrait in a frame, the skill and the voice on a banner,
/// a white edge and a slight tilt. Tied voices share one sticker, cut into strips.
struct Sticker: View {
    let voices: [Voice]
    let language: AppLanguage
    /// Points per art pixel; the portrait is 16 art pixels wide.
    var pixel: CGFloat = 5

    init(voice: Voice, language: AppLanguage, pixel: CGFloat = 5) {
        self.init(voices: [voice], language: language, pixel: pixel)
    }

    init(voices: [Voice], language: AppLanguage, pixel: CGFloat = 5) {
        self.voices = voices
        self.language = language
        self.pixel = pixel
    }

    /// Every voice leans its own way, like stickers slapped on a laptop; a shared sticker sits straight.
    private var tilt: Double {
        voices.count == 1 ? [-5, 4, -3, 5, -4, 3, -6][Voice.allCases.firstIndex(of: voices[0])!] : -2
    }
    private var scale: CGFloat { pixel / 5 }
    private var width: CGFloat { CGFloat(PixelArt.size) * pixel }
    private var frameColor: Color { voices.count == 1 ? voices[0].color : Color(white: 0.75) }

    var body: some View {
        VStack(spacing: 0) {
            PixelPortrait(voices: voices, pixel: pixel)
                .overlay(Rectangle().stroke(frameColor, lineWidth: 2 * scale))
            Group {
                if voices.count == 1 {
                    VStack(spacing: 1 * scale) {
                        Text(voices[0].skill(language).uppercased())
                            .font(.system(size: 11 * scale, weight: .black, design: .serif))
                            .tracking(1)
                            .foregroundStyle(voices[0].color)
                        Text(voices[0].name(language).uppercased())
                            .font(.system(size: 7 * scale, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(white: 0.85))
                    }
                } else {
                    // Tied voices: one line each, so long skill names are never cut.
                    VStack(alignment: .leading, spacing: 2 * scale) {
                        ForEach(voices, id: \.self) { voice in
                            Text(voice.skill(language).uppercased())
                                .font(.system(size: 9 * scale, weight: .black, design: .serif))
                                .foregroundStyle(voice.color)
                        }
                    }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: width)
            .padding(.vertical, 4 * scale)
            .background(Color(red: 0.1, green: 0.09, blue: 0.11))
        }
        .padding(3 * scale)
        .background(Color(red: 0.1, green: 0.09, blue: 0.11))
        .padding(3 * scale)
        .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 6 * scale))
        .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
        .rotationEffect(.degrees(tilt))
    }
}

/// Who the user picks: today, all time, and the leaders of each recent day.
struct StatsView: View {
    @ObservedObject var state: AppState

    private var ui: UIStrings { state.ui }

    var body: some View {
        let today = state.stats.counts(on: PickStats.dayKey(Date()))
        let allTime = state.stats.allTime
        VStack(alignment: .leading, spacing: 12) {
            if allTime.isEmpty {
                Text(ui.noPicksYet)
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(.secondary)
            } else {
                section(ui.today, counts: today)
                section(ui.allTime, counts: allTime)
                let recent = state.stats.recentDays(7)
                if !recent.isEmpty {
                    title(ui.recentDays)
                    ForEach(recent, id: \.day) { entry in
                        HStack {
                            Text(entry.day)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                            PixelPortrait(voices: entry.leaders, pixel: 1.25)
                            Text(ui.and(entry.leaders.map { $0.name(state.language) }))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(entry.leaders.count == 1 ? entry.leaders[0].color : .primary)
                            Spacer()
                            Text(ui.picks(entry.total))
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private func title(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(1)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func section(_ name: String, counts: [Voice: Int]) -> some View {
        let total = max(counts.values.reduce(0, +), 1)
        title(name)
        VStack(spacing: 4) {
            ForEach(Voice.allCases, id: \.self) { voice in
                let n = counts[voice] ?? 0
                HStack(spacing: 6) {
                    PixelPortrait(voice: voice, pixel: 1.25)
                    Text(voice.name(state.language))
                        .font(.system(size: 11))
                        .frame(width: 100, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(voice.color.opacity(n > 0 ? 0.85 : 0.15))
                            .frame(width: max(4, geo.size.width * CGFloat(n) / CGFloat(total)))
                    }
                    .frame(height: 8)
                    Text("\(n)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
            }
        }
    }
}
