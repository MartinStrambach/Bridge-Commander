import Foundation

/// User-adjustable column widths for the commit graph table.
/// The description column is flexible and absorbs the remaining space,
/// so only the fixed columns are stored.
public struct GitGraphColumnWidths: Codable, Equatable, Sendable {
	public enum Column: CaseIterable, Sendable {
		case graph
		case author
		case date
		case hash
	}

	public var graph: Double
	public var author: Double
	public var date: Double
	public var hash: Double

	public init(
		graph: Double = 140,
		author: Double = 130,
		date: Double = 130,
		hash: Double = 70
	) {
		self.graph = graph
		self.author = author
		self.date = date
		self.hash = hash
	}

	public static func range(for column: Column) -> ClosedRange<Double> {
		switch column {
		case .graph:
			40...600
		case .author:
			50...400
		case .date:
			60...400
		case .hash:
			40...300
		}
	}

	/// Reads and writes a column's width; writes are clamped to the column's allowed range
	public subscript(column: Column) -> Double {
		get {
			switch column {
			case .graph:
				graph
			case .author:
				author
			case .date:
				date
			case .hash:
				hash
			}
		}
		set {
			let range = Self.range(for: column)
			let clamped = min(max(newValue, range.lowerBound), range.upperBound)
			switch column {
			case .graph:
				graph = clamped
			case .author:
				author = clamped
			case .date:
				date = clamped
			case .hash:
				hash = clamped
			}
		}
	}
}
