import AppKit
import SwiftUI
import ClipStackCore

final class PanelModel: ObservableObject {
    @Published var items: [ClipItem] = []
    @Published var selected = 0
    /// Drives the card sliding up from the bottom edge.
    @Published var presented = false
    /// Space taken by the Dock at the bottom of the screen, so the card sits above it.
    @Published var bottomInset: CGFloat = 0
    /// Where the mouse was when the list opened. Hover only takes over the highlight once the
    /// mouse moves away from here, so a resting mouse under the card can't steal ↩.
    var mouseAtOpen = NSPoint.zero

    var mouseHasMoved: Bool {
        let now = NSEvent.mouseLocation
        return abs(now.x - mouseAtOpen.x) > 3 || abs(now.y - mouseAtOpen.y) > 3
    }
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

/// Frosts the whole screen and slides the clip card up from the bottom center.
/// Handles ↑ ↓ ↩ ⎋, 1–9/0, ⌫ and mouse clicks.
final class PanelController: NSObject, NSWindowDelegate {
    var onChoose: ((ClipItem, NSRunningApplication?) -> Void)?
    var onRemove: ((ClipItem) -> Void)?
    var isVisible: Bool { panel.isVisible && model.presented }

    private let panel: KeyPanel
    private let model = PanelModel()
    private var targetApp: NSRunningApplication?

    override init() {
        panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: true)
        super.init()
        panel.isFloatingPanel = true
        panel.level = .popUpMenu // above the menu bar and Dock
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.delegate = self
        panel.onKeyDown = { [weak self] event in self?.handleKey(event) ?? false }
        panel.contentView = NSHostingView(rootView: OverlayView(
            model: model,
            choose: { [weak self] index in self?.choose(index) },
            dismiss: { [weak self] in self?.hide(animated: true) }))
    }

    func show(items: [ClipItem]) {
        targetApp = NSWorkspace.shared.frontmostApplication
        // The screen you're working on: the one with the mouse.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]

        model.items = items
        model.selected = 0
        model.bottomInset = screen.visibleFrame.minY - screen.frame.minY
        model.mouseAtOpen = mouse
        model.presented = false

        panel.setFrame(screen.frame, display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
        DispatchQueue.main.async {
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.84)) {
                self.model.presented = true
            }
        }
    }

    /// Animated for cancel; instant after choosing a clip so the paste lands immediately.
    func hide(animated: Bool = false) {
        guard panel.isVisible else { return }
        guard animated else {
            model.presented = false
            panel.orderOut(nil)
            return
        }
        withAnimation(.easeIn(duration: 0.14)) { model.presented = false }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.model.presented else { return } // reopened meanwhile
            self.panel.orderOut(nil)
        })
    }

    /// Pressing the shortcut again while the list is open moves down one row.
    func selectNext() {
        move(1)
    }

    /// Testing aid: renders the overlay's content (without the live blur) to a PNG.
    func snapshot(to url: URL) {
        guard let view = panel.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide(animated: true) // switched apps or spaces
    }

    // MARK: - Keys

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 125, 48: move(1)                // ↓, ⇥
        case 126: move(-1)                   // ↑
        case 36, 76: choose(model.selected)  // ↩, keypad enter
        case 53: hide(animated: true)        // ⎋
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
        withAnimation(.easeOut(duration: 0.15)) {
            let item = model.items.remove(at: model.selected)
            model.selected = min(model.selected, max(0, model.items.count - 1))
            onRemove?(item)
        }
    }
}

// MARK: - Views

/// Full-screen light frost with the clip card at the bottom center.
struct OverlayView: View {
    @ObservedObject var model: PanelModel
    var choose: (Int) -> Void
    var dismiss: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            // A light frost: the blur is faded so the screen stays recognizable behind it.
            VisualEffect(material: .fullScreenUI, alpha: 0.75)
            // Clicking anywhere outside the card closes it.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)
            ClipCard(model: model, choose: choose)
                .padding(.bottom, model.bottomInset + 56)
                .offset(y: model.presented ? 0 : 220)
                .opacity(model.presented ? 1 : 0)
        }
        .ignoresSafeArea()
    }
}

/// Just the clips: number, text. Nothing else.
struct ClipCard: View {
    @ObservedObject var model: PanelModel
    var choose: (Int) -> Void

    static let width: CGFloat = 520
    /// At most this many rows are on screen; the rest scroll into view as you move down.
    static let visibleRows = 3
    static let rowSpacing: CGFloat = 2
    private let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    private var listHeight: CGFloat {
        let rows = CGFloat(min(model.items.count, Self.visibleRows))
        return rows * ClipRow.height + max(rows - 1, 0) * Self.rowSpacing
    }

    var body: some View {
        Group {
            if model.items.isEmpty {
                Text("Nothing copied yet")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 40)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(spacing: Self.rowSpacing) {
                            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                                ClipRow(index: index, item: item, selected: index == model.selected)
                                    .id(index)
                                    .onContinuousHover { phase in
                                        if case .active = phase, model.mouseHasMoved, model.selected != index {
                                            model.selected = index
                                        }
                                    }
                                    .onTapGesture { choose(index) }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                    .frame(height: listHeight)
                    // Keep the highlighted row on screen: scroll just enough as you move past the edge.
                    .onChange(of: model.selected) { selected in
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(selected) }
                    }
                    .onChange(of: model.presented) { presented in
                        if presented { proxy.scrollTo(0, anchor: .top) }
                    }
                }
            }
        }
        .padding(6)
        .frame(width: Self.width)
        .background(VisualEffect(material: .popover))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 30, y: 12)
    }
}

struct ClipRow: View {
    static let height: CGFloat = 40

    let index: Int
    let item: ClipItem
    let selected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text(index < 10 ? "\((index + 1) % 10)" : "")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(selected ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                .frame(width: 10)
            Text(item.preview(maxLength: 90))
                .font(.system(size: 14))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: Self.height)
        // A soft neutral highlight instead of the system accent blue.
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(selected ? 0.08 : 0)))
        .contentShape(Rectangle())
    }
}

/// Native blur material. Kept active even though ClipStack is never the frontmost app.
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var alpha: CGFloat = 1

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.alphaValue = alpha
    }
}
