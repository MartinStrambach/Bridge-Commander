//
//  AppSettings.swift
//  Bridge Commander
//
//  Application settings stored in UserDefaults
//

import Foundation
import Combine

class AppSettings: ObservableObject {
    @Published var youtrackAuthToken: String {
        didSet {
            UserDefaults.standard.set(youtrackAuthToken, forKey: "youtrackAuthToken")
        }
    }

    @Published var periodicRefreshInterval: PeriodicRefreshInterval {
        didSet {
            UserDefaults.standard.set(periodicRefreshInterval.rawValue, forKey: "periodicRefreshInterval")
        }
    }

    init() {
        self.youtrackAuthToken = UserDefaults.standard.string(forKey: "youtrackAuthToken") ?? ""
        let savedInterval = UserDefaults.standard.double(forKey: "periodicRefreshInterval")
		self.periodicRefreshInterval = if savedInterval > 0 {
			PeriodicRefreshInterval(rawValue: savedInterval) ?? .fiveMinutes
		} else {
			.fiveMinutes
		}
    }

    /// Clears the token
    func clear() {
        youtrackAuthToken = ""
        UserDefaults.standard.removeObject(forKey: "youtrackAuthToken")
    }
}

enum PeriodicRefreshInterval: Double, CaseIterable {
    case tenSeconds = 10
    case oneMinute = 60
    case threeMinutes = 180
    case fiveMinutes = 300
    case tenMinutes = 600
    case fifteenMinutes = 900
    case thirtyMinutes = 1800

    var displayName: String {
        switch self {
        case .tenSeconds:
            return "10 seconds"
        case .oneMinute:
            return "1 minute"
        case .threeMinutes:
            return "3 minutes"
        case .fiveMinutes:
            return "5 minutes"
        case .tenMinutes:
            return "10 minutes"
        case .fifteenMinutes:
            return "15 minutes"
        case .thirtyMinutes:
            return "30 minutes"
        }
    }

    var timeInterval: TimeInterval {
        return self.rawValue
    }
}
