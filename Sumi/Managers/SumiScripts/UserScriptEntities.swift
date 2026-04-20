//
//  UserScriptEntities.swift
//  Sumi
//
//  SwiftData persistence for Sumi's native userscript runtime.
//

import Foundation
import SwiftData

@Model
final class UserScriptEntity {
    @Attribute(.unique) var id: UUID
    var namespace: String
    var name: String
    var version: String?
    var scriptDescription: String?
    var author: String?
    var iconURLString: String?
    var homepageURLString: String?
    var supportURLString: String?
    var downloadURLString: String?
    var updateURLString: String?
    var sourcePath: String
    var contentHash: String
    var metadataJSON: String
    var isEnabled: Bool
    var allowPrivateBrowsing: Bool
    var installDate: Date
    var lastUpdateDate: Date
    var lastRunError: String?

    init(
        id: UUID = UUID(),
        namespace: String,
        name: String,
        version: String?,
        scriptDescription: String?,
        author: String?,
        iconURLString: String?,
        homepageURLString: String?,
        supportURLString: String?,
        downloadURLString: String?,
        updateURLString: String?,
        sourcePath: String,
        contentHash: String,
        metadataJSON: String,
        isEnabled: Bool = true,
        allowPrivateBrowsing: Bool = false,
        installDate: Date = Date(),
        lastUpdateDate: Date = Date(),
        lastRunError: String? = nil
    ) {
        self.id = id
        self.namespace = namespace
        self.name = name
        self.version = version
        self.scriptDescription = scriptDescription
        self.author = author
        self.iconURLString = iconURLString
        self.homepageURLString = homepageURLString
        self.supportURLString = supportURLString
        self.downloadURLString = downloadURLString
        self.updateURLString = updateURLString
        self.sourcePath = sourcePath
        self.contentHash = contentHash
        self.metadataJSON = metadataJSON
        self.isEnabled = isEnabled
        self.allowPrivateBrowsing = allowPrivateBrowsing
        self.installDate = installDate
        self.lastUpdateDate = lastUpdateDate
        self.lastRunError = lastRunError
    }
}

@Model
final class UserScriptResourceEntity {
    @Attribute(.unique) var id: UUID
    var scriptId: UUID
    var kind: String
    var name: String
    var sourceURLString: String
    var localPath: String
    var mimeType: String?
    var contentHash: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        scriptId: UUID,
        kind: String,
        name: String,
        sourceURLString: String,
        localPath: String,
        mimeType: String?,
        contentHash: String,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.scriptId = scriptId
        self.kind = kind
        self.name = name
        self.sourceURLString = sourceURLString
        self.localPath = localPath
        self.mimeType = mimeType
        self.contentHash = contentHash
        self.updatedAt = updatedAt
    }
}

@Model
final class UserScriptValueEntity {
    @Attribute(.unique) var id: UUID
    var scriptId: UUID
    var profileId: UUID?
    var key: String
    var valueJSON: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        scriptId: UUID,
        profileId: UUID?,
        key: String,
        valueJSON: String,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.scriptId = scriptId
        self.profileId = profileId
        self.key = key
        self.valueJSON = valueJSON
        self.updatedAt = updatedAt
    }
}
