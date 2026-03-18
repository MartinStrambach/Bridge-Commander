// BridgeCommander/TerminalMode/TerminalViewStore.swift
import AppKit
import Foundation
import Observation
import SwiftTerm

@MainActor
@Observable
final class TerminalViewStore {
    private var views: [String: LocalProcessTerminalView] = [:]

    /// Returns the existing terminal view for a session, or creates and starts a new one.
    func view(
        for session: TerminalSession,
        onStatusChange: @escaping @Sendable (String, TerminalSessionStatus) -> Void
    ) -> LocalProcessTerminalView {
        if let existing = views[session.repositoryPath] {
            return existing
        }

        let terminalView = LocalProcessTerminalView(frame: .zero)

        // Escape single quotes in path for shell safety
        let escapedPath = session.repositoryPath.replacingOccurrences(of: "'", with: "'\\''")

        terminalView.processDelegate = TerminalProcessDelegate(
            repositoryPath: session.repositoryPath,
            onConnected: { onStatusChange(session.repositoryPath, .active) },
            onFailed: { message in onStatusChange(session.repositoryPath, .failed(message)) }
        )

        terminalView.startProcess(
            executable: "/bin/zsh",
            args: ["-c", "cd '\(escapedPath)' && exec zsh"],
            environment: nil,
            execName: "zsh"
        )

        views[session.repositoryPath] = terminalView
        return terminalView
    }

    func removeSession(for repositoryPath: String) {
        views.removeValue(forKey: repositoryPath)
    }

    func killAll() {
        // Removing references lets ARC release LocalProcessTerminalView instances,
        // whose deinit cleans up the underlying PTY. The OS also reclaims child
        // processes when the app exits.
        views.removeAll()
    }
}

// MARK: - TerminalProcessDelegate

final class TerminalProcessDelegate: LocalProcessTerminalViewDelegate {
    private let repositoryPath: String
    private let onConnected: () -> Void
    private let onFailed: (String) -> Void
    private var hasConnected = false

    init(repositoryPath: String, onConnected: @escaping () -> Void, onFailed: @escaping (String) -> Void) {
        self.repositoryPath = repositoryPath
        self.onConnected = onConnected
        self.onFailed = onFailed
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        if !hasConnected {
            hasConnected = true
            DispatchQueue.main.async { self.onConnected() }
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        if !hasConnected {
            DispatchQueue.main.async {
                self.onFailed("Process exited with code \(exitCode ?? -1)")
            }
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
}
