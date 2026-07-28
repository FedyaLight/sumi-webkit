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
import SumiDomain

@MainActor
final class FindInPageTabExtension: SumiNavigationStartResponding, SumiSameDocumentNavigationResponding {
    let model = FindInPageModel()
    private weak var webView: (any FindInPageWebView)?
    private var cancellable: AnyCancellable?

    private(set) var isActive = false
    private var documentKind: FindInPageDocumentKind?
    private var searchGeneration: UInt64 = 0
    private var presentationIdentity: ObjectIdentifier?
    private var resultIdentity: ResultIdentity?

    private struct ResultIdentity: Equatable {
        let query: String
        let presentation: ObjectIdentifier
    }

    private func nextSearchGeneration() -> UInt64 {
        searchGeneration &+= 1
        return searchGeneration
    }

    private func isCurrentSearchGeneration(_ generation: UInt64) -> Bool {
        generation == searchGeneration && model.isVisible
    }

    func show(with webView: any FindInPageWebView) {
        let newPresentationIdentity = ObjectIdentifier(webView)
        if presentationIdentity != newPresentationIdentity {
            self.webView?.dismissFindSession()
            presentationIdentity = newPresentationIdentity
            resultIdentity = nil
            documentKind = nil
            isActive = false
            model.update(progress: nil)
        }
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
        let canRestoreProgress = !alreadyVisible
            && documentKind != .pdf
            && !model.text.isEmpty
            && model.progress != nil
            && resultIdentity == currentResultIdentity
        model.show()

        guard !alreadyVisible else {
            guard !model.text.isEmpty,
                  documentKind != .pdf else { return }

            await find(
                model.text,
                preservesSelection: true,
                showsOverlay: true,
                determinesMatchIndex: true,
                generation: generation
            )
            return
        }

        if canRestoreProgress {
            await find(
                model.text,
                preservesSelection: true,
                showsOverlay: true,
                determinesMatchIndex: true,
                generation: generation
            )
            return
        }

        await reset()
        guard isCurrentSearchGeneration(generation) else { return }
        guard !model.text.isEmpty else { return }

        await find(model.text, showsOverlay: true, generation: generation)
        await doItOneMoreTimeForPdf(with: model.text, generation: generation)
    }

    private func reset() async {
        model.update(progress: nil)
        resultIdentity = nil
        isActive = false
        documentKind = await webView?.prepareFindSession()
    }

    private func textDidChange(from oldValue: String, to string: String, generation: UInt64) async {
        guard !string.isEmpty else {
            await reset()
            return
        }

        await find(
            string,
            preservesSelection: isActive,
            showsOverlay: true,
            generation: generation
        )
        await doItOneMoreTimeForPdf(with: string, oldValue: oldValue, generation: generation)
    }

    private func doItOneMoreTimeForPdf(
        with string: String,
        preservesSelection: Bool = true,
        oldValue: String? = nil,
        generation: UInt64
    ) async {
        guard documentKind == .pdf, oldValue != string else { return }
        await find(
            string,
            preservesSelection: preservesSelection,
            generation: generation
        )
    }

    private func find(
        _ string: String,
        direction: FindInPageSearchDirection = .forward,
        preservesSelection: Bool = false,
        showsOverlay: Bool = false,
        determinesMatchIndex: Bool = false,
        generation: UInt64
    ) async {
        guard !string.isEmpty else {
            await reset()
            return
        }

        let wasActive = isActive
        let primaryRequest = FindInPageSearchRequest(
            query: string,
            direction: direction,
            preservesSelection: preservesSelection,
            showsOverlay: wasActive && showsOverlay,
            determinesMatchIndex: determinesMatchIndex
        )
        let result = await webView?.search(primaryRequest)
        guard isCurrentSearchGeneration(generation) else { return }

        switch result {
        case .found(matches: let matchesFound):
            let currentSelection = calculateCurrentIndex(
                direction: direction,
                preservesSelection: preservesSelection,
                matchesFound: matchesFound ?? 1
            )
            var finalMatchesFound = matchesFound

            if !wasActive,
               model.isVisible,
               documentKind != .pdf {
                webView?.dismissFindSession()
                let overlayResult = await webView?.search(FindInPageSearchRequest(
                    query: string,
                    preservesSelection: true,
                    showsOverlay: true
                ))
                guard isCurrentSearchGeneration(generation) else { return }

                switch overlayResult {
                case .found(let overlayMatches):
                    finalMatchesFound = overlayMatches ?? finalMatchesFound
                case .notFound:
                    webView?.dismissFindSession()
                    isActive = false
                    resultIdentity = currentResultIdentity
                    model.update(progress: .init(currentSelection: 0, matchesFound: 0))
                    return
                case .cancelled, .none:
                    return
                }
            }

            isActive = true
            resultIdentity = currentResultIdentity
            model.update(progress: finalMatchesFound.map {
                FindInPageProgress(
                    currentSelection: currentSelection,
                    matchesFound: $0
                )
            })

        case .notFound:
            webView?.dismissFindSession()
            isActive = false
            resultIdentity = currentResultIdentity
            model.update(progress: .init(currentSelection: 0, matchesFound: 0))

        case .cancelled, .none:
            break
        }
    }

    private var currentResultIdentity: ResultIdentity? {
        guard let presentationIdentity else { return nil }
        return ResultIdentity(query: model.text, presentation: presentationIdentity)
    }

    private func calculateCurrentIndex(
        direction: FindInPageSearchDirection,
        preservesSelection: Bool,
        matchesFound: UInt
    ) -> UInt {
        guard let currentIndex = model.currentSelection else { return 1 }

        if preservesSelection {
            return currentIndex

        } else if direction == .backward {
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
        webView?.dismissFindSession()
        isActive = false
    }

    func findNext() {
        guard !model.text.isEmpty else { return }
        let generation = nextSearchGeneration()
        Task { @MainActor [isActive] in
            await find(
                model.text,
                showsOverlay: model.isVisible,
                generation: generation
            )
            await doItOneMoreTimeForPdf(
                with: model.text,
                oldValue: isActive ? model.text : "",
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
                direction: .backward,
                showsOverlay: model.isVisible,
                generation: generation
            )
        }
    }

    func navigationDidStart() {
        close()
        model.update(progress: nil)
        resultIdentity = nil
        documentKind = nil
    }

    func navigationDidSameDocumentNavigation(type navigationType: SumiSameDocumentNavigationType) {
        if navigationType == .sessionStatePush || navigationType == .sessionStatePop {
            close()
            model.update(progress: nil)
            resultIdentity = nil
            documentKind = nil
        }
    }
}
