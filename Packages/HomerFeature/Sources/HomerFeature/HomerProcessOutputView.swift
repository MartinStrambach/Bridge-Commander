import AppKit
import AppUI
import ComposableArchitecture
import SwiftUI

/// One command's output in a sheet over the process page (`view-artifact-dialog.tsx`):
/// stdout or stderr, a Claude command's stdout as the conversation or raw, live while it runs.
struct HomerProcessOutputView: View {
	@Bindable
	var store: StoreOf<HomerProcessOutputReducer>

	@Environment(\.dismiss)
	private var dismiss

	var body: some View {
		VStack(spacing: 0) {
			header
			Divider()
			content
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.frame(minWidth: 760, idealWidth: 1000, minHeight: 520, idealHeight: 760)
		.task { store.send(.task) }
	}

	private var header: some View {
		HStack(spacing: 10) {
			Text(store.isLiveCommand ? "Live Output — Command \(store.executionIndex)" : "Output — Command \(store.executionIndex)")
				.scaledFont(.headline)

			Picker("Stream", selection: $store.stream) {
				ForEach(HomerOutputStream.allCases, id: \.self) { stream in
					Text(stream.title).tag(stream)
				}
			}
			.pickerStyle(.segmented)
			.labelsHidden()
			.fixedSize()

			if let path = store.path {
				Text(HomerArtifactPath.fileName(path))
					.scaledFont(.callout, design: .monospaced)
					.foregroundStyle(.secondary)
			}
			if store.output.hasLoaded, !store.output.isComplete {
				HomerLiveBadge()
			}
			if store.output.isLoading {
				ProgressView()
					.controlSize(.small)
			}

			Spacer()

			if store.output.transcript.isClaude {
				Picker("View", selection: Binding(
					get: { store.effectiveMode },
					set: { store.send(.binding(.set(\.mode, $0))) }
				)) {
					Text("Claude").tag(HomerProcessOutputReducer.Mode.conversation)
					Text("Raw").tag(HomerProcessOutputReducer.Mode.raw)
				}
				.pickerStyle(.segmented)
				.labelsHidden()
				.fixedSize()
			}

			Button {
				store.send(.refreshTapped)
			} label: {
				Label("Refresh", systemImage: "arrow.clockwise")
			}
			.buttonStyle(.scaledBordered)
			.disabled(store.path == nil || store.output.isLoading)

			Button("Done") { dismiss() }
				.buttonStyle(.scaledBorderedProminent)
				.keyboardShortcut(.cancelAction)
		}
		.padding(12)
	}

	@ViewBuilder
	private var content: some View {
		let output = store.output
		if store.path == nil {
			placeholder("No \(store.stream.title.lowercased()) for this command")
		}
		else if !output.hasLoaded {
			if let error = output.error {
				placeholder("Failed to load the output: \(error)", isError: true)
			}
			else {
				ProgressView("Loading output…")
			}
		}
		else {
			VStack(spacing: 0) {
				if let error = output.error {
					HomerErrorBanner(message: error)
					Divider()
				}
				if output.text.isEmpty {
					placeholder(output.isComplete ? "The file is empty" : "Waiting for output…")
						.frame(maxHeight: .infinity)
				}
				else if store.effectiveMode == .conversation, output.transcript.isClaude {
					HomerClaudeTranscriptView(
						transcript: output.transcript,
						isLive: !output.isComplete,
						commandStart: store.commandStart
					)
				}
				else {
					HomerLogTextView(text: output.text, followsEnd: !output.isComplete)
				}
			}
		}
	}

	private func placeholder(_ text: String, isError: Bool = false) -> some View {
		Text(text)
			.scaledFont(.callout)
			.foregroundStyle(isError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
			.textSelection(.enabled)
			.padding()
	}
}

struct HomerLiveBadge: View {
	var body: some View {
		Text("Live")
			.scaledFont(.caption)
			.fontWeight(.semibold)
			.padding(.horizontal, 6)
			.padding(.vertical, 1)
			.background(Color.secondary.opacity(0.18), in: Capsule())
	}
}

// MARK: - Raw text

/// A log as plain monospaced text, in an `NSTextView`: a command's output runs to megabytes,
/// which a SwiftUI `Text` lays out all at once on every change. Text the live tail adds is
/// appended rather than set again, and the view follows the end while it is at the end.
struct HomerLogTextView: NSViewRepresentable {
	let text: String
	/// Keep the newest line in view as text arrives — unless the user scrolled up.
	let followsEnd: Bool

	@Environment(\.uiFontScale)
	private var scale

	func makeNSView(context: Context) -> NSScrollView {
		let scrollView = NSTextView.scrollableTextView()
		scrollView.hasHorizontalScroller = false
		scrollView.borderType = .noBorder
		if let textView = scrollView.documentView as? NSTextView {
			textView.isEditable = false
			textView.isSelectable = true
			textView.isRichText = false
			textView.usesFindBar = true
			textView.isIncrementalSearchingEnabled = true
			textView.textContainerInset = NSSize(width: 8, height: 8)
			textView.drawsBackground = true
			textView.backgroundColor = .textBackgroundColor
		}
		return scrollView
	}

	func updateNSView(_ scrollView: NSScrollView, context: Context) {
		guard let textView = scrollView.documentView as? NSTextView, let storage = textView.textStorage else {
			return
		}
		let font = NSFont.monospacedSystemFont(ofSize: UIFontScale.pointSize(of: .callout) * scale, weight: .regular)
		let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.textColor]
		let coordinator = context.coordinator
		let wasAtEnd = isScrolledToEnd(scrollView)

		if coordinator.font != font {
			coordinator.font = font
			storage.setAttributedString(NSAttributedString(string: text, attributes: attributes))
		}
		else if text.utf8.starts(with: coordinator.text.utf8) {
			// Byte-wise: `count` and `hasPrefix` walk characters, slow on a long log.
			let added = text.utf8.dropFirst(coordinator.text.utf8.count)
			if !added.isEmpty {
				storage.append(NSAttributedString(string: String(decoding: added, as: UTF8.self), attributes: attributes))
			}
		}
		else {
			storage.setAttributedString(NSAttributedString(string: text, attributes: attributes))
		}
		coordinator.text = text

		if followsEnd, wasAtEnd {
			textView.scrollToEndOfDocument(nil)
		}
	}

	func makeCoordinator() -> Coordinator {
		Coordinator()
	}

	private func isScrolledToEnd(_ scrollView: NSScrollView) -> Bool {
		guard let documentView = scrollView.documentView else {
			return true
		}
		let visible = scrollView.contentView.documentVisibleRect
		return visible.maxY >= documentView.bounds.maxY - 24
	}

	final class Coordinator {
		var text = ""
		var font: NSFont?
	}
}

// MARK: - Claude conversation

/// A Claude command's stdout as the conversation (`claude-artifact-view.tsx`): a summary of
/// the run — or, while it runs, a live header — then Claude's messages and tool calls, each
/// call folded to one line until opened. Only the last message is shown in full.
///
/// A `List`, not a lazy stack in a scroll view: a long conversation inside a sheet would hand
/// the sheet an ever-changing ideal height (AppUI's README).
struct HomerClaudeTranscriptView: View {
	let transcript: HomerClaudeTranscript
	let isLive: Bool
	let commandStart: Double?

	private static let bottomID = "bottom"

	var body: some View {
		ScrollViewReader { proxy in
			List {
				Group {
					if isLive, transcript.outcome == nil {
						liveHeader
					}
					else {
						summary
					}
				}
				.listRowSeparator(.hidden)

				ForEach(Array(transcript.items.enumerated()), id: \.element.id) { index, item in
					row(item, isLastMessage: index == transcript.lastMessageIndex)
						.listRowSeparator(.hidden)
				}

				Color.clear
					.frame(height: 1)
					.id(Self.bottomID)
					.listRowSeparator(.hidden)
			}
			.listStyle(.plain)
			.onChange(of: transcript.items.count) {
				if isLive {
					proxy.scrollTo(Self.bottomID, anchor: .bottom)
				}
			}
		}
	}

	@ViewBuilder
	private func row(_ item: HomerClaudeTranscript.Item, isLastMessage: Bool) -> some View {
		switch item {
		case let .message(_, text):
			if isLastMessage {
				VStack(alignment: .leading, spacing: 3) {
					Text("Claude")
						.scaledFont(.caption)
						.fontWeight(.medium)
						.foregroundStyle(.secondary)
					Text(text)
						.scaledFont(.body)
						.textSelection(.enabled)
						.fixedSize(horizontal: false, vertical: true)
				}
				.padding(.vertical, 4)
			}
			else {
				HomerTranscriptBlock(
					title: "Claude message",
					titleColor: .secondary,
					preview: String(text.prefix(100)),
					isRunning: false
				) {
					blockText(text, color: .primary)
				}
			}
		case let .tool(tool):
			HomerTranscriptBlock(
				title: tool.name,
				titleColor: .blue,
				preview: tool.inputPreview,
				isRunning: isLive && tool.id == transcript.inflightToolID
			) {
				VStack(alignment: .leading, spacing: 8) {
					VStack(alignment: .leading, spacing: 3) {
						caption("Input")
						blockText(tool.input, color: .primary)
					}
					if let result = tool.result {
						Divider()
						VStack(alignment: .leading, spacing: 3) {
							caption("Result")
							blockText(result, color: .green)
						}
					}
				}
			}
		}
	}

	private func caption(_ text: String) -> some View {
		Text(text)
			.scaledFont(.caption)
			.foregroundStyle(.secondary)
	}

	private func blockText(_ text: String, color: Color) -> some View {
		// Tool results can be whole files; past this the raw view is the place to read them.
		let limit = 20000
		let shown = text.count > limit ? String(text.prefix(limit)) + "\n… (\(text.count - limit) more characters — see Raw)" : text
		return Text(shown)
			.scaledFont(.caption, design: .monospaced)
			.foregroundStyle(color)
			.textSelection(.enabled)
			.fixedSize(horizontal: false, vertical: true)
			.frame(maxWidth: .infinity, alignment: .leading)
	}

	private var summary: some View {
		HomerFlowLayout(spacing: 16) {
			if let model = transcript.model {
				Text(model)
					.scaledFont(.caption, design: .monospaced)
					.foregroundStyle(.secondary)
			}
			if let outcome = transcript.outcome {
				Text(outcome.isError ? "error" : "success")
					.scaledFont(.caption)
					.fontWeight(.semibold)
					.foregroundStyle(.white)
					.padding(.horizontal, 6)
					.padding(.vertical, 1)
					.background(outcome.isError ? Color.red : Color.secondary, in: Capsule())
				metric("cost", HomerFormat.cost(outcome.costUsd))
				metric("tokens", Self.tokens(outcome))
				metric(
					"duration",
					"\(Self.seconds(outcome.durationMs)) (api \(Self.seconds(outcome.apiDurationMs)))"
				)
				metric("turns", "\(outcome.turns)")
			}
		}
		.padding(10)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
	}

	private var liveHeader: some View {
		TimelineView(.periodic(from: .now, by: 1)) { context in
			HomerFlowLayout(spacing: 16) {
				HomerLiveBadge()
				if let model = transcript.model {
					Text(model)
						.scaledFont(.caption, design: .monospaced)
						.foregroundStyle(.secondary)
				}
				if transcript.turns > 0 {
					Text("turn \(transcript.turns)")
						.scaledFont(.caption)
						.fontWeight(.medium)
				}
				if let commandStart {
					let elapsed = max(0, Int(context.date.timeIntervalSince1970) - Int(commandStart))
					metric("elapsed", String(format: "%d:%02d", elapsed / 60, elapsed % 60))
				}
				if let usage = transcript.runningUsage {
					metric("~", "\(usage.input.formatted()) in / \(usage.output.formatted()) out (running)")
				}
			}
		}
		.padding(10)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
	}

	private func metric(_ name: String, _ value: String) -> some View {
		Text("\(Text(name).foregroundStyle(.secondary)) \(Text(value).fontWeight(.medium))")
			.scaledFont(.caption)
	}

	private static func seconds(_ milliseconds: Double) -> String {
		String(format: "%.1fs", milliseconds / 1000)
	}

	private static func tokens(_ outcome: HomerClaudeTranscript.Outcome) -> String {
		var text = "in \(outcome.inputTokens.formatted()) / out \(outcome.outputTokens.formatted())"
		if outcome.cacheReadTokens > 0 {
			text += " / cache↑ \(outcome.cacheReadTokens.formatted())"
		}
		if outcome.cacheCreationTokens > 0 {
			text += " / cache+ \(outcome.cacheCreationTokens.formatted())"
		}
		return text
	}
}

/// A folded block of the conversation: one line with its title and a preview, opened in place.
struct HomerTranscriptBlock<Content: View>: View {
	let title: String
	let titleColor: Color
	let preview: String
	let isRunning: Bool
	@ViewBuilder
	let content: () -> Content

	@State
	private var isExpanded = false

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			Button {
				isExpanded.toggle()
			} label: {
				HStack(spacing: 6) {
					Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
						.scaledFont(.caption2)
						.foregroundStyle(.secondary)
						.frame(width: 10)
					Text(title)
						.scaledFont(.caption, design: .monospaced)
						.fontWeight(.semibold)
						.foregroundStyle(titleColor)
					if isRunning {
						ProgressView()
							.controlSize(.mini)
							.help("Tool running")
					}
					if !isExpanded {
						Text(preview)
							.scaledFont(.caption, design: .monospaced)
							.foregroundStyle(.secondary)
							.lineLimit(1)
							.truncationMode(.tail)
					}
					Spacer(minLength: 0)
				}
				.padding(.horizontal, 10)
				.padding(.vertical, 6)
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)

			if isExpanded {
				Divider()
				content()
					.padding(10)
			}
		}
		.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
		.overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.25)))
	}
}
