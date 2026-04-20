//
//  UserScript.swift
//  Sumi
//
//  Model representing a single loaded userscript with its metadata,
//  code, and runtime state.
//

import Foundation
import WebKit

final class UserScript: Identifiable {
    let id: UUID
    let filename: String
    /// When `lazyScriptBody` is enabled, code may be empty until first `assembledCode` / `code` access; then loaded from `sourceFileURL`.
    var metadata: UserScriptMetadata
    /// Source file for deferred body load (nil when body is stored in `metadata.code`).
    private(set) var sourceFileURL: URL?
    var isEnabled: Bool
    /// Bundled Sumi compat preludes from `// @sumi-compat` (after GM shim, before @require).
    var compatPreludeFragments: [String]
    var requiredCode: [String]  // Contents of @require resources, in order
    var resourceData: [String: String] // Contents of @resource resources, mapped by name
    var menuCommands: [String: String] = [:] // caption: uuid/id for callback

    /// Date the source file was last modified on disk.
    var lastModified: Date

    init(
        id: UUID = UUID(),
        filename: String,
        metadata: UserScriptMetadata,
        sourceFileURL: URL? = nil,
        isEnabled: Bool = true,
        compatPreludeFragments: [String] = [],
        requiredCode: [String] = [],
        resourceData: [String: String] = [:],
        lastModified: Date = Date()
    ) {
        self.id = id
        self.filename = filename
        self.metadata = metadata
        self.sourceFileURL = sourceFileURL
        self.isEnabled = isEnabled
        self.compatPreludeFragments = compatPreludeFragments
        self.requiredCode = requiredCode
        self.resourceData = resourceData
        self.lastModified = lastModified
    }

    // MARK: - Computed Properties

    var name: String { metadata.name }
    var code: String {
        resolveDeferredBodyIfNeeded()
        return metadata.code
    }
    var fileType: UserScriptFileType { metadata.fileType }

    var injectionTime: WKUserScriptInjectionTime {
        switch metadata.runAt {
        case .documentStart:
            return .atDocumentStart
        case .documentBody, .documentEnd, .documentIdle:
            return .atDocumentEnd
        }
    }

    var forMainFrameOnly: Bool {
        metadata.noframes
    }

    var effectiveWeight: Int {
        metadata.weight
    }

    /// Whether this script uses any GM APIs that require content-world isolation.
    var requiresContentWorldIsolation: Bool {
        let grants = metadata.grants
        if grants.isEmpty || grants.contains("none") {
            return false
        }
        return true
    }

    /// Whether this script uses GM_xmlhttpRequest / GM.xmlHttpRequest.
    var usesXMLHttpRequest: Bool {
        let grants = metadata.grants
        return grants.contains("GM_xmlhttpRequest") || grants.contains("GM.xmlHttpRequest")
    }

    /// The full assembled code including @require prepends, GM API shim, and user code.
    func assembledCode(gmShim: String) -> String {
        resolveDeferredBodyIfNeeded()
        var parts: [String] = []

        // 1. GM API shim. @require dependencies run in the same userscript
        // sandbox and may use GM_* globals too.
        if requiresContentWorldIsolation {
            parts.append(gmShim)
        }

        // 2. Sumi compat preludes (@sumi-compat), before remote @require bodies.
        for fragment in compatPreludeFragments {
            parts.append(fragment)
        }

        // 3. Required scripts, in metadata order.
        for req in requiredCode {
            parts.append(req)
        }

        // 4. User code wrapped in IIFE with error handling unless @unwrap asks
        // for global execution.
        if metadata.unwrap {
            parts.append("""
            \(code)
            //# sourceURL=sumi-userscript://\(filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename)
            """)
            return parts.joined(separator: "\n\n")
        }

        let safeFilename = filename.replacingOccurrences(of: "`", with: "\\`")
        let wrapperPrefix = metadata.topLevelAwait ? "(async () => {" : "(() => {"
        let wrappedCode = """
        \(wrapperPrefix)
            try {
        // ===UserScript===start===
        \(code)
        // ===UserScript====end====
            } catch (error) {
                console.error(`\(safeFilename)`, error);
            }
        })(); //# sourceURL=sumi-userscript://\(filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename)
        """
        parts.append(wrappedCode)

        return parts.joined(separator: "\n\n")
    }

    private func resolveDeferredBodyIfNeeded() {
        guard let fileURL = sourceFileURL, metadata.code.isEmpty else { return }
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
              let reparsed = UserScriptMetadataParser.parse(content)
        else {
            return
        }
        metadata = reparsed
        compatPreludeFragments = UserScriptCompatAssembly.preludeFragments(for: reparsed)
        sourceFileURL = nil
    }
}
