import AppKit

/// The app icons a person can pick in Settings. Generalissimo is the one built into the app bundle.
///
/// macOS has no alternate app icons, so a pick changes the icon the running app shows (Dock, app switcher, Settings).
/// Finder keeps the bundle icon.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case posterLight
    case poster
    case posterDark
    case laurelLight
    case laurelOlive
    case laurelDark

    static let storageKey = "appearance.appIcon"
    static let fallback = AppIconChoice.poster

    var id: String { rawValue }

    var title: String {
        switch self {
        case .posterLight: "Morning Rally"
        case .poster: "Generalissimo"
        case .posterDark: "Night Shift"
        case .laurelLight: "State Portrait"
        case .laurelOlive: "Olive Branch"
        case .laurelDark: "Old Regime"
        }
    }

    /// The picker image in Assets.xcassets/AppIcons, with a dark variant.
    var imageName: String { "AppIcon-\(rawValue)" }

    static var current: AppIconChoice {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? fallback.rawValue
        return AppIconChoice(rawValue: raw) ?? fallback
    }

    /// Shows the saved icon. The built-in icon goes back to the bundle's, so macOS keeps drawing it as Liquid Glass.
    static func applyCurrent() {
        current.apply()
    }

    func apply() {
        NSApp.applicationIconImage = self == Self.fallback ? nil : NSImage(named: imageName)
    }
}
