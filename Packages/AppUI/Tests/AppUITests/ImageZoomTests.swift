import CoreGraphics
import SwiftUI
import Testing
@testable import AppUI

struct ImageZoomTests {
	@Test func pinchAtCenterScalesWithoutOffset() {
		let zoom = ImageZoom.identity.magnified(by: 2, anchor: .center)
		#expect(zoom.scale == 2)
		#expect(zoom.offset == .zero)
	}

	@Test func pinchKeepsAnchoredPointInPlace() {
		// The top-left corner stays put, so the image shifts right and down by half the added size.
		let zoom = ImageZoom.identity.magnified(by: 2, anchor: .topLeading)
		#expect(zoom.offset == CGSize(width: 0.5, height: 0.5))
	}

	@Test func scaleIsClamped() {
		#expect(ImageZoom.identity.magnified(by: 0.2, anchor: .center) == .identity)
		#expect(ImageZoom.identity.magnified(by: 100, anchor: .center).scale == ImageZoom.maxScale)
	}

	@Test func zoomingBackOutRecentersImage() {
		let zoomedIn = ImageZoom.identity.magnified(by: 4, anchor: .bottomTrailing)
		#expect(zoomedIn.magnified(by: 0.25, anchor: .topLeading) == .identity)
	}

	@Test func panIsMeasuredInFittedSize() {
		let zoom = ImageZoom(scale: 3, offset: .zero)
			.panned(by: CGSize(width: 50, height: -20), fittedSize: CGSize(width: 200, height: 100))
		#expect(zoom.offset == CGSize(width: 0.25, height: -0.2))
	}

	@Test func panCannotRevealSpaceBesideImage() {
		let zoom = ImageZoom(scale: 2, offset: .zero)
			.panned(by: CGSize(width: 1000, height: -1000), fittedSize: CGSize(width: 100, height: 100))
		#expect(zoom.offset == CGSize(width: 0.5, height: -0.5))
		#expect(ImageZoom.identity.panned(by: CGSize(width: 10, height: 10), fittedSize: CGSize(width: 100, height: 100)) == .identity)
	}
}
