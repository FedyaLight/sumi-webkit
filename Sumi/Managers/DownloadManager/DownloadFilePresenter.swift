import Foundation

final class DownloadFilePresenter {
    private var source: DispatchSourceFileSystemObject?

    init(url: URL, onDeleted: @escaping @Sendable () -> Void) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.delete, .rename],
            queue: .main
        )
        source.setEventHandler(handler: onDeleted)
        source.setCancelHandler {
            close(descriptor)
        }
        self.source = source
        source.resume()
    }

    deinit {
        source?.cancel()
    }
}
