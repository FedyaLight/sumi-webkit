//
//  UserScriptStore+SwiftData.swift
//  Sumi
//
//  SwiftData mirror for installed userscripts. Source of truth remains the
//  on-disk catalog (`manifest.json` + script files). Entities are registered
//  in SumiStartupPersistence for the schema; only this store writes them.
//

import Foundation
import SwiftData

extension UserScriptStore {

    func persist(
        script: UserScript,
        sourceURL: URL
    ) {
        guard let context else { return }
        let metadataJSON = Self.metadataSnapshotJSON(script.metadata)
        let hash = Self.sha256Hex((try? Data(contentsOf: sourceURL)) ?? Data(script.code.utf8))
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
                    isEnabled: script.isEnabled
                )
            )
        }
        try? context.save()
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
        try? context.save()
    }

    func clearPersistedResources(for scriptId: UUID) {
        guard let context else { return }
        let descriptor = FetchDescriptor<UserScriptResourceEntity>()
        let existing = (try? context.fetch(descriptor)) ?? []
        for resource in existing where resource.scriptId == scriptId {
            context.delete(resource)
        }
        try? context.save()
    }

    func existingEntity(namespace: String, name: String) -> UserScriptEntity? {
        guard let context else { return nil }
        let descriptor = FetchDescriptor<UserScriptEntity>()
        return try? context.fetch(descriptor).first {
            $0.namespace == namespace && $0.name == name
        }
    }

    func contextEntity(filename: String) -> UserScriptEntity? {
        guard let context else { return nil }
        let descriptor = FetchDescriptor<UserScriptEntity>()
        return try? context.fetch(descriptor).first {
            URL(fileURLWithPath: $0.sourcePath).lastPathComponent == filename
        }
    }
}
