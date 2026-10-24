import AppKit
import Combine
import CortesCore
import SwiftUI

/// Floating panel above all windows that never steals focus from the chat you are in.
final class ParliamentPanel: NSPanel {
    init(rootView: some View) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 400, height: 520),
                   styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView, .resizable],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        backgroundColor = .clear
        contentView = NSHostingView(rootView: rootView)
    }

    override var canBecomeKey: Bool { true }

    func showTopRight() {
        if !isVisible, let screen = NSScreen.main?.visibleFrame {
            setFrameTopLeftPoint(NSPoint(x: screen.maxX - frame.width - 20, y: screen.maxY - 20))
        }
        orderFrontRegardless()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private var panel: ParliamentPanel!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var menuObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load the voice corpus now, so a packaging mistake shows at launch and not mid-conversation.
        _ = StyleCorpus.shared
        panel = ParliamentPanel(rootView: ParliamentView(state: state))
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "theatermasks", accessibilityDescription: "Cortes")
        // @Published fires before the property changes, so the new values are passed in.
        menuObserver = state.$language.combineLatest(state.$whisperEnabled)
            .sink { [weak self] lang, whisper in self?.buildMenu(lang, whisper: whisper) }

        hotKey = HotKey { [weak self] in self?.askAboutSelection() }

        if !SelectionGrabber.isTrusted { SelectionGrabber.requestAccess() }
        panel.showTopRight()
        // `open Cortes.app --args --listen` starts call mode right away, for demos and testing.
        if CommandLine.arguments.contains("--listen") { state.toggleListening() }
        // `--probe-chat <bundle id>` logs a chat app's accessibility structure (never its text), to tune ChatReader.
        if let i = CommandLine.arguments.firstIndex(of: "--probe-chat"), i + 1 < CommandLine.arguments.count {
            ChatReader.probe(bundleID: CommandLine.arguments[i + 1])
        }
    }

    private func buildMenu(_ lang: AppLanguage, whisper: Bool) {
        let ui = UIStrings(lang)
        let menu = NSMenu()
        menu.addItem(withTitle: ui.showPanel, action: #selector(showPanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: ui.askAbout, action: #selector(askAboutClipboard), keyEquivalent: "").target = self
        menu.addItem(withTitle: ui.settings + "…", action: #selector(showSettings), keyEquivalent: ",").target = self
        let whisperItem = NSMenuItem(title: ui.whisper, action: #selector(toggleWhisper), keyEquivalent: "")
        whisperItem.target = self
        whisperItem.state = whisper ? .on : .off
        menu.addItem(whisperItem)
        menu.addItem(withTitle: ui.listen, action: #selector(toggleListening), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let languageItem = NSMenuItem(title: ui.language, action: nil, keyEquivalent: "")
        let languages = NSMenu()
        for option in AppLanguage.allCases {
            let item = NSMenuItem(title: option.displayName, action: #selector(pickLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.state = option == lang ? .on : .off
            languages.addItem(item)
        }
        languageItem.submenu = languages
        menu.addItem(languageItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: ui.hotkeyHint, action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(withTitle: ui.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func showPanel() { panel.showTopRight() }

    @objc private func showSettings() {
        state.showStats = false
        state.showSettings = true
        panel.showTopRight()
    }

    @objc private func toggleListening() {
        panel.showTopRight()
        state.toggleListening()
    }

    @objc private func toggleWhisper() {
        state.whisperEnabled.toggle()
    }

    @objc private func pickLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let lang = AppLanguage(rawValue: raw) else { return }
        state.language = lang
        state.rerunInCurrentLanguage()
    }

    /// Fallback that needs no Accessibility permission: ask about whatever is on the clipboard.
    @objc private func askAboutClipboard() {
        panel.showTopRight()
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state.show(error: state.ui.noSelection)
            return
        }
        state.ask(text)
    }

    private func askAboutSelection() {
        // The panel never takes focus, so the chat app is still frontmost here.
        state.chatApp = NSWorkspace.shared.frontmostApplication
        let history = state.readChatHistory && SelectionGrabber.isTrusted
            ? ChatReader.lastMessages(state.chatHistoryCount) : []
        panel.showTopRight()
        Task {
            do {
                state.ask(try await SelectionGrabber.grab(), history: history)
            } catch SelectionGrabber.Failure.accessibilityNotGranted {
                SelectionGrabber.requestAccess()
                state.show(error: state.ui.accessibilityNeeded)
            } catch {
                // Nothing selected: with chat history on, answer the last message in it.
                if history.isEmpty { state.show(error: state.ui.noSelection) } else { state.ask(nil, history: history) }
            }
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
