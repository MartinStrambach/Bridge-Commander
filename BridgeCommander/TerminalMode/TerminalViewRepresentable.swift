// BridgeCommander/TerminalMode/TerminalViewRepresentable.swift
import AppKit
import ComposableArchitecture
import SwiftUI
import SwiftTerm

/// A single NSView container that hosts all terminal sessions as direct subviews.
///
/// All `LocalProcessTerminalView` instances live inside this one container and
/// are shown/hidden via `isHidden` rather than being added to and removed from
/// the view hierarchy. This prevents the intermediate zero-frame `setFrameSize`
/// call that otherwise fires when a view is re-parented, which would send a
/// SIGWINCH to the shell and cause zsh to clear the visible terminal output.
///
/// Auto Layout constraints pin each terminal view to the container's edges, so
/// the frame resolves from the container's correct bounds in one step.
struct TerminalContainerRepresentable: NSViewRepresentable {
    let terminalViewStore: TerminalViewStore
    let sessions: IdentifiedArrayOf<TerminalSession>
    let activeSessionId: UUID?
    let onStatusChange: @Sendable (UUID, TerminalSessionStatus) -> Void

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        for session in sessions {
            switch session.status {
            case .launching, .active, .waitingForInput:
                let termView = terminalViewStore.view(for: session, onStatusChange: onStatusChange)
                if termView.superview !== nsView {
                    termView.translatesAutoresizingMaskIntoConstraints = false
                    nsView.addSubview(termView)
                    NSLayoutConstraint.activate([
                        termView.topAnchor.constraint(equalTo: nsView.topAnchor),
                        termView.bottomAnchor.constraint(equalTo: nsView.bottomAnchor),
                        termView.leadingAnchor.constraint(equalTo: nsView.leadingAnchor),
                        termView.trailingAnchor.constraint(equalTo: nsView.trailingAnchor),
                    ])
                }
                let isActive = session.id == activeSessionId
                termView.isHidden = !isActive
                if isActive {
                    termView.window?.makeFirstResponder(termView)
                }
            case .failed:
                break
            }
        }
    }
}
