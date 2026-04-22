//
//  SumiScriptsRemoteInstall.swift
//  Sumi
//
//  Remote URL detection, install preview/fetch, and NSAlert confirmation.
//  Kept separate from SumiScriptsManager to keep lifecycle/injection code readable.
//

import AppKit
import Foundation

/// Parsed remote script shown in the install confirmation dialog.
struct SumiScriptsInstallPreview {
    let metadata: UserScriptMetadata
}

enum SumiScriptsRemoteInstall {

    static func isUserscriptURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        let absolute = url.absoluteString.lowercased()
        if path.hasSuffix(".user.js")
            || path.hasSuffix(".user.css")
            || absolute.contains(".user.js?")
            || absolute.contains(".user.css?")
        {
            return true
        }

        let host = url.host?.lowercased() ?? ""
        // Greasy Fork / Sleazy Fork often serve code under /scripts/…/code/… without a traditional path suffix.
        if (host.contains("greasyfork.org") || host.contains("sleazyfork.org"))
            && path.contains("/scripts/")
            && path.contains("/code/")
            && (path.contains(".user.js") || absolute.contains(".user.js"))
        {
            return true
        }

        if host == "openuserjs.org" || host == "www.openuserjs.org" {
            if path.hasPrefix("/install/") || path.hasPrefix("/src/scripts/") {
                return true
            }
        }

        if host.contains("githubusercontent.com"), path.contains(".user.js") {
            return true
        }

        return false
    }

    static func previewScript(from url: URL) async throws -> SumiScriptsInstallPreview {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let content = String(data: data, encoding: .utf8),
              let metadata = UserScriptMetadataParser.parse(content)
        else {
            throw SumiUserScriptError.invalidMetadata
        }
        return SumiScriptsInstallPreview(metadata: metadata)
    }

    @MainActor
    static func confirmInstall(preview: SumiScriptsInstallPreview, url: URL) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Install Userscript?"
        let metadata = preview.metadata
        let scopes = (metadata.matches + metadata.includes).prefix(6).joined(separator: "\n")
        let connects = metadata.connects.isEmpty ? "None" : metadata.connects.joined(separator: ", ")
        alert.informativeText = """
        \(metadata.name)
        Version: \(metadata.version ?? "unknown")
        Author: \(metadata.author ?? "unknown")

        Runs on:
        \(scopes.isEmpty ? "No declared pages" : scopes)

        Network access: \(connects)
        Source: \(url.absoluteString)
        """
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @MainActor
    static func showInstallError(_ error: Error, url: URL) {
        let alert = NSAlert(error: error)
        alert.messageText = "Userscript Install Failed"
        alert.informativeText = "\(url.absoluteString)\n\n\(error.localizedDescription)"
        alert.runModal()
    }
}
