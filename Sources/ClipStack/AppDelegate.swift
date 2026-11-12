import AppKit
import Combine
import SwiftUI
import ClipStackCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let prefs: Preferences
    private let history: ClipHistory
    private let monitor: ClipboardMonitor
    private let hotKey = HotKey()
    private let panel = PanelController()
    private let system = SystemState()
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()
    private var askedForAccessThisLaunch = false
    private let isTesting: Bool
    private let dataDir: URL

    override init() {
        // `--data-dir <path>` keeps history and settings separate from the real ones (for testing).
        let args = CommandLine.arguments
        let dataDir: URL
        let defaults: UserDefaults
        let testIndex = args.firstIndex(of: "--data-dir").flatMap { $0 + 1 < args.count ? $0 : nil }
        isTesting = testIndex != nil
        if let i = testIndex {
            dataDir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
            defaults = UserDefaults(suiteName: "com.jonathanberg.clipstack.testing") ?? .standard
            defaults.set(true, forKey: "hasOnboarded")
        } else {
            dataDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ClipStack", isDirectory: true)
            defaults = .standard
        }
        self.dataDir = dataDir
        prefs = Preferences(defaults: defaults)
        history = ClipHistory(limit: ClipHistory.defaultLimit, persists: true,
                              storeURL: dataDir.appendingPathComponent("history.json"))
        let prefs = self.prefs
        monitor = ClipboardMonitor(history: history, isPaused: { prefs.paused })
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        monitor.start()

        hotKey.onPress = { [weak self] in self?.shortcutPressed() }
        registerShortcut(prefs.shortcut)

        panel.onChoose = { [weak self] item, app in self?.paste(item, into: app) }
        panel.onRemove = { [weak self] item in self?.history.remove(item.id) }

        // @Published fires before the value is stored, so use the value handed to the sink.
        prefs.$shortcut.dropFirst().sink { [weak self] in self?.registerShortcut($0) }.store(in: &subscriptions)
        prefs.$paused.sink { [weak self] in self?.statusItem.button?.appearsDisabled = $0 }.store(in: &subscriptions)

        if isTesting {
            // Lets scripts open the popup without synthesizing keystrokes.
            DistributedNotificationCenter.default().addObserver(
                forName: .init("com.jonathanberg.clipstack.testing.show"), object: nil, queue: .main
            ) { [weak self] _ in self?.shortcutPressed() }
            // Opens the overlay, saves a picture of it, and closes it again within a second,
            // so a test never leaves it holding the keyboard.
            DistributedNotificationCenter.default().addObserver(
                forName: .init("com.jonathanberg.clipstack.testing.snapshot"), object: nil, queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                if !self.panel.isVisible { self.shortcutPressed() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    self.panel.snapshot(to: self.dataDir.appendingPathComponent("panel.png"))
                    self.panel.hide()
                }
            }
        }

        if !prefs.hasOnboarded {
            prefs.hasOnboarded = true
            DispatchQueue.main.async { self.showWelcome() }
        }
    }

    // MARK: - Shortcut → popup → paste

    private func registerShortcut(_ shortcut: Shortcut) {
        system.shortcutTaken = !hotKey.register(shortcut)
    }

    private func shortcutPressed() {
        if panel.isVisible {
            panel.selectNext()
        } else {
            panel.show(items: history.items)
        }
    }

    private func paste(_ item: ClipItem, into app: NSRunningApplication?) {
        Paster.copy(item.text)
        monitor.skipCurrent() // our own write is not a new copy
        history.promote(item.id)
        if Paster.canAutoPaste {
            Paster.pressPaste(in: app)
        } else {
            // It's on the clipboard; the user presses ⌘V. Ask once per launch for auto-paste.
            app?.activate(options: [])
            if !askedForAccessThisLaunch {
                askedForAccessThisLaunch = true
                Paster.requestAccess()
            }
        }
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "ClipStack")
            ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipStack")
        image?.isTemplate = true
        statusItem.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let hint = NSMenuItem(title: "Press \(prefs.shortcut.displayString) in any app", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

        if history.items.isEmpty {
            let empty = NSMenuItem(title: "No clips yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for (i, clip) in history.items.enumerated() {
                let item = NSMenuItem(title: clip.preview(maxLength: 48), action: #selector(copyFromMenu(_:)),
                                      keyEquivalent: i < 9 ? "\(i + 1)" : "")
                item.keyEquivalentModifierMask = []
                item.representedObject = clip.id
                item.target = self
                item.toolTip = "Copy to clipboard"
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())

        add(to: menu, "Pause Collecting", #selector(togglePause)).state = prefs.paused ? .on : .off
        add(to: menu, "Clear History", #selector(clearHistory))
        menu.addItem(.separator())
        if !Paster.canAutoPaste {
            add(to: menu, "Allow Auto-Paste…", #selector(allowAutoPaste))
        }
        system.refresh()
        add(to: menu, "Launch at Login", #selector(toggleLaunchAtLogin)).state = system.launchAtLogin ? .on : .off
        add(to: menu, "Settings…", #selector(openSettings), key: ",")
        menu.addItem(.separator())
        add(to: menu, "Quit ClipStack", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp)
    }

    @discardableResult
    private func add(to menu: NSMenu, _ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        menu.addItem(item)
        return item
    }

    @objc private func copyFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let clip = history.items.first(where: { $0.id == id }) else { return }
        Paster.copy(clip.text)
        monitor.skipCurrent()
        history.promote(id)
    }

    @objc private func togglePause() { prefs.paused.toggle() }
    @objc private func clearHistory() { history.clear() }
    @objc private func toggleLaunchAtLogin() { system.setLaunchAtLogin(!system.launchAtLogin) }

    @objc private func allowAutoPaste() {
        Paster.requestAccess()
        Paster.openAccessibilitySettings()
    }

    // MARK: - Windows

    @objc private func openSettings() {
        system.refresh()
        if settingsWindow == nil {
            let view = SettingsView(
                prefs: prefs, system: system,
                recordingChanged: { [weak self] recording in
                    guard let self else { return }
                    // Release the shortcut while recording so pressing it again can be captured.
                    if recording { self.hotKey.unregister() } else { self.registerShortcut(self.prefs.shortcut) }
                })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "ClipStack"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                                                   queue: .main) { [weak self] _ in self?.system.refresh() }
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func showWelcome() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "ClipStack is running in your menu bar"
        alert.informativeText = """
            Copy as usual. Then press \(prefs.shortcut.displayString) in any app to see your recent clips — \
            ↑ ↓ to pick one, ↩ to paste it.

            To paste for you, ClipStack needs Accessibility access. Without it, the clip is copied \
            and you press ⌘V yourself.
            """
        alert.addButton(withTitle: "Allow Accessibility…")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            Paster.requestAccess()
        }
    }
}
