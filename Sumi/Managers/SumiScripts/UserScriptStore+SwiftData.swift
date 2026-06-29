//
//  UserScriptStore+SwiftData.swift
//  Sumi
//
//  SwiftData mirror for installed userscripts. Source of truth remains the
//  on-disk catalog (`manifest.json` + script files). Entities are registered
//  in SumiStartupPersistence for the schema; only this store writes them.
//

import Foundation
import OSLog
import SwiftData

private enum UserScriptSwiftDataDiagnostics {
    static let log = Logger.sumi(category: "SumiScripts")
}

extension UserScriptStore {
    func persist(
        script: SumiInstalledUserScript,
        sourceURL: URL
    ) {
        guard let context else { return }
        let metadataJSON = Self.metadataSnapshotJSON(script.metadata)
        let hash = Self.sha256Hex(sourceDataForHash(sourceURL: sourceURL, fallbackCode: script.code))
        if let entity = existingEntity(namespace: script.metadata.namespace ?? "", name: script.metadata.name) {
            entity.version = script.metadata.version
            entity.scriptDescription = script.metadata.description
            entity.author = script.metadata.author
            entity.iconURLString = script.metadata.icon
            entity.homepageURLString = script.metadata.homepageURL
            entity.supportURLString = script.metadata.supportURL
            entity.downloadURLString = script.metadata.downloadURL
            entity.updateURLString = script.metadata.updateURL
            entity.sourcePath = sourceURL.path
            entity.contentHash = hash
            entity.metadataJSON = metadataJSON
            entity.isEnabled = script.isEnabled
            entity.lastUpdateDate = Date()
        } else {
            context.insert(
                UserScriptEntity(
                    id: script.id,
                    namespace: script.metadata.namespace ?? "",
                    name: script.metadata.name,
                    version: script.metadata.version,
                    scriptDescription: script.metadata.description,
                    author: script.metadata.author,
                    iconURLString: script.metadata.icon,
                    homepageURLString: script.metadata.homepageURL,
                    supportURLString: script.metadata.supportURL,
                    downloadURLString: script.metadata.downloadURL,
                    updateURLString: script.metadata.updateURL,
                    sourcePath: sourceURL.path,
                    contentHash: hash,
                    metadataJSON: metadataJSON,
                    isEnabled: script.isEnabled,
                    allowPrivateBrowsing: script.allowPrivateBrowsing
                )
            )
        }
        saveUserScriptContext(context, operation: "saving userscript metadata mirror for \(script.filename)")
    }

    func persistResource(
        scriptId: UUID,
        kind: String,
        name: String,
        sourceURL: URL,
        localFile: URL,
        mimeType: String?,
        data: Data
    ) {
        guard let context else { return }
        context.insert(
            UserScriptResourceEntity(
                scriptId: scriptId,
                kind: kind,
                name: name,
                sourceURLString: sourceURL.absoluteString,
                localPath: localFile.path,
                mimeType: mimeType,
                contentHash: Self.sha256Hex(data)
            )
        )
        saveUserScriptContext(context, operation: "saving userscript resource mirror for \(name)")
    }

    func clearPersistedResources(for scriptId: UUID) {
        guard let context else { return }
        let descriptor = FetchDescriptor<UserScriptResourceEntity>()
        let existing: [UserScriptResourceEntity]
        do {
            existing = try context.fetch(descriptor)
        } catch {
            UserScriptSwiftDataDiagnostics.log.error(
                "Failed to fetch userscript resources before clearing \(scriptId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        for resource in existing where resource.scriptId == scriptId {
            context.delete(resource)
        }
        saveUserScriptContext(context, operation: "clearing userscript resources for \(scriptId.uuidString)")
    }

    func existingEntity(namespace: String, name: String) -> UserScriptEntity? {
        guard let context else { return nil }
        let descriptor = FetchDescriptor<UserScriptEntity>()
        do {
            return try context.fetch(descriptor).first {
                $0.namespace == namespace && $0.name == name
            }
        } catch {
            UserScriptSwiftDataDiagnostics.log.error(
                "Failed to fetch userscript entity for \(namespace, privacy: .public)/\(name, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    func contextEntity(filename: String) -> UserScriptEntity? {
        guard let context else { return nil }
        let descriptor = FetchDescriptor<UserScriptEntity>()
        do {
            return try context.fetch(descriptor).first {
                URL(fileURLWithPath: $0.sourcePath).lastPathComponent == filename
            }
        } catch {
            UserScriptSwiftDataDiagnostics.log.error(
                "Failed to fetch userscript entity for \(filename, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private func sourceDataForHash(sourceURL: URL, fallbackCode: String) -> Data {
        do {
            return try Data(contentsOf: sourceURL)
        } catch {
            UserScriptSwiftDataDiagnostics.log.error(
                "Failed to read userscript source for SwiftData hash at \(sourceURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return Data(fallbackCode.utf8)
        }
    }

    private func saveUserScriptContext(_ context: ModelContext, operation: String) {
        do {
            try context.save()
        } catch {
            UserScriptSwiftDataDiagnostics.log.error(
                "Failed \(operation, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
