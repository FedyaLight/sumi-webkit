import Foundation

struct UserscriptsNativeMessageBox: @unchecked Sendable {
    let value: [String: Any]
}

struct UserscriptsNativeReplyBox: @unchecked Sendable {
    let value: Any
}

/// Adapts untyped native messages to the serialized library module.
final class UserscriptsLibraryProtocolService: Sendable {
    private let library: UserscriptsLibrary

    init(session: URLSession? = nil) {
        library = UserscriptsLibrary(
            remoteContent: UserscriptsRemoteContentLoader(session: session)
        )
    }

    func handle(
        message: UserscriptsNativeMessageBox,
        scriptsURL: URL,
        stateRootURL: URL,
        extensionVersion: String
    ) async -> UserscriptsNativeReplyBox {
        await library.execute(
            message: message,
            location: UserscriptsLibraryLocation(
                scriptsURL: scriptsURL,
                stateRootURL: stateRootURL
            ),
            extensionVersion: extensionVersion
        )
    }
}
