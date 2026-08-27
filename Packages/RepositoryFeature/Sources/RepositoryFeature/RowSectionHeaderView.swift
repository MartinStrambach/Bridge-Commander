import SwiftUI

/// Splits a repo group's worktree rows by ticket state or into ticketed and ticketless, depending
/// on the sort mode.
/// Deliberately quiet — it sits between rows inside a group, so it must not compete with the
/// group's own header row.
struct RowSectionHeaderView: View {
	let header: RowSectionHeader

	var body: some View {
		HStack(spacing: 6) {
			Circle()
				.fill(header.section.color)
				.frame(width: 6, height: 6)
			Text(header.section.title.uppercased())
				.font(.caption2)
				.fontWeight(.semibold)
				.foregroundStyle(.secondary)
				.lineLimit(1)
			Text("\(header.count)")
				.font(.caption2)
				.foregroundStyle(.secondary)
				.padding(.horizontal, 5)
				.padding(.vertical, 1)
				.background(Color.secondary.opacity(0.15), in: Capsule())
			Spacer(minLength: 0)
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 5)
		.background(header.section.background)
	}
}

#Preview {
	VStack(spacing: 0) {
		RowSectionHeaderView(header: RowSectionHeader(section: .ticketState(.inProgress), count: 3))
		RowSectionHeaderView(header: RowSectionHeader(section: .ticketState(.waitingToCodeReview), count: 2))
		RowSectionHeaderView(header: RowSectionHeader(section: .ticketState(.accepted), count: 4))
		RowSectionHeaderView(header: RowSectionHeader(section: .ticketState(.done), count: 12))
		RowSectionHeaderView(header: RowSectionHeader(section: .tickets, count: 5))
		RowSectionHeaderView(header: RowSectionHeader(section: .noTicket, count: 1))
	}
	.frame(width: 420)
}
