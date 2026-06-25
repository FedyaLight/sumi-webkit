//
//  NativeMessagingStdioFraming.swift
//  Sumi
//
//  Shared length-prefixed JSON framing used by documented native-messaging transports.
//

import Foundation

enum NativeMessagingStdioFramingError: Error, Equatable {
    case malformedMessage
}

enum NativeMessagingStdioFraming {
    /// Standard native messaging frame cap used by Chromium-style hosts.
    static let maxFrameBytes = 1_048_576

    static func encode(_ object: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw NativeMessagingStdioFramingError.malformedMessage
        }
        let json = try JSONSerialization.data(withJSONObject: object)
        var length = UInt32(json.count).littleEndian
        var data = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        data.append(json)
        return data
    }

    static func decodeNext(from buffer: inout Data) -> Any? {
        guard buffer.count >= MemoryLayout<UInt32>.size else { return nil }
        let length = buffer.prefix(MemoryLayout<UInt32>.size)
            .enumerated()
            .reduce(UInt32(0)) { result, element in
                let (offset, byte) = element
                return result | (UInt32(byte) << UInt32(offset * 8))
            }
        let frameSize = Int(length)
        guard frameSize <= maxFrameBytes else {
            buffer.removeAll(keepingCapacity: false)
            return NSNull()
        }
        guard buffer.count >= MemoryLayout<UInt32>.size + frameSize else {
            return nil
        }
        let jsonStart = MemoryLayout<UInt32>.size
        let jsonEnd = jsonStart + frameSize
        let json = buffer.subdata(in: jsonStart..<jsonEnd)
        buffer.removeSubrange(0..<jsonEnd)
        return (try? JSONSerialization.jsonObject(with: json)) ?? NSNull()
    }
}
