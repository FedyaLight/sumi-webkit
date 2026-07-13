import AppKit
import Foundation
import WebKit

@MainActor
protocol DownloadWebKitTransportAdapting: AnyObject {
    func makeTransport(for download: WKDownload) -> any DownloadTransport
}

@MainActor
final class SumiWebKitDownloadTransportFactory: DownloadWebKitTransportAdapting {
    func makeTransport(for download: WKDownload) -> any DownloadTransport {
        SumiWebKitDownloadTransport(download: download)
    }
}

@MainActor
final class SumiWebKitDownloadTransport: NSObject, DownloadTransport, WKDownloadDelegate {
    private enum Phase {
        case idle
        case running
        case cancelRequested
        case settled
    }

    private let download: WKDownload
    private weak var eventDelegate: (any DownloadTransportDelegate)?
    private var phase: Phase = .idle

    init(download: WKDownload) {
        self.download = download
        super.init()
    }

    var progress: Progress {
        download.progress
    }

    var promptWindow: NSWindow? {
        download.targetWebView?.window
            ?? download.originatingWebView?.window
            ?? NSApp.keyWindow
    }

    func start(delegate: any DownloadTransportDelegate) {
        guard phase == .idle else { return }
        phase = .running
        eventDelegate = delegate
        download.delegate = self
    }

    func cancel() {
        switch phase {
        case .idle, .running:
            break
        case .cancelRequested, .settled:
            return
        }
        phase = .cancelRequested
        download.cancel { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.settle(.cancelled)
            }
        }
    }

    func download(
        _: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String
    ) async -> URL? {
        guard phase == .running, let eventDelegate else { return nil }
        let destination = await eventDelegate.downloadTransport(
            self,
            decideDestinationUsing: response,
            suggestedFilename: suggestedFilename
        )
        guard phase == .running else { return nil }
        return destination
    }

    func downloadDidFinish(_: WKDownload) {
        settle(.finished)
    }

    func download(_: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let nsError = error as NSError
        let wasCancelled = phase == .cancelRequested
            || nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
        if wasCancelled {
            settle(.cancelled)
        } else {
            settle(.failed(error: error, resumeData: resumeData))
        }
    }

    func download(
        _: WKDownload,
        didReceive _: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor @Sendable (
            URLSession.AuthChallengeDisposition,
            URLCredential?
        ) -> Void
    ) {
        completionHandler(.performDefaultHandling, nil)
    }

    private enum Settlement {
        case finished
        case cancelled
        case failed(error: Error, resumeData: Data?)
    }

    private func settle(_ settlement: Settlement) {
        guard phase != .settled else { return }
        phase = .settled
        guard let eventDelegate else { return }

        switch settlement {
        case .finished:
            eventDelegate.downloadTransportDidFinish(self)
        case .cancelled:
            eventDelegate.downloadTransport(self, didFail: .cancelled)
        case .failed(let error, let resumeData):
            eventDelegate.downloadTransport(
                self,
                didFail: .failed(error: error, resumeData: resumeData)
            )
        }
    }
}
