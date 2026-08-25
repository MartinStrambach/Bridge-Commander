import Foundation
import Testing
@testable import ToolsIntegration

@Suite("Tuist command building")
struct TuistCommandHelperTests {
	private let misePath = "/Users/test/.local/bin/mise"

	private func command(
		_ action: TuistAction,
		shouldOpenXcode: Bool = true,
		runMode: TuistRunMode = .mise
	) -> String {
		TuistCommandHelper.shellCommand(
			for: action,
			shouldOpenXcode: shouldOpenXcode,
			misePath: misePath,
			runMode: runMode
		)
	}

	// MARK: - Command Strings

	@Test("clean without a category runs the bare clean subcommand")
	func cleanCommandString() {
		#expect(TuistAction.clean(nil).commandString == "clean")
	}

	@Test(
		"each action maps to its tuist subcommand",
		arguments: [
			(TuistAction.generate, "generate"),
			(.generateWithoutCache, "generate --cache-profile none"),
			(.install, "install"),
			(.installUpdate, "install -u"),
			(.cache(.externalOnly), "cache --cache-profile only-external"),
			(.cache(.all), "cache --cache-profile all-possible"),
			(.edit, "edit"),
			(.inspectDependencies, "inspect dependencies --only implicit"),
			(.clean(nil), "clean"),
			(.clean(.binaries), "clean binaries"),
		]
	)
	func commandStrings(action: TuistAction, expected: String) {
		#expect(action.commandString == expected)
	}

	// MARK: - Clean

	@Test("clean runs through mise when the run mode is mise")
	func cleanViaMise() {
		#expect(command(.clean(nil), runMode: .mise) == "\(misePath) exec -- tuist clean")
	}

	@Test("clean runs tuist directly when the run mode is native")
	func cleanViaNative() {
		#expect(command(.clean(nil), runMode: .native) == "tuist clean")
	}

	@Test("clean never gets the --no-open flag", arguments: [true, false])
	func cleanIgnoresOpenXcode(shouldOpenXcode: Bool) {
		#expect(command(.clean(nil), shouldOpenXcode: shouldOpenXcode, runMode: .native) == "tuist clean")
	}

	// MARK: - Clean Categories

	@Test(
		"every clean category is passed through as a single positional argument",
		arguments: TuistCleanCategory.allCases
	)
	func cleanCategoryArgument(category: TuistCleanCategory) {
		#expect(command(.clean(category), runMode: .native) == "tuist clean \(category.rawValue)")
	}

	@Test(
		"clean category raw values match the tokens the Tuist CLI parses",
		arguments: [
			(TuistCleanCategory.binaries, "binaries"),
			(.selectiveTests, "selectiveTests"),
			(.dependencies, "dependencies"),
			(.manifests, "manifests"),
			(.plugins, "plugins"),
			(.projectDescriptionHelpers, "projectDescriptionHelpers"),
			(.editProjects, "editProjects"),
			(.generatedAutomationProjects, "generatedAutomationProjects"),
			(.runs, "runs"),
			(.generationMetadata, "generationMetadata"),
		]
	)
	func cleanCategoryRawValues(category: TuistCleanCategory, expected: String) {
		#expect(category.rawValue == expected)
	}

	@Test("the clean submenu offers every category exactly once")
	func cleanCategoriesAreUnique() {
		let rawValues = TuistCleanCategory.allCases.map(\.rawValue)
		#expect(rawValues.count == 10)
		#expect(Set(rawValues).count == rawValues.count)
	}

	@Test("a clean category runs through mise when the run mode is mise")
	func cleanCategoryViaMise() {
		#expect(command(.clean(.selectiveTests), runMode: .mise) == "\(misePath) exec -- tuist clean selectiveTests")
	}

	// MARK: - --no-open Flag

	@Test("generate gets --no-open only when Xcode should stay closed")
	func generateNoOpenFlag() {
		#expect(command(.generate, shouldOpenXcode: true, runMode: .native) == "tuist generate")
		#expect(command(.generate, shouldOpenXcode: false, runMode: .native) == "tuist generate --no-open")
	}

	@Test("generate without cache gets --no-open only when Xcode should stay closed")
	func generateWithoutCacheNoOpenFlag() {
		#expect(
			command(.generateWithoutCache, shouldOpenXcode: true, runMode: .native)
				== "tuist generate --cache-profile none"
		)
		#expect(
			command(.generateWithoutCache, shouldOpenXcode: false, runMode: .native)
				== "tuist generate --cache-profile none --no-open"
		)
	}

	@Test(
		"non-generate actions never get --no-open",
		arguments: [
			TuistAction.install, .installUpdate, .cache(.all), .edit, .inspectDependencies, .clean(nil),
			.clean(.binaries),
		]
	)
	func nonGenerateActionsIgnoreNoOpen(action: TuistAction) {
		#expect(!command(action, shouldOpenXcode: false, runMode: .native).contains("--no-open"))
	}
}
