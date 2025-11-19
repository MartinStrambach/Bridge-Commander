//
//  BridgeCommanderApp.swift
//  Bridge Commander
//
//  Main application entry point for Bridge Commander
//

import SwiftUI

@main
struct BridgeCommanderApp: App {
    @StateObject private var appSettings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appSettings)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Settings {
            SettingsView(settings: appSettings)
        }
    }
}
