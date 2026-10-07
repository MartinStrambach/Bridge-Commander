import AppKit
import AppUI
import ComposableArchitecture
import SwiftUI

/// The console's Continuations page (`app/(dashboard)/continuations/page.tsx`): the pending
/// continuations, then — only when there are any — those that failed to fire, each a card as in
/// `components/continuations/continuation-item.tsx`. A run number opens that run's web console
/// page.
struct HomerContinuationsView: View {
	@Bindable
	var store: StoreOf<HomerContinuationsReducer>

	var body: some View {
		VStack(spacing: 0) {
			if let error = store.loadError {
				HomerErrorBanner(message: error)
				Divider()
			}
			content
		}
		.alert($store.scope(\.$alert, action: \.alert))
	}

	@ViewBuilder
	private var content: some View {
		if !store.hasLoaded {
			ProgressView("Loading continuations…")
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		else if store.pending.isEmpty, store.failed.isEmpty {
			EmptyStateView(
				title: "No Pending Continuations",
				systemImage: "point.3.connected.trianglepath.dotted",
				description: "Parked workflows waiting on a watched run to finish before starting a follow-up agent show up here."
			)
		}
		else {
			// A plain stack, like the questions: a handful of cards, each with links and a button.
			ScrollView {
				VStack(alignment: .leading, spacing: 20) {
					section(
						"Continuations",
						description: "Parked workflows waiting on a watched run to finish before starting a follow-up agent"
					) {
						if store.pending.isEmpty {
							Text("No pending continuations.")
								.scaledFont(.callout)
								.foregroundStyle(.secondary)
						}
						else {
							ForEach(store.pending) { continuation in
								HomerContinuationCard(store: store, continuation: continuation)
							}
						}
					}

					if !store.failed.isEmpty {
						section(
							"Failed to fire",
							description: "Continuations that never started their follow-up agent, with the reason"
						) {
							ForEach(store.failed) { continuation in
								HomerContinuationCard(store: store, continuation: continuation)
							}
						}
					}
				}
				.padding()
			}
		}
	}

	private func section(
		_ title: String,
		description: String,
		@ViewBuilder content: () -> some View
	) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			VStack(alignment: .leading, spacing: 2) {
				Text(title)
					.scaledFont(.title3)
					.fontWeight(.semibold)
				Text(description)
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
			}
			content()
		}
	}
}

struct HomerContinuationCard: View {
	let store: StoreOf<HomerContinuationsReducer>
	let continuation: HomerContinuation

	private var isCancelling: Bool {
		store.cancellingIDs.contains(continuation.id)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 8) {
				HomerContinuationStatusBadge(status: continuation.status)
				Text(HomerFormat.timestamp(continuation.createdAt))
					.scaledFont(.caption, design: .monospaced)
					.foregroundStyle(.secondary)
					.help("Created")
				Spacer()
			}

			Text(sentence)
				.scaledFont(.body)
				.fixedSize(horizontal: false, vertical: true)

			Text(origin)
				.scaledFont(.callout)
				.foregroundStyle(.secondary)

			if let started {
				Text(started)
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
			}

			if continuation.status == .failed {
				Text("Continuation failed: \(continuation.error ?? "")")
					.scaledFont(.callout)
					.foregroundStyle(.red)
					.textSelection(.enabled)
					.fixedSize(horizontal: false, vertical: true)
			}

			if continuation.isCancellable, let expiresAt = continuation.expiresAt {
				Text("Expires \(HomerFormat.timestamp(expiresAt)).")
					.scaledFont(.caption)
					.foregroundStyle(.secondary)
			}

			if continuation.isCancellable {
				HStack {
					if let error = store.cancelErrors[continuation.id] {
						Text(error)
							.scaledFont(.callout)
							.foregroundStyle(.red)
							.fixedSize(horizontal: false, vertical: true)
					}
					Spacer()
					if isCancelling {
						ProgressView()
							.controlSize(.small)
					}
					Button("Cancel Continuation", role: .destructive) {
						store.send(.cancelTapped(id: continuation.id))
					}
					.buttonStyle(.scaledBordered)
					.controlSize(.small)
					.tint(.red)
					.disabled(isCancelling)
					.help("Stop \(continuation.agentName) from starting when run #\(continuation.watchedProcessId) finishes")
				}
			}
		}
		.padding(14)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
		.overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.3)))
		// Settled continuations read as done, as in the console.
		.opacity(continuation.status == .pending ? 1 : 0.8)
		.environment(\.openURL, OpenURLAction { url in
			guard let processId = Self.processId(from: url) else {
				return .systemAction
			}
			store.send(.processTapped(processId: processId))
			return .handled
		})
		.contextMenu {
			contextMenu
		}
	}

	// MARK: - Text

	/// "When watched run #12 finishes, start **follow-up**." The run numbers are links the
	/// card's `openURL` action turns into `processTapped`, so the sentence wraps as one text.
	private var sentence: AttributedString {
		var text = AttributedString("When watched run ")
		text += Self.runLink(continuation.watchedProcessId)
		text += AttributedString(" finishes, start ")
		text += Self.emphasized(continuation.agentName)
		text += AttributedString(".")
		return text
	}

	/// "Origin: **starter** (#7)"
	private var origin: AttributedString {
		var text = AttributedString("Origin: ")
		text += Self.emphasized(continuation.originAgentName)
		text += AttributedString(" (")
		text += Self.runLink(continuation.originProcessId)
		text += AttributedString(")")
		return text
	}

	/// "Started run #99 07.10.26 18:52:55." — a dispatched continuation's run.
	private var started: AttributedString? {
		guard continuation.status == .dispatched, let firedProcessId = continuation.firedProcessId else {
			return nil
		}
		var text = AttributedString("Started run ")
		text += Self.runLink(firedProcessId)
		if let firedAt = continuation.firedAt {
			text += AttributedString("  \(HomerFormat.timestamp(firedAt))")
		}
		text += AttributedString(".")
		return text
	}

	private static func emphasized(_ string: String) -> AttributedString {
		var text = AttributedString(string)
		text.inlinePresentationIntent = .stronglyEmphasized
		return text
	}

	private static func runLink(_ processId: Int) -> AttributedString {
		var text = AttributedString("#\(processId)")
		text.link = processURL(processId)
		return text
	}

	/// A run number's link inside a card's text — never opened as a URL: the card's `openURL`
	/// action reads the id back with `processId(from:)`.
	nonisolated static func processURL(_ processId: Int) -> URL? {
		URL(string: "\(processLinkScheme):\(processId)")
	}

	nonisolated static func processId(from url: URL) -> Int? {
		guard url.scheme == processLinkScheme else {
			return nil
		}
		return Int(url.absoluteString.dropFirst(processLinkScheme.count + 1))
	}

	private nonisolated static let processLinkScheme = "homer-process"

	@ViewBuilder
	private var contextMenu: some View {
		Button {
			store.send(.processTapped(processId: continuation.watchedProcessId))
		} label: {
			Label("Open Watched Run #\(continuation.watchedProcessId)", systemImage: "eye")
		}
		Button {
			store.send(.processTapped(processId: continuation.originProcessId))
		} label: {
			Label("Open Origin Run #\(continuation.originProcessId)", systemImage: "arrow.turn.left.up")
		}
		if let firedProcessId = continuation.firedProcessId {
			Button {
				store.send(.processTapped(processId: firedProcessId))
			} label: {
				Label("Open Started Run #\(firedProcessId)", systemImage: "play")
			}
		}
		Divider()
		Button {
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(String(continuation.id), forType: .string)
		} label: {
			Label("Copy Continuation ID", systemImage: "doc.on.doc")
		}
		if continuation.isCancellable {
			Divider()
			Button(role: .destructive) {
				store.send(.cancelTapped(id: continuation.id))
			} label: {
				Label("Cancel Continuation…", systemImage: "xmark.octagon")
			}
			.disabled(isCancelling)
		}
	}
}

/// A continuation's status as the console's colored badge shows it.
struct HomerContinuationStatusBadge: View {
	let status: HomerContinuationStatus

	var body: some View {
		Text(status.title)
			.scaledFont(.caption)
			.fontWeight(.semibold)
			.foregroundStyle(.white)
			.padding(.horizontal, 7)
			.padding(.vertical, 2)
			.background(color, in: Capsule())
			.help("Continuation status: \(status.title)")
	}

	private var color: Color {
		switch status {
		case .pending:
			.orange
		case .dispatching:
			.blue
		case .dispatched:
			.green
		case .failed:
			.red
		case .cancelled, .expired, .unknown:
			.gray
		}
	}
}
