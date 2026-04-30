import Foundation
import SwiftUI
import UIKit

// MARK: - Font Style

enum FontStyle: String, CaseIterable, Identifiable {
    case `default` = "Default"
    case serif     = "Serif"
    case dyslexic  = "Dyslexic"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var description: String {
        switch self {
        case .default:  return "SF Pro — the standard system font"
        case .serif:    return "New York — elegant serif for comfortable reading"
        case .dyslexic: return "Verdana — distinct letterforms that reduce letter confusion, designed for screen readability"
        }
    }

    var icon: String {
        switch self {
        case .default:  return "textformat"
        case .serif:    return "textformat.serif"
        case .dyslexic: return "textformat.alt"
        }
    }

    /// Used as a hint for `Font.Design`-based rendering (e.g. environment font fallback).
    var fontDesign: Font.Design {
        switch self {
        case .default:  return .default
        case .serif:    return .serif
        case .dyslexic: return .default   // Verdana is applied via custom name, not design
        }
    }

    /// The font to set at the app-root environment level.
    /// Views that don't specify an explicit font inherit this.
    var environmentFont: Font {
        switch self {
        case .default:  return .system(.body)
        case .serif:    return .system(.body, design: .serif)
        case .dyslexic: return Font.custom("Verdana", size: 17, relativeTo: .body)
        }
    }

    /// A fixed-size version used for in-settings previews.
    func previewFont(size: CGFloat = 20) -> Font {
        switch self {
        case .default:  return .system(size: size)
        case .serif:    return .system(size: size, design: .serif)
        case .dyslexic: return Font.custom("Verdana", size: size)
        }
    }
}

// MARK: - Text Size
// Stored as a Double (0–4, whole steps). Step 2 = "Default" — returns nil so
// the OS accessibility text-size setting is respected unchanged.
extension Double {
    /// Maps the slider step value to a DynamicTypeSize override.
    /// Returns nil at step 2 (Default) to preserve the user's system setting.
    var asDynamicTypeSize: DynamicTypeSize? {
        switch Int(self.rounded()) {
        case 0: return .small
        case 1: return .medium
        case 2: return nil          // Default — honour iOS accessibility setting
        case 3: return .xLarge
        case 4: return .xxLarge
        default: return nil
        }
    }

    /// Human-readable label for each slider step.
    var fontSizeLabel: String {
        switch Int(self.rounded()) {
        case 0: return "XS"
        case 1: return "S"
        case 2: return "Default"
        case 3: return "L"
        case 4: return "XL"
        default: return "Default"
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @AppStorage("appearanceMode") var appearanceModeRaw: String = AppearanceMode.system.rawValue
    @AppStorage("notificationSettings") private var notificationSettingsData: Data = Data()

    @AppStorage("appleIntelligenceEnabled") var appleIntelligenceEnabled:  Bool   = false
    @AppStorage("translateCommentsEnabled") var translateCommentsEnabled:  Bool   = true
    @AppStorage("hideTabBarLabels")         var hideTabBarLabels:          Bool   = false
    @AppStorage("markdownDefaultView")      var markdownDefaultViewRaw:    String = MarkdownDefaultView.source.rawValue

    var markdownDefaultView: MarkdownDefaultView {
        get { MarkdownDefaultView(rawValue: markdownDefaultViewRaw) ?? .source }
        set { markdownDefaultViewRaw = newValue.rawValue }
    }

    // MARK: Accessibility
    @AppStorage("fontStyle")    var fontStyleRaw:  String = FontStyle.default.rawValue
    /// Slider step 0–4; step 2 = Default (no OS override). See Double.asDynamicTypeSize.
    @AppStorage("fontSizeStep") var fontSizeStep:  Double = 2.0

    var fontStyle: FontStyle {
        get { FontStyle(rawValue: fontStyleRaw) ?? .default }
        set { fontStyleRaw = newValue.rawValue }
    }

    @AppStorage("accentColorR") private var accentColorR: Double = -1
    @AppStorage("accentColorG") private var accentColorG: Double = -1
    @AppStorage("accentColorB") private var accentColorB: Double = -1

    var accentColor: Color? {
        guard accentColorR != -1 else { return nil }
        return Color(red: accentColorR, green: accentColorG, blue: accentColorB)
    }

    func setAccentColor(_ color: Color?) {
        guard let color = color else {
            accentColorR = -1
            accentColorG = -1
            accentColorB = -1
            return
        }
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        accentColorR = Double(r)
        accentColorG = Double(g)
        accentColorB = Double(b)
    }

    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceModeRaw) ?? .system }
        set { appearanceModeRaw = newValue.rawValue }
    }

    var colorScheme: ColorScheme? {
        switch appearanceMode {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    var notificationSettings: NotificationSettings {
        get {
            (try? JSONDecoder().decode(NotificationSettings.self, from: notificationSettingsData))
                ?? NotificationSettings()
        }
        set {
            notificationSettingsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    private init() {}
}

enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}

// MARK: - Markdown View Preference

enum MarkdownDefaultView: String, CaseIterable {
    case source = "Source"
    case reader = "Reader"
}
