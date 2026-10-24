import CortesCore
import SwiftUI

/// Everything you can tune without touching .env. Keys stay in .env; this only shows whether they were found.
struct SettingsView: View {
    @ObservedObject var state: AppState

    private var ui: UIStrings { state.ui }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section(ui.settingsModel) {
                Picker("", selection: $state.backend) {
                    Text(ui.backendAuto).tag(AppState.Backend.auto)
                    Text(ui.backendCloud).tag(AppState.Backend.cloud)
                    Text(ui.backendLocal).tag(AppState.Backend.local)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                status(state.hasGeminiKey, ui.geminiKey)
                status(state.localAvailable ?? false, ui.localModel, pending: state.localAvailable == nil)
            }

            section(ui.settingsChat) {
                Toggle(ui.pasteIntoChat, isOn: $state.pasteIntoChat)
                    .toggleStyle(.switch).controlSize(.mini).font(.system(size: 12))
                Toggle(ui.readChatHistory, isOn: $state.readChatHistory)
                    .toggleStyle(.switch).controlSize(.mini).font(.system(size: 12))
                if state.readChatHistory {
                    slider(ui.chatHistoryCount, value: Binding(get: { Double(state.chatHistoryCount) },
                                                               set: { state.chatHistoryCount = Int($0) }),
                           in: 5...30, step: 1, unit: "")
                    Text(ui.readChatHistoryHint)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            section(ui.settingsCall) {
                slider(ui.phrasePause, value: $state.phrasePause, in: 0.8...3, step: 0.1, unit: ui.seconds)
                slider(ui.callCooldown, value: $state.callCooldown, in: 5...60, step: 5, unit: ui.seconds)
                Picker(ui.speechModel, selection: $state.whisperModel) {
                    Text(ui.whisperBase).tag("openai_whisper-base")
                    Text(ui.whisperSmall).tag("openai_whisper-small")
                }
                .font(.system(size: 12))
            }

            section(ui.settingsWhisper) {
                Toggle(ui.whisper, isOn: $state.whisperEnabled)
                Toggle(ui.autoWhisperOnCalls, isOn: $state.autoWhisperOnCalls)
                    .disabled(!state.whisperEnabled)
                status(state.hasElevenLabsKey, ui.elevenLabsKey)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.system(size: 12))

            Text(ui.keysHint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .onAppear { state.checkLocalModel() }
        .onChange(of: state.backend) { _, _ in state.checkLocalModel() }
        .onChange(of: state.phrasePause) { _, pause in state.listener.setPause(pause) }
        .onChange(of: state.whisperModel) { _, _ in state.restartListening() }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double,
                        unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 12))
                Spacer()
                Text("\(value.wrappedValue, specifier: step < 1 ? "%.1f" : "%.0f") \(unit)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step).controlSize(.mini)
        }
    }

    private func status(_ ok: Bool, _ label: String, pending: Bool = false) -> some View {
        Label(label, systemImage: pending ? "ellipsis.circle" : ok ? "checkmark.circle.fill" : "xmark.circle")
            .font(.system(size: 11))
            .foregroundStyle(pending ? Color.secondary : ok ? Color.green : Color.orange)
    }
}
