import Foundation

struct UserscriptAvailableUpdate: Sendable {
    let file: UserscriptLibraryFile
    let remoteVersion: String
}

/// Owns manifest synchronization, remote-version checks, and resources.
actor UserscriptsLibraryUpdater {
    private let repository: UserscriptsLibraryRepository
    private let metadata: UserscriptsMetadataPolicy
    private let remoteContent: UserscriptsRemoteContentLoader

    init(remoteContent: UserscriptsRemoteContentLoader) {
        repository = UserscriptsLibraryRepository()
        metadata = UserscriptsMetadataPolicy()
        self.remoteContent = remoteContent
    }

    func synchronize(
        files: [UserscriptLibraryFile],
        stateRootURL: URL
    ) async throws {
        var manifest = repository.manifest(at: stateRootURL)
        let filenames = Set(files.map(\.filename))
        manifest.disabled = Array(
            Set(manifest.disabled).intersection(filenames)
        ).sorted()
        manifest.declarativeNetRequest = []
        manifest.exclude = [:]
        manifest.excludeMatch = [:]
        manifest.include = [:]
        manifest.match = [:]
        manifest.require = [:]
        for (key, value) in UserscriptsLibraryManifest.defaultSettings
            where manifest.settings[key] == nil {
            manifest.settings[key] = value
        }

        for file in files {
            if file.runAt == "request" {
                manifest.declarativeNetRequest.append(file.filename)
            } else {
                append(file, metadataKey: "match", to: &manifest.match)
                append(file, metadataKey: "include", to: &manifest.include)
                append(
                    file,
                    metadataKey: "exclude-match",
                    to: &manifest.excludeMatch
                )
                append(file, metadataKey: "exclude", to: &manifest.exclude)
            }
            let required = file.metadata["require"] ?? []
            if required.isEmpty == false {
                manifest.require[file.filename] = required.map(
                    metadata.sanitizeResourceName
                )
                try await synchronizeRequiredResources(
                    required,
                    for: file.filename,
                    stateRootURL: stateRootURL
                )
            }
        }
        manifest.declarativeNetRequest.sort()
        try repository.writeManifest(manifest, at: stateRootURL)
        removeOrphanedResources(
            validFilenames: filenames,
            stateRootURL: stateRootURL
        )
    }

    func availableUpdates(
        scriptsURL: URL
    ) async throws -> [UserscriptAvailableUpdate] {
        var updates: [UserscriptAvailableUpdate] = []
        for file in try repository.files(in: scriptsURL) {
            guard let current = file.metadata["version"]?.first,
                  let updateString = file.metadata["updateURL"]?.first,
                  let updateURL = metadata.validatedRemoteURL(updateString),
                  let remote = await remoteContent.stringIfAvailable(
                      from: updateURL
                  ),
                  let parsed = metadata.parse(content: remote),
                  let remoteVersion = parsed.metadata["version"]?.first,
                  metadata.isVersion(remoteVersion, newerThan: current) else {
                continue
            }
            updates.append(
                UserscriptAvailableUpdate(
                    file: file,
                    remoteVersion: remoteVersion
                )
            )
        }
        return updates
    }

    func updateAll(_ location: UserscriptsLibraryLocation) async throws {
        for file in try repository.files(in: location.scriptsURL) {
            guard file.metadata["version"] != nil,
                  file.metadata["updateURL"] != nil else { continue }
            do {
                try await updateSingle(
                    filename: file.filename,
                    location: location,
                    synchronizeAfterWrite: false
                )
            } catch {
                continue
            }
        }
        try await synchronize(
            files: repository.files(in: location.scriptsURL),
            stateRootURL: location.stateRootURL
        )
    }

    func updateSingle(
        filename: String,
        location: UserscriptsLibraryLocation,
        synchronizeAfterWrite: Bool = true
    ) async throws {
        let fileURL = try repository.scriptURL(
            named: filename,
            in: location.scriptsURL,
            mustExist: true
        )
        guard let file = try repository.files(in: location.scriptsURL)
            .first(where: { $0.filename == filename }),
              let current = file.metadata["version"]?.first,
              let updateString = file.metadata["updateURL"]?.first,
              let updateURL = metadata.validatedRemoteURL(updateString),
              let updateContent = await remoteContent.stringIfAvailable(
                  from: updateURL
              ),
              let parsed = metadata.parse(content: updateContent),
              let remoteVersion = parsed.metadata["version"]?.first,
              metadata.isVersion(remoteVersion, newerThan: current) else {
            return
        }
        let downloadString = file.metadata["downloadURL"]?.first
            ?? updateString
        guard let downloadURL = metadata.validatedRemoteURL(downloadString)
        else { return }
        let content = downloadURL == updateURL
            ? updateContent
            : try await remoteContent.string(from: downloadURL)
        try repository.replaceScript(
            content,
            at: fileURL,
            scriptsURL: location.scriptsURL
        )
        if synchronizeAfterWrite {
            try await synchronize(
                files: repository.files(in: location.scriptsURL),
                stateRootURL: location.stateRootURL
            )
        }
    }

    func remoteUpdate(for content: String) async -> [String: String] {
        guard let parsed = metadata.parse(content: content),
              let current = parsed.metadata["version"]?.first else {
            return ["error": "Update failed, version value required"]
        }
        guard let updateString = parsed.metadata["updateURL"]?.first,
              let updateURL = metadata.validatedRemoteURL(updateString) else {
            return ["error": "Update failed, invalid updateURL"]
        }
        do {
            let updateContent = try await remoteContent.string(from: updateURL)
            guard let remote = metadata.parse(content: updateContent),
                  let remoteVersion = remote.metadata["version"]?.first else {
                return [
                    "error": "Update failed, couldn't parse remote file contents",
                ]
            }
            guard metadata.isVersion(remoteVersion, newerThan: current) else {
                return ["info": "No updates found"]
            }
            let downloadString = parsed.metadata["downloadURL"]?.first
                ?? updateString
            guard let downloadURL = metadata.validatedRemoteURL(downloadString)
            else { return ["error": "Update failed, invalid downloadURL"] }
            return [
                "content": downloadURL == updateURL
                    ? updateContent
                    : try await remoteContent.string(from: downloadURL),
            ]
        } catch {
            return ["error": "Update failed, updateURL unreachable"]
        }
    }

    private func append(
        _ file: UserscriptLibraryFile,
        metadataKey: String,
        to dictionary: inout [String: [String]]
    ) {
        metadata.append(
            file.filename,
            values: file.metadata[metadataKey] ?? [],
            to: &dictionary
        )
    }

    private func synchronizeRequiredResources(
        _ resources: [String],
        for filename: String,
        stateRootURL: URL
    ) async throws {
        let directory = stateRootURL
            .appendingPathComponent("require", isDirectory: true)
            .appendingPathComponent(
                metadata.sanitizeFilename(filename),
                isDirectory: true
            )
        try repository.ensureDirectory(at: directory)
        let expected = Set(resources.map(metadata.sanitizeResourceName))
        for resource in resources {
            guard let remoteURL = metadata.validatedRemoteURL(resource) else {
                continue
            }
            let destination = directory.appendingPathComponent(
                metadata.sanitizeResourceName(resource)
            )
            if repository.fileExists(at: destination) == false {
                do {
                    try repository.write(
                        await remoteContent.data(from: remoteURL),
                        to: destination
                    )
                } catch {
                    continue
                }
            }
        }
        for child in repository.children(at: directory)
            where expected.contains(child.lastPathComponent) == false {
            repository.removeIfPresent(child)
        }
    }

    func removeOrphanedResources(
        validFilenames: Set<String>,
        stateRootURL: URL
    ) {
        let root = stateRootURL.appendingPathComponent(
            "require",
            isDirectory: true
        )
        let valid = Set(validFilenames.map(metadata.sanitizeFilename))
        for child in repository.children(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) where valid.contains(child.lastPathComponent) == false {
            repository.removeIfPresent(child)
        }
    }
}
