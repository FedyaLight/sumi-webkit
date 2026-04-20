//
//  FindInPageViewController.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import AppKit
import Combine

@MainActor
protocol FindInPageDelegate: AnyObject {
    func findInPageNext(_ sender: Any)
    func findInPagePrevious(_ sender: Any)
    func findInPageDone(_ sender: Any)
}

final class FindInPageViewController: NSViewController {

    weak var delegate: FindInPageDelegate?

    var model: FindInPageModel? {
        didSet {
            guard oldValue !== model else { return }
            subscribeToModelChanges(model: model)
        }
    }

    @IBOutlet weak var backgroundView: ColorView!
    @IBOutlet weak var closeButton: NSButton!
    @IBOutlet weak var textField: NSTextField!
    @IBOutlet weak var focusRingView: FocusRingView!
    @IBOutlet weak var statusField: NSTextField!
    @IBOutlet weak var nextButton: NSButton!
    @IBOutlet weak var previousButton: NSButton!

    private var modelCancellables = Set<AnyCancellable>()
    private var lastSyncedFocusRingStroke: Bool?

    private enum Copy {
        static let statusFormat = "%lu of %lu"
        static let placeholder = "Find in page"
        static let closeTooltip = "Close"
        static let nextTooltip = "Next"
        static let previousTooltip = "Previous"
    }

    static func create() -> FindInPageViewController {
        let storyboard = NSStoryboard(name: "FindInPage", bundle: .main)
        return (storyboard.instantiateInitialController() as? FindInPageViewController)!
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        textField.placeholderString = Copy.placeholder
        textField.delegate = self

        closeButton.toolTip = Copy.closeTooltip
        nextButton.toolTip = Copy.nextTooltip
        previousButton.toolTip = Copy.previousTooltip

        nextButton.setAccessibilityIdentifier("FindInPageController.nextButton")
        closeButton.setAccessibilityIdentifier("FindInPageController.closeButton")
        previousButton.setAccessibilityIdentifier("FindInPageController.previousButton")
        textField.setAccessibilityIdentifier("FindInPageController.textField")
        textField.setAccessibilityRole(.textField)
        statusField.setAccessibilityIdentifier("FindInPageController.statusField")
        statusField.setAccessibilityRole(.textField)

        applyChromeColors(nil)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        subscribeToModelChanges(model: model)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        modelCancellables.removeAll()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        syncFocusRingWithFirstResponderIfNeeded()
    }

    @IBAction func findInPageNext(_ sender: Any?) {
        delegate?.findInPageNext(self)
    }

    @IBAction func findInPagePrevious(_ sender: Any?) {
        delegate?.findInPagePrevious(self)
    }

    @IBAction func findInPageDone(_ sender: Any?) {
        delegate?.findInPageDone(self)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard NSApp.sumi_findIsReturnOrEnterPressed,
              var modifiers = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask)
        else {
            return false
        }
        modifiers.remove(.capsLock)
        switch modifiers {
        case .shift:
            delegate?.findInPagePrevious(self)
            return true
        case []:
            delegate?.findInPageNext(self)
            return true
        default:
            return false
        }
    }

    func makeMeFirstResponder() {
        if textField.sumi_findIsFirstResponder {
            textField.currentEditor()?.selectAll(nil)
        } else {
            textField.sumi_findMakeMeFirstResponder()
        }
    }

    private func subscribeToModelChanges(model: FindInPageModel?) {
        modelCancellables.removeAll()
        lastSyncedFocusRingStroke = nil

        guard let model else { return }
        updateFieldStates(model: model)

        model.$text.receive(on: DispatchQueue.main).sink { [weak self] text in
            self?.textField.stringValue = text
        }.store(in: &modelCancellables)

        model.$matchesFound.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.rebuildStatus()
            self?.updateFieldStates()
        }.store(in: &modelCancellables)

        model.$currentSelection.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.rebuildStatus()
        }.store(in: &modelCancellables)
    }

    private func rebuildStatus() {
        guard let model else { return }
        statusField.stringValue = {
            guard let matchesFound = model.matchesFound,
                  let currentSelection = model.currentSelection else { return "" }
            return String(format: Copy.statusFormat, currentSelection, matchesFound)
        }()
    }

    private func updateView(firstResponder: Bool) {
        focusRingView.updateView(stroke: firstResponder)
    }

    private func updateFieldStates(model: FindInPageModel? = nil) {
        guard let model = model ?? self.model else { return }

        statusField.isHidden = model.text.isEmpty
        nextButton.isEnabled = model.matchesFound.map { $0 > 0 } ?? !model.text.isEmpty
        previousButton.isEnabled = model.matchesFound.map { $0 > 0 } ?? !model.text.isEmpty
    }

    /// When `paint` is `nil`, uses catalog assets (e.g. before the first SwiftUI theme sync).
    func applyChromeColors(_ paint: FindInPageChromePaint?) {
        if let paint {
            backgroundView.backgroundColor = paint.shellBackground
            focusRingView.sumi_findApplyChromePaint(paint)
            textField.textColor = paint.primaryText
            statusField.textColor = paint.secondaryText
            let font = textField.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            textField.placeholderAttributedString = NSAttributedString(
                string: Copy.placeholder,
                attributes: [
                    .foregroundColor: paint.secondaryText.withAlphaComponent(0.85),
                    .font: font,
                ]
            )
            textField.placeholderString = nil

            for case let hover as MouseOverButton in [closeButton, nextButton, previousButton] {
                hover.normalTintColor = paint.secondaryText
                hover.updateTintColor()
            }
        } else {
            applyChromeColorsFromAssets()
        }
    }

    private func applyChromeColorsFromAssets() {
        backgroundView.backgroundColor = NSColor(named: "FindInPageBackgroundColor", bundle: .main) ?? .quaternaryLabelColor
        focusRingView.sumi_findApplyAssetColors()
        textField.textColor = .labelColor
        statusField.textColor = .secondaryLabelColor
        textField.placeholderAttributedString = nil
        textField.placeholderString = Copy.placeholder
    }

    private func syncFocusRingWithFirstResponderIfNeeded() {
        let focused = textField.sumi_findIsFirstResponder
        guard focused != lastSyncedFocusRingStroke else { return }
        lastSyncedFocusRingStroke = focused
        updateView(firstResponder: focused)
    }
}

extension FindInPageViewController: NSTextFieldDelegate {

    func controlTextDidChange(_ obj: Notification) {
        model?.find(textField.stringValue)
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        updateView(firstResponder: true)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        updateView(firstResponder: false)
    }
}
