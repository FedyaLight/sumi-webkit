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
    private var searchGeneration: UInt64 = 0

    private enum Constants {
        static let maxMatches: UInt = 1000
    }

    private func nextSearchGeneration() -> UInt64 {
        searchGeneration &+= 1
        return searchGeneration
    }

    private func isCurrentSearchGeneration(_ generation: UInt64) -> Bool {
        generation == searchGeneration && model.isVisible
    }

    func show(with webView: any FindInPageWebView) {
        self.webView = webView

        if cancellable == nil {
            cancellable = model.$text
                .dropFirst()
                .debounce(for: 0.2, scheduler: RunLoop.main)
                .scan((old: "", new: model.text)) { ($0.new, $1) }
                .sink { [weak self] change in
                    guard let self else { return }
                    let generation = self.nextSearchGeneration()
                    Task { @MainActor in
                        await self.textDidChange(from: change.old, to: change.new, generation: generation)
                    }
                }
        }

        let generation = nextSearchGeneration()
        Task { @MainActor in
            await showFindInPage(generation: generation)
        }
    }

    private func showFindInPage(generation: UInt64) async {
        let alreadyVisible = model.isVisible
        model.show()

        guard !alreadyVisible else {
            guard !model.text.isEmpty,
                  !isPdf else { return }

            await find(
                model.text,
                with: [.noIndexChange, .determineMatchIndex, .showOverlay],
                generation: generation
            )
            return
        }

        await reset()
        guard isCurrentSearchGeneration(generation) else { return }
        guard !model.text.isEmpty else { return }

        await find(model.text, with: .showOverlay, generation: generation)
        await doItOneMoreTimeForPdf(with: model.text, generation: generation)
    }

    private func reset() async {
        model.update(currentSelection: nil, matchesFound: nil)
        isActive = false

        webView?.clearFindInPageState()
        try? await webView?.deselectAll()
        self.isPdf = (await webView?.mimeType == UTType.pdf.preferredMIMEType)
    }

    private func textDidChange(from oldValue: String, to string: String, generation: UInt64) async {
        guard !string.isEmpty else {
            await reset()
            return
        }

        var options = _WKFindOptions.showOverlay

        if isActive {
            options.insert(.noIndexChange)
        }

        await find(string, with: options, generation: generation)
        await doItOneMoreTimeForPdf(with: string, oldValue: oldValue, generation: generation)
    }

    private func doItOneMoreTimeForPdf(
        with string: String,
        options: _WKFindOptions = .noIndexChange,
        oldValue: String? = nil,
        generation: UInt64
    ) async {
        guard isPdf, oldValue != string else { return }
        await find(string, with: options, generation: generation)
    }

    private func find(
        _ string: String,
        with options: _WKFindOptions = [],
        generation: UInt64
    ) async {
        guard !string.isEmpty else {
            await reset()
            return
        }

        if options.contains(.noIndexChange) {
            try? await webView?.collapseSelectionToStart()
        }

        var options = options.union([.caseInsensitive, .wrapAround, .showFindIndicator])
        if !self.isActive {
            options.remove(.showOverlay)
        }

        let result = await webView?.find(string, with: options, maxCount: Constants.maxMatches)
        guard isCurrentSearchGeneration(generation) else { return }

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
                await find(string, with: [.noIndexChange, .showOverlay], generation: generation)
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
        _ = nextSearchGeneration()
        model.close()
        cancellable = nil
        webView?.clearFindInPageState()
        isActive = false
    }

    func findNext() {
        guard !model.text.isEmpty else { return }
        let generation = nextSearchGeneration()
        Task { @MainActor [isActive] in
            await find(model.text, with: model.isVisible ? .showOverlay : [], generation: generation)
            await doItOneMoreTimeForPdf(
                with: model.text,
                oldValue: (isActive ? model.text : ""),
                generation: generation
            )
        }
    }

    func findPrevious() {
        guard !model.text.isEmpty else { return }
        let generation = nextSearchGeneration()
        Task { @MainActor in
            await find(
                model.text,
                with: model.isVisible ? [.showOverlay, .backwards] : [.backwards],
                generation: generation
            )
        }
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
