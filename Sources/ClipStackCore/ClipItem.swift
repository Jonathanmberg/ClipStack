import Foundation

/// One thing the user copied.
public struct ClipItem: Codable, Equatable, Identifiable {
    public let id: UUID
    public let text: String
    public let copiedAt: Date

    public init(text: String, id: UUID = UUID(), copiedAt: Date = Date()) {
        self.id = id
        self.text = text
        self.copiedAt = copiedAt
    }

    /// A single line for the list: runs of whitespace (newlines included) become one space,
    /// and long text is cut with "…".
    public func preview(maxLength: Int = 70) -> String {
        // Only look at the start of very long clips; a preview never needs more.
        let head = text.prefix(maxLength * 8)
        let collapsed = head.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let truncated = collapsed.count > maxLength || head.count < text.count
        guard truncated else { return collapsed }
        return String(collapsed.prefix(maxLength - 1)) + "…"
    }

    /// True when the whole clip is a single web or mail link.
    public var isURL: Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(where: { $0.isWhitespace }),
              let url = URL(string: t), let scheme = url.scheme?.lowercased() else { return false }
        switch scheme {
        case "http", "https", "ftp": return url.host != nil
        case "mailto": return true
        default: return false
        }
    }
}
