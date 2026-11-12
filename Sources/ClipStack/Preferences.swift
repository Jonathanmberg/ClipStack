import Foundation
import ClipStackCore

/// User settings, saved in UserDefaults.
final class Preferences: ObservableObject {
    private let defaults: UserDefaults

    @Published var shortcut: Shortcut {
        didSet { defaults.set(try? JSONEncoder().encode(shortcut), forKey: "shortcut") }
    }
    @Published var paused: Bool {
        didSet { defaults.set(paused, forKey: "paused") }
    }

    var hasOnboarded: Bool {
        get { defaults.bool(forKey: "hasOnboarded") }
        set { defaults.set(newValue, forKey: "hasOnboarded") }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "shortcut"),
           let saved = try? JSONDecoder().decode(Shortcut.self, from: data), saved.isUsable {
            shortcut = saved
        } else {
            shortcut = .default
        }
        paused = defaults.bool(forKey: "paused")
    }
}
