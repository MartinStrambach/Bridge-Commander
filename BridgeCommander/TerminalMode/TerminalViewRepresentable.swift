// BridgeCommander/TerminalMode/TerminalViewRepresentable.swift
import AppKit
import SwiftUI
import SwiftTerm

struct TerminalViewRepresentable: NSViewRepresentable {
    let terminalView: LocalProcessTerminalView

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        terminalView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // Nothing to update — the terminal manages itself
    }
}
