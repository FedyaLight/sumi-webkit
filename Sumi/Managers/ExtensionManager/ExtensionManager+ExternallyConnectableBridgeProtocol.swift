//
//  ExtensionManager+ExternallyConnectableBridgeProtocol.swift
//  Sumi
//
//  Typed bridge envelopes for externally_connectable native/page/isolated messaging.
//

import Foundation

@available(macOS 15.5, *)
enum ExternallyConnectableBridgeCodec {
    static func decode<T: Decodable>(
        _ type: T.Type,
        from foundationObject: Any
    ) -> T? {
        guard JSONSerialization.isValidJSONObject(foundationObject),
              let data = try? JSONSerialization.data(withJSONObject: foundationObject, options: [.sortedKeys])
        else {
            return nil
        }

        return try? JSONDecoder().decode(type, from: data)
    }

    static func foundationObject<T: Encodable>(
        from value: T
    ) -> Any? {
        guard let data = try? JSONEncoder().encode(value) else {
            return nil
        }

        return try? JSONSerialization.jsonObject(with: data)
    }
}

@available(macOS 15.5, *)
enum ExternallyConnectableBridgeJSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: ExternallyConnectableBridgeJSONValue])
    case array([ExternallyConnectableBridgeJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let object = try? container.decode([String: ExternallyConnectableBridgeJSONValue].self) {
            self = .object(object)
        } else if let array = try? container.decode([ExternallyConnectableBridgeJSONValue].self) {
            self = .array(array)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported externally_connectable JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let string):
            try container.encode(string)
        case .number(let number):
            try container.encode(number)
        case .bool(let bool):
            try container.encode(bool)
        case .object(let object):
            try container.encode(object)
        case .array(let array):
            try container.encode(array)
        case .null:
            try container.encodeNil()
        }
    }

    var foundationObject: Any {
        switch self {
        case .string(let string):
            return string
        case .number(let number):
            return number
        case .bool(let bool):
            return bool
        case .object(let object):
            return object.mapValues(\.foundationObject)
        case .array(let array):
            return array.map(\.foundationObject)
        case .null:
            return NSNull()
        }
    }
}

@available(macOS 15.5, *)
struct ExternallyConnectableBridgeEnvelope: Decodable {
    let bridgeVersion: Int?
    let featureName: String
    let method: String
    let id: String?
    let params: [String: ExternallyConnectableBridgeJSONValue]?

    func decodeParams<T: Decodable>(
        _ type: T.Type
    ) -> T? {
        ExternallyConnectableBridgeCodec.decode(
            type,
            from: (params ?? [:]).mapValues(\.foundationObject)
        )
    }
}

@available(macOS 15.5, *)
struct ExternallyConnectableBridgeSenderMetadata: Codable {
    let origin: String?
    let url: String?
    let frameId: Int?

    var foundationObject: [String: Any] {
        [
            "origin": origin as Any,
            "url": url as Any,
            "frameId": frameId as Any,
        ]
    }
}

@available(macOS 15.5, *)
struct ExternallyConnectableNativeSendMessageRequest: Decodable {
    let documentURL: String?
    let extensionId: String?
    let message: ExternallyConnectableBridgeJSONValue?
    let options: ExternallyConnectableBridgeJSONValue?
    let origin: String?
    let requestType: String?
    let timeoutMs: Double?
}

@available(macOS 15.5, *)
struct ExternallyConnectableNativeConnectOpenRequest: Decodable {
    let documentURL: String?
    let extensionId: String?
    let origin: String?
    let timeoutMs: Double?
    let portId: String?
    let connectInfo: [String: ExternallyConnectableBridgeJSONValue]?
}

@available(macOS 15.5, *)
struct ExternallyConnectableNativeConnectPostMessageRequest: Decodable {
    let documentURL: String?
    let extensionId: String?
    let origin: String?
    let timeoutMs: Double?
    let portId: String?
    let message: ExternallyConnectableBridgeJSONValue?
}

@available(macOS 15.5, *)
struct ExternallyConnectableNativeConnectDisconnectRequest: Decodable {
    let documentURL: String?
    let extensionId: String?
    let origin: String?
    let timeoutMs: Double?
    let portId: String?
}

@available(macOS 15.5, *)
struct ExternallyConnectableNativeConnectMessageEvent: Decodable {
    let portId: String?
    let message: ExternallyConnectableBridgeJSONValue?
}

@available(macOS 15.5, *)
struct ExternallyConnectableNativeConnectDisconnectEvent: Decodable {
    let portId: String?
    let error: String?
}

@available(macOS 15.5, *)
struct ExternallyConnectableNativeAcceptedResponse: Encodable {
    let accepted: Bool
    let portId: String?

    init(
        accepted: Bool = true,
        portId: String? = nil
    ) {
        self.accepted = accepted
        self.portId = portId
    }

    enum CodingKeys: String, CodingKey {
        case accepted
        case portId
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accepted, forKey: .accepted)
        try container.encodeIfPresent(portId, forKey: .portId)
    }
}
