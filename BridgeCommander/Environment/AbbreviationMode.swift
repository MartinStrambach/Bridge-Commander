//
//  AbbreviationMode.swift
//  Bridge Commander
//
//  Environment object for managing button abbreviation mode
//

import SwiftUI
import Combine

class AbbreviationMode: ObservableObject {
    @Published var isAbbreviated: Bool = false
}
