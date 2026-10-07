import Foundation
import IOSurface

/// A coarse summary of the screen, cheap enough to take every few tens of milliseconds while an
/// animation runs: a grid laid over the framebuffer, each cell holding the mean of a sparse sample
/// of its pixels.
///
/// It is read straight out of the simulator's `IOSurface` under a read-only lock — no Core Image,
/// no copy. A fingerprint is only ever compared with another of the same screen, so a pixel's
/// value is simply the sum of its bytes: that moves whenever the pixel does whatever the channel
/// order ('BGRA' in practice), and alpha, constant on an opaque framebuffer, cancels out.
struct ScreenFingerprint: Equatable, Sendable {
	let columns: Int
	let rows: Int
	/// Row-major, one per cell: the mean byte sum of the cell's sampled pixels, in sixteenths so
	/// a change too small to move a whole unit of the mean still shows.
	let cells: [UInt32]

	init(columns: Int, rows: Int, cells: [UInt32]) {
		precondition(cells.count == columns * rows, "a fingerprint needs one value per cell")
		self.columns = columns
		self.rows = rows
		self.cells = cells
	}

	/// How many cells differ from `other`'s by more than `tolerance`. Fingerprints of different
	/// grids (the surface was replaced by one of another size) differ everywhere.
	func changedCells(comparedTo other: ScreenFingerprint, tolerance: UInt32) -> Int {
		guard columns == other.columns, rows == other.rows else {
			return max(cells.count, other.cells.count)
		}
		var changed = 0
		for index in cells.indices {
			let a = cells[index]
			let b = other.cells[index]
			if (a > b ? a - b : b - a) > tolerance {
				changed += 1
			}
		}
		return changed
	}

	/// Cells about 48 pixels square — 16 points on a 3× screen — so a caret, a checkmark or a
	/// toggle's knob covers a few whole cells rather than vanishing into a large one's mean.
	static let cellSize = 48

	/// Every third pixel across and every fourth row down: about 190 samples a cell, from a quarter
	/// of the framebuffer's rows. A vertical stroke 1 point wide is 2–3 pixels, so text and a caret
	/// are still seen; reading every pixel would cost twelve times as much for the same verdict.
	/// Measured on a 1206×2622 framebuffer: ~0.7 ms a fingerprint optimized, ~2 ms in Debug.
	static let columnStride = 3
	static let rowStride = 4

	/// Samples a framebuffer. Nil when it is not one this can read — 4 bytes a pixel, unplanar and
	/// uncompressed, which is what CoreSimulator hands out ('BGRA') — or cannot be locked.
	static func sample(_ surface: IOSurfaceRef) -> ScreenFingerprint? {
		let width = IOSurfaceGetWidth(surface)
		let height = IOSurfaceGetHeight(surface)
		guard
			width > 0,
			height > 0,
			IOSurfaceGetBytesPerElement(surface) == 4,
			IOSurfaceGetPlaneCount(surface) == 0,
			IOSurfaceGetElementWidth(surface) == 1,
			IOSurfaceGetElementHeight(surface) == 1
		else {
			return nil
		}

		guard IOSurfaceLock(surface, .readOnly, nil) == kIOReturnSuccess else {
			return nil
		}
		defer {
			IOSurfaceUnlock(surface, .readOnly, nil)
		}
		return sample(
			UnsafeRawPointer(IOSurfaceGetBaseAddress(surface)),
			width: width,
			height: height,
			bytesPerRow: IOSurfaceGetBytesPerRow(surface)
		)
	}

	/// Samples 4-byte pixels in memory: `height` rows of `bytesPerRow` bytes.
	///
	/// Written for an unoptimized build too, which the app's Debug configuration is: plain `while`
	/// loops over raw pointers, and the cell of each sampled column worked out once. With `for`
	/// over ranges, arrays and a byte loop per pixel a fingerprint took ~400 ms at `-Onone`.
	static func sample(
		_ base: UnsafeRawPointer,
		width: Int,
		height: Int,
		bytesPerRow: Int,
		cellSize: Int = cellSize,
		columnStride: Int = columnStride,
		rowStride: Int = rowStride
	) -> ScreenFingerprint {
		let columns = max(1, (width + cellSize / 2) / cellSize)
		let rows = max(1, (height + cellSize / 2) / cellSize)
		let cellCount = columns * rows

		// Byte offset and grid column of each sampled pixel in a row.
		let sampledColumns = (width - columnStride / 2 + columnStride - 1) / columnStride
		let offsets = UnsafeMutablePointer<Int>.allocate(capacity: sampledColumns)
		let cellColumns = UnsafeMutablePointer<Int>.allocate(capacity: sampledColumns)
		let sums = UnsafeMutablePointer<UInt64>.allocate(capacity: cellCount)
		let counts = UnsafeMutablePointer<UInt64>.allocate(capacity: cellCount)
		defer {
			offsets.deallocate()
			cellColumns.deallocate()
			sums.deallocate()
			counts.deallocate()
		}
		sums.initialize(repeating: 0, count: cellCount)
		counts.initialize(repeating: 0, count: cellCount)
		var index = 0
		while index < sampledColumns {
			let x = columnStride / 2 + index * columnStride
			offsets[index] = x * 4
			cellColumns[index] = Swift.min(x * columns / width, columns - 1)
			index += 1
		}

		var y = rowStride / 2
		while y < height {
			let rowCells = sums + Swift.min(y * rows / height, rows - 1) * columns
			let rowCounts = counts + Swift.min(y * rows / height, rows - 1) * columns
			let line = base + y * bytesPerRow
			var column = 0
			while column < sampledColumns {
				let pixel = line.loadUnaligned(fromByteOffset: offsets[column], as: UInt32.self)
				// The four bytes summed, two lanes at a time.
				let pairs = (pixel & 0x00FF_00FF) &+ ((pixel >> 8) & 0x00FF_00FF)
				rowCells[cellColumns[column]] &+= UInt64((pairs & 0xFFFF) &+ (pairs >> 16))
				rowCounts[cellColumns[column]] &+= 1
				column += 1
			}
			y += rowStride
		}

		var cells = [UInt32](repeating: 0, count: cellCount)
		index = 0
		while index < cellCount {
			if counts[index] > 0 {
				cells[index] = UInt32(truncatingIfNeeded: sums[index] * 16 / counts[index])
			}
			index += 1
		}
		return ScreenFingerprint(columns: columns, rows: rows, cells: cells)
	}
}
