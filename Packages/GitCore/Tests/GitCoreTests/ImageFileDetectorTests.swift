import Testing

@testable import GitCore

struct ImageFileDetectorTests {

	@Test(arguments: ["logo.png", "Assets/photo.jpg", "a/b/c.jpeg", "anim.gif", "icon.icns", "pic.webp", "scan.tiff", "shot.heic"])
	func recognisesRasterImages(path: String) {
		#expect(ImageFileDetector.isImage(path: path))
	}

	@Test
	func extensionMatchIsCaseInsensitive() {
		#expect(ImageFileDetector.isImage(path: "Screenshot.PNG"))
		#expect(ImageFileDetector.isImage(path: "photo.JPEG"))
	}

	@Test(arguments: ["Sources/App.swift", "README.md", "vector.svg", "font.ttf", "png", "archive.png.zip", ".png.bak"])
	func rejectsNonImages(path: String) {
		#expect(!ImageFileDetector.isImage(path: path))
	}
}
