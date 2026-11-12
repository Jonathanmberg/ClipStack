import AppKit
import SwiftUI
import ClipStackCore

final class PanelModel: ObservableObject {
    @Published var items: [ClipItem] = []
    @Published var selected = 0
    @Published var shortcutLabel = ""
}

/// A borderless panel that can take keystrokes without activating ClipStack,
/// so the app you were typing in stays frontmost.
final class KeyPanel: NSPanel {
    var onKeyDown: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKeyDown?(event) == true { return }
        super.sendEvent(event)
    }
}

/// Shows the clip list near the text cursor and handles ↑ ↓ ↩ ⎋, 1–9/0, ⌫ and mouse clicks.
final class PanelController: NSObject, NSWindowDelegate {
    static let width: CGFloat = 360

    var onChoose: ((ClipItem, NSRunningApplication?) -> Void)?
    var onRemove: ((ClipItem) -> Void)?
    var isVisible: Bool { panel.isVisible }

    private let panel: KeyPanel
    private let model = PanelModel()
    private var targetApp: NSRunningApplication?

    override init() {
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.delegate = self
        panel.onKeyDown = { [weak self] event in self?.handleKey(event) ?? false }
        panel.contentView = NSHostingView(rootView: ClipListView(model: model) { [weak self] index in
            self?.choose(index)
        })
    }

    func show(items: [ClipItem], shortcutLabel: String, appearance: NSAppearance?) {
        targetApp = NSWorkspace.shared.frontmostApplication
        model.items = items
        model.selected = 0
        model.shortcutLabel = shortcutLabel
        panel.appearance = appearance
        let size = NSSize(width: Self.width, height: ClipListView.height(rows: items.count))
        panel.setFrame(NSRect(origin: origin(for: size), size: size), display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// Pressing the shortcut again while the list is open moves down one row.
    func selectNext() {
        move(1)
    }

    /// Testing aid: renders the panel's content to a PNG.
    func snapshot(to url: URL) {
        guard let view = panel.contentView else { return }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide() // clicked somewhere else
    }

    // MARK: - Keys

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 125, 48: move(1)                // ↓, ⇥
        case 126: move(-1)                   // ↑
        case 36, 76: choose(model.selected)  // ↩, keypad enter
        case 53: hide()                      // ⎋
        case 51, 117: removeSelected()       // ⌫, ⌦
        default:
            // 1–9 paste that row right away, 0 pastes row 10.
            if let c = event.charactersIgnoringModifiers, c.count == 1, let n = Int(c) {
                choose(n == 0 ? 9 : n - 1)
            }
        }
        return true // the list owns the keyboard while it's open
    }

    private func move(_ delta: Int) {
        guard !model.items.isEmpty else { return }
        model.selected = (model.selected + delta + model.items.count) % model.items.count
    }

    private func choose(_ index: Int) {
        guard model.items.indices.contains(index) else { return }
        let item = model.items[index]
        let app = targetApp
        hide()
        onChoose?(item, app)
    }

    private func removeSelected() {
        guard model.items.indices.contains(model.selected) else { return }
        let item = model.items.remove(at: model.selected)
        model.selected = min(model.selected, max(0, model.items.count - 1))
        onRemove?(item)
        // Shrink from the bottom, keeping the top edge where it was.
        var frame = panel.frame
        let newHeight = ClipListView.height(rows: model.items.count)
        frame.origin.y += frame.height - newHeight
        frame.size.height = newHeight
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    // MARK: - Placement

    /// Just below the text cursor if we can find it, otherwise below the mouse; kept on screen.
    private func origin(for size: NSSize) -> NSPoint {
        let anchor = Caret.rect() ?? NSRect(origin: NSEvent.mouseLocation, size: .zero)
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        var x = anchor.minX
        var y = anchor.minY - size.height - 6
        if y < area.minY { y = anchor.maxY + 6 } // no room below: open above
        x = min(max(x, area.minX), area.maxX - size.width)
        y = min(max(y, area.minY), area.maxY - size.height)
        return NSPoint(x: x, y: y)
    }
}

// MARK: - Views

struct ClipListView: View {
    @ObservedObject var model: PanelModel
    var choose: (Int) -> Void

    static let headerHeight: CGFloat = 30
    static let rowHeight: CGFloat = 30
    static let listPadding: CGFloat = 6
    static let footerHeight: CGFloat = 24

    static func height(rows: Int) -> CGFloat {
        headerHeight + 1 + listPadding * 2 + CGFloat(max(rows, 1)) * rowHeight + 1 + footerHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ClipStack").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(model.shortcutLabel).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: Self.headerHeight)

            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)

            VStack(spacing: 0) {
                if model.items.isEmpty {
                    Text("Nothing copied yet — copy something with ⌘C")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: Self.rowHeight)
                } else {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        ClipRow(index: index, item: item, selected: index == model.selected)
                            .onHover { inside in if inside { model.selected = index } }
                            .onTapGesture { choose(index) }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, Self.listPadding)

            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)

            Text("↑↓ choose   ↩ paste   ⌫ remove   esc close")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .frame(height: Self.footerHeight)
        }
        .frame(width: PanelController.width, height: Self.height(rows: model.items.count), alignment: .top)
        .background(VisualEffect())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }
}

struct ClipRow: View {
    let index: Int
    let item: ClipItem
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(index < 10 ? "\((index + 1) % 10)" : " ")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
                .frame(width: 12)
            Text(item.preview())
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(selected ? Color.white : Color.primary)
            Spacer(minLength: 0)
            if item.isURL {
                Image(systemName: "link")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: ClipListView.rowHeight)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(selected ? Color.accentColor : Color.clear))
        .contentShape(Rectangle())
    }
}

/// The native translucent menu material.
struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active // stay translucent even though ClipStack isn't the active app
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
