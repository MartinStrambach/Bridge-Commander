//
//  RepositoryIcon.swift
//  Bridge Commander
//
//  Icon component for displaying repository type
//

import SwiftUI

struct RepositoryIcon: View {
    let isWorktree: Bool

    var body: some View {
        Image(systemName: isWorktree ? "tree" : "folder.badge.gearshape")
            .font(.title2)
            .foregroundColor(isWorktree ? .blue : .green)
            .frame(width: 32)
    }
}

#Preview {
    HStack(spacing: 20) {
        RepositoryIcon(isWorktree: false)
        RepositoryIcon(isWorktree: true)
    }
    .padding()
}
