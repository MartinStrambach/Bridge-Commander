import Foundation

/// Assigns the branch's changed files to modules.
enum ModuleChangeClassifier {

	/// Every module folder; ask git which of them existed at the merge-base.
	static func directories(of modules: [DependencyModule]) -> [String] {
		Array(Set(modules.flatMap(\.directories).filter { !$0.isEmpty })).sorted()
	}

	/// A file belongs to the module with the longest folder containing it, so a nested module
	/// (":user:testing" inside ":user", an iOS framework's `ios/` inside its KMP module) claims
	/// its own files. A module is new when none of its folders existed at the merge-base, and
	/// changed when it existed and owns a changed file.
	static func classify(
		changedPaths: [String],
		modules: [DependencyModule],
		existingDirectoriesAtBase: Set<String>
	) -> (new: Set<String>, changed: Set<String>, counts: [String: Int]) {
		var moduleByDirectory: [String: String] = [:]
		for module in modules {
			for directory in module.directories where !directory.isEmpty {
				moduleByDirectory[directory] = module.id
			}
		}

		var counts: [String: Int] = [:]
		for path in changedPaths {
			if let owner = owner(of: path, in: moduleByDirectory) {
				counts[owner, default: 0] += 1
			}
		}

		var new: Set<String> = []
		var changed: Set<String> = []
		for module in modules where counts[module.id] != nil {
			let directories = module.directories.filter { !$0.isEmpty }
			if !directories.isEmpty, directories.allSatisfy({ !existingDirectoriesAtBase.contains($0) }) {
				new.insert(module.id)
			}
			else {
				changed.insert(module.id)
			}
		}
		return (new, changed, counts)
	}

	private static func owner(of path: String, in moduleByDirectory: [String: String]) -> String? {
		var components = path.split(separator: "/")
		// The file's own name is never a module folder.
		_ = components.popLast()
		while !components.isEmpty {
			if let owner = moduleByDirectory[components.joined(separator: "/")] {
				return owner
			}
			components.removeLast()
		}
		return nil
	}
}
