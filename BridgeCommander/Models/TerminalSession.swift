// BridgeCommander/Models/TerminalSession.swift
import Foundation

enum TerminalSessionStatus: Equatable {
    case launching
    case active
    case failed(String)
}

struct TerminalSession: Identifiable, Equatable {
    var id: String { repositoryPath }
    let repositoryPath: String
    var status: TerminalSessionStatus

    init(repositoryPath: String) {
        self.repositoryPath = repositoryPath
        self.status = .launching
    }
}
