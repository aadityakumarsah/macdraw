import AppKit
import SwiftUI

/// App-wide light/dark theme. Persisted in UserDefaults and mirrored to the
/// app's NSAppearance so AppKit views + SwiftUI chrome (material, semantic
/// colors) follow the user's choice. The drawing toolbar stays pinned dark on
/// purpose (a floating HUD that must stay legible on any wallpaper), but the
/// canvas itself already supports light/dark through `canvasBackground`.
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published private(set) var theme: Theme = .dark

    enum Theme: String {
        case dark
        case light

        var appearance: NSAppearance {
            switch self {
            case .dark: return NSAppearance(named: .darkAqua) ?? NSAppearance.current
            case .light: return NSAppearance(named: .aqua) ?? NSAppearance.current
            }
        }

        var colorScheme: ColorScheme {
            self == .dark ? .dark : .light
        }
    }

    static let defaultsKey = "macdraw.themeMode"

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.defaultsKey)
        theme = stored == Theme.light.rawValue ? .light : .dark
        applyTheme()
    }

    /// Toggle light↔dark and persist. Everything themed observes `toggle`.
    func toggle() {
        theme = theme == .dark ? .light : .dark
        UserDefaults.standard.set(theme.rawValue, forKey: Self.defaultsKey)
        applyTheme()
    }

    /// Set a specific theme (used by sync bootstrap when the server
    /// preferences arrive).
    func set(_ newTheme: Theme) {
        guard theme != newTheme else { return }
        theme = newTheme
        UserDefaults.standard.set(theme.rawValue, forKey: Self.defaultsKey)
        applyTheme()
    }

    private func applyTheme() {
        // `NSApp.appearance` drives AppKit controls + NSHostingView material
        // defaults; the observable `theme` drives explicit SwiftUI tokens.
        NSApp.appearance = theme.appearance
    }
}