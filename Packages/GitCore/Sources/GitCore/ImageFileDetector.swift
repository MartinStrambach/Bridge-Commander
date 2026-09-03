import Foundation

/// Decides whether a path points at a raster image the diff viewer can render.
///
/// Only formats AppKit decodes natively are listed. SVG is deliberately absent: git diffs it as
/// text, so it never reaches the binary path this detector guards.
public nonisolated enum ImageFileDetector {

	public static let supportedExtensions: Set<String> = [
		"png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp", "avif", "ico", "icns",
	]

	public static func isImage(path: String) -> Bool {
		let fileExtension = (path as NSString).pathExtension.lowercased()
		return supportedExtensions.contains(fileExtension)
	}
}
