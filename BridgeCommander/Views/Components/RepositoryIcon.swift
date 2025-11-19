//
//  RepositoryIcon.swift
//  Bridge Commander
//
//  Icon component for displaying repository type
//

import SwiftUI

struct RepositoryIcon: View {
    let isWorktree: Bool
    let isMergeInProgress: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: isWorktree ? "tree" : "folder.badge.gearshape")
                .font(.title2)
                .foregroundColor(isWorktree ? .blue : .green)
                .frame(width: 32)

            // Merge indicator badge
            if isMergeInProgress {
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.red))
                    .offset(x: 2, y: -2)
            }
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        RepositoryIcon(isWorktree: false, isMergeInProgress: false)
        RepositoryIcon(isWorktree: true, isMergeInProgress: false)
        RepositoryIcon(isWorktree: false, isMergeInProgress: true)
        RepositoryIcon(isWorktree: true, isMergeInProgress: true)
    }
    .padding()
}
