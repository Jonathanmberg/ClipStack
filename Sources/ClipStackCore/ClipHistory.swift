import Foundation

/// The most recent unique clips, newest first, optionally saved to a local JSON file.
public final class ClipHistory {
    public static let allowedLimits = [5, 10, 20, 50]
    public static let defaultLimit = 5
    /// Clips larger than this (in UTF-8 bytes) are not recorded.
    public static let maxTextBytes = 1_000_000

    public private(set) var items: [ClipItem] = []

    public var limit: Int {
        didSet {
            limit = max(1, limit)
            trim()
            save()
        }
    }

    /// When false nothing is written to disk and any existing file is deleted.
    public var persists: Bool {
        didSet {
            guard persists != oldValue else { return }
            if persists { save() } else { deleteStore() }
        }
    }

    private let storeURL: URL?

    public init(limit: Int = ClipHistory.defaultLimit, persists: Bool, storeURL: URL?) {
        self.limit = max(1, limit)
        self.persists = persists
        self.storeURL = storeURL
        if persists { load() } else { deleteStore() }
        trim()
    }

    /// Records a new copy. Returns false when it was ignored
    /// (blank, too large, or the same as the newest clip).
    @discardableResult
    public func add(_ text: String, at date: Date = Date()) -> Bool {
        let key = Self.dedupeKey(text)
        guard !key.isEmpty, text.utf8.count <= Self.maxTextBytes else { return false }
        if items.first?.text == text { return false }
        // Copying something already in the list (ignoring surrounding whitespace) moves it to the
        // top instead of duplicating it; the newest version of the text is kept.
        items.removeAll { Self.dedupeKey($0.text) == key }
        items.insert(ClipItem(text: text, copiedAt: date), at: 0)
        trim()
        save()
        return true
    }

    /// Moves a clip to the top, e.g. after the user pasted it from the list.
    public func promote(_ id: UUID, at date: Date = Date()) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        items.insert(ClipItem(text: item.text, id: item.id, copiedAt: date), at: 0)
        save()
    }

    public func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    public func clear() {
        items.removeAll()
        deleteStore()
    }

    private static func dedupeKey(_ text: String) -> Substring {
        let start = text.firstIndex(where: { !$0.isWhitespace }) ?? text.endIndex
        let end = text.lastIndex(where: { !$0.isWhitespace }).map(text.index(after:)) ?? start
        return text[start..<max(start, end)]
    }

    // MARK: - Storage

    private func trim() {
        if items.count > limit { items.removeLast(items.count - limit) }
    }

    private func load() {
        guard let url = storeURL,
              let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode([ClipItem].self, from: data) else { return }
        items = saved
    }

    private func save() {
        guard persists, let url = storeURL else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        guard let data = try? JSONEncoder().encode(items) else { return }
        // Write an owner-only temp file, then atomically rename it over the old one.
        let tmp = url.path + ".tmp"
        if fm.createFile(atPath: tmp, contents: data, attributes: [.posixPermissions: 0o600]) {
            rename(tmp, url.path)
        }
    }

    private func deleteStore() {
        guard let url = storeURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
