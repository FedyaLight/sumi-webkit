//
//  SafariExtensionDiagnosticJSON.swift
//  Sumi
//
//  Shared JSON formatting for Safari extension diagnostic reports.
//

import Foundation

enum SafariExtensionDiagnosticJSON {
    static func encodedString<T: Encodable>(
        _ value: T,
        dateEncodingStrategy: JSONEncoder.DateEncodingStrategy = .deferredToDate,
        outputFormatting: JSONEncoder.OutputFormatting = [.sortedKeys]
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = dateEncodingStrategy
        encoder.outputFormatting = outputFormatting
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    static func prettyPrintedString<T: Encodable>(_ value: T) throws -> String {
        try encodedString(
            value,
            dateEncodingStrategy: .iso8601,
            outputFormatting: [.sortedKeys, .prettyPrinted]
        )
    }
}
