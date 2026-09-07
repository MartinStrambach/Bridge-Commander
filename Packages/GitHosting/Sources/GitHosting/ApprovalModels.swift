import Foundation

/// Whether the branch's PR/MR has been signed off on.
///
/// Deliberately a tri-state rather than a fraction: GitHub exposes no "N of M
/// required" count on a pull request at all, and GitLab's `approvalsRequired` is a
/// Premium field, so a denominator is not available everywhere. `ApprovalStatus`
/// carries the count separately for the cases that do report one.
public nonisolated enum ApprovalDecision: String, Sendable, Equatable {
	case approved
	case changesRequested
	case reviewRequired

	/// SF Symbol name for the status icon. Lives here (no SwiftUI) so it is
	/// unit-testable — same rationale as `PipelineState.systemImageName`.
	public var systemImageName: String {
		switch self {
		case .approved: "person.fill.checkmark"
		case .changesRequested: "person.fill.xmark"
		case .reviewRequired: "person.fill.questionmark"
		}
	}
}

/// Someone who has weighed in on a PR/MR, reduced to what the row needs to draw them.
public nonisolated struct Reviewer: Equatable, Sendable, Identifiable {
	/// Fixed palette size for `colorIndex`. The avatar stack maps the index onto
	/// its own colours; keeping the modulus here means the mapping is testable
	/// without SwiftUI.
	public static let colorCount = 8

	public let username: String
	public let displayName: String
	public let avatarURL: String?

	public var id: String { username }

	public init(username: String, displayName: String, avatarURL: String? = nil) {
		self.username = username
		self.displayName = displayName
		self.avatarURL = avatarURL
	}

	/// The avatar resized by the host to `pixels` square.
	///
	/// Worth doing: unsized, GitHub hands back the original upload — routinely
	/// 460x460 and a few hundred KB — for a face drawn at 16pt. That is both a
	/// wasteful download on every refresh and blurrier than asking for the right
	/// size, because the downscale then happens at draw time.
	///
	/// Hosts spell the parameter differently, and the URL may already carry a
	/// query (GitLab appends a `?v=` cache buster), so this goes through
	/// `URLComponents` rather than string concatenation.
	public func avatarURL(pixels: Int) -> URL? {
		guard
			let avatarURL,
			var components = URLComponents(string: avatarURL)
		else {
			return nil
		}

		let host = components.host?.lowercased() ?? ""
		let name: String =
			if host.hasSuffix("gitlab.com") {
				"width"
			}
			// Gravatar (GitLab's fallback for users with no upload) and GitHub
			// both use `s`.
			else {
				"s"
			}

		var items = components.queryItems ?? []
		items.removeAll { $0.name == name }
		items.append(URLQueryItem(name: name, value: String(pixels)))
		components.queryItems = items

		return components.url
	}

	/// Up to two letters for the monogram fallback: initials of the first two words
	/// of the display name, or its first letter when it is a single word. Falls back
	/// to the username when the display name has no letters to take (empty, or
	/// punctuation/emoji only), and to "?" when neither yields anything.
	public var initials: String {
		if let fromDisplayName = Self.initials(from: displayName) {
			return fromDisplayName
		}
		if let fromUsername = Self.initials(from: username) {
			return fromUsername
		}
		return "?"
	}

	/// Stable bucket in `0..<Reviewer.colorCount` for the monogram colour.
	///
	/// Deliberately *not* `hashValue`: Swift seeds string hashing per process, so
	/// the same person would change colour on every app launch. This folds the
	/// username's UTF-8 bytes instead, which is stable across launches and machines.
	public var colorIndex: Int {
		var hash: UInt32 = 2_166_136_261 // FNV-1a offset basis
		for byte in username.utf8 {
			hash ^= UInt32(byte)
			hash = hash &* 16_777_619 // FNV-1a prime
		}
		return Int(hash % UInt32(Self.colorCount))
	}

	/// First letters of up to the first two whitespace-separated words that start
	/// with a letter. `nil` when the source has no such word.
	private static func initials(from source: String) -> String? {
		let letters = source
			.split(whereSeparator: { $0.isWhitespace || $0 == "." || $0 == "_" || $0 == "-" })
			.compactMap { $0.first(where: \.isLetter) }
			.prefix(2)

		guard !letters.isEmpty else {
			return nil
		}
		return String(letters).uppercased()
	}
}

/// Review sign-off state for a single PR/MR.
public nonisolated struct ApprovalStatus: Equatable, Sendable {
	public let decision: ApprovalDecision
	public let approvedBy: [Reviewer]
	public let changesRequestedBy: [Reviewer]
	/// Number of approvals the project requires. `nil` when the provider does not
	/// report one — always on GitHub, and on GitLab tiers without approval rules —
	/// so the UI can tell "no denominator available" from "zero required".
	public let approvalsRequired: Int?
	/// How many of those are still outstanding.
	public let approvalsLeft: Int?

	/// How many required approvals are already covered.
	///
	/// Derived from `approvalsLeft` rather than `approvedBy.count`: one reviewer can
	/// satisfy several approval rules at once (sitting in more than one of the
	/// groups a rule draws from), so counting distinct approvers understates
	/// progress and leaves a fully approved MR reading as, say, "2 of 8".
	public var approvalsSatisfied: Int? {
		guard let approvalsRequired, let approvalsLeft else {
			return nil
		}
		return max(0, approvalsRequired - approvalsLeft)
	}

	public init(
		decision: ApprovalDecision,
		approvedBy: [Reviewer] = [],
		changesRequestedBy: [Reviewer] = [],
		approvalsRequired: Int? = nil,
		approvalsLeft: Int? = nil
	) {
		self.decision = decision
		self.approvedBy = approvedBy
		self.changesRequestedBy = changesRequestedBy
		self.approvalsRequired = approvalsRequired
		self.approvalsLeft = approvalsLeft
	}
}
