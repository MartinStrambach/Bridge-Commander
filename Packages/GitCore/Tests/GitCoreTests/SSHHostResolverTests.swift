import Testing
@testable import GitCore

@Suite("SSHHostResolver.hostname(fromSSHConfigDump:)")
struct SSHHostResolverTests {
	@Test("extracts the hostname an alias resolves to")
	func extractsResolvedHostname() {
		let dump = """
		host gitlab-work
		user git
		hostname gitlab.com
		port 22
		addressfamily any
		"""
		#expect(SSHHostResolver.hostname(fromSSHConfigDump: dump) == "gitlab.com")
	}

	@Test("an unaliased host resolves to itself")
	func identityResolution() {
		let dump = """
		host gitlab.com
		user martin.strambach
		hostname gitlab.com
		port 22
		"""
		#expect(SSHHostResolver.hostname(fromSSHConfigDump: dump) == "gitlab.com")
	}

	@Test("other keys sharing the prefix letters are not mistaken for hostname")
	func ignoresSimilarKeys() {
		let dump = """
		host gitlab-work
		canonicalizehostname false
		hostkeyalias something
		hostname gitlab.com
		"""
		#expect(SSHHostResolver.hostname(fromSSHConfigDump: dump) == "gitlab.com")
	}

	@Test("output without a hostname line yields nil")
	func missingHostnameYieldsNil() {
		let dump = """
		host gitlab-work
		user git
		port 22
		"""
		#expect(SSHHostResolver.hostname(fromSSHConfigDump: dump) == nil)
	}

	@Test("a bare or empty hostname value yields nil")
	func emptyValueYieldsNil() {
		#expect(SSHHostResolver.hostname(fromSSHConfigDump: "hostname \n") == nil)
		#expect(SSHHostResolver.hostname(fromSSHConfigDump: "") == nil)
	}
}
