import AppUI
import ComposableArchitecture
import SwiftUI

/// The console's Costs page (`app/(dashboard)/costs/page.tsx`, `components/costs/*`): the
/// global spend of the last minute and each agent's of the last day against their caps, then the
/// ledger's per-agent spend for a month and of all time.
struct HomerCostsView: View {
	let store: StoreOf<HomerCostsReducer>

	var body: some View {
		VStack(spacing: 0) {
			ForEach(store.errorMessages, id: \.self) { message in
				HomerErrorBanner(message: message)
				Divider()
			}
			if store.isLoading {
				ProgressView("Loading costs…")
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
			else {
				ScrollView {
					VStack(alignment: .leading, spacing: 16) {
						Text("Rolling-window Claude spend against configured caps, plus persistent monthly and all-time statistics.")
							.scaledFont(.callout)
							.foregroundStyle(.secondary)
						globalSpend
						perAgentSpend
						monthlyCosts
						totalCosts
					}
					.padding()
					.frame(maxWidth: 900, alignment: .leading)
					.frame(maxWidth: .infinity)
				}
			}
		}
	}

	// MARK: - Rolling windows

	private var globalSpend: some View {
		HomerCostCard("Global spend (last 60 s)") {
			if let snapshot = store.snapshot {
				if let takenAt = snapshot.snapshotAtSec {
					Text("As of \(HomerFormat.timestamp(takenAt))")
						.scaledFont(.caption)
						.foregroundStyle(.secondary)
				}
			}
		} content: {
			if let snapshot = store.snapshot {
				HomerCostUsageBar(
					spentUsd: snapshot.globalUsdLast60s,
					capUsd: snapshot.globalCapUsdPerMin,
					label: "Global spend per minute"
				)
			}
			else {
				HomerCostPlaceholder(failed: store.snapshotError != nil)
			}
		}
	}

	private var perAgentSpend: some View {
		HomerCostCard("Per-agent spend (last 24 h)") {
			if let snapshot = store.snapshot {
				let usages = snapshot.agentUsages
				if usages.isEmpty {
					HomerCostEmptyText("No agent spend recorded yet.")
				}
				else {
					Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
						GridRow {
							Text("Agent")
							Text("Spent (last 24 h)")
								.gridColumnAlignment(.trailing)
							Text("Cap")
								.gridColumnAlignment(.trailing)
							Text("Usage")
						}
						.scaledFont(.caption)
						.fontWeight(.medium)
						.foregroundStyle(.secondary)
						Divider()
						ForEach(usages) { usage in
							GridRow {
								Text(usage.agentName)
									.fontWeight(.medium)
									.lineLimit(1)
									.textSelection(.enabled)
								HomerCostAmount(usage.spentUsd)
								Group {
									if let cap = usage.capUsd {
										HomerCostAmount(cap)
									}
									else {
										Text(verbatim: "—")
									}
								}
								.foregroundStyle(.secondary)
								HomerCostUsageBar(
									spentUsd: usage.spentUsd,
									capUsd: usage.capUsd,
									label: "\(usage.agentName) spend per day",
									compact: true
								)
								.frame(minWidth: 140, maxWidth: .infinity)
							}
						}
					}
				}
			}
			else {
				HomerCostPlaceholder(failed: store.snapshotError != nil)
			}
		}
	}

	// MARK: - Ledger

	private var monthlyCosts: some View {
		HomerCostCard("Monthly costs per agent (UTC)") {
			HStack(spacing: 8) {
				if store.monthly != nil, !store.isMonthlyCurrent, store.monthlyError == nil {
					ProgressView()
						.controlSize(.small)
				}
				Picker("Month", selection: Binding(
					get: { store.shownMonth ?? "" },
					set: { store.send(.monthSelected($0)) }
				)) {
					if store.monthChoices.isEmpty {
						Text(verbatim: "—").tag("")
					}
					ForEach(store.monthChoices, id: \.self) { month in
						Text(HomerFormat.month(month)).tag(month)
					}
				}
				.labelsHidden()
				.fixedSize()
				.disabled(store.monthly == nil)
				.help("Select month")
			}
		} content: {
			if let monthly = store.monthly {
				HomerCostLedgerTable(
					rows: monthly.rows,
					totalUsd: monthly.totalUsd,
					emptyText: "No costs recorded for this month."
				)
				// The previous month stays until the picked one answers, as in the console.
				.opacity(store.isMonthlyCurrent ? 1 : 0.5)
			}
			else {
				HomerCostPlaceholder(failed: store.monthlyError != nil)
			}
		}
	}

	private var totalCosts: some View {
		HomerCostCard("All-time costs per agent") {
			if let totals = store.totals {
				HomerCostLedgerTable(rows: totals.rows, totalUsd: totals.totalUsd, emptyText: "No costs recorded yet.")
			}
			else {
				HomerCostPlaceholder(failed: store.totalsError != nil)
			}
		}
	}
}

// MARK: - Pieces

/// A section of the page, drawn like the questions' cards: a title, an optional accessory at its
/// trailing edge, the content below.
private struct HomerCostCard<Accessory: View, Content: View>: View {
	let title: String
	let accessory: Accessory
	let content: Content

	init(_ title: String, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
		self.title = title
		self.accessory = accessory()
		self.content = content()
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack(alignment: .firstTextBaseline) {
				Text(title)
					.scaledFont(.headline)
				Spacer(minLength: 8)
				accessory
			}
			content
				.scaledFont(.body)
		}
		.padding(14)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
		.overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
	}
}

private extension HomerCostCard where Accessory == EmptyView {
	init(_ title: String, @ViewBuilder content: () -> Content) {
		self.init(title, accessory: { EmptyView() }, content: content)
	}
}

/// A USD amount in the console's `$0.0000`, digits aligned.
private struct HomerCostAmount: View {
	let usd: Double

	init(_ usd: Double) {
		self.usd = usd
	}

	var body: some View {
		Text(HomerFormat.cost(usd))
			.scaledFont(.body, design: .monospaced)
			.textSelection(.enabled)
	}
}

private struct HomerCostEmptyText: View {
	let text: String

	init(_ text: String) {
		self.text = text
	}

	var body: some View {
		Text(text)
			.scaledFont(.callout)
			.foregroundStyle(.secondary)
	}
}

/// A card whose data has not arrived: a spinner, or a dash once its call failed (the banner above
/// says why).
private struct HomerCostPlaceholder: View {
	let failed: Bool

	var body: some View {
		if failed {
			HomerCostEmptyText("Not available.")
		}
		else {
			ProgressView()
				.controlSize(.small)
		}
	}
}

/// The console's `CostUsageBar`: spend against a cap, the bar green, yellow from 80 % and red at
/// the cap. Without a cap there is no bar, only the spend. `compact` (a table row) leaves the
/// amounts to the row's own columns and puts the percentage under the bar.
private struct HomerCostUsageBar: View {
	let spentUsd: Double
	let capUsd: Double?
	let label: String
	var compact = false

	var body: some View {
		if let capUsd {
			let usage = HomerCostUsage(spentUsd: spentUsd, capUsd: capUsd)
			VStack(alignment: .leading, spacing: compact ? 2 : 4) {
				if !compact {
					HStack(alignment: .firstTextBaseline) {
						Text(verbatim: "\(HomerFormat.cost(spentUsd)) / \(HomerFormat.cost(capUsd))")
							.scaledFont(.body, design: .monospaced)
							.textSelection(.enabled)
						Spacer(minLength: 8)
						Text(usage.level == .overCap ? "\(usage.percentText) — cap exceeded" : usage.percentText)
							.scaledFont(.caption)
							.fontWeight(.medium)
							.foregroundStyle(textColor(usage.level))
					}
				}
				HomerCostBar(fraction: usage.percent / 100, color: barColor(usage.level))
					.accessibilityElement()
					.accessibilityLabel(label)
					.accessibilityValue(usage.percentText)
				if compact {
					Text(usage.percentText)
						.scaledFont(.caption)
						.foregroundStyle(usage.level == .normal ? .secondary : textColor(usage.level))
				}
			}
		}
		else if compact {
			Text("No cap")
				.scaledFont(.caption)
				.foregroundStyle(.secondary)
		}
		else {
			HStack(alignment: .firstTextBaseline) {
				Text(HomerFormat.cost(spentUsd))
					.scaledFont(.body, design: .monospaced)
					.textSelection(.enabled)
				Spacer(minLength: 8)
				Text("no cap configured")
					.scaledFont(.caption)
					.foregroundStyle(.secondary)
			}
		}
	}

	private func barColor(_ level: HomerCostUsage.Level) -> Color {
		switch level {
		case .normal:
			.green
		case .nearCap:
			.yellow
		case .overCap:
			.red
		}
	}

	/// Orange rather than the bar's yellow: yellow text is unreadable on a light background.
	private func textColor(_ level: HomerCostUsage.Level) -> Color {
		switch level {
		case .normal:
			.secondary
		case .nearCap:
			.orange
		case .overCap:
			.red
		}
	}
}

private struct HomerCostBar: View {
	let fraction: Double
	let color: Color

	var body: some View {
		Capsule()
			.fill(.quaternary)
			.frame(height: 8)
			.overlay(alignment: .leading) {
				GeometryReader { proxy in
					Capsule()
						.fill(color)
						.frame(width: proxy.size.width * fraction)
				}
			}
			.clipShape(Capsule())
			.animation(.default, value: fraction)
	}
}

/// A ledger's per-agent spend with a total row, as `MonthlyCostsCard`/`TotalCostsCard` show it.
private struct HomerCostLedgerTable: View {
	let rows: [HomerAgentCost]
	let totalUsd: Double
	let emptyText: String

	var body: some View {
		if rows.isEmpty {
			HomerCostEmptyText(emptyText)
		}
		else {
			Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
				GridRow {
					Text("Agent")
						.frame(maxWidth: .infinity, alignment: .leading)
					Text("Spent")
						.gridColumnAlignment(.trailing)
				}
				.scaledFont(.caption)
				.fontWeight(.medium)
				.foregroundStyle(.secondary)
				Divider()
				ForEach(rows) { row in
					GridRow {
						Text(row.agentName)
							.fontWeight(.medium)
							.lineLimit(1)
							.textSelection(.enabled)
						HomerCostAmount(row.usd)
					}
				}
				Divider()
				GridRow {
					Text("Total")
					HomerCostAmount(totalUsd)
				}
				.fontWeight(.semibold)
			}
		}
	}
}
