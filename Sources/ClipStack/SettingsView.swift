import AppKit
import ServiceManagement
import SwiftUI
import ClipStackCore

/// State shown in the menu bar and settings that lives outside Preferences.
final class SystemState: ObservableObject {
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var shortcutTaken = false

    func refresh() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("ClipStack: launch at login failed: \(error.localizedDescription)")
        }
        refresh()
    }
}

/// The only setting: the shortcut that opens ClipStack.
struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var system: SystemState
    var recordingChanged: (Bool) -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent("Open ClipStack") {
                    HStack(spacing: 8) {
                        if prefs.shortcut != .default {
                            Button("Reset") { prefs.shortcut = .default }
                        }
                        ShortcutRecorder(shortcut: $prefs.shortcut, recordingChanged: recordingChanged)
                    }
                }
            } footer: {
                Group {
                    if system.shortcutTaken {
                        Text("Another app is already using \(prefs.shortcut.displayString). Pick a different shortcut.")
                            .foregroundStyle(.red)
                    } else {
                        Text("Click the shortcut, then press the keys you want. It needs ⌘, ⌥ or ⌃.")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Click, then press the new key combination. Esc cancels.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    var recordingChanged: (Bool) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Type a shortcut…" : shortcut.displayString) {
            recording ? stop() : start()
        }
        .frame(minWidth: 120)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        recordingChanged(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // esc
                stop()
                return nil
            }
            let candidate = Shortcut(event: event)
            if candidate.isUsable {
                shortcut = candidate
                stop()
            } else {
                NSSound.beep() // needs ⌘, ⌥ or ⌃
            }
            return nil
        }
    }

    private func stop() {
        guard recording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        recordingChanged(false)
    }
}
