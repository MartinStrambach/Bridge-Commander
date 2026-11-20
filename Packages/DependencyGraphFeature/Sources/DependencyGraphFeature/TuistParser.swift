import Foundation

/// Reads the iOS module structure from Tuist's `ProjectDescriptionHelpers` as text: a framework
/// registry (static members building `Framework<Kind>` values) and the target builder calls that
/// list each framework's dependencies. See the package README for the forms understood.
enum TuistParser {

	// MARK: - Registry

	struct Framework: Equatable {
		/// The static member dependencies refer to it by (`.AppCore`).
		let member: String
		/// The target's name.
		let name: String
		/// The registry's kind, lowercased without the "Kind" suffix (`Framework<CoreKind>` →
		/// "core").
		let kind: String
		/// The Kotlin Multiplatform module the framework wraps, as its folder path's tail.
		let kmpName: String?
	}

	/// The frameworks declared as `static var X: Self { Self("X", kmpName: "y") }` inside
	/// `extension FrameworkDependency where Self == Framework<SomeKind>` blocks.
	static func frameworks(inRegistry text: String) -> [Framework] {
		let headers = text.matches(of: registryHeader).map { match in
			(position: match.range.lowerBound, kind: kindName(String(match.output.1)))
		}
		return text.matches(of: registryMember).compactMap { match in
			guard let kind = headers.last(where: { $0.position < match.range.lowerBound })?.kind else {
				return nil
			}
			return Framework(
				member: String(match.output.1),
				name: String(match.output.2),
				kind: kind,
				kmpName: match.output.3.map(String.init)
			)
		}
	}

	private static func kindName(_ typeName: String) -> String {
		let base = typeName.hasSuffix("Kind") ? String(typeName.dropLast(4)) : typeName
		return base.lowercased()
	}

	// MARK: - Targets

	struct Target: Equatable {
		let name: String
		let isExtension: Bool
		let dependencies: [String]
		let testDependencies: [String]
	}

	/// Every `Target.<builder>(.Member, …)` call: the first argument names the target,
	/// `internalDependencies:` and `testsInternalDependencies:` list what it and its tests link.
	/// Builders are not named, so a helper of any name counts; a first argument outside the
	/// registry counts only for a builder with "Extension" in its name (an app extension).
	/// Names are registry members; only those in `known` count as dependencies, which drops
	/// external ones and `.targetDependency` suffixes.
	static func targets(in text: String, known: Set<String>) -> [Target] {
		text.matches(of: targetBuilderCall).compactMap { match -> Target? in
			guard let arguments = balancedContents(
				of: text,
				openingAt: text.index(before: match.range.upperBound),
				open: "(",
				close: ")"
			),
				let name = arguments.firstMatch(of: /^\s*\.(\w+)/)?.output.1
			else {
				return nil
			}

			let isExtension = match.output.1.localizedCaseInsensitiveContains("extension")
			guard known.contains(String(name)) || isExtension else {
				return nil
			}

			return Target(
				name: String(name),
				isExtension: !known.contains(String(name)),
				dependencies: dependencyNames(labelled: internalDependenciesLabel, in: arguments, known: known),
				testDependencies: dependencyNames(labelled: testsInternalDependenciesLabel, in: arguments, known: known)
			)
		}
	}

	/// Targets whose dependencies come from a list function rather than an argument: a
	/// `func f(…) -> [any FrameworkDependency]` lists frameworks, and a function body that binds
	/// `let x = Framework<Kind>.Member` and calls `f(` makes Member depend on that list. That is
	/// how a builder spells out an app-sized framework's long dependency list.
	static func listedDependencies(in texts: [String], known: Set<String>) -> [(target: String, dependencies: [String])] {
		var lists: [String: [String]] = [:]
		for text in texts {
			for match in text.matches(of: listFunction) {
				guard let body = balancedContents(
					of: text,
					openingAt: text.index(before: match.range.upperBound),
					open: "{",
					close: "}"
				) else {
					continue
				}
				lists[String(match.output.1)] = memberNames(in: body, known: known)
			}
		}
		guard !lists.isEmpty else {
			return []
		}

		var result: [(target: String, dependencies: [String])] = []
		for text in texts {
			for match in text.matches(of: functionDeclaration) {
				guard let body = balancedContents(
					of: text,
					openingAt: text.index(before: match.range.upperBound),
					open: "{",
					close: "}"
				),
					let target = body.firstMatch(of: frameworkBinding)?.output.1,
					known.contains(String(target))
				else {
					continue
				}

				for (function, dependencies) in lists where body.contains("\(function)(") {
					result.append((String(target), dependencies))
				}
			}
		}
		return result
	}

	private static func dependencyNames(labelled label: Regex<Substring>, in arguments: String, known: Set<String>) -> [String] {
		guard let match = arguments.firstMatch(of: label),
		      let list = balancedContents(
		      	of: arguments,
		      	openingAt: arguments.index(before: match.range.upperBound),
		      	open: "[",
		      	close: "]"
		      )
		else {
			return []
		}
		return memberNames(in: list, known: known)
	}

	private static func memberNames(in text: String, known: Set<String>) -> [String] {
		var seen: Set<String> = []
		return text.matches(of: /\.(\w+)/).compactMap { match in
			let name = String(match.output.1)
			guard known.contains(name), seen.insert(name).inserted else {
				return nil
			}
			return name
		}
	}

	/// What lies between the bracket at `openingAt` and its partner, counting nested brackets of
	/// the same kind. Nil when it is never closed.
	static func balancedContents(of text: String, openingAt start: String.Index, open: Character, close: Character) -> String? {
		guard start < text.endIndex, text[start] == open else {
			return nil
		}

		var depth = 0
		var index = start
		while index < text.endIndex {
			let character = text[index]
			if character == open {
				depth += 1
			}
			else if character == close {
				depth -= 1
				if depth == 0 {
					return String(text[text.index(after: start) ..< index])
				}
			}
			index = text.index(after: index)
		}
		return nil
	}

	// MARK: - Patterns

	nonisolated(unsafe) private static let registryHeader =
		/extension\s+FrameworkDependency\s+where\s+Self\s*==\s*Framework<(\w+)>/

	nonisolated(unsafe) private static let registryMember =
		/static\s+var\s+(\w+)\s*:\s*Self\s*\{\s*Self\(\s*"([^"]+)"(?:\s*,\s*kmpName:\s*"([^"]+)")?\s*,?\s*\)/

	nonisolated(unsafe) private static let targetBuilderCall = /Target\.(\w+)\s*\(/

	nonisolated(unsafe) private static let listFunction =
		/func\s+(\w+)\s*\([^)]*\)\s*->\s*\[\s*any\s+FrameworkDependency\s*\]\s*\{/

	nonisolated(unsafe) private static let functionDeclaration = /func\s+\w+\s*\([^)]*\)[^{]*\{/

	nonisolated(unsafe) private static let frameworkBinding = /let\s+\w+\s*=\s*Framework<\w+>\.(\w+)/

	/// Not preceded by a letter, so `testsInternalDependencies:` does not match.
	nonisolated(unsafe) private static let internalDependenciesLabel = /(?:^|[^A-Za-z])internalDependencies\s*:\s*\[/

	nonisolated(unsafe) private static let testsInternalDependenciesLabel = /testsInternalDependencies\s*:\s*\[/
}
