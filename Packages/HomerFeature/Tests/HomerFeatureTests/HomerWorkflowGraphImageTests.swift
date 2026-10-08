import AppKit
@testable import HomerFeature
import SwiftUI
import Testing

@MainActor
@Suite("Homer workflow graph image")
struct HomerWorkflowGraphImageTests {
	private static let layout = HomerGraphLayout.make(
		topology: .init(
			nodes: [.init(id: "__start__"), .init(id: "plan"), .init(id: "__end__")],
			edges: [.init(source: "__start__", target: "plan"), .init(source: "plan", target: "__end__")]
		),
		nodeSizes: [
			"__start__": CGSize(width: 56, height: 28),
			"plan": CGSize(width: 72, height: 36),
			"__end__": CGSize(width: 56, height: 28),
		],
		labelSizes: [:]
	)!

	@Test("the image is the whole graph with its padding, at twice the pixels and marked as such")
	func png() throws {
		let data = try #require(HomerWorkflowGraphDrawing.pngData(
			layout: Self.layout,
			status: nil,
			scale: 1,
			colorScheme: .light
		))
		let bitmap = try #require(NSBitmapImageRep(data: data))
		let padding = HomerWorkflowGraphDrawing.imagePadding
		let width = Self.layout.size.width + 2 * padding
		let height = Self.layout.size.height + 2 * padding
		#expect(Double(bitmap.size.width) == Double(width))
		#expect(Double(bitmap.size.height) == Double(height))
		#expect(bitmap.pixelsWide == Int((width * HomerWorkflowGraphDrawing.imageScale).rounded()))
		#expect(bitmap.pixelsHigh == Int((height * HomerWorkflowGraphDrawing.imageScale).rounded()))
	}

	@Test("the file name keeps the run or agent's name, with what a file name cannot hold replaced")
	func fileName() {
		#expect(HomerWorkflowGraphDrawing.fileName("Run 42 workflow") == "Run 42 workflow.png")
		#expect(HomerWorkflowGraphDrawing.fileName("team/factory: graph") == "team-factory- graph.png")
	}
}
