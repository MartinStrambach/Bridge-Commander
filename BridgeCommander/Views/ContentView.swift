//
//  ContentView.swift
//  Bridge Commander
//
//  Main view for the Bridge Commander application
//

import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = RepositoryScanner()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Content area
            if scanner.isScanning {
                scanningView
            } else if scanner.repositories.isEmpty {
                emptyStateView
            } else {
                repositoryListView
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bridge Commander")
                    .font(.title2)
                    .fontWeight(.bold)

                if let directory = scanner.selectedDirectory {
                    Text(directory)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("No directory selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 12) {
                if !scanner.repositories.isEmpty {
                    Text("\(scanner.repositories.count) repositories")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button(action: scanner.clearResults) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Clear results")
                }

                Button(action: scanner.selectAndScanDirectory) {
                    Label("Select Directory", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)
                .disabled(scanner.isScanning)
            }
        }
        .padding()
    }

    // MARK: - Scanning View

    private var scanningView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Scanning for repositories...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("No Repositories Found")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Select a directory to scan for Git repositories and worktrees")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: scanner.selectAndScanDirectory) {
                Label("Select Directory", systemImage: "folder")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Repository List View

    private var repositoryListView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(scanner.repositories) { repository in
                    RepositoryRowView(repository: repository)
                    Divider()
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
