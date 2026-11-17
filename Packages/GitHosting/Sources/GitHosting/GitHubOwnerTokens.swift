import Foundation

/// GitHub tokens for owners (organizations or users) the main token does not reach.
///
/// A fine-grained token belongs to one owner, so a personal one cannot see an organization's
/// repositories and no single fine-grained token covers both. A repository uses its owner's
/// token when one is set here, and the main `githubToken` otherwise.
public nonisolated struct GitHubOwnerTokens: Equatable, Sendable {
	/// Tokens by owner as the user typed it. GitHub logins do not distinguish case, so lookups
	/// and additions compare case-insensitively; an owner is listed once.
	public private(set) var tokens: [String: String]

	public init(tokens: [String: String] = [:]) {
		self.tokens = [:]
		for (owner, token) in tokens.sorted(by: { $0.key < $1.key }) {
			setToken(token, forOwner: owner)
		}
	}

	/// The owners in the order Settings lists them.
	public var owners: [String] {
		tokens.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
	}

	/// Whether any owner has a token, as opposed to only being listed.
	public var hasTokens: Bool {
		tokens.values.contains { !$0.isEmpty }
	}

	/// The owner's token as stored, `""` for a listed owner without one yet, nil for an owner
	/// that is not listed.
	public func token(forOwner owner: String) -> String? {
		listedOwner(owner).flatMap { tokens[$0] }
	}

	/// The owner as it is listed, whatever case it is asked for in; nil when it is not listed.
	public func listedOwner(_ owner: String) -> String? {
		tokens.keys.first { $0.caseInsensitiveCompare(owner) == .orderedSame }
	}

	/// The token for a repository of `owner`: the owner's own when it has one, else `main`.
	public func token(forRepositoryOf owner: String, main: String) -> String {
		guard let token = token(forOwner: owner), !token.isEmpty else {
			return main
		}
		return token
	}

	/// Lists the owner without a token. Does nothing for an owner already listed, or for text
	/// that names none.
	public mutating func add(_ owner: String) {
		guard let owner = Self.normalizedOwner(owner), listedOwner(owner) == nil else {
			return
		}
		tokens[owner] = ""
	}

	/// Sets the owner's token, listing the owner first if needed (an import adds owners this way;
	/// Settings edits only listed ones).
	public mutating func setToken(_ token: String, forOwner owner: String) {
		guard let owner = Self.normalizedOwner(owner) else {
			return
		}
		// Trimmed like the main token: a pasted newline corrupts the Bearer header.
		tokens[listedOwner(owner) ?? owner] = token.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	public mutating func remove(_ owner: String) {
		if let stored = listedOwner(owner) {
			tokens[stored] = nil
		}
	}

	/// The owner as GitHub names it, from what a user types or pastes: `acme`, `@acme`,
	/// `acme/app`, a link to either, or the SSH address `origin` shows
	/// (`git@github.com:acme/app.git`). Nil for text that names no owner.
	public static func normalizedOwner(_ text: String) -> String? {
		var owner = text.trimmingCharacters(in: .whitespacesAndNewlines)
		let prefixes = ["ssh://", "git@github.com:", "git@github.com/", "https://", "http://", "www.", "github.com/", "@"]
		for prefix in prefixes where owner.lowercased().hasPrefix(prefix) {
			owner.removeFirst(prefix.count)
		}
		owner = String(owner.prefix { $0 != "/" })
		// A login is letters, digits and hyphens; anything else was not an owner.
		let isLogin = !owner.isEmpty && owner.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
		return isLogin ? owner : nil
	}
}

extension GitHubOwnerTokens: RawRepresentable {
	public init?(rawValue: String) {
		guard let tokens = try? JSONDecoder().decode([String: String].self, from: Data(rawValue.utf8)) else {
			return nil
		}
		self.init(tokens: tokens)
	}

	public var rawValue: String {
		let encoder = JSONEncoder()
		// Stable output, so an unchanged value is never written back as a "new" one.
		encoder.outputFormatting = .sortedKeys
		// The dictionary, and the type is not `Codable`: a type both `RawRepresentable` and `Codable`
		// encodes as its `rawValue`, which would encode the type again, without end.
		guard let data = try? encoder.encode(tokens) else {
			return ""
		}
		return String(decoding: data, as: UTF8.self)
	}

	/// Spelled out: as a `RawRepresentable` the type would otherwise pick up the standard
	/// library's `==` that compares raw values, i.e. JSON strings.
	public static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.tokens == rhs.tokens
	}
}

/// What testing an owner's token found: whose token it is, and the owner as GitHub knows it.
public nonisolated struct GitHubOwnerTokenVerification: Equatable, Sendable {
	/// The user the token belongs to: for an organization's fine-grained token still a person.
	public let login: String
	/// The owner in GitHub's spelling.
	public let owner: String
	public let isOrganization: Bool

	public init(login: String, owner: String, isOrganization: Bool) {
		self.login = login
		self.owner = owner
		self.isOrganization = isOrganization
	}
}
