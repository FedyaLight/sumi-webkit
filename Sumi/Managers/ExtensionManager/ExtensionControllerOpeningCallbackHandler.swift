import AppKit
import Foundation
import WebKit

/// Owns the asynchronous WebKit tab/window callback transactions. The
/// delegate bridge only adapts protocol entry points; this handler owns
/// preload, target publication, presentation and exactly-once settlement.
@available(macOS 15.5, *)
@MainActor
struct ExtensionControllerOpeningCallbackHandler {
    func openNewTab(
        configuration: WKWebExtension.TabConfiguration,
        evidence: ExtensionControllerCallbackEvidence,
        runtime: ExtensionControllerTabOpeningCallbackRuntime,
        completionHandler: @escaping (
            (any WKWebExtensionTab)?,
            (any Error)?
        ) -> Void
    ) {
        guard runtime.admission.isCurrent(evidence) else {
            completionHandler(nil, CancellationError())
            return
        }
        Task { @MainActor in
            do {
                guard runtime.admission.isCurrent(evidence) else {
                    throw CancellationError()
                }
                let load = runtime.loadResolver.resolve(
                    configuration.url,
                    controller: evidence.controller
                )
                guard load.hasUnresolvedExtensionOwnership == false else {
                    throw ExtensionManagerCallbackError
                        .requestedTabUnavailable
                }
                if case .extensionOwned(let loadContext) = load.ownership {
                    guard loadContext === evidence.context else {
                        throw ExtensionManagerCallbackError
                            .requestedTabUnavailable
                    }
                }
                _ = try await runtime.contextPreloader.prepare(
                    load: load,
                    requestedWindow: configuration.window,
                    controller: evidence.controller,
                    extensionContext: evidence.context
                )
                guard runtime.admission.isCurrent(evidence) else {
                    throw CancellationError()
                }
                let tab = try runtime.tabOpening.open(
                    url: configuration.url,
                    shouldBeActive: configuration.shouldBeActive,
                    shouldBePinned: configuration.shouldBePinned,
                    requestedWindow: configuration.window,
                    controller: evidence.controller,
                    extensionContext: evidence.context,
                    evidence: evidence,
                    callbackAdmission: runtime.admission,
                    reason: "webExtensionController.openNewTabUsing"
                )
                guard runtime.admission.isCurrent(evidence),
                      let adapter = runtime.adapterResolver.stableAdapter(for: tab)
                else {
                    throw CancellationError()
                }
                completionHandler(adapter, nil)
            } catch {
                completionHandler(
                    nil,
                    SumiWebExtensionCallbackErrorMapper
                        .webExtensionCallbackError(from: error)
                )
            }
        }
    }

    func openNewWindow(
        request: ExtensionWindowOpeningRequest,
        evidence: ExtensionControllerCallbackEvidence,
        runtime: ExtensionControllerOpeningCallbackRuntime,
        completionHandler: @escaping (
            (any WKWebExtensionWindow)?,
            (any Error)?
        ) -> Void
    ) {
        guard runtime.admission.isCurrent(evidence) else {
            completionHandler(nil, CancellationError())
            return
        }
        guard request.shouldBePrivate == false else {
            completionHandler(
                nil,
                ExtensionManagerCallbackError.privateWindowsUnsupported.nsError()
            )
            return
        }

        guard request.windowType == .popup else {
            runtime.windowRouter.open(
                request: request,
                evidence: evidence,
                admission: runtime.admission,
                completion: completionHandler
            )
            return
        }

        Task { @MainActor in
            guard runtime.admission.isCurrent(evidence) else {
                completionHandler(nil, CancellationError())
                return
            }
            let parentWindow = runtime.windowQuery.activeExtensionWindowState.flatMap {
                runtime.windowQuery.appKitWindow(for: $0)
            }
            guard runtime.admission.isCurrent(evidence) else {
                completionHandler(nil, CancellationError())
                return
            }
            let presentation = await runtime.windowPresentation
                .presentExtensionPopupWindow(
                request: request,
                evidence: evidence,
                admission: runtime.admission,
                runtime: runtime.auxiliaryRuntime,
                parentWindow: parentWindow
            )
            guard runtime.admission.isCurrent(evidence) else {
                presentation?.retire()
                completionHandler(nil, CancellationError())
                return
            }
            guard let presentation else {
                completionHandler(
                    nil,
                    ExtensionManagerCallbackError.extensionPopupWindowUnavailable
                        .nsError()
                )
                return
            }
            completionHandler(presentation.adapter, nil)
        }
    }
}
