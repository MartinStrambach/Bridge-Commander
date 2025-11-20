//
//  XcodeProjectButton.swift
//  Bridge Commander
//
//  Button component for opening/generating Xcode projects
//

import SwiftUI

struct XcodeProjectButton: View {
    let repositoryPath: String
    @EnvironmentObject var abbreviationMode: AbbreviationMode

    @State private var state: XcodeProjectState = .idle
    @State private var showingWarning = false
    @State private var projectExists: Bool?

    var body: some View {
        Group {
            if state.isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8, anchor: .center)
                    Text(buttonLabel)
                        .font(.body)
                }
                .frame(minWidth: abbreviationMode.isAbbreviated ? UIConstants.abbreviatedButtonWidth : UIConstants.normalButtonWidth)
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            } else if projectExists == false {
                Button(action: handleButtonClick) {
                    Label(buttonLabel, systemImage: buttonIcon)
                        .frame(minWidth: abbreviationMode.isAbbreviated ? UIConstants.abbreviatedButtonWidth : UIConstants.normalButtonWidth)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            } else {
                Button(action: handleButtonClick) {
                    Label(buttonLabel, systemImage: buttonIcon)
                        .frame(minWidth: abbreviationMode.isAbbreviated ? UIConstants.abbreviatedButtonWidth : UIConstants.normalButtonWidth)
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.regular)
        .fixedSize(horizontal: true, vertical: false)
        .disabled(state.isProcessing)
        .help(buttonTooltip)
        .task {
            checkProjectExists()
        }
        .alert("No Xcode Project Found", isPresented: $showingWarning) {
            Button("Cancel", role: .cancel) {
                state = .idle
            }
            Button("Generate") {
                Task {
                    await generateAndOpenProject()
                }
            }
        } message: {
            Text("No Xcode project or workspace was found in ios/Flashscore.\n\nWould you like to generate one by running 'ti' and 'tg' commands in the ios/Flashscore folder?")
        }
    }

    // MARK: - Computed Properties

    private var buttonLabel: String {
        switch state {
        case .idle:
            if projectExists == false {
                return abbreviationMode.isAbbreviated ? "Gen" : "Generate Xcode"
            } else {
                return abbreviationMode.isAbbreviated ? "Xcd" : "Xcode"
            }
        case .checking:
            return abbreviationMode.isAbbreviated ? "Chck" : "Checking"
        case .runningTi:
            return abbreviationMode.isAbbreviated ? "ti" : "Running ti"
        case .runningTg:
            return abbreviationMode.isAbbreviated ? "tg" : "Running tg"
        case .opening:
            return abbreviationMode.isAbbreviated ? "Opn" : "Opening"
        case .error:
            return abbreviationMode.isAbbreviated ? "Xcd" : "Xcode"
        }
    }

    private var buttonIcon: String {
        if projectExists == false && state == .idle {
            return "exclamationmark.triangle"
        } else {
            return "hammer"
        }
    }

    private var buttonTooltip: String {
        switch state {
        case .idle:
            if projectExists == false {
                return "Xcode project not found - click to generate"
            } else {
                return "Open Xcode project or workspace"
            }
        case .error(let message):
            return "Error: \(message)"
        default:
            return state.displayMessage
        }
    }

    // MARK: - Actions

    private func handleButtonClick() {
        Task {
            await checkAndOpenProject()
        }
    }

    private func checkProjectExists() {
        projectExists = XcodeProjectDetector.hasXcodeProject(in: repositoryPath)
    }

    @MainActor
    private func checkAndOpenProject() async {
        state = .checking

        // Check if project exists
        if let projectPath = XcodeProjectDetector.findXcodeProject(in: repositoryPath) {
            // Project exists, open it directly
            projectExists = true
            state = .opening
            do {
                try XcodeProjectGenerator.openProject(at: projectPath)
                state = .idle
            } catch {
                state = .error(error.localizedDescription)
                showErrorAlert(error.localizedDescription)
            }
        } else {
            // No project found, show warning
            projectExists = false
            state = .idle
            showingWarning = true
        }
    }

    @MainActor
    private func generateAndOpenProject() async {
        do {
            let projectPath = try await XcodeProjectGenerator.generateProject(at: repositoryPath) { newState in
                state = newState
            }

            state = .opening
            try XcodeProjectGenerator.openProject(at: projectPath)
            projectExists = true
            state = .idle

        } catch {
            state = .error(error.localizedDescription)
            showErrorAlert(error.localizedDescription)
        }
    }

    private func showErrorAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Xcode Project Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()

        // Reset to idle after showing error
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            state = .idle
        }
    }
}

#Preview {
    XcodeProjectButton(repositoryPath: "/Users/username/projects/my-project")
        .padding()
}
