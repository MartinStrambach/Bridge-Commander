import Foundation

/// Any JSON value, for the JSON-RPC messages MCP exchanges, whose `params` and `result` shapes
/// depend on the method.
public enum JSONValue: Codable, Equatable, Sendable {
	case null
	case bool(Bool)
	case number(Double)
	case string(String)
	case array([JSONValue])
	case object([String: JSONValue])

	public init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		if container.decodeNil() {
			self = .null
		}
		else if let value = try? container.decode(Bool.self) {
			self = .bool(value)
		}
		else if let value = try? container.decode(Double.self) {
			self = .number(value)
		}
		else if let value = try? container.decode(String.self) {
			self = .string(value)
		}
		else if let value = try? container.decode([JSONValue].self) {
			self = .array(value)
		}
		else {
			self = try .object(container.decode([String: JSONValue].self))
		}
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		switch self {
		case .null:
			try container.encodeNil()
		case let .bool(value):
			try container.encode(value)
		case let .number(value):
			// Whole numbers go out without a fraction: JSON-RPC ids are compared as written.
			if value.rounded() == value, abs(value) < 1e15 {
				try container.encode(Int64(value))
			}
			else {
				try container.encode(value)
			}
		case let .string(value):
			try container.encode(value)
		case let .array(value):
			try container.encode(value)
		case let .object(value):
			try container.encode(value)
		}
	}

	public subscript(key: String) -> JSONValue? {
		if case let .object(object) = self {
			return object[key]
		}
		return nil
	}

	public var stringValue: String? {
		if case let .string(value) = self {
			return value
		}
		return nil
	}

	/// A number, or a string holding one — models occasionally quote numbers.
	public var doubleValue: Double? {
		switch self {
		case let .number(value):
			value
		case let .string(value):
			Double(value)
		default:
			nil
		}
	}
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
	ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
	public init(stringLiteral value: String) {
		self = .string(value)
	}

	public init(booleanLiteral value: Bool) {
		self = .bool(value)
	}

	public init(integerLiteral value: Int) {
		self = .number(Double(value))
	}

	public init(arrayLiteral elements: JSONValue...) {
		self = .array(elements)
	}

	public init(dictionaryLiteral elements: (String, JSONValue)...) {
		self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
	}
}
