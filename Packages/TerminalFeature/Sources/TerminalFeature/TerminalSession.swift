// BridgeCommander/Models/TerminalSession.swift
import Foundation

public enum TerminalSessionStatus: Equatable, Sendable {
	case launching
	case active
	case waitingForInput
	case failed(String)
}

public struct TerminalSession: Identifiable, Equatable, Sendable {
	public let id: UUID
	public let repositoryPath: String
	public let startingDirectory: String
	public var tabIndex: Int
	public var status: TerminalSessionStatus

	public init(repositoryPath: String, startingDirectory: String? = nil, tabIndex: Int = 1) {
		self.id = UUID()
		self.repositoryPath = repositoryPath
		self.startingDirectory = startingDirectory ?? repositoryPath
		self.tabIndex = tabIndex
		self.status = .launching
	}
}
