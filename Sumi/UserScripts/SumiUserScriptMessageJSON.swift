//
//  SumiUserScriptMessageJSON.swift
//  Sumi
//
//  JSON encoding helpers for native userscript bridge responses.
//

import Foundation
import OSLog

enum SumiUserScriptMessageJSON {
    private static let log = Logger.sumi(category: "UserScripts")

    static func optionalString<T: Encodable>(_ value: T, context: String) -> String? {
        do {
            return try encodedString(value)
        } catch {
            log.error(
                "Failed to encode userscript message response \(context, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    static func string<T: Encodable>(
        _ value: T,
        context: String,
        fallback: String
    ) -> String {
        do {
            return try encodedString(value)
        } catch {
            log.error(
                "Failed to encode userscript error response \(context, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return fallback
        }
    }

    private static func encodedString<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}
