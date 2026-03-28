// BridgeCommander/TerminalMode/TerminalViewRepresentable.swift
import AppKit
import ComposableArchitecture
import SwiftTerm
import SwiftUI

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

	// MARK: - Coordinator

	/// Owns strong references to per-session TerminalProcessDelegate instances.
	/// SwiftUI manages the coordinator's lifetime — it lives as long as the representable
	/// is in the view hierarchy, ensuring delegates are released when the terminal panel closes.
	final class Coordinator {
		var processDelegates: [UUID: TerminalProcessDelegate] = [:]
	}

	let terminalViewStore: TerminalViewStore
	let sessions: IdentifiedArrayOf<TerminalSession>
	let activeSessionId: UUID?
	let onStatusChange: @Sendable (UUID, TerminalSessionStatus) -> Void

	func makeNSView(context: Context) -> NSView {
		NSView(frame: .zero)
	}

	func makeCoordinator() -> Coordinator {
		Coordinator()
	}

	func updateNSView(_ nsView: NSView, context: Context) {
		for session in sessions {
			switch session.status {
			case .active,
			     .launching,
			     .waitingForInput:
				let sessionId = session.id

				// Retrieve or create the process delegate, held strongly by the coordinator.
				// LocalProcessTerminalView.processDelegate is a weak var, so the coordinator
				// must own the strong reference for callbacks to fire.
				let delegate: TerminalProcessDelegate
				if let existing = context.coordinator.processDelegates[sessionId] {
					delegate = existing
				}
				else {
					let newDelegate = TerminalProcessDelegate(
						onFailed: { message in onStatusChange(sessionId, .failed(message)) }
					)
					context.coordinator.processDelegates[sessionId] = newDelegate
					delegate = newDelegate
				}

				let termView = terminalViewStore.view(
					for: session,
					processDelegate: delegate,
					onStatusChange: onStatusChange
				)
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
					if termView.window != nil {
						termView.window?.makeFirstResponder(termView)
					}
					else {
						DispatchQueue.main.async {
							termView.window?.makeFirstResponder(termView)
						}
					}
				}

			case .failed:
				break
			}
		}

		// Release delegates for sessions that are no longer present (killed or failed).
		let activeIds = Set(sessions.map(\.id))
		context.coordinator.processDelegates = context.coordinator
			.processDelegates
			.filter { activeIds.contains($0.key) }
	}

}
