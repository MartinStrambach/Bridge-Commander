//
//  BridgeCommanderApp.swift
//  Bridge Commander
//
//  Main application entry point for Bridge Commander
//

import SwiftUI

@main
struct BridgeCommanderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
