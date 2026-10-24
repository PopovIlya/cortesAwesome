import AppKit
import ApplicationServices
import CortesCore
import os

/// Reads the last messages visible in the frontmost chat window (Slack, Telegram, Messages…) through the
/// Accessibility API. Authors are not reliably exposed, so it returns message texts in screen order.
enum ChatReader {
    private static let log = Logger(subsystem: "ai.cortes.parliament", category: "chat")

    struct Item {
        let text: String
        let frame: CGRect
        let role: String
    }

    /// The last `limit` message texts of the frontmost app's focused window, oldest first.
    static func lastMessages(_ limit: Int, in app: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) -> [String] {
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return [] }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        wakeAccessibility(element)
        guard let (window, windowFrame) = chatWindow(element) else { return [] }

        var items: [Item] = []
        var visited = 0
        collect(window, in: windowFrame, into: &items, visited: &visited, depth: 0)
        let messages = Array(ChatColumn.messages(items.map { ($0.text, $0.frame) }, window: windowFrame).suffix(limit))
        log.info("\(app.bundleIdentifier ?? "?", privacy: .public): \(visited) nodes, \(items.count) texts, \(messages.count) messages")
        return messages
    }

    /// The focused window, else the main one, else the first window that has a frame.
    private static func chatWindow(_ app: AXUIElement) -> (AXUIElement, CGRect)? {
        let candidates: [AXUIElement?] = [attribute(app, kAXFocusedWindowAttribute), attribute(app, kAXMainWindowAttribute)]
        let windows: [AXUIElement] = attribute(app, kAXWindowsAttribute) ?? []
        for window in candidates.compactMap({ $0 }) + windows {
            if let frame = frame(of: window), frame.width > 100 { return (window, frame) }
        }
        return nil
    }

    /// Electron apps (Slack) and some Qt apps (Telegram Desktop) build their accessibility tree only when asked.
    private static func wakeAccessibility(_ app: AXUIElement) {
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    /// Walks the window's tree, skipping whole branches that lie outside the window: chat apps keep long
    /// virtual lists (every chat, every old message) in the tree, far off screen.
    private static func collect(_ element: AXUIElement, in window: CGRect, into items: inout [Item],
                                visited: inout Int, depth: Int) {
        guard depth < 60, visited < 20_000 else { return }
        visited += 1
        // Keep a few screens above the window: recent messages scrolled out of view are still history.
        let reach = CGRect(x: window.minX, y: window.minY - window.height * 3,
                           width: window.width, height: window.height * 4)
        if depth > 0, let frame = frame(of: element), frame.width > 0 || frame.height > 0,
           !frame.intersects(reach) { return }
        let role: String = attribute(element, kAXRoleAttribute) ?? ""
        if ["AXStaticText", "AXTextArea", "AXTextField"].contains(role),
           !(attribute(element, "AXEditable") ?? false) || role == "AXStaticText",
           let text = text(of: element), let frame = frame(of: element), frame.height > 0 {
            // The box you type in is not a message.
            let focused: Bool = attribute(element, kAXFocusedAttribute) ?? false
            if !focused { items.append(Item(text: text, frame: frame, role: role)) }
        }
        let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) ?? []
        for child in children { collect(child, in: window, into: &items, visited: &visited, depth: depth + 1) }
    }

    private static func text(of element: AXUIElement) -> String? {
        for key in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
            if let value: String = attribute(element, key), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let position: AXValue = attribute(element, kAXPositionAttribute),
              let size: AXValue = attribute(element, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position, .cgPoint, &point)
        AXValueGetValue(size, .cgSize, &extent)
        return CGRect(origin: point, size: extent)
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else { return nil }
        if T.self == AXUIElement.self { return (value as! T) }
        if T.self == AXValue.self { return (value as! T) }
        return value as? T
    }

    /// Structure only, never the text: roles, how many texts, their lengths and where they sit.
    /// Used to tune the column heuristics for a new chat app.
    static func probe(bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            log.error("probe: \(bundleID, privacy: .public) is not running"); return
        }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        wakeAccessibility(element)
        let windows: [AXUIElement] = attribute(element, kAXWindowsAttribute) ?? []
        log.info("probe \(bundleID, privacy: .public): \(windows.count) windows, hidden \(app.isHidden)")
        for (i, w) in windows.enumerated() {
            let role: String = attribute(w, kAXRoleAttribute) ?? "?"
            let minimized: Bool = attribute(w, kAXMinimizedAttribute) ?? false
            log.info("probe window \(i): role \(role, privacy: .public), frame \(frame(of: w).map { "\(Int($0.width))x\(Int($0.height))" } ?? "none", privacy: .public), minimized \(minimized)")
        }
        guard let (window, windowFrame) = chatWindow(element) else {
            log.error("probe: no window for \(bundleID, privacy: .public)"); return
        }
        var items: [Item] = []
        var visited = 0
        collect(window, in: windowFrame, into: &items, visited: &visited, depth: 0)
        let roles = Dictionary(grouping: items, by: \.role).mapValues(\.count)
        log.info("probe \(bundleID, privacy: .public): window \(Int(windowFrame.width))x\(Int(windowFrame.height)), \(visited) nodes, texts by role \(roles.description, privacy: .public)")
        for item in items.suffix(40) {
            let x = (item.frame.minX - windowFrame.minX) / windowFrame.width
            let y = (item.frame.minY - windowFrame.minY) / windowFrame.height
            log.info("probe item \(item.role, privacy: .public) len \(item.text.count) x \(x, format: .fixed(precision: 2)) y \(y, format: .fixed(precision: 2)) w \(Int(item.frame.width))")
        }
        log.info("probe: \(ChatColumn.messages(items.map { ($0.text, $0.frame) }, window: windowFrame).count) message lines after filtering")
    }
}
