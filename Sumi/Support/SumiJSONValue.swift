import Foundation

enum SumiJSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([SumiJSONValue])
    case object([String: SumiJSONValue])

    init(foundationObject value: Any?) {
        switch value {
        case nil, is NSNull:
            self = .null
        case let value as Bool:
            self = .bool(value)
        case let value as Int:
            self = .int(value)
        case let value as Double:
            self = .double(value)
        case let value as Float:
            self = .double(Double(value))
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .double(value.doubleValue)
            }
        case let value as String:
            self = .string(value)
        case let value as [Any]:
            self = .array(value.map(SumiJSONValue.init(foundationObject:)))
        case let value as [String: Any]:
            self = .object(value.mapValues(SumiJSONValue.init(foundationObject:)))
        default:
            self = .string(String(describing: value!))
        }
    }

    var foundationObject: Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .int(let value):
            return value
        case .double(let value):
            return value
        case .string(let value):
            return value
        case .array(let values):
            return values.map(\.foundationObject)
        case .object(let values):
            return values.mapValues(\.foundationObject)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([SumiJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: SumiJSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let values):
            try container.encode(values)
        case .object(let values):
            try container.encode(values)
        }
    }
}
