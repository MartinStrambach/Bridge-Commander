import Foundation
import GitCore

/// One row of the commit graph: a commit dot plus the line segments
/// needed to render its cell. All segments are self-contained within the
/// row's cell so rows can be rendered lazily:
/// - pass-through lanes draw a straight vertical line through the full row
/// - incoming columns draw curves from the top edge into the dot (center)
/// - outgoing columns draw curves from the dot to the bottom edge
public struct GitGraphRow: Equatable, Sendable, Identifiable {
	public let commit: GitLogCommit

	/// Column of this commit's dot
	public let column: Int

	/// Columns whose lane runs straight through the full height of the row
	public let passThroughColumns: [Int]

	/// Columns from which lines converge into the dot (top half of the row).
	/// Contains the dot's own column when its lane continues from above.
	public let incomingColumns: [Int]

	/// Columns to which lines diverge from the dot (bottom half of the row).
	/// Contains the dot's own column when the first parent continues below.
	public let outgoingColumns: [Int]

	public var id: String { commit.hash }

	public init(
		commit: GitLogCommit,
		column: Int,
		passThroughColumns: [Int],
		incomingColumns: [Int],
		outgoingColumns: [Int]
	) {
		self.commit = commit
		self.column = column
		self.passThroughColumns = passThroughColumns
		self.incomingColumns = incomingColumns
		self.outgoingColumns = outgoingColumns
	}
}

/// Assigns commits to graph lanes (columns), SourceTree-style.
///
/// Commits must be in topological order (children before parents), as
/// produced by `git log --topo-order`. Each lane tracks the commit hash it
/// is waiting for; when that commit appears, all lanes waiting for it
/// converge into its dot, and the lane continues with the first parent.
/// Additional parents of merge commits either join an existing lane or
/// open a new one, reusing freed slots so columns stay stable.
public nonisolated enum GitGraphLayout {
	public static func layout(commits: [GitLogCommit]) -> [GitGraphRow] {
		// Expected commit hash per column; nil marks a free slot available for reuse
		var lanes: [String?] = []
		var rows: [GitGraphRow] = []
		rows.reserveCapacity(commits.count)

		for commit in commits {
			let matching = lanes.indices.filter { lanes[$0] == commit.hash }

			let column: Int
			if let first = matching.first {
				column = first
			}
			else if let free = lanes.firstIndex(where: { $0 == nil }) {
				column = free
			}
			else {
				column = lanes.count
				lanes.append(nil)
			}

			let passThroughColumns = lanes.indices.filter {
				lanes[$0] != nil && !matching.contains($0)
			}

			for index in matching {
				lanes[index] = nil
			}

			var outgoingColumns: [Int] = []
			if let firstParent = commit.parents.first {
				lanes[column] = firstParent
				outgoingColumns.append(column)

				for parent in commit.parents.dropFirst() {
					if let existing = lanes.firstIndex(of: parent) {
						outgoingColumns.append(existing)
					}
					else if let free = lanes.firstIndex(where: { $0 == nil }) {
						lanes[free] = parent
						outgoingColumns.append(free)
					}
					else {
						lanes.append(parent)
						outgoingColumns.append(lanes.count - 1)
					}
				}
			}
			else {
				lanes[column] = nil
			}

			rows.append(
				GitGraphRow(
					commit: commit,
					column: column,
					passThroughColumns: passThroughColumns,
					incomingColumns: matching,
					outgoingColumns: outgoingColumns
				)
			)

			while case .some(nil) = lanes.last {
				lanes.removeLast()
			}
		}

		return rows
	}

	/// Total number of columns needed to render all rows
	public static func laneCount(rows: [GitGraphRow]) -> Int {
		rows.reduce(0) { count, row in
			max(
				count,
				row.column + 1,
				(row.passThroughColumns.max() ?? -1) + 1,
				(row.incomingColumns.max() ?? -1) + 1,
				(row.outgoingColumns.max() ?? -1) + 1
			)
		}
	}
}
