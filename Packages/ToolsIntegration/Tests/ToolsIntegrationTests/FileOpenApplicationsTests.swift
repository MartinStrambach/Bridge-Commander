import Foundation
import Testing

@testable import ToolsIntegration

@Suite("File open applications")
struct FileOpenApplicationsTests {
	@Test func theFileTypeIsTheLowercasedExtensionOrEmpty() {
		#expect(FileOpenApplications.fileType(ofFileAt: "/repo/App/Main.KT") == "kt")
		#expect(FileOpenApplications.fileType(ofFileAt: "/repo/Package.resolved") == "resolved")
		#expect(FileOpenApplications.fileType(ofFileAt: "/repo/LICENSE") == "")
	}

	@Test func aFileTypeIsNamedForPeople() {
		#expect(FileOpenApplications.displayName(ofFileType: "kt") == ".kt files")
		#expect(FileOpenApplications.displayName(ofFileType: "") == "files without an extension")
	}

	@Test func theStoredValueRoundTripsThroughItsRawValue() {
		let choices = FileOpenApplications(bundleIdentifiers: ["kt": "com.google.android.studio", "": "com.apple.TextEdit"])
		#expect(FileOpenApplications(rawValue: choices.rawValue) == choices)
		#expect(FileOpenApplications(rawValue: "not json") == nil)
	}

	@Test func aChoiceIsStoredAsTheApplicationsBundleIdentifier() {
		#expect(FileOpenApplications.bundleIdentifier(ofApplicationAt: URL(filePath: "/System/Applications/TextEdit.app")) == "com.apple.TextEdit")
	}

	@Test func anUninstalledApplicationCountsAsNoChoice() {
		let choices = FileOpenApplications(bundleIdentifiers: ["kt": "com.example.not-installed"])
		#expect(choices.application(forFileType: "kt") == nil)
		#expect(choices.application(forFileType: "kts") == nil)
	}
}

@Suite("File open application kind")
struct FileOpenApplicationKindTests {
	@Test func xcodeIsToldApartByItsBundleIdentifier() {
		#expect(FileOpenApplicationKind(bundleIdentifier: "com.apple.dt.Xcode") == .xcode)
	}

	@Test func androidStudioAndJetBrainsIDEsTakeALine() {
		for identifier in ["com.google.android.studio", "com.jetbrains.intellij", "com.jetbrains.intellij.ce", "com.jetbrains.pycharm"] {
			#expect(FileOpenApplicationKind(bundleIdentifier: identifier) == .jetBrains(bundleIdentifier: identifier))
		}
	}

	@Test func otherApplicationsGetOpen() {
		#expect(FileOpenApplicationKind(bundleIdentifier: "com.jetbrains.fleet") == .other)
		#expect(FileOpenApplicationKind(bundleIdentifier: "com.jetbrains.toolbox") == .other)
		#expect(FileOpenApplicationKind(bundleIdentifier: "com.microsoft.VSCode") == .other)
		#expect(FileOpenApplicationKind(bundleIdentifier: nil) == .other)
	}

	@Test func sourceCodeOpensInsideTheProject() {
		#expect(FileOpenApplicationKind.isSourceCode("/repo/Sources/App.swift"))
		#expect(FileOpenApplicationKind.isSourceCode("/repo/Sources/View.m"))
		#expect(!FileOpenApplicationKind.isSourceCode("/repo/data.json"))
		#expect(!FileOpenApplicationKind.isSourceCode("/repo/README.md"))
	}
}
