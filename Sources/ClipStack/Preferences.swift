import AppKit
import ClipStackCore

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, dark, light
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .dark: return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        }
    }
}

/// User settings, saved in UserDefaults.
final class Preferences: ObservableObject {
    private let defaults: UserDefaults

    @Published var shortcut: Shortcut {
        didSet { defaults.set(try? JSONEncoder().encode(shortcut), forKey: "shortcut") }
    }
    @Published var historyLimit: Int {
        didSet { defaults.set(historyLimit, forKey: "historyLimit") }
    }
    @Published var persistHistory: Bool {
        didSet { defaults.set(persistHistory, forKey: "persistHistory") }
    }
    @Published var paused: Bool {
        didSet { defaults.set(paused, forKey: "paused") }
    }
    @Published var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: "appearance") }
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
        let limit = defaults.integer(forKey: "historyLimit")
        historyLimit = ClipHistory.allowedLimits.contains(limit) ? limit : ClipHistory.defaultLimit
        persistHistory = defaults.object(forKey: "persistHistory") as? Bool ?? true
        paused = defaults.bool(forKey: "paused")
        appearance = AppearanceMode(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
    }
}
