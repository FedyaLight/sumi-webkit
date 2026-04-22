//
//  ExtensionRuntimeBundledScript.swift
//  Sumi
//
//  Bundled runtime templates for WebExtension compatibility shims.
//

import Foundation

/// Type anchor for `Bundle(for:)` — must live in the Sumi app target alongside
/// `ExtensionRuntimeResources/*.js`.
final class ExtensionRuntimeBundleLocator {}

enum ExtensionRuntimeBundledScript {
    static let resourceSubdirectory = "ExtensionRuntimeResources"

    private static var bundle: Bundle {
        Bundle(for: ExtensionRuntimeBundleLocator.self)
    }

    static func source(fileName: String) -> String? {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let base = (trimmed as NSString).deletingPathExtension
        let ext = (trimmed as NSString).pathExtension.isEmpty
            ? "js"
            : (trimmed as NSString).pathExtension

        guard let url = bundle.url(
            forResource: base,
            withExtension: ext,
            subdirectory: resourceSubdirectory
        ) ?? bundle.url(forResource: base, withExtension: ext) else {
            return nil
        }

        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func rendered(
        fileName: String,
        replacements: [String: String] = [:]
    ) -> String? {
        guard var source = source(fileName: fileName) else {
            return nil
        }

        for (placeholder, value) in replacements.sorted(by: { $0.key < $1.key }) {
            source = source.replacingOccurrences(of: placeholder, with: value)
        }

        return source
    }
}
