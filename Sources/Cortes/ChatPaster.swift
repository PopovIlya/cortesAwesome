import AppKit

/// Puts the picked reply into the chat's input box, ready to send. It never presses Enter:
/// sending stays your decision.
@MainActor
enum ChatPaster {
    /// Activates the chat app (if another app came forward meanwhile) and pastes the clipboard into its focused field.
    static func paste(into app: NSRunningApplication?) async {
        guard await activate(app) else { return }
        press(9, flags: .maskCommand) // V
    }

    /// Brings the chat app forward if needed. False when there is no chat app to type into.
    @discardableResult
    static func activate(_ app: NSRunningApplication?) async -> Bool {
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier, !app.isTerminated else { return false }
        if NSWorkspace.shared.frontmostApplication != app {
            app.activate()
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return true
    }

    /// Removes text this app pasted a moment ago: one Backspace per character, so a draft typed before it stays.
    static func erase(_ text: String) {
        for _ in 0..<text.count { press(51) } // Delete
    }

    private static func press(_ key: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
}
