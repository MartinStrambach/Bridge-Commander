import AppUI
import ComposableArchitecture
import SwiftUI

/// The console's questions page: open questions, each answered with one of its options or a
/// typed answer (`components/questions/question-item.tsx`).
struct HomerQuestionListView: View {
	let store: StoreOf<HomerConsoleReducer>

	var body: some View {
		VStack(spacing: 0) {
			if let error = store.questionsError {
				HomerErrorBanner(message: error)
				Divider()
			}
			if !store.hasLoadedQuestions {
				ProgressView("Loading questions…")
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
			else if store.questions.isEmpty {
				EmptyStateView(
					title: "No Open Questions",
					systemImage: "checkmark.bubble",
					description: "Questions agents ask while they run show up here."
				)
			}
			else {
				// A plain stack: there are a handful of questions at most (Homer caps them per
				// process), and each card holds a text field, which a recycling list would not keep
				// focus in.
				ScrollView {
					VStack(spacing: 12) {
						ForEach(store.questions) { question in
							HomerQuestionCard(store: store, question: question)
						}
					}
					.padding()
				}
			}
		}
	}
}

struct HomerQuestionCard: View {
	let store: StoreOf<HomerConsoleReducer>
	let question: HomerQuestion

	private var isAnswering: Bool {
		store.answeringQuestionIDs.contains(question.id)
	}

	private var draft: Binding<String> {
		Binding(
			get: { store.answerDrafts[question.id] ?? "" },
			set: { store.send(.answerDraftChanged(questionId: question.id, text: $0)) }
		)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			header

			Text(Self.markdown(question.text))
				.scaledFont(.body)
				.textSelection(.enabled)
				.fixedSize(horizontal: false, vertical: true)

			if let dispatch = question.dispatch {
				Text("Answering will start **\(dispatch.agentName)**.")
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
			}

			if !question.options.isEmpty {
				HomerFlowLayout(spacing: 6) {
					ForEach(question.options, id: \.self) { option in
						Button(option) {
							store.send(.answerTapped(questionId: question.id, answer: option))
						}
						.buttonStyle(.scaledBordered)
					}
				}
			}

			HStack {
				TextField(question.options.isEmpty ? "Type an answer…" : "Or type an answer…", text: draft)
					.textFieldStyle(.roundedBorder)
					.onSubmit(submitDraft)
				Button("Send", action: submitDraft)
					.buttonStyle(.scaledBordered)
					.disabled(draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
				if isAnswering {
					ProgressView()
						.controlSize(.small)
				}
			}

			if let error = store.answerErrors[question.id] {
				Text(error)
					.scaledFont(.callout)
					.foregroundStyle(.red)
			}
		}
		.disabled(isAnswering)
		.padding(14)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
		.overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.5)))
	}

	private var header: some View {
		HStack(spacing: 8) {
			Text("Waiting for answer")
				.scaledFont(.caption)
				.fontWeight(.semibold)
				.foregroundStyle(.white)
				.padding(.horizontal, 7)
				.padding(.vertical, 2)
				.background(.orange, in: Capsule())

			Text(question.agentName)
				.scaledFont(.callout)
				.fontWeight(.semibold)

			Button {
				store.send(.processTapped(processId: question.processId))
			} label: {
				Text(verbatim: "#\(question.processId)")
					.scaledFont(.callout, design: .monospaced)
			}
			.buttonStyle(.link)
			.help("Open the process that asked")

			Spacer()

			Text(question.createdDate, format: .relative(presentation: .named))
				.scaledFont(.callout)
				.foregroundStyle(.secondary)
				.help(question.createdDate.formatted(date: .abbreviated, time: .standard))
		}
	}

	private func submitDraft() {
		store.send(.answerTapped(questionId: question.id, answer: draft.wrappedValue))
	}

	/// The question's Markdown, inline formatting only with its line breaks kept. Block syntax
	/// (lists, headings) shows as written, which still reads. Images never load: `Text` does not
	/// fetch them, which is the point — an agent-supplied image URL would otherwise beacon on
	/// view, the reason the console renders only their alt text.
	static func markdown(_ text: String) -> AttributedString {
		let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
		return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
	}
}

/// Lays its subviews out left to right, wrapping onto new lines — for a question's options,
/// which are as many as the agent offered.
struct HomerFlowLayout: Layout {
	var spacing: CGFloat

	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
		let rows = rows(for: subviews, width: proposal.width ?? .infinity)
		let width = rows.map(\.width).max() ?? 0
		let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
		return CGSize(width: width, height: height)
	}

	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
		var y = bounds.minY
		for row in rows(for: subviews, width: bounds.width) {
			var x = bounds.minX
			for index in row.indices {
				let size = subviews[index].sizeThatFits(.unspecified)
				subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
				x += size.width + spacing
			}
			y += row.height + spacing
		}
	}

	private struct Row {
		var indices: [Int] = []
		var width: CGFloat = 0
		var height: CGFloat = 0
	}

	private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
		var rows: [Row] = []
		var current = Row()
		for index in subviews.indices {
			let size = subviews[index].sizeThatFits(.unspecified)
			let widthWithItem = current.indices.isEmpty ? size.width : current.width + spacing + size.width
			if !current.indices.isEmpty, widthWithItem > width {
				rows.append(current)
				current = Row()
			}
			current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
			current.height = max(current.height, size.height)
			current.indices.append(index)
		}
		if !current.indices.isEmpty {
			rows.append(current)
		}
		return rows
	}
}
