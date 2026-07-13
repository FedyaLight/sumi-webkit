import Foundation

final class DownloadFilePresenter {
    private let url: URL
    private let onDeleted: @Sendable () -> Void
    private var fileSource: DispatchSourceFileSystemObject?
    private var directorySource: DispatchSourceFileSystemObject?

    init(url: URL, onDeleted: @escaping @Sendable () -> Void) {
        self.url = url
        self.onDeleted = onDeleted
        attachFileSourceIfPresent()
        if fileSource == nil {
            attachDirectorySource()
        }
    }

    private func attachFileSourceIfPresent() {
        guard fileSource == nil,
              FileManager.default.fileExists(atPath: url.path)
        else { return }
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
        fileSource = source
        source.resume()
        directorySource?.cancel()
        directorySource = nil
    }

    private func attachDirectorySource() {
        let descriptor = open(url.deletingLastPathComponent().path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.attachFileSourceIfPresent()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        directorySource = source
        source.resume()
    }

    deinit {
        fileSource?.cancel()
        directorySource?.cancel()
    }
}
