import AppKit
import Darwin
import Foundation

@available(macOS 15.5, *)
@MainActor
final class UserscriptsNativeMessagingAdapter: SumiNativeMessagingProtocolAdapter {
    let protocolIdentifier = UserscriptsNativeMessagingIdentifiers.protocolIdentifier
    let portInactivityTimeout: Duration? = nil

    private final class WeakSession {
        weak var value: SumiNativeMessagingPortSession?
        init(_ value: SumiNativeMessagingPortSession) { self.value = value }
    }

    private let locationStore: UserscriptsLibraryLocationStore
    private let service: UserscriptsLibraryProtocolService
    private var portSessions: [ObjectIdentifier: WeakSession] = [:]
    private var watcher: DispatchSourceFileSystemObject?
    private var watchedURL: URL?
    private var watchedSecurityScopedURL: URL?
    private var changeTask: Task<Void, Never>?

    init(
        locationStore: UserscriptsLibraryLocationStore = UserscriptsLibraryLocationStore(),
        service: UserscriptsLibraryProtocolService = UserscriptsLibraryProtocolService()
    ) {
        self.locationStore = locationStore
        self.service = service
    }

    isolated deinit {
        watcher?.cancel()
        changeTask?.cancel()
        watchedSecurityScopedURL?.stopAccessingSecurityScopedResource()
    }

    func supports(hostBundleIdentifier: String) -> Bool {
        hostBundleIdentifier == UserscriptsNativeMessagingIdentifiers.containingAppBundleIdentifier
    }

    func relayOneShotMessage(
        request: SumiNativeMessagingOneShotRequest,
        launcher: SumiHostApplicationLaunching,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        guard request.applicationIdentifier
                == UserscriptsNativeMessagingIdentifiers.applicationIdentifier,
              request.hostBundleIdentifier
                == UserscriptsNativeMessagingIdentifiers.containingAppBundleIdentifier,
              let message = request.message as? [String: Any],
              let command = message["name"] as? String else {
            replyHandler(nil, unsupportedProtocolError())
            return
        }

        switch command {
        case "OPEN_SAVE_LOCATION":
            let url = locationStore.scriptsURL()
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
            replyHandler(["success": true], nil)
        case "CHANGE_SAVE_LOCATION":
            chooseSaveLocation(replyHandler: replyHandler)
        case "OPEN_APP":
            Task { @MainActor in
                do {
                    try await launcher.openApplication(
                        withBundleIdentifier:
                            UserscriptsNativeMessagingIdentifiers.containingAppBundleIdentifier
                    )
                    replyHandler(["success": true], nil)
                } catch {
                    replyHandler(nil, error)
                }
            }
        default:
            relay(message: message, replyHandler: replyHandler)
        }
    }

    func connectPort(
        session: SumiNativeMessagingPortSession,
        launcher: SumiHostApplicationLaunching,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        _ = launcher
        portSessions[ObjectIdentifier(session)] = WeakSession(session)
        startWatcherIfNeeded()
        completionHandler(nil)
    }

    func relayPortMessage(
        session: SumiNativeMessagingPortSession,
        message: Any
    ) -> Bool {
        _ = message
        return portSessions[ObjectIdentifier(session)]?.value != nil
    }

    func disconnectPort(session: SumiNativeMessagingPortSession) {
        portSessions.removeValue(forKey: ObjectIdentifier(session))
        pruneReleasedSessions()
        if portSessions.isEmpty {
            stopWatcher()
        }
    }

    private func relay(
        message: [String: Any],
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        let scriptsURL = locationStore.scriptsURL()
        let stateRootURL = locationStore.stateRootURL
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0"
        let service = service
        Task { @MainActor [weak self] in
            let response = await service.handle(
                message: UserscriptsNativeMessageBox(value: message),
                scriptsURL: scriptsURL,
                stateRootURL: stateRootURL,
                extensionVersion: version
            )
            self?.startWatcherIfNeeded()
            replyHandler(response.value, nil)
        }
    }

    private func chooseSaveLocation(
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = "Choose Userscripts Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = locationStore.scriptsURL()
        panel.begin { [weak self] response in
            guard let self else {
                replyHandler(
                    nil,
                    SumiNativeMessagingErrorMapper.relayError(
                        code: .relayCancelled,
                        diagnostic: nil
                    )
                )
                return
            }
            guard response == .OK, let url = panel.url else {
                replyHandler(["cancelled": true], nil)
                return
            }
            do {
                try self.locationStore.storeExternalScriptsURL(url)
                self.restartWatcher()
                self.broadcastSaveLocationChanged()
                replyHandler(["success": true, "saveLocation": url.path], nil)
            } catch {
                replyHandler(nil, error)
            }
        }
    }

    private func startWatcherIfNeeded() {
        guard watcher == nil else { return }
        let scriptsURL = locationStore.scriptsURL()
        let didStart = scriptsURL.startAccessingSecurityScopedResource()
        do {
            try FileManager.default.createDirectory(
                at: scriptsURL,
                withIntermediateDirectories: true
            )
        } catch {
            if didStart { scriptsURL.stopAccessingSecurityScopedResource() }
            return
        }
        let descriptor = open(scriptsURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            if didStart { scriptsURL.stopAccessingSecurityScopedResource() }
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.directoryDidChange() }
        }
        source.setCancelHandler { close(descriptor) }
        watchedURL = scriptsURL.standardizedFileURL
        watchedSecurityScopedURL = didStart ? scriptsURL : nil
        watcher = source
        source.resume()
    }

    private func directoryDidChange() {
        changeTask?.cancel()
        changeTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch {
                return
            }
            guard Task.isCancelled == false, let self else { return }
            if self.watchedURL != self.locationStore.scriptsURL().standardizedFileURL {
                self.restartWatcher()
            }
            let message = UserscriptsNativeMessageBox(value: ["name": "NATIVE_CHECKS"])
            _ = await self.service.handle(
                message: message,
                scriptsURL: self.locationStore.scriptsURL(),
                stateRootURL: self.locationStore.stateRootURL,
                extensionVersion: Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleShortVersionString"
                ) as? String ?? "0"
            )
            self.broadcastSaveLocationChanged()
        }
    }

    private func broadcastSaveLocationChanged() {
        pruneReleasedSessions()
        for session in portSessions.values.compactMap(\.value) {
            session.sendReplyToExtension(["name": "SAVE_LOCATION_CHANGED"])
            session.touchPortActivity()
        }
    }

    private func pruneReleasedSessions() {
        portSessions = portSessions.filter { $0.value.value != nil }
    }

    private func restartWatcher() {
        stopWatcher()
        if portSessions.isEmpty == false { startWatcherIfNeeded() }
    }

    private func stopWatcher() {
        changeTask?.cancel()
        changeTask = nil
        watcher?.cancel()
        watcher = nil
        watchedSecurityScopedURL?.stopAccessingSecurityScopedResource()
        watchedSecurityScopedURL = nil
        watchedURL = nil
    }

    private func unsupportedProtocolError() -> NSError {
        SumiNativeMessagingErrorMapper.relayError(
            code: .companionAppProtocolUnknown,
            diagnostic: nil
        )
    }
}
