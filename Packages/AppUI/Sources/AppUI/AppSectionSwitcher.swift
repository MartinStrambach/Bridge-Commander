import SwiftUI

/// The main window's top-level sections, switched from the start of each section's header.
public enum AppSection: String, CaseIterable, Sendable {
	case repositories
	case homer

	public var title: String {
		switch self {
		case .repositories:
			"Repositories"
		case .homer:
			"Homer"
		}
	}

	public var systemImage: String {
		switch self {
		case .repositories:
			"folder"
		case .homer:
			"waveform.path.ecg"
		}
	}
}

/// Stands where the window title used to: every section's header starts with it, so it stays in
/// one place while the rest of the header changes under it. A section's badge (Homer's open
/// questions) shows from whichever section is on screen.
public struct AppSectionSwitcher: View {
	@Binding
	private var selection: AppSection
	private let badges: [AppSection: Int]

	public init(selection: Binding<AppSection>, badges: [AppSection: Int] = [:]) {
		self._selection = selection
		self.badges = badges
	}

	public var body: some View {
		HStack(spacing: 2) {
			ForEach(AppSection.allCases, id: \.self) { section in
				segment(section)
			}
		}
		.padding(2)
		// Opaque, like the "Active terminals" chip beside it, so the control reads as one piece
		// against the window background.
		.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
	}

	private func segment(_ section: AppSection) -> some View {
		let isSelected = selection == section
		let badge = badges[section] ?? 0
		return Button {
			selection = section
		} label: {
			HStack(spacing: 6) {
				Image(systemName: section.systemImage)
				Text(section.title)
					.fontWeight(.semibold)
				if badge > 0 {
					Text("\(badge)")
						.scaledFont(.caption2)
						.fontWeight(.bold)
						.monospacedDigit()
						.foregroundStyle(.white)
						.padding(.horizontal, 5)
						.padding(.vertical, 1)
						.background(.orange, in: Capsule())
				}
			}
			.scaledFont(.headline)
			.foregroundStyle(isSelected ? .primary : .secondary)
			.padding(.horizontal, 10)
			.padding(.vertical, 5)
			.background {
				if isSelected {
					RoundedRectangle(cornerRadius: 5)
						.fill(Color.accentColor.opacity(0.18))
				}
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.help(helpText(section, badge: badge))
		.accessibilityAddTraits(isSelected ? .isSelected : [])
	}

	private func helpText(_ section: AppSection, badge: Int) -> String {
		switch section {
		case .repositories:
			"Repositories and worktrees"
		case .homer:
			badge > 0
				? "Homer console — \(badge) open \(badge == 1 ? "question" : "questions")"
				: "Homer console"
		}
	}
}

#Preview {
	@Previewable @State var selection = AppSection.repositories
	AppSectionSwitcher(selection: $selection, badges: [.homer: 2])
		.padding()
}
