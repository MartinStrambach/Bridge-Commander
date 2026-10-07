import Foundation
@testable import HomerFeature
import Testing

@Suite("Homer agent permissions")
struct HomerAgentPermissionsTests {
	private let factory = HomerAgent(name: "factory", isWritable: true)
	private let deploy = HomerAgent(name: "deploy-ios", isWritable: true)
	private let baked = HomerAgent(name: "baked", isWritable: false)

	@Test("an admin is offered everything but editing an agent the server cannot write")
	func admin() {
		let admin = HomerUser(username: "admin", role: "admin")

		#expect(admin.canRun(factory))
		#expect(admin.canEdit(factory))
		#expect(!admin.canEdit(baked))
		#expect(admin.canCreateAgents)
		#expect(admin.canReloadAgents)
	}

	@Test("a user is offered what their grants' actions and agent patterns allow")
	func grants() {
		let user = HomerUser(username: "dev", grants: [
			HomerUser.Grant(agents: ["factory"], actions: ["read", "run"]),
			HomerUser.Grant(agents: ["deploy-*"], actions: ["edit"]),
		])

		#expect(user.canRun(factory))
		#expect(!user.canEdit(factory))
		#expect(!user.canRun(deploy))
		#expect(user.canEdit(deploy))
		#expect(user.canCreateAgents)
		#expect(!user.canReloadAgents)
	}

	@Test("a read-only user is offered neither Run nor New Agent")
	func readOnly() {
		let user = HomerUser(username: "viewer", grants: [HomerUser.Grant(agents: ["*"], actions: ["read", "control"])])

		#expect(!user.canRun(factory))
		#expect(!user.canEdit(factory))
		#expect(!user.canCreateAgents)
		#expect(user.isGranted("control", on: "anything"))
		#expect(!user.isGranted("debug", on: nil))
	}
}
