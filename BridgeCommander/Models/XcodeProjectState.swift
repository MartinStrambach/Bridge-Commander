//
//  XcodeProjectState.swift
//  Bridge Commander
//
//  State enum for tracking Xcode project generation progress
//

import Foundation

enum XcodeProjectState: Equatable {
    case idle
    case checking
    case runningTi
    case runningTg
    case opening
    case error(String)

    var displayMessage: String {
        switch self {
        case .idle:
            return "Open Xcode Project"
        case .checking:
            return "Checking..."
        case .runningTi:
            return "Running ti..."
        case .runningTg:
            return "Running tg..."
        case .opening:
            return "Opening..."
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var isProcessing: Bool {
        switch self {
        case .idle, .error:
            return false
        default:
            return true
        }
    }
}
