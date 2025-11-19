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

    init() {
        self.youtrackAuthToken = UserDefaults.standard.string(forKey: "youtrackAuthToken") ?? ""
    }

    /// Clears the token
    func clear() {
        youtrackAuthToken = ""
        UserDefaults.standard.removeObject(forKey: "youtrackAuthToken")
    }
}
