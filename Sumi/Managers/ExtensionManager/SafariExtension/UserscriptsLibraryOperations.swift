import Foundation

actor UserscriptsLibrary {
    private typealias ParsedFile = UserscriptLibraryFile
    private typealias Manifest = UserscriptsLibraryManifest

    private let repository: UserscriptsLibraryRepository
    private let metadata: UserscriptsMetadataPolicy
    private let projection: UserscriptsLibraryProjection
    private let updater: UserscriptsLibraryUpdater
    private let remoteContent: UserscriptsRemoteContentLoader

    init(remoteContent: UserscriptsRemoteContentLoader) {
        let repository = UserscriptsLibraryRepository()
        let metadata = UserscriptsMetadataPolicy()
        self.repository = repository
        self.metadata = metadata
        projection = UserscriptsLibraryProjection(
            repository: repository,
            metadata: metadata
        )
        updater = UserscriptsLibraryUpdater(remoteContent: remoteContent)
        self.remoteContent = remoteContent
    }

    func execute(
        message boxedMessage: UserscriptsNativeMessageBox,
        location: UserscriptsLibraryLocation,
        extensionVersion: String
    ) async -> UserscriptsNativeReplyBox {
        let message = boxedMessage.value
        guard let name = message["name"] as? String else {
            return reply(error: "Failed to parse inbound message")
        }

        let scriptsURL = location.scriptsURL
        let stateRootURL = location.stateRootURL
        do {
            try repository.prepare(location)
            switch name {
            case "NATIVE_CHECKS":
                let files = try scanFiles(in: scriptsURL)
                try await updater.synchronize(
                    files: files,
                    stateRootURL: stateRootURL
                )
                return UserscriptsNativeReplyBox(value: ["success": "Native checks complete"])
            case "REQ_PLATFORM":
                return UserscriptsNativeReplyBox(value: ["platform": "macos"])
            case "REQ_USERSCRIPTS":
                guard let url = message["url"] as? String,
                      let isTop = message["isTop"] as? Bool else {
                    return reply(error: "Failed to parse inbound message")
                }
                return UserscriptsNativeReplyBox(
                    value: try projection.injectionPayload(
                        for: url,
                        isTop: isTop,
                        scriptsURL: scriptsURL,
                        stateRootURL: stateRootURL,
                        extensionVersion: extensionVersion
                    )
                )
            case "REQ_REQUESTS":
                return UserscriptsNativeReplyBox(
                    value: try projection.requestScripts(
                        scriptsURL: scriptsURL,
                        stateRootURL: stateRootURL
                    )
                )
            case "REQ_CONTEXT_MENU_SCRIPTS":
                return UserscriptsNativeReplyBox(
                    value: try projection.contextMenuScripts(
                        scriptsURL: scriptsURL,
                        stateRootURL: stateRootURL,
                        extensionVersion: extensionVersion
                    )
                )
            case "POPUP_BADGE_COUNT":
                guard let url = message["url"] as? String else {
                    return reply(error: "Failed to parse inbound message")
                }
                let matches = try projection.popupMatches(
                    url: url,
                    frameURLs: message["frameUrls"] as? [String] ?? [],
                    scriptsURL: scriptsURL,
                    stateRootURL: stateRootURL
                )
                let manifest = readManifest(stateRootURL: stateRootURL)
                let blocked = manifest.blacklist.contains {
                    metadata.matchesMatchPattern(url: url, pattern: $0)
                }
                let count = blocked ? 0 : matches.filter {
                    guard let filename = $0["filename"] as? String else {
                        return false
                    }
                    return manifest.disabled.contains(filename) == false
                }.count
                return UserscriptsNativeReplyBox(value: ["count": count])
            case "POPUP_MATCHES":
                guard let url = message["url"] as? String else {
                    return reply(error: "Failed to parse inbound message")
                }
                return UserscriptsNativeReplyBox(value: [
                    "matches": try projection.popupMatches(
                        url: url,
                        frameURLs: message["frameUrls"] as? [String] ?? [],
                        scriptsURL: scriptsURL,
                        stateRootURL: stateRootURL
                    ),
                ])
            case "POPUP_UPDATES", "POPUP_CHECK_UPDATES":
                return UserscriptsNativeReplyBox(value: [
                    "updates": try await availableUpdateDictionaries(
                        scriptsURL: scriptsURL
                    ),
                ])
            case "POPUP_UPDATE_ALL":
                try await updater.updateAll(
                    UserscriptsLibraryLocation(
                        scriptsURL: scriptsURL,
                        stateRootURL: stateRootURL
                    )
                )
                return UserscriptsNativeReplyBox(value: [
                    "updates": try await availableUpdateDictionaries(
                        scriptsURL: scriptsURL
                    ),
                ])
            case "POPUP_UPDATE_SINGLE":
                guard let filename = message["filename"] as? String,
                      let url = message["url"] as? String else {
                    return reply(error: "Failed to parse inbound message")
                }
                try await updater.updateSingle(
                    filename: filename,
                    location: UserscriptsLibraryLocation(
                        scriptsURL: scriptsURL,
                        stateRootURL: stateRootURL
                    )
                )
                return UserscriptsNativeReplyBox(value: [
                    "items": try projection.popupMatches(
                        url: url,
                        frameURLs: message["frameUrls"] as? [String] ?? [],
                        scriptsURL: scriptsURL,
                        stateRootURL: stateRootURL
                    ),
                ])
            case "TOGGLE_EXTENSION":
                guard let active = message["active"] as? String,
                      active == "true" || active == "false" else {
                    return reply(error: "missing or wrong message content")
                }
                var manifest = readManifest(stateRootURL: stateRootURL)
                manifest.settings["active"] = active
                try writeManifest(manifest, stateRootURL: stateRootURL)
                return success()
            case "TOGGLE_ITEM":
                guard let item = message["item"] as? [String: Any],
                      let filename = item["filename"] as? String,
                      let current = metadata.boolLike(item["disabled"]) else {
                    return reply(error: "Failed to parse inbound message")
                }
                try toggle(
                    filename: filename,
                    currentlyDisabled: current,
                    scriptsURL: scriptsURL,
                    stateRootURL: stateRootURL
                )
                return success()
            case "POPUP_INSTALL_CHECK":
                guard let content = message["content"] as? String else {
                    return reply(error: "failed to get script content")
                }
                return UserscriptsNativeReplyBox(
                    value: try installCheck(content: content, scriptsURL: scriptsURL)
                )
            case "POPUP_INSTALL_SCRIPT":
                guard let content = message["content"] as? String,
                      let type = message["type"] as? String else {
                    return reply(error: "failed to get script content (2)")
                }
                return UserscriptsNativeReplyBox(
                    value: try await save(
                        oldFilename: nil,
                        type: type,
                        content: content,
                        scriptsURL: scriptsURL,
                        stateRootURL: stateRootURL
                    )
                )
            case "PAGE_INIT_DATA":
                return UserscriptsNativeReplyBox(value: [
                    "saveLocation": scriptsURL.path,
                    "platform": "macos",
                    "scheme": "sumi-userscripts",
                    "version": extensionVersion,
                    "build": extensionVersion,
                ])
            case "PAGE_LEGACY_IMPORT":
                let manifest = readManifest(stateRootURL: stateRootURL)
                var result: [String: Any] = manifest.settings
                result["blacklist"] = manifest.blacklist
                return UserscriptsNativeReplyBox(value: result)
            case "PAGE_ALL_FILES":
                let disabled = Set(
                    readManifest(stateRootURL: stateRootURL).disabled
                )
                return UserscriptsNativeReplyBox(
                    value: try scanFiles(in: scriptsURL).map {
                        metadata.fileDictionary(
                            $0,
                            disabledFilenames: disabled
                        )
                    }
                )
            case "PAGE_SAVE":
                guard let item = message["item"] as? [String: Any],
                      let oldFilename = item["filename"] as? String,
                      let type = item["type"] as? String,
                      let content = message["content"] as? String else {
                    return reply(error: "Failed to parse inbound message")
                }
                return UserscriptsNativeReplyBox(
                    value: try await save(
                        oldFilename: oldFilename,
                        type: type,
                        content: content,
                        scriptsURL: scriptsURL,
                        stateRootURL: stateRootURL
                    )
                )
            case "PAGE_TRASH":
                guard let item = message["item"] as? [String: Any],
                      let filename = item["filename"] as? String else {
                    return reply(error: "Failed to parse inbound message")
                }
                try await trash(
                    filename: filename,
                    scriptsURL: scriptsURL,
                    stateRootURL: stateRootURL
                )
                return success()
            case "PAGE_UPDATE":
                guard let content = message["content"] as? String else {
                    return reply(error: "Failed to parse inbound message")
                }
                return UserscriptsNativeReplyBox(
                    value: await updater.remoteUpdate(for: content)
                )
            case "CANCEL_REQUESTS":
                await remoteContent.cancelAll()
                return success()
            case "PAGE_UPDATE_SETTINGS":
                guard let settings = message["settings"] as? [String: String]
                else {
                    return reply(error: "Failed to parse inbound message")
                }
                var manifest = readManifest(stateRootURL: stateRootURL)
                manifest.settings = settings
                for (key, value) in Manifest.defaultSettings
                    where manifest.settings[key] == nil {
                    manifest.settings[key] = value
                }
                try writeManifest(manifest, stateRootURL: stateRootURL)
                return success()
            case "PAGE_UPDATE_BLACKLIST":
                guard let blacklist = message["blacklist"] as? [String] else {
                    return reply(error: "Failed to parse inbound message")
                }
                var manifest = readManifest(stateRootURL: stateRootURL)
                manifest.blacklist = Array(Set(blacklist)).sorted()
                try writeManifest(manifest, stateRootURL: stateRootURL)
                return success()
            case "OPEN_APP":
                return success()
            default:
                return reply(error: "Unsupported Userscripts native command")
            }
        } catch {
            return reply(error: error.localizedDescription)
        }
    }

    private func scanFiles(in scriptsURL: URL) throws -> [ParsedFile] {
        try repository.files(in: scriptsURL)
    }

    private func toggle(
        filename: String,
        currentlyDisabled: Bool,
        scriptsURL: URL,
        stateRootURL: URL
    ) throws {
        _ = try safeFileURL(filename: filename, scriptsURL: scriptsURL, mustExist: true)
        var manifest = readManifest(stateRootURL: stateRootURL)
        if currentlyDisabled {
            manifest.disabled.removeAll { $0 == filename }
        } else if manifest.disabled.contains(filename) == false {
            manifest.disabled.append(filename)
            manifest.disabled.sort()
        }
        try writeManifest(manifest, stateRootURL: stateRootURL)
    }

    private func installCheck(content: String, scriptsURL: URL) throws -> [String: Any] {
        guard let parsed = parse(content: content), let name = parsed.metadata["name"]?.first else {
            return ["error": "userscript metadata is invalid"]
        }
        let installed = try scanFiles(in: scriptsURL).contains {
            $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }
        return [
            "success": installed ? "Click to re-install" : "Click to install",
            "metadata": parsed.metadata,
            "installed": installed,
        ]
    }

    private func save(
        oldFilename: String?,
        type: String,
        content: String,
        scriptsURL: URL,
        stateRootURL: URL
    ) async throws -> [String: Any] {
        guard type == "js" || type == "css",
              let parsed = parse(content: content),
              let rawName = parsed.metadata["name"]?.first else {
            return ["error": "failed to parse metadata"]
        }
        let filename = "\(sanitizeFilename(rawName)).user.\(type)"
        guard filename.utf8.count <= 250 else { return ["error": "filename too long"] }

        let files = try scanFiles(in: scriptsURL)
        if files.contains(where: {
            $0.filename.caseInsensitiveCompare(filename) == .orderedSame
                && $0.filename.caseInsensitiveCompare(oldFilename ?? "") != .orderedSame
        }) {
            return ["error": "filename already taken"]
        }

        let destination = try safeFileURL(
            filename: filename,
            scriptsURL: scriptsURL,
            mustExist: false
        )
        try repository.writeScript(
            content,
            to: destination,
            replacing: oldFilename,
            in: scriptsURL
        )

        let updatedFiles = try scanFiles(in: scriptsURL)
        try await updater.synchronize(
            files: updatedFiles,
            stateRootURL: stateRootURL
        )
        guard let saved = updatedFiles.first(where: { $0.filename == filename }) else {
            return ["error": "failed to read saved file"]
        }
        return fileDictionary(saved)
    }

    private func trash(
        filename: String,
        scriptsURL: URL,
        stateRootURL: URL
    ) async throws {
        try repository.trashScript(named: filename, in: scriptsURL)
        let files = try scanFiles(in: scriptsURL)
        var manifest = readManifest(stateRootURL: stateRootURL)
        let valid = Set(files.map(\.filename))
        manifest.disabled = manifest.disabled.filter(valid.contains)
        try writeManifest(manifest, stateRootURL: stateRootURL)
        await updater.removeOrphanedResources(
            validFilenames: valid,
            stateRootURL: stateRootURL
        )
    }

    private func readManifest(stateRootURL: URL) -> Manifest {
        repository.manifest(at: stateRootURL)
    }

    private func writeManifest(
        _ manifest: Manifest,
        stateRootURL: URL
    ) throws {
        try repository.writeManifest(manifest, at: stateRootURL)
    }

    private func safeFileURL(
        filename: String,
        scriptsURL: URL,
        mustExist: Bool
    ) throws -> URL {
        try repository.scriptURL(
            named: filename,
            in: scriptsURL,
            mustExist: mustExist
        )
    }

    private func parse(content: String) -> (
        metadata: [String: [String]],
        code: String,
        metablock: String
    )? {
        metadata.parse(content: content)
    }

    private func fileDictionary(
        _ file: ParsedFile,
        disabledFilenames: Set<String> = []
    ) -> [String: Any] {
        metadata.fileDictionary(
            file,
            disabledFilenames: disabledFilenames
        )
    }

    private func availableUpdateDictionaries(
        scriptsURL: URL
    ) async throws -> [[String: Any]] {
        try await updater.availableUpdates(scriptsURL: scriptsURL).map { update in
            var dictionary = fileDictionary(update.file)
            dictionary["remoteVersion"] = update.remoteVersion
            return dictionary
        }
    }

    private func sanitizeFilename(_ value: String) -> String {
        metadata.sanitizeFilename(value)
    }

    private func success() -> UserscriptsNativeReplyBox {
        UserscriptsNativeReplyBox(value: ["success": true])
    }

    private func reply(error: String) -> UserscriptsNativeReplyBox {
        UserscriptsNativeReplyBox(value: ["error": error])
    }

}
