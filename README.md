# ClipStack

**Your clipboard, one shortcut away.**

ClipStack is a free, open-source clipboard history for macOS. It sits quietly in your menu bar and remembers the last few things you copied. Press **⌃⌥V** in any app, pick a clip with the arrow keys, hit **↩**, and it's pasted right where you were typing.

```
┌──────────────────────────────────────┐
│ ClipStack                       ⌃⌥V  │
├──────────────────────────────────────┤
│ 1  hello@example.com                 │
│ 2  https://github.com/…           🔗 │
│ 3  npm install                       │
│ 4  Meeting notes for Thursday        │
│ 5  Hello, how are you?               │
├──────────────────────────────────────┤
│  ↑↓ choose   ↩ paste   esc close     │
└──────────────────────────────────────┘
```

No accounts. No cloud. No subscription. Your clips never leave your Mac.

## How it works

1. Copy things the way you always do (⌘C).
2. Press **⌃⌥V** (Control-Option-V) wherever you want to paste.
3. Choose a clip:
   - **↑ / ↓** (or press ⌃⌥V again) to move, **↩** to paste
   - **1–9, 0** to paste that row instantly
   - or click it with the mouse
4. **Esc** closes the list without changing anything. **⌫** removes the highlighted clip from history.

Normal ⌘C, ⌘X and ⌘V keep working exactly as before. The shortcut can be changed in Settings.

## Install

1. Download **ClipStack.dmg** from the [latest release](https://github.com/Jonathanmberg/clipstack/releases/latest).
2. Open it and drag **ClipStack** into **Applications**.
3. Launch ClipStack. Its icon appears in the menu bar.
4. When asked, allow ClipStack under **System Settings → Privacy & Security → Accessibility**.

No Xcode, Homebrew or developer tools needed. Requires macOS 13 Ventura or later; runs natively on Apple Silicon and Intel.

> If a release isn't notarized yet, macOS will say it can't verify the developer. Right-click ClipStack in Applications → **Open** → **Open** once.

### Why Accessibility?

ClipStack uses it for exactly two things: pressing ⌘V for you in the app you were typing in, and finding your text cursor so the list opens next to it. It does **not** log keystrokes — the shortcut is registered with macOS's standard hot-key API, which only reports that one key combination.

Without the permission ClipStack still works: choosing a clip copies it, and you press ⌘V yourself.

## Menu bar

Click the ClipStack icon to see recent clips (click one to copy it), pause collecting, clear history, toggle launch at login, or open Settings.

## Settings

| | |
|---|---|
| **Shortcut** | Any combination with ⌘, ⌥ or ⌃. Default ⌃⌥V. |
| **History** | Keep the last 5 (default), 10, 20 or 50 clips. |
| **Remember after restart** | Turn off to keep history in memory only; the saved file is deleted. |
| **Pause collecting** | While paused, ClipStack doesn't read the clipboard at all. |
| **Appearance** | System, Dark or Light popup. |
| **Launch at login** | Start ClipStack automatically. |

## Privacy

- Clipboard contents stay on your Mac. ClipStack makes **no network requests** — no analytics, telemetry, accounts, sync or ads.
- History is saved to `~/Library/Application Support/ClipStack/history.json`, readable only by your user account (file mode 600). Turn off *Remember clips after restart* to never write it.
- Clear history at any time from the menu bar or Settings.
- ClipStack skips clips that apps mark as concealed or transient using the [nspasteboard.org](http://nspasteboard.org) conventions (used by 1Password and other password managers), and skips copied files. It **cannot** recognize a password you copied from somewhere that doesn't set those markers — pause collecting or remove the clip with ⌫ if that matters.
- Only plain text and links are recorded. Images and files are ignored.

## Build from source

Requires Xcode 15+ (Swift 5.9+).

```bash
git clone https://github.com/Jonathanmberg/clipstack.git
cd clipstack
swift test        # unit tests
./build.sh        # → dist/ClipStack.app and dist/ClipStack.dmg (universal)
```

`swift run ClipStack --data-dir /tmp/clipstack-dev` runs a development copy whose history and settings are kept separate from your real ones.

Note: local builds are ad-hoc signed, so macOS treats every rebuild as a new app and you'll need to re-allow Accessibility after rebuilding.

### Releases

Pushing a tag like `v0.1.0` runs [`.github/workflows/release.yml`](.github/workflows/release.yml), which tests, builds the universal DMG and attaches it to a GitHub Release. Add the Developer ID certificate and Apple notarization secrets listed at the top of that file to get a signed, notarized build (requires an Apple Developer Program membership).

### Project layout

```
Sources/ClipStackCore/   history, clip and shortcut models (no UI, unit-tested)
Sources/ClipStack/       the menu bar app
  AppDelegate.swift        wiring, menu bar, settings window
  ClipboardMonitor.swift   watches the clipboard (changeCount polling)
  HotKey.swift             global shortcut (Carbon RegisterEventHotKey)
  ClipPanel.swift          the floating list (NSPanel + SwiftUI)
  Paster.swift             copy + synthetic ⌘V, text-cursor lookup
  SettingsView.swift       settings + shortcut recorder
  Preferences.swift        UserDefaults-backed settings
Tests/                   XCTest suite for ClipStackCore
```

## Roadmap

- Homebrew cask: `brew install --cask clipstack`
- Optional search when the list is larger
- Image clips

## License

[MIT](LICENSE) © 2026 Jonathan Berg
