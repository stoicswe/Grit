import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @AppStorage("appearanceMode") var appearanceModeRaw: String = AppearanceMode.system.rawValue
    @AppStorage("notificationSettings") private var notificationSettingsData: Data = Data()
    @AppStorage("subscribedProjects") private var subscribedProjectsData: Data = Data()

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

    var subscribedProjectIDs: Set<Int> {
        get {
            (try? JSONDecoder().decode(Set<Int>.self, from: subscribedProjectsData)) ?? []
        }
        set {
            subscribedProjectsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    func toggleProjectSubscription(_ projectID: Int) {
        var ids = subscribedProjectIDs
        if ids.contains(projectID) {
            ids.remove(projectID)
        } else {
            ids.insert(projectID)
        }
        subscribedProjectIDs = ids
    }

    func isSubscribed(to projectID: Int) -> Bool {
        subscribedProjectIDs.contains(projectID)
    }

    private init() {}
}

enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}
