import Foundation
import SwiftUI
import UIKit

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @AppStorage("appearanceMode") var appearanceModeRaw: String = AppearanceMode.system.rawValue
    @AppStorage("notificationSettings") private var notificationSettingsData: Data = Data()

    @AppStorage("appleIntelligenceEnabled") var appleIntelligenceEnabled: Bool = false
    @AppStorage("translateCommentsEnabled") var translateCommentsEnabled: Bool = true

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
