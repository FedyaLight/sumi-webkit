import Foundation

struct UserscriptsNativeMessageBox: @unchecked Sendable {
    let value: [String: Any]
}

struct UserscriptsNativeReplyBox: @unchecked Sendable {
    let value: Any
}

actor UserscriptsLibraryProtocolService {
    private struct ParsedFile {
        let url: URL
        let filename: String
        let type: String
        let content: String
        let code: String
        let metablock: String
        let metadata: [String: [String]]
        let modifiedAt: Date

        var name: String { metadata["name"]?.first ?? filename }
        var runAt: String { metadata["run-at"]?.first ?? "document-end" }
        var noframes: Bool { metadata["noframes"] != nil }
    }

    private struct Manifest: Codable {
        var blacklist: [String] = []
        var declarativeNetRequest: [String] = []
        var disabled: [String] = []
        var exclude: [String: [String]] = [:]
        var excludeMatch: [String: [String]] = [:]
        var include: [String: [String]] = [:]
        var match: [String: [String]] = [:]
        var require: [String: [String]] = [:]
        var settings: [String: String] = Self.defaultSettings

        enum CodingKeys: String, CodingKey {
            case blacklist, declarativeNetRequest, disabled, exclude, include, match, require, settings
            case excludeMatch = "exclude-match"
        }

        static let defaultSettings = [
            "active": "true",
            "autoCloseBrackets": "true",
            "autoHint": "true",
            "descriptions": "true",
            "languageCode": Locale.current.language.languageCode?.identifier ?? "en",
            "lint": "false",
            "log": "false",
            "sortOrder": "lastModifiedDesc",
            "showCount": "true",
            "showInvisibles": "true",
            "tabSize": "4",
        ]
    }

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 60
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    func handle(
        message boxedMessage: UserscriptsNativeMessageBox,
        scriptsURL: URL,
        stateRootURL: URL,
        extensionVersion: String
    ) async -> UserscriptsNativeReplyBox {
        let message = boxedMessage.value
        guard let name = message["name"] as? String else {
            return reply(error: "Failed to parse inbound message")
        }

        do {
            try prepare(scriptsURL: scriptsURL, stateRootURL: stateRootURL)
            switch name {
            case "NATIVE_CHECKS":
                let files = try scanFiles(in: scriptsURL)
                try await synchronize(files: files, stateRootURL: stateRootURL)
                return UserscriptsNativeReplyBox(value: ["success": "Native checks complete"])
            case "REQ_PLATFORM":
                return UserscriptsNativeReplyBox(value: ["platform": "macos"])
            case "REQ_USERSCRIPTS":
                guard let url = message["url"] as? String,
                      let isTop = message["isTop"] as? Bool else {
                    return reply(error: "Failed to parse inbound message")
                }
                return UserscriptsNativeReplyBox(
                    value: try injectionPayload(
                        for: url,
                        isTop: isTop,
                        scriptsURL: scriptsURL,
                        stateRootURL: stateRootURL,
                        extensionVersion: extensionVersion
                    )
                )
            case "REQ_REQUESTS":
                return UserscriptsNativeReplyBox(
                    value: try requestScripts(scriptsURL: scriptsURL, stateRootURL: stateRootURL)
                )
            case "REQ_CONTEXT_MENU_SCRIPTS":
                return UserscriptsNativeReplyBox(
                    value: try contextMenuScripts(
                        scriptsURL: scriptsURL,
                        stateRootURL: stateRootURL,
                        extensionVersion: extensionVersion
                    )
                )
            case "POPUP_BADGE_COUNT":
                guard let url = message["url"] as? String else {
                    return reply(error: "Failed to parse inbound message")
                }
                let frames = message["frameUrls"] as? [String] ?? []
                let matches = try popupMatches(
                    url: url,
                    frameURLs: frames,
                    scriptsURL: scriptsURL,
                    stateRootURL: stateRootURL
                )
                let manifest = readManifest(stateRootURL: stateRootURL)
                let blocked = manifest.blacklist.contains {
                    matchesMatchPattern(url: url, pattern: $0)
                }
                let count = blocked ? 0 : matches.filter {
                    guard let filename = $0["filename"] as? String else { return false }
                    return manifest.disabled.contains(filename) == false
                }.count
                return UserscriptsNativeReplyBox(value: ["count": count])
            case "POPUP_MATCHES":
                guard let url = message["url"] as? String else {
                    return reply(error: "Failed to parse inbound message")
                }
                return UserscriptsNativeReplyBox(value: [
                    "matches": try popupMatches(
                        url: url,
                        frameURLs: message["frameUrls"] as? [String] ?? [],
                        scriptsURL: scriptsURL,
                        stateRootURL: stateRootURL
                    ),
                ])
            case "POPUP_UPDATES", "POPUP_CHECK_UPDATES":
                return UserscriptsNativeReplyBox(value: [
                    "updates": try await availableUpdates(scriptsURL: scriptsURL),
                ])
            case "POPUP_UPDATE_ALL":
                try await updateAll(scriptsURL: scriptsURL, stateRootURL: stateRootURL)
                return UserscriptsNativeReplyBox(value: [
                    "updates": try await availableUpdates(scriptsURL: scriptsURL),
                ])
            case "POPUP_UPDATE_SINGLE":
                guard let filename = message["filename"] as? String,
                      let url = message["url"] as? String else {
                    return reply(error: "Failed to parse inbound message")
                }
                try await updateSingle(
                    filename: filename,
                    scriptsURL: scriptsURL,
                    stateRootURL: stateRootURL
                )
                return UserscriptsNativeReplyBox(value: [
                    "items": try popupMatches(
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
                      let current = boolLike(item["disabled"]) else {
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
                let disabled = Set(readManifest(stateRootURL: stateRootURL).disabled)
                return UserscriptsNativeReplyBox(
                    value: try scanFiles(in: scriptsURL).map {
                        fileDictionary($0, disabledFilenames: disabled)
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
                try trash(
                    filename: filename,
                    scriptsURL: scriptsURL,
                    stateRootURL: stateRootURL
                )
                return success()
            case "PAGE_UPDATE":
                guard let content = message["content"] as? String else {
                    return reply(error: "Failed to parse inbound message")
                }
                return UserscriptsNativeReplyBox(value: await remoteUpdate(for: content))
            case "CANCEL_REQUESTS":
                await cancelRequests()
                return success()
            case "PAGE_UPDATE_SETTINGS":
                guard let settings = message["settings"] as? [String: String] else {
                    return reply(error: "Failed to parse inbound message")
                }
                var manifest = readManifest(stateRootURL: stateRootURL)
                manifest.settings = settings
                for (key, value) in Manifest.defaultSettings where manifest.settings[key] == nil {
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

    private func prepare(scriptsURL: URL, stateRootURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: stateRootURL, withIntermediateDirectories: true)
        try withSecurityScope(for: scriptsURL) {
            try fileManager.createDirectory(at: scriptsURL, withIntermediateDirectories: true)
        }
        try fileManager.createDirectory(
            at: stateRootURL.appendingPathComponent("require", isDirectory: true),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: manifestURL(stateRootURL).path) == false {
            try writeManifest(Manifest(), stateRootURL: stateRootURL)
        }
    }

    private func scanFiles(in scriptsURL: URL) throws -> [ParsedFile] {
        try withSecurityScope(for: scriptsURL) {
            let keys: Set<URLResourceKey> = [
                .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey,
            ]
            return try FileManager.default.contentsOfDirectory(
                at: scriptsURL,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ).compactMap { url in
                do {
                    let filename = url.lastPathComponent
                    guard isAllowedFilename(filename) else { return nil }
                    let values = try url.resourceValues(forKeys: keys)
                    guard values.isRegularFile == true,
                          values.isSymbolicLink != true else { return nil }
                    let content = try String(contentsOf: url, encoding: .utf8)
                    guard let parsed = parse(content: content),
                          let type = fileType(filename) else { return nil }
                    return ParsedFile(
                        url: url,
                        filename: filename,
                        type: type,
                        content: content,
                        code: parsed.code,
                        metablock: parsed.metablock,
                        metadata: parsed.metadata,
                        modifiedAt: values.contentModificationDate ?? .distantPast
                    )
                } catch {
                    return nil
                }
            }.sorted { $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedAscending }
        }
    }

    private func synchronize(files: [ParsedFile], stateRootURL: URL) async throws {
        var manifest = readManifest(stateRootURL: stateRootURL)
        let filenames = Set(files.map(\.filename))
        manifest.disabled = Array(Set(manifest.disabled).intersection(filenames)).sorted()
        manifest.declarativeNetRequest = []
        manifest.exclude = [:]
        manifest.excludeMatch = [:]
        manifest.include = [:]
        manifest.match = [:]
        manifest.require = [:]
        for (key, value) in Manifest.defaultSettings where manifest.settings[key] == nil {
            manifest.settings[key] = value
        }

        for file in files {
            if file.runAt == "request" {
                manifest.declarativeNetRequest.append(file.filename)
            } else {
                append(file.filename, values: file.metadata["match"] ?? [], to: &manifest.match)
                append(file.filename, values: file.metadata["include"] ?? [], to: &manifest.include)
                append(
                    file.filename,
                    values: file.metadata["exclude-match"] ?? [],
                    to: &manifest.excludeMatch
                )
                append(file.filename, values: file.metadata["exclude"] ?? [], to: &manifest.exclude)
            }

            let required = file.metadata["require"] ?? []
            if required.isEmpty == false {
                manifest.require[file.filename] = required.map(sanitizeResourceName)
                try await synchronizeRequiredResources(
                    required,
                    for: file.filename,
                    stateRootURL: stateRootURL
                )
            }
        }
        manifest.declarativeNetRequest.sort()
        try writeManifest(manifest, stateRootURL: stateRootURL)
        try cleanOrphanedResources(validFilenames: filenames, stateRootURL: stateRootURL)
    }

    private func injectionPayload(
        for url: String,
        isTop: Bool,
        scriptsURL: URL,
        stateRootURL: URL,
        extensionVersion: String
    ) throws -> [String: Any] {
        let manifest = readManifest(stateRootURL: stateRootURL)
        let files = try matchingFiles(
            url: url,
            files: scanFiles(in: scriptsURL),
            manifest: manifest
        )
        var css: [[String: Any]] = []
        var js: [[String: Any]] = []
        var menu: [[String: Any]] = []

        for file in files where isTop || file.noframes == false {
            guard file.runAt != "request" else { continue }
            var code = file.code
            for requiredURL in (file.metadata["require"] ?? []).reversed() {
                let localURL = requiredResourceURL(
                    requiredURL,
                    for: file.filename,
                    stateRootURL: stateRootURL
                )
                if let requiredCode = readStringIfAvailable(at: localURL) {
                    code = requiredCode + "\n" + code
                }
            }

            let weight = normalizedWeight(file.metadata["weight"]?.first)
            if file.type == "css" {
                css.append([
                    "code": code, "filename": file.filename, "name": file.name,
                    "type": "css", "weight": weight,
                ])
                continue
            }

            let item: [String: Any] = [
                "code": code,
                "scriptMetaStr": file.metablock,
                "scriptObject": scriptObject(for: file),
                "type": "js",
                "weight": weight,
            ]
            if file.runAt == "context-menu" {
                menu.append(item)
            } else {
                js.append(item)
            }
        }

        return [
            "files": ["css": css, "js": js, "menu": menu],
            "scriptHandler": "Userscripts",
            "scriptHandlerVersion": extensionVersion,
        ]
    }

    private func requestScripts(scriptsURL: URL, stateRootURL: URL) throws -> [[String: String]] {
        let manifest = readManifest(stateRootURL: stateRootURL)
        guard manifest.settings["active"] == "true" else { return [] }
        return try scanFiles(in: scriptsURL).compactMap { file in
            guard file.runAt == "request", manifest.disabled.contains(file.filename) == false else {
                return nil
            }
            return ["name": file.name, "code": file.code]
        }
    }

    private func contextMenuScripts(
        scriptsURL: URL,
        stateRootURL: URL,
        extensionVersion: String
    ) throws -> [String: Any] {
        let manifest = readManifest(stateRootURL: stateRootURL)
        guard manifest.settings["active"] == "true" else {
            return ["files": ["menu": []]]
        }
        let files = try scanFiles(in: scriptsURL).filter {
            $0.runAt == "context-menu" && manifest.disabled.contains($0.filename) == false
        }
        let syntheticURL = "https://userscripts.invalid/"
        var payload = try injectionPayload(
            for: syntheticURL,
            isTop: true,
            scriptsURL: scriptsURL,
            stateRootURL: stateRootURL,
            extensionVersion: extensionVersion
        )
        let menu = files.map { file -> [String: Any] in
            [
                "code": file.code,
                "scriptMetaStr": file.metablock,
                "scriptObject": scriptObject(for: file),
                "type": "js",
                "weight": normalizedWeight(file.metadata["weight"]?.first),
            ]
        }
        payload["files"] = ["menu": menu]
        return payload
    }

    private func popupMatches(
        url: String,
        frameURLs: [String],
        scriptsURL: URL,
        stateRootURL: URL
    ) throws -> [[String: Any]] {
        guard url.hasPrefix("http://") || url.hasPrefix("https://") else { return [] }
        let manifest = readManifest(stateRootURL: stateRootURL)
        let files = try scanFiles(in: scriptsURL)
        let disabled = Set(manifest.disabled)
        var result = matchingFiles(
            url: url,
            files: files,
            manifest: manifest,
            includeDisabled: true,
            respectsActivation: false,
            respectsBlacklist: false
        ).map {
            fileDictionary($0, disabledFilenames: disabled)
        }
        let topFilenames = Set(result.compactMap { $0["filename"] as? String })
        var frameFilenames: Set<String> = []
        for frameURL in Set(frameURLs) where frameURL != url {
            for file in matchingFiles(
                url: frameURL,
                files: files,
                manifest: manifest,
                includeDisabled: true,
                respectsActivation: false,
                respectsBlacklist: false
            )
                where file.noframes == false && topFilenames.contains(file.filename) == false {
                frameFilenames.insert(file.filename)
            }
        }
        for file in files where frameFilenames.contains(file.filename) {
            var dictionary = fileDictionary(file, disabledFilenames: disabled)
            dictionary["subframe"] = true
            result.append(dictionary)
        }
        return result
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
        try withSecurityScope(for: scriptsURL) {
            try Data(content.utf8).write(to: destination, options: [.atomic])
            if let oldFilename,
               oldFilename.caseInsensitiveCompare(filename) != .orderedSame {
                do {
                    let oldURL = try safeFileURL(
                        filename: oldFilename,
                        scriptsURL: scriptsURL,
                        mustExist: true
                    )
                    try FileManager.default.trashItem(at: oldURL, resultingItemURL: nil)
                } catch {
                    // A newly-created editor item has no old file; the saved file is still valid.
                }
            }
        }

        let updatedFiles = try scanFiles(in: scriptsURL)
        try await synchronize(files: updatedFiles, stateRootURL: stateRootURL)
        guard let saved = updatedFiles.first(where: { $0.filename == filename }) else {
            return ["error": "failed to read saved file"]
        }
        return fileDictionary(saved)
    }

    private func trash(filename: String, scriptsURL: URL, stateRootURL: URL) throws {
        let url = try safeFileURL(filename: filename, scriptsURL: scriptsURL, mustExist: false)
        try withSecurityScope(for: scriptsURL) {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        let files = try scanFiles(in: scriptsURL)
        var manifest = readManifest(stateRootURL: stateRootURL)
        let valid = Set(files.map(\.filename))
        manifest.disabled = manifest.disabled.filter(valid.contains)
        try writeManifest(manifest, stateRootURL: stateRootURL)
        try cleanOrphanedResources(validFilenames: valid, stateRootURL: stateRootURL)
    }

    private func availableUpdates(scriptsURL: URL) async throws -> [[String: Any]] {
        var updates: [[String: Any]] = []
        for file in try scanFiles(in: scriptsURL) {
            guard let current = file.metadata["version"]?.first,
                  let updateString = file.metadata["updateURL"]?.first,
                  let updateURL = validatedRemoteURL(updateString),
                  let remote = await downloadStringIfAvailable(updateURL),
                  let parsed = parse(content: remote),
                  let remoteVersion = parsed.metadata["version"]?.first,
                  isVersion(remoteVersion, newerThan: current) else {
                continue
            }
            var dictionary = fileDictionary(file)
            dictionary["remoteVersion"] = remoteVersion
            updates.append(dictionary)
        }
        return updates
    }

    private func updateAll(scriptsURL: URL, stateRootURL: URL) async throws {
        for file in try scanFiles(in: scriptsURL) {
            guard file.metadata["version"] != nil, file.metadata["updateURL"] != nil else { continue }
            do {
                try await updateSingle(
                    filename: file.filename,
                    scriptsURL: scriptsURL,
                    stateRootURL: stateRootURL,
                    synchronizeAfterWrite: false
                )
            } catch {
                continue
            }
        }
        try await synchronize(files: scanFiles(in: scriptsURL), stateRootURL: stateRootURL)
    }

    private func updateSingle(
        filename: String,
        scriptsURL: URL,
        stateRootURL: URL,
        synchronizeAfterWrite: Bool = true
    ) async throws {
        let fileURL = try safeFileURL(filename: filename, scriptsURL: scriptsURL, mustExist: true)
        guard let file = try scanFiles(in: scriptsURL).first(where: { $0.filename == filename }),
              let current = file.metadata["version"]?.first,
              let updateString = file.metadata["updateURL"]?.first,
              let updateURL = validatedRemoteURL(updateString),
              let updateContent = await downloadStringIfAvailable(updateURL),
              let updateParsed = parse(content: updateContent),
              let remoteVersion = updateParsed.metadata["version"]?.first,
              isVersion(remoteVersion, newerThan: current) else {
            return
        }
        let downloadStringValue = file.metadata["downloadURL"]?.first ?? updateString
        guard let downloadURL = validatedRemoteURL(downloadStringValue) else { return }
        let content = downloadURL == updateURL ? updateContent : try await downloadString(downloadURL)
        try withSecurityScope(for: scriptsURL) {
            try Data(content.utf8).write(to: fileURL, options: [.atomic])
        }
        if synchronizeAfterWrite {
            try await synchronize(files: scanFiles(in: scriptsURL), stateRootURL: stateRootURL)
        }
    }

    private func remoteUpdate(for content: String) async -> [String: String] {
        guard let parsed = parse(content: content),
              let current = parsed.metadata["version"]?.first else {
            return ["error": "Update failed, version value required"]
        }
        guard let updateString = parsed.metadata["updateURL"]?.first,
              let updateURL = validatedRemoteURL(updateString) else {
            return ["error": "Update failed, invalid updateURL"]
        }
        do {
            let updateContent = try await downloadString(updateURL)
            guard let remote = parse(content: updateContent),
                  let remoteVersion = remote.metadata["version"]?.first else {
                return ["error": "Update failed, couldn't parse remote file contents"]
            }
            guard isVersion(remoteVersion, newerThan: current) else {
                return ["info": "No updates found"]
            }
            let downloadStringValue = parsed.metadata["downloadURL"]?.first ?? updateString
            guard let downloadURL = validatedRemoteURL(downloadStringValue) else {
                return ["error": "Update failed, invalid downloadURL"]
            }
            return ["content": downloadURL == updateURL
                    ? updateContent
                    : try await downloadString(downloadURL)]
        } catch {
            return ["error": "Update failed, updateURL unreachable"]
        }
    }

    private func synchronizeRequiredResources(
        _ resources: [String],
        for filename: String,
        stateRootURL: URL
    ) async throws {
        let directory = stateRootURL
            .appendingPathComponent("require", isDirectory: true)
            .appendingPathComponent(sanitizeFilename(filename), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let expected = Set(resources.map(sanitizeResourceName))
        for resource in resources {
            guard let remoteURL = validatedRemoteURL(resource) else { continue }
            let destination = directory.appendingPathComponent(sanitizeResourceName(resource))
            if FileManager.default.fileExists(atPath: destination.path) == false {
                do {
                    let data = try await downloadData(remoteURL)
                    try data.write(to: destination, options: [.atomic])
                } catch {
                    continue
                }
            }
        }
        for child in directoryChildren(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) where expected.contains(child.lastPathComponent) == false {
            removeItemIfPresent(at: child)
        }
    }

    private func cleanOrphanedResources(validFilenames: Set<String>, stateRootURL: URL) throws {
        let root = stateRootURL.appendingPathComponent("require", isDirectory: true)
        let valid = Set(validFilenames.map(sanitizeFilename))
        for child in directoryChildren(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) where valid.contains(child.lastPathComponent) == false {
            removeItemIfPresent(at: child)
        }
    }

    private func matchingFiles(
        url: String,
        files: [ParsedFile],
        manifest: Manifest,
        includeDisabled: Bool = false,
        respectsActivation: Bool = true,
        respectsBlacklist: Bool = true
    ) -> [ParsedFile] {
        if respectsActivation, manifest.settings["active"] != "true" { return [] }
        if respectsBlacklist,
           manifest.blacklist.contains(where: {
               matchesMatchPattern(url: url, pattern: $0)
           }) { return [] }

        return files.filter { file in
            guard (includeDisabled || manifest.disabled.contains(file.filename) == false),
                  file.runAt != "request" else { return false }
            let included = (file.metadata["match"] ?? []).contains {
                matchesMatchPattern(url: url, pattern: $0)
            } || (file.metadata["include"] ?? []).contains {
                matchesIncludePattern(url: url, pattern: $0)
            }
            let excluded = (file.metadata["exclude-match"] ?? []).contains {
                matchesMatchPattern(url: url, pattern: $0)
            } || (file.metadata["exclude"] ?? []).contains {
                matchesIncludePattern(url: url, pattern: $0)
            }
            return included && excluded == false
        }
    }

    private func matchesMatchPattern(url: String, pattern: String) -> Bool {
        guard let components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased() else { return false }
        if pattern == "<all_urls>" { return scheme == "http" || scheme == "https" }

        guard let separator = pattern.range(of: "://") else { return false }
        let patternScheme = String(pattern[..<separator.lowerBound]).lowercased()
        let remainder = pattern[separator.upperBound...]
        guard let slash = remainder.firstIndex(of: "/") else { return false }
        let patternHost = String(remainder[..<slash]).lowercased()
        let patternPath = String(remainder[slash...])

        let schemeMatches = patternScheme == "*"
            ? scheme == "http" || scheme == "https"
            : patternScheme == scheme
        guard schemeMatches else { return false }

        let hostMatches: Bool
        if patternHost == "*" {
            hostMatches = true
        } else if patternHost.hasPrefix("*.") {
            let suffix = String(patternHost.dropFirst(2))
            hostMatches = host == suffix || host.hasSuffix("." + suffix)
        } else {
            hostMatches = host == patternHost
        }
        guard hostMatches else { return false }

        let pathAndQuery = components.percentEncodedPath
            + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
        return globMatches(pathAndQuery, pattern: patternPath, caseInsensitive: false)
    }

    private func matchesIncludePattern(url: String, pattern: String) -> Bool {
        if pattern.count >= 2, pattern.hasPrefix("/"), pattern.hasSuffix("/") {
            let expression = String(pattern.dropFirst().dropLast())
            return url.range(of: expression, options: [.regularExpression, .caseInsensitive]) != nil
        }
        return globMatches(url, pattern: pattern, caseInsensitive: true)
    }

    private func globMatches(
        _ value: String,
        pattern: String,
        caseInsensitive: Bool
    ) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
        var options: String.CompareOptions = [.regularExpression]
        if caseInsensitive { options.insert(.caseInsensitive) }
        return value.range(of: "^\(escaped)$", options: options) != nil
    }

    private func fileDictionary(
        _ file: ParsedFile,
        disabledFilenames: Set<String> = []
    ) -> [String: Any] {
        var result: [String: Any] = [
            "canUpdate": file.metadata["version"] != nil && file.metadata["updateURL"] != nil,
            "content": file.content,
            "disabled": disabledFilenames.contains(file.filename),
            "filename": file.filename,
            "lastModified": Int(file.modifiedAt.timeIntervalSince1970 * 1_000),
            "metadata": file.metadata,
            "name": file.name,
            "noframes": file.noframes,
            "type": file.type,
        ]
        if let description = file.metadata["description"]?.first {
            result["description"] = description
        }
        if file.runAt == "request" { result["request"] = true }
        return result
    }

    private func scriptObject(for file: ParsedFile) -> [String: Any] {
        let grants = normalizedGrants(file.metadata["grant"] ?? [])
        var object: [String: Any] = [
            "description": file.metadata["description"]?.first ?? "",
            "excludes": file.metadata["exclude"] ?? [],
            "exclude-match": file.metadata["exclude-match"] ?? [],
            "filename": file.filename,
            "grant": grants,
            "icon": file.metadata["icon"]?.first ?? "",
            "includes": file.metadata["include"] ?? [],
            "inject-into": normalizedInjectInto(file.metadata["inject-into"]?.first),
            "matches": file.metadata["match"] ?? [],
            "name": file.name,
            "noframes": file.noframes,
            "namespace": file.metadata["namespace"]?.first ?? "",
            "resources": file.metadata["resource"] ?? [],
            "require": file.metadata["require"] ?? [],
            "run-at": normalizedRunAt(file.runAt),
            "version": file.metadata["version"]?.first ?? "",
        ]
        for (key, value) in file.metadata where object[key] == nil {
            object[key] = value.count == 1 ? value[0] : value
        }
        return object
    }

    private func readManifest(stateRootURL: URL) -> Manifest {
        let url = manifestURL(stateRootURL)
        let decoded: Manifest
        do {
            decoded = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
        } catch {
            return Manifest()
        }
        var manifest = decoded
        for (key, value) in Manifest.defaultSettings where manifest.settings[key] == nil {
            manifest.settings[key] = value
        }
        return manifest
    }

    private func writeManifest(_ manifest: Manifest, stateRootURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL(stateRootURL), options: [.atomic])
    }

    private func manifestURL(_ stateRootURL: URL) -> URL {
        stateRootURL.appendingPathComponent("manifest.json", isDirectory: false)
    }

    private func safeFileURL(filename: String, scriptsURL: URL, mustExist: Bool) throws -> URL {
        guard isAllowedFilename(filename), URL(fileURLWithPath: filename).lastPathComponent == filename else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let root = scriptsURL.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = scriptsURL.appendingPathComponent(filename).standardizedFileURL
        guard candidate.deletingLastPathComponent() == scriptsURL.standardizedFileURL else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        if mustExist {
            let resolved = candidate.resolvingSymlinksInPath()
            guard resolved.deletingLastPathComponent() == root,
                  FileManager.default.fileExists(atPath: resolved.path) else {
                throw CocoaError(.fileNoSuchFile)
            }
        }
        return candidate
    }

    private func isAllowedFilename(_ filename: String) -> Bool {
        guard filename.isEmpty == false, filename.utf8.count <= 250 else { return false }
        let lower = filename.lowercased()
        return lower.hasSuffix(".js") || lower.hasSuffix(".css")
    }

    private func fileType(_ filename: String) -> String? {
        if filename.lowercased().hasSuffix(".js") { return "js" }
        if filename.lowercased().hasSuffix(".css") { return "css" }
        return nil
    }

    private func parse(content: String) -> (
        metadata: [String: [String]], code: String, metablock: String
    )? {
        let markers = [
            ("// ==UserScript==", "// ==/UserScript=="),
            ("/* ==UserStyle==", "==/UserStyle== */"),
        ]
        guard let markers = markers.first(where: {
            content.range(of: $0.0) != nil && content.range(of: $0.1) != nil
        }),
        let start = content.range(of: markers.0),
        let end = content.range(of: markers.1, range: start.upperBound..<content.endIndex)
        else {
            return nil
        }

        let metablock = String(content[start.lowerBound..<end.upperBound])
        var metadata: [String: [String]] = [:]
        for rawLine in metablock.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("//") { line = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
            if line.hasPrefix("*") { line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces) }
            guard line.hasPrefix("@") else { continue }
            let body = line.dropFirst()
            let parts = body.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard let keyPart = parts.first else { continue }
            let key = String(keyPart)
            let value = parts.count > 1
                ? String(parts[1]).trimmingCharacters(in: .whitespaces)
                : ""
            metadata[key, default: []].append(value)
        }
        guard metadata["name"]?.first?.isEmpty == false else { return nil }
        let code = String(content[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (metadata, code, metablock)
    }

    private func append(
        _ filename: String,
        values: [String],
        to dictionary: inout [String: [String]]
    ) {
        for value in values where value.isEmpty == false {
            if dictionary[value, default: []].contains(filename) == false {
                dictionary[value, default: []].append(filename)
                dictionary[value]?.sort()
            }
        }
    }

    private func normalizedWeight(_ value: String?) -> String {
        String(min(999, max(1, Int(value ?? "1") ?? 1)))
    }

    private func boolLike(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? Int { return value != 0 }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }

    private func normalizedInjectInto(_ value: String?) -> String {
        ["auto", "content", "page"].contains(value ?? "") ? value! : "auto"
    }

    private func normalizedRunAt(_ value: String) -> String {
        ["context-menu", "document-start", "document-end", "document-idle"].contains(value)
            ? value
            : "document-end"
    }

    private func normalizedGrants(_ grants: [String]) -> [String] {
        if grants.contains("none") { return [] }
        let supported: Set<String> = [
            "GM.info", "GM_info", "GM.addStyle", "GM.openInTab", "GM.closeTab",
            "GM.setValue", "GM.getValue", "GM.deleteValue", "GM.listValues",
            "GM.setClipboard", "GM.getTab", "GM.saveTab", "GM_xmlhttpRequest",
            "GM.xmlHttpRequest",
        ]
        return Array(Set(grants).intersection(supported)).sorted()
    }

    private func sanitizeFilename(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix(".") { result = "%2" + result.dropFirst() }
        return result
            .replacingOccurrences(of: "/", with: "%2F")
            .replacingOccurrences(of: ":", with: "%3A")
            .replacingOccurrences(of: "\\", with: "%5C")
    }

    private func sanitizeResourceName(_ value: String) -> String {
        let sanitized = sanitizeFilename(value)
        guard sanitized.utf8.count > 180 else { return sanitized }
        let prefix = String(sanitized.prefix(140))
        return prefix + "-" + stableHexDigest(value)
    }

    private func requiredResourceURL(
        _ resource: String,
        for filename: String,
        stateRootURL: URL
    ) -> URL {
        stateRootURL
            .appendingPathComponent("require", isDirectory: true)
            .appendingPathComponent(sanitizeFilename(filename), isDirectory: true)
            .appendingPathComponent(sanitizeResourceName(resource), isDirectory: false)
    }

    private func validatedRemoteURL(_ string: String) -> URL? {
        guard let url = URL(string: string),
              url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }

    private func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    private func stableHexDigest(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private func downloadString(_ url: URL) async throws -> String {
        let data = try await downloadData(url)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return string
    }

    private func downloadStringIfAvailable(_ url: URL) async -> String? {
        do {
            return try await downloadString(url)
        } catch {
            return nil
        }
    }

    private func downloadData(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
              data.count <= 16 * 1_024 * 1_024 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func cancelRequests() async {
        await withCheckedContinuation { continuation in
            session.getAllTasks { tasks in
                tasks.forEach { $0.cancel() }
                continuation.resume()
            }
        }
    }

    private func readStringIfAvailable(at url: URL) -> String? {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func directoryChildren(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options: FileManager.DirectoryEnumerationOptions
    ) -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: options
            )
        } catch {
            return []
        }
    }

    private func removeItemIfPresent(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            return
        }
    }

    private func withSecurityScope<T>(for url: URL, _ body: () throws -> T) rethrows -> T {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        return try body()
    }

    private func success() -> UserscriptsNativeReplyBox {
        UserscriptsNativeReplyBox(value: ["success": true])
    }

    private func reply(error: String) -> UserscriptsNativeReplyBox {
        UserscriptsNativeReplyBox(value: ["error": error])
    }
}
