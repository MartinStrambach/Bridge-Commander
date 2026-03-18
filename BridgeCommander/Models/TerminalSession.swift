// BridgeCommander/Models/TerminalSession.swift
import Foundation

enum TerminalSessionStatus: Equatable {
    case launching
    case active
    case waitingForInput
    case failed(String)
}

struct TerminalSession: Identifiable, Equatable {
    let id: UUID
    let repositoryPath: String
    var tabIndex: Int
    var status: TerminalSessionStatus

    init(repositoryPath: String, tabIndex: Int = 1) {
        self.id = UUID()
        self.repositoryPath = repositoryPath
        self.tabIndex = tabIndex
        self.status = .launching
    }
}
