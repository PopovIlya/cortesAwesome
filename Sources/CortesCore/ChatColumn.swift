import CoreGraphics
import Foundation

/// Picks the messages out of the texts a chat window exposes through Accessibility.
public enum ChatColumn {
    /// Keeps the conversation column: drops the chat list on the left, the header, the input box,
    /// timestamps and one-word UI labels; sorts top to bottom. Messages partly scrolled out of view count.
    public static func messages(_ items: [(text: String, frame: CGRect)], window: CGRect) -> [String] {
        let left = window.minX + window.width * 0.28
        let header = window.minY + window.height * 0.08
        let bottom = window.maxY - window.height * 0.12
        // Times, dates and day separators ("12:40", "24.10.2026", "24 октября", "Today").
        let timestamp = try! NSRegularExpression(
            pattern: #"^\s*(\d{1,2}:\d{2}(\s?[AP]M)?|\d{1,2}\.\d{1,2}\.\d{2,4}|\d{1,2}\s\p{L}+(\s\d{4})?|\p{L}+\s\d{1,2}(,\s\d{4})?|today|yesterday|сегодня|вчера)\s*$"#,
            options: .caseInsensitive)
        var seen = Set<String>()
        return items
            .filter { $0.frame.minX >= left && $0.frame.minY < bottom }
            // The chat title lies wholly inside the header band; scrolled-up messages lie above the window.
            .filter { !($0.frame.minY >= window.minY && $0.frame.maxY <= header) }
            .filter { item in
                // One short word is a button or a label, not a message.
                let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.count >= 12 || (text.count >= 2 && text.contains(" ")) else { return false }
                return timestamp.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil
            }
            .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { seen.insert($0).inserted }
    }
}
