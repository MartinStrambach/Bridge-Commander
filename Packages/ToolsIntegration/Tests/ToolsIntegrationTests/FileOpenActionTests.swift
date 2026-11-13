import Foundation
import Testing

@testable import ToolsIntegration

@Suite("File open action")
struct FileOpenActionTests {
	private typealias Facts = FileOpenAction.Facts

	private let xcode = URL(filePath: "/Applications/Xcode.app")

	@Test func aFileItsDefaultAppOpensSafelyGoesThere() {
		let facts = Facts(isDirectory: false, isActive: false, isText: true, defaultApplication: xcode)
		#expect(FileOpenAction(facts) == .open(in: xcode))
	}

	/// `Package.resolved`, or a `.kt` without Android Studio as its default: the application chosen
	/// in Bridge Commander, text or not.
	@Test func aFileNoAppClaimsGoesToTheChosenApplication() {
		#expect(FileOpenAction(Facts(isDirectory: false, isActive: false, isText: true)) == .openInChosenApplication)
		#expect(FileOpenAction(Facts(isDirectory: false, isActive: false, isText: false)) == .openInChosenApplication)
	}

	/// `gradlew` or a `.command` would run in Terminal; the editor shows it instead.
	@Test func anActiveTextFileGoesToTheEditorEvenWithADefaultApp() {
		let facts = Facts(isDirectory: false, isActive: true, isText: true, defaultApplication: xcode)
		#expect(FileOpenAction(facts) == .openInEditor)
	}

	/// Not even the chosen application: an unclaimed executable is still revealed.
	@Test func anActiveBinaryIsRevealed() {
		#expect(FileOpenAction(Facts(isDirectory: false, isActive: true, isText: false, defaultApplication: xcode)) == .revealInFinder)
		#expect(FileOpenAction(Facts(isDirectory: false, isActive: true, isText: false)) == .revealInFinder)
	}

	@Test func aPlainDirectoryOpensButABundleThatLaunchesIsRevealed() {
		#expect(FileOpenAction(Facts(isDirectory: true, isActive: false, isText: false)) == .openFolder)
		#expect(FileOpenAction(Facts(isDirectory: true, isActive: true, isText: false)) == .revealInFinder)
	}
}

/// The facts as read from real files.
@Suite("File open facts")
struct FileOpenFactsTests {
	private let directory: URL

	init() throws {
		directory = FileManager.default.temporaryDirectory
			.appending(component: "FileOpenFactsTests-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	}

	private func file(_ name: String, contents: Data = Data("text\n".utf8), executable: Bool = false) throws -> String {
		let url = directory.appending(component: name)
		try contents.write(to: url)
		if executable {
			try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
		}
		return url.path
	}

	@Test func anExtensionlessExecutableIsActiveText() throws {
		defer { try? FileManager.default.removeItem(at: directory) }
		let facts = try FileOpenAction.Facts(at: file("gradlew", contents: Data("#!/bin/sh\n".utf8), executable: true))
		#expect(facts.isActive)
		#expect(facts.isText)
		#expect(FileOpenAction(facts) == .openInEditor)
	}

	@Test func aCommandFileIsActive() throws {
		defer { try? FileManager.default.removeItem(at: directory) }
		#expect(try FileOpenAction.Facts(at: file("release.command")).isActive)
	}

	@Test func aResolvedFileIsPlainText() throws {
		defer { try? FileManager.default.removeItem(at: directory) }
		let facts = try FileOpenAction.Facts(at: file("Package.resolved"))
		#expect(!facts.isActive)
		#expect(facts.isText)
		#expect(!facts.isDirectory)
	}

	@Test func aFileWithANulByteIsNotText() throws {
		defer { try? FileManager.default.removeItem(at: directory) }
		#expect(try !FileOpenAction.Facts(at: file("blob.bin", contents: Data([0x89, 0x50, 0x00, 0x47]))).isText)
	}

	@Test func anEmptyFileIsText() throws {
		defer { try? FileManager.default.removeItem(at: directory) }
		#expect(try FileOpenAction.Facts(at: file("EMPTY", contents: Data())).isText)
	}

	@Test func aDirectoryIsNeitherActiveNorText() throws {
		defer { try? FileManager.default.removeItem(at: directory) }
		let facts = FileOpenAction.Facts(at: directory.path)
		#expect(facts.isDirectory)
		#expect(!facts.isActive)
		#expect(!facts.isText)
	}
}
