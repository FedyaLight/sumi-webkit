//
//  FindInPageTabExtension.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Combine
import Foundation
import UniformTypeIdentifiers
import WebKit

@MainActor
protocol FindInPageWebView: AnyObject {
    var mimeType: String? { get async }

    func collapseSelectionToStart() async throws
    func deselectAll() async throws
    func find(_ string: String, with options: _WKFindOptions, maxCount: UInt) async -> FocusableWKWebView.FindResult
    func clearFindInPageState()
}

extension FocusableWKWebView: FindInPageWebView {}

@MainActor
final class FindInPageTabExtension: SumiNavigationStartResponding, SumiSameDocumentNavigationResponding {

    let model = FindInPageModel()
    private weak var webView: (any FindInPageWebView)?
    private var cancellable: AnyCancellable?

    private(set) var isActive = false
    private var isPdf = false
    private var presentationMode: FindPresentationMode = .overlay
    private var presentationGeneration: UInt = 0

    private enum FindPresentationMode {
        case overlay
        case pageInteractionHighlight
    }

    private enum Constants {
        static let maxMatches: UInt = 1000
    }

    func show(with webView: any FindInPageWebView) {
        self.webView = webView

        if cancellable == nil {
            cancellable = model.$text
                .dropFirst()
                .debounce(for: 0.2, scheduler: RunLoop.main)
                .scan((old: "", new: model.text)) { ($0.new, $1) }
                .sink { [weak self] change in
                    Task { @MainActor in
                        await self?.textDidChange(from: change.old, to: change.new)
                    }
                }
        }

        Task { @MainActor in
            await showFindInPage()
        }
    }

    private func showFindInPage() async {
        let alreadyVisible = model.isVisible
        model.show()

        guard !alreadyVisible else {
            resetOverlayPresentation()
            guard !model.text.isEmpty,
                  !isPdf else { return }

            await find(model.text, with: [.noIndexChange, .determineMatchIndex, .showOverlay])
            return
        }

        await reset()
        guard !model.text.isEmpty else { return }

        await find(model.text, with: .showOverlay)
        await doItOneMoreTimeForPdf(with: model.text)
    }

    private func reset() async {
        model.update(currentSelection: nil, matchesFound: nil)
        isActive = false
        resetOverlayPresentation()

        webView?.clearFindInPageState()
        try? await webView?.deselectAll()
        self.isPdf = (await webView?.mimeType == UTType.pdf.preferredMIMEType)
    }

    private func textDidChange(from oldValue: String, to string: String) async {
        guard !string.isEmpty else {
            await reset()
            return
        }

        resetOverlayPresentation()

        var options = _WKFindOptions.showOverlay

        if isActive {
            options.insert(.noIndexChange)
        }

        await find(string, with: options)
        await doItOneMoreTimeForPdf(with: string, oldValue: oldValue)
    }

    private func doItOneMoreTimeForPdf(
        with string: String,
        options: _WKFindOptions = .noIndexChange,
        oldValue: String? = nil
    ) async {
        guard isPdf, oldValue != string else { return }
        await find(string, with: options)
    }

    private func find(
        _ string: String,
        with options: _WKFindOptions = [],
        collapseSelectionForNoIndexChange: Bool = true,
        showsFindIndicator: Bool = true
    ) async {
        guard !string.isEmpty else {
            await reset()
            return
        }

        if collapseSelectionForNoIndexChange, options.contains(.noIndexChange) {
            try? await webView?.collapseSelectionToStart()
        }

        var options = options.union([.caseInsensitive, .wrapAround])
        if showsFindIndicator {
            options.insert(.showFindIndicator)
        }
        if !self.isActive {
            options.remove(.showOverlay)
        }

        let result = await webView?.find(string, with: options, maxCount: Constants.maxMatches)

        switch result {
        case .found(matches: let matchesFound):
            self.model.update(
                currentSelection: calculateCurrentIndex(with: options, matchesFound: matchesFound ?? 1),
                matchesFound: matchesFound
            )

            if !self.isActive {
                self.isActive = true

                guard self.model.isVisible,
                      !isPdf else { break }

                webView?.clearFindInPageState()
                await find(string, with: [.noIndexChange, .showOverlay])
            }

        case .notFound:
            self.webView?.clearFindInPageState()
            self.isActive = false
            self.model.update(currentSelection: 0, matchesFound: 0)

        case .cancelled, .none:
            break
        }
    }

    private func calculateCurrentIndex(with options: _WKFindOptions, matchesFound: UInt) -> UInt {
        guard let currentIndex = model.currentSelection else { return 1 }

        if options.contains(.noIndexChange) {
            return currentIndex

        } else if options.contains(.backwards) {
            return currentIndex > 1 ? currentIndex - 1 : matchesFound

        } else if currentIndex < matchesFound {
            return currentIndex + 1
        }
        return 1
    }

    func close() {
        guard model.isVisible else { return }
        model.close()
        cancellable = nil
        webView?.clearFindInPageState()
        isActive = false
        resetOverlayPresentation()
    }

    func findNext() {
        guard !model.text.isEmpty else { return }
        resetOverlayPresentation()
        Task { @MainActor [isActive] in
            await find(model.text, with: model.isVisible ? .showOverlay : [])
            await doItOneMoreTimeForPdf(with: model.text, oldValue: (isActive ? model.text : ""))
        }
    }

    func findPrevious() {
        guard !model.text.isEmpty else { return }
        resetOverlayPresentation()
        Task { @MainActor in
            await find(model.text, with: model.isVisible ? [.showOverlay, .backwards] : [.backwards])
        }
    }

    func pageInteractionWillBegin() {
        guard model.isVisible,
              isActive,
              !model.text.isEmpty,
              model.matchesFound != 0,
              presentationMode != .pageInteractionHighlight
        else { return }

        presentationMode = .pageInteractionHighlight
        presentationGeneration &+= 1
        let generation = presentationGeneration

        webView?.clearFindInPageState()

        Task { @MainActor [weak self] in
            guard let self,
                  self.presentationMode == .pageInteractionHighlight,
                  self.presentationGeneration == generation
            else { return }

            await self.find(
                self.model.text,
                with: [.noIndexChange, .showHighlight],
                collapseSelectionForNoIndexChange: false,
                showsFindIndicator: false
            )
        }
    }

    private func resetOverlayPresentation() {
        guard presentationMode != .overlay else { return }
        presentationMode = .overlay
        presentationGeneration &+= 1
    }

    func navigationDidStart() {
        close()
    }

    func navigationDidSameDocumentNavigation(type navigationType: SumiSameDocumentNavigationType) {
        if navigationType == .sessionStatePush || navigationType == .sessionStatePop {
            close()
        }
    }

}
