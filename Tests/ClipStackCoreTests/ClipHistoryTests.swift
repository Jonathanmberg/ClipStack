import XCTest
@testable import ClipStackCore

final class ClipHistoryTests: XCTestCase {
    private var dir: URL!
    private var store: URL { dir.appendingPathComponent("history.json") }

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("clipstack-tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func texts(_ h: ClipHistory) -> [String] { h.items.map(\.text) }

    func testNewestFirst() {
        let h = ClipHistory(limit: 5, persists: false, storeURL: nil)
        h.add("one"); h.add("two"); h.add("three")
        XCTAssertEqual(texts(h), ["three", "two", "one"])
    }

    func testIgnoresConsecutiveDuplicate() {
        let h = ClipHistory(limit: 5, persists: false, storeURL: nil)
        XCTAssertTrue(h.add("same"))
        XCTAssertFalse(h.add("same"))
        XCTAssertEqual(texts(h), ["same"])
    }

    func testRecopyMovesToTop() {
        let h = ClipHistory(limit: 5, persists: false, storeURL: nil)
        h.add("a"); h.add("b"); h.add("c"); h.add("a")
        XCTAssertEqual(texts(h), ["a", "c", "b"])
    }

    func testWhitespaceOnlyDifferenceIsSameClip() {
        let h = ClipHistory(limit: 5, persists: false, storeURL: nil)
        h.add("npm install\n"); h.add("other"); h.add("  npm install")
        XCTAssertEqual(texts(h), ["  npm install", "other"])
    }

    func testIgnoresBlankAndHuge() {
        let h = ClipHistory(limit: 5, persists: false, storeURL: nil)
        XCTAssertFalse(h.add(""))
        XCTAssertFalse(h.add("  \n\t "))
        XCTAssertFalse(h.add(String(repeating: "x", count: ClipHistory.maxTextBytes + 1)))
        XCTAssertTrue(h.items.isEmpty)
    }

    func testLimitKeepsNewest() {
        let h = ClipHistory(limit: 5, persists: false, storeURL: nil)
        for i in 1...8 { h.add("item \(i)") }
        XCTAssertEqual(texts(h), ["item 8", "item 7", "item 6", "item 5", "item 4"])
        h.limit = 2
        XCTAssertEqual(texts(h), ["item 8", "item 7"])
    }

    func testPromoteAndRemove() {
        let h = ClipHistory(limit: 5, persists: false, storeURL: nil)
        h.add("a"); h.add("b"); h.add("c")
        let a = h.items[2]
        h.promote(a.id)
        XCTAssertEqual(texts(h), ["a", "c", "b"])
        XCTAssertEqual(h.items[0].id, a.id)
        h.remove(h.items[1].id)
        XCTAssertEqual(texts(h), ["a", "b"])
    }

    func testPersistsAcrossRestarts() throws {
        let h = ClipHistory(limit: 5, persists: true, storeURL: store)
        h.add("hello@example.com"); h.add("https://github.com")
        let reopened = ClipHistory(limit: 5, persists: true, storeURL: store)
        XCTAssertEqual(texts(reopened), ["https://github.com", "hello@example.com"])

        let perms = try FileManager.default.attributesOfItem(atPath: store.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
    }

    func testDisablingPersistenceDeletesFile() {
        let h = ClipHistory(limit: 5, persists: true, storeURL: store)
        h.add("secret")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.path))
        h.persists = false
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.path))
        h.add("still in memory")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.path))
        XCTAssertEqual(texts(h), ["still in memory", "secret"])
    }

    func testStartingWithPersistenceOffDeletesOldFile() {
        ClipHistory(limit: 5, persists: true, storeURL: store).add("old")
        let h = ClipHistory(limit: 5, persists: false, storeURL: store)
        XCTAssertTrue(h.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.path))
    }

    func testClearWipesDisk() {
        let h = ClipHistory(limit: 5, persists: true, storeURL: store)
        h.add("a")
        h.clear()
        XCTAssertTrue(h.items.isEmpty)
        XCTAssertTrue(ClipHistory(limit: 5, persists: true, storeURL: store).items.isEmpty)
    }

    func testLoadTrimsToLimit() {
        let big = ClipHistory(limit: 20, persists: true, storeURL: store)
        for i in 1...12 { big.add("\(i)") }
        XCTAssertEqual(ClipHistory(limit: 5, persists: true, storeURL: store).items.count, 5)
    }
}

final class ClipItemTests: XCTestCase {
    func testPreviewIsOneLine() {
        XCTAssertEqual(ClipItem(text: "  line one\n\n  line\ttwo  ").preview(), "line one line two")
    }

    func testPreviewTruncates() {
        let p = ClipItem(text: String(repeating: "abcde ", count: 50)).preview(maxLength: 20)
        XCTAssertEqual(p.count, 20)
        XCTAssertTrue(p.hasSuffix("…"))
    }

    func testURLDetection() {
        XCTAssertTrue(ClipItem(text: "https://github.com/foo").isURL)
        XCTAssertTrue(ClipItem(text: " mailto:a@b.co\n").isURL)
        XCTAssertFalse(ClipItem(text: "npm install").isURL)
        XCTAssertFalse(ClipItem(text: "see https://github.com").isURL)
        XCTAssertFalse(ClipItem(text: "file:///etc/hosts").isURL)
    }
}

final class ShortcutTests: XCTestCase {
    func testDefaultIsControlOptionV() {
        XCTAssertEqual(Shortcut.default.displayString, "⌃⌥V")
        XCTAssertTrue(Shortcut.default.isUsable)
    }

    func testModifierOrder() {
        let s = Shortcut(keyCode: 9, modifiers: Shortcut.command | Shortcut.shift | Shortcut.option | Shortcut.control)
        XCTAssertEqual(s.displayString, "⌃⌥⇧⌘V")
    }

    func testShiftAloneIsNotUsable() {
        XCTAssertFalse(Shortcut(keyCode: 9, modifiers: Shortcut.shift).isUsable)
        XCTAssertFalse(Shortcut(keyCode: 9, modifiers: 0).isUsable)
    }

    func testCodableRoundTrip() throws {
        let s = Shortcut(keyCode: 7, modifiers: Shortcut.command)
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(Shortcut.self, from: data), s)
    }
}
