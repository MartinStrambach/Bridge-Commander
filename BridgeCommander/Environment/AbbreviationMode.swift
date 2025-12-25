import ComposableArchitecture
import SwiftUI

extension SharedReaderKey where Self == InMemoryKey<Bool> {
	static var isAbbreviated: Self {
		inMemory("isAbbreviated")
	}
}
