/// A page of the Settings window, listed in its sidebar.
enum SettingsCategory: String, CaseIterable, Identifiable {
	case general
	case accounts
	case repositoryGroups
	case worktrees
	case terminal
	case externalApps
	case tuist
	case updates

	var id: Self { self }

	var title: String {
		switch self {
		case .general: "General"
		case .accounts: "Accounts"
		case .repositoryGroups: "Repository Groups"
		case .worktrees: "Branches & Worktrees"
		case .terminal: "Terminal"
		case .externalApps: "External Apps"
		case .tuist: "Tuist"
		case .updates: "Updates"
		}
	}

	var systemImage: String {
		switch self {
		case .general: "gearshape"
		case .accounts: "person.crop.circle"
		case .repositoryGroups: "folder"
		case .worktrees: "arrow.triangle.branch"
		case .terminal: "terminal"
		case .externalApps: "app.badge"
		case .tuist: "hammer"
		case .updates: "arrow.down.circle"
		}
	}
}
