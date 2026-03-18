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

        terminalView.processDelegate = TerminalProcessDelegate(
            repositoryPath: session.repositoryPath,
            onFailed: { message in onStatusChange(session.repositoryPath, .failed(message)) }
        )

        terminalView.startProcess(
            executable: "/bin/zsh",
            args: ["-l"],
            environment: nil,
            execName: nil,
            currentDirectory: session.repositoryPath
        )

        onStatusChange(session.repositoryPath, .active)

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
    private let onFailed: @Sendable (String) -> Void

    init(repositoryPath: String, onFailed: @escaping @Sendable (String) -> Void) {
        self.repositoryPath = repositoryPath
        self.onFailed = onFailed
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async {
            self.onFailed("Terminal process exited (code \(exitCode ?? -1))")
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
}
