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

private final class FindInPageBackgroundView: ColorView {
    weak var textField: NSTextField?
    weak var textActivationBoundaryView: NSView? {
        didSet {
            invalidateTextActivationCursorRects()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard textActivationRect.contains(point), let textField else {
            super.mouseDown(with: event)
            return
        }

        window?.makeFirstResponder(textField)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let cursorRect = textActivationRect.intersection(visibleRect)
        guard cursorRect.width > 0, cursorRect.height > 0 else { return }
        addCursorRect(cursorRect, cursor: .iBeam)
    }

    func invalidateTextActivationCursorRects() {
        window?.invalidateCursorRects(for: self)
    }

    private var textActivationRect: NSRect {
        guard let textActivationBoundaryView else { return bounds }
        let boundaryRect = convert(textActivationBoundaryView.bounds, from: textActivationBoundaryView)
        return NSRect(
            x: bounds.minX,
            y: bounds.minY,
            width: max(0, boundaryRect.minX - 8 - bounds.minX),
            height: bounds.height
        )
    }
}

private final class FindInPageTextField: NSTextField {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let cursorRect = bounds.intersection(visibleRect)
        guard cursorRect.width > 0, cursorRect.height > 0 else { return }
        addCursorRect(cursorRect, cursor: .iBeam)
    }
}

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

    private weak var backgroundView: FindInPageBackgroundView!
    weak var closeButton: NSButton!
    weak var textField: NSTextField!
    weak var focusRingView: FocusRingView!
    weak var statusField: NSTextField!
    weak var nextButton: NSButton!
    weak var previousButton: NSButton!

    private var statusPillView: ColorView?
    private weak var textActivationBoundaryView: NSView?
    private var modelCancellables = Set<AnyCancellable>()
    private var lastSyncedFocusRingStroke: Bool?

    private enum Copy {
        static let statusFormat = "%lu / %lu"
        static let placeholder = "Find in page"
        static let closeTooltip = "Close"
        static let nextTooltip = "Next"
        static let previousTooltip = "Previous"
    }

    static func create() -> FindInPageViewController {
        FindInPageViewController(nibName: nil, bundle: nil)
    }

    override func loadView() {
        let backgroundView = FindInPageBackgroundView(frame: NSRect(
            x: 0,
            y: 0,
            width: FindInPageChromeLayout.panelWidth,
            height: FindInPageChromeLayout.panelHeight
        ))
        backgroundView.cornerRadius = 16
        backgroundView.borderWidth = 0.5
        backgroundView.borderColor = NSColor.separatorColor.withAlphaComponent(0.45)
        backgroundView.interceptClickEvents = true

        let textField = FindInPageTextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 14)
        textField.lineBreakMode = .byClipping
        textField.cell?.usesSingleLineMode = true
        textField.cell?.isScrollable = true
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let statusPillView = ColorView(frame: .zero)
        statusPillView.translatesAutoresizingMaskIntoConstraints = false
        statusPillView.cornerRadius = 7
        statusPillView.backgroundColor = NSColor.labelColor.withAlphaComponent(0.07)

        let statusField = NSTextField(labelWithString: "")
        statusField.translatesAutoresizingMaskIntoConstraints = false
        statusField.alignment = .center
        statusField.font = .systemFont(ofSize: 13, weight: .medium)
        statusField.lineBreakMode = .byClipping
        statusPillView.addSubview(statusField)

        let previousButton = makeChromeButton(
            imageName: "Find-Previous",
            tooltip: Copy.previousTooltip,
            action: #selector(findInPagePrevious(_:))
        )
        let nextButton = makeChromeButton(
            imageName: "Find-Next",
            tooltip: Copy.nextTooltip,
            action: #selector(findInPageNext(_:))
        )
        let closeButton = makeChromeButton(
            imageName: "Close-Large",
            tooltip: Copy.closeTooltip,
            action: #selector(findInPageDone(_:))
        )

        let stackView = NSStackView(views: [
            textField,
            statusPillView,
            previousButton,
            nextButton,
            closeButton,
        ])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.spacing = 8
        stackView.setCustomSpacing(12, after: textField)
        stackView.setCustomSpacing(8, after: statusPillView)
        stackView.setCustomSpacing(4, after: previousButton)
        stackView.setCustomSpacing(10, after: nextButton)
        backgroundView.addSubview(stackView)

        let focusRingView = FocusRingView(frame: .zero)
        focusRingView.isHidden = true
        backgroundView.addSubview(focusRingView)

        backgroundView.textField = textField

        self.backgroundView = backgroundView
        self.textField = textField
        self.focusRingView = focusRingView
        self.statusPillView = statusPillView
        self.statusField = statusField
        self.previousButton = previousButton
        self.nextButton = nextButton
        self.closeButton = closeButton
        self.view = backgroundView

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 18),
            stackView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -10),
            stackView.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
            stackView.heightAnchor.constraint(equalToConstant: 28),

            statusPillView.widthAnchor.constraint(equalToConstant: 52),
            statusPillView.heightAnchor.constraint(equalToConstant: 28),
            statusField.leadingAnchor.constraint(equalTo: statusPillView.leadingAnchor, constant: 8),
            statusField.trailingAnchor.constraint(equalTo: statusPillView.trailingAnchor, constant: -8),
            statusField.centerYAnchor.constraint(equalTo: statusPillView.centerYAnchor),

            previousButton.widthAnchor.constraint(equalToConstant: 26),
            previousButton.heightAnchor.constraint(equalToConstant: 26),
            nextButton.widthAnchor.constraint(equalToConstant: 26),
            nextButton.heightAnchor.constraint(equalToConstant: 26),
            closeButton.widthAnchor.constraint(equalToConstant: 26),
            closeButton.heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureAppKitViewsAfterNibLoad()

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

    private func configureAppKitViewsAfterNibLoad() {
        focusRingView.configureAfterNibLoadIfNeeded()
        for case let hover as MouseOverButton in [closeButton, nextButton, previousButton] {
            hover.configureAfterNibLoadIfNeeded()
        }
    }

    private func makeChromeButton(imageName: String, tooltip: String, action: Selector) -> MouseOverButton {
        let button = MouseOverButton(frame: .zero)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.setButtonType(.momentaryChange)
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.cornerRadius = 7
        button.mouseOverColor = NSColor.labelColor.withAlphaComponent(0.06)
        button.mouseDownColor = NSColor.labelColor.withAlphaComponent(0.12)
        button.mouseOverTintColor = .labelColor
        button.mouseDownTintColor = .labelColor
        button.mustAnimateOnMouseOver = true
        button.contentTintColor = .secondaryLabelColor

        let image = NSImage(named: imageName)?.copy() as? NSImage
        image?.isTemplate = true
        button.image = image

        return button
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
        updateTextActivationBoundary()
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
        guard NSApp.sumi_chromeIsReturnOrEnterPressed,
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
        if textField.sumi_chromeIsFirstResponder {
            textField.currentEditor()?.selectAll(nil)
        } else {
            textField.sumi_chromeMakeMeFirstResponder()
        }
    }

    private func subscribeToModelChanges(model: FindInPageModel?) {
        modelCancellables.removeAll()
        lastSyncedFocusRingStroke = nil

        guard let model else { return }

        applyModelState(
            text: model.text,
            matchesFound: model.matchesFound,
            currentSelection: model.currentSelection
        )

        Publishers.CombineLatest3(
            model.$text.removeDuplicates(),
            model.$matchesFound.removeDuplicates(),
            model.$currentSelection.removeDuplicates()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] text, matchesFound, currentSelection in
            self?.applyModelState(
                text: text,
                matchesFound: matchesFound,
                currentSelection: currentSelection
            )
        }
        .store(in: &modelCancellables)
    }

    private func applyModelState(text: String, matchesFound: UInt?, currentSelection: UInt?) {
        if textField.stringValue != text {
            textField.stringValue = text
        }
        rebuildStatus(matchesFound: matchesFound, currentSelection: currentSelection)
        updateFieldStates(text: text, matchesFound: matchesFound, currentSelection: currentSelection)
    }

    private func rebuildStatus(matchesFound: UInt?, currentSelection: UInt?) {
        statusField.stringValue = {
            guard let matchesFound,
                  let currentSelection else { return "" }
            return String(format: Copy.statusFormat, currentSelection, matchesFound)
        }()
    }

    private func updateView(firstResponder: Bool) {
        focusRingView.updateView(stroke: firstResponder)
    }

    private func updateFieldStates(text: String, matchesFound: UInt?, currentSelection: UInt?) {
        let isEmpty = text.isEmpty
        let canNavigate = matchesFound.map { $0 > 0 } ?? !isEmpty
        let hasStatus = !isEmpty && matchesFound != nil && currentSelection != nil

        statusPillView?.isHidden = !hasStatus
        statusField.isHidden = !hasStatus
        nextButton.isHidden = isEmpty
        previousButton.isHidden = isEmpty
        nextButton.isEnabled = canNavigate
        previousButton.isEnabled = canNavigate
        updateTextActivationBoundary()
    }

    private func updateTextActivationBoundary() {
        guard isViewLoaded, let closeButton else { return }

        let visibleBoundaryViews = [statusPillView, previousButton, nextButton, closeButton].compactMap { $0 }
            .filter { !$0.isHidden && $0.superview != nil }
        let firstBoundaryView = visibleBoundaryViews.min { lhs, rhs in
            lhs.convert(lhs.bounds, to: backgroundView).minX < rhs.convert(rhs.bounds, to: backgroundView).minX
        } ?? closeButton

        if textActivationBoundaryView !== firstBoundaryView {
            textActivationBoundaryView = firstBoundaryView
            backgroundView.textActivationBoundaryView = firstBoundaryView
        }

        backgroundView.invalidateTextActivationCursorRects()
        textField.window?.invalidateCursorRects(for: textField)
    }

    /// When `paint` is `nil`, uses catalog assets (e.g. before the first SwiftUI theme sync).
    func applyChromeColors(_ paint: FindInPageChromePaint?) {
        if let paint {
            backgroundView.backgroundColor = paint.shellBackground
            focusRingView.sumi_chromeApplyChromePaint(paint)
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
                hover.mouseOverTintColor = paint.primaryText
                hover.mouseDownTintColor = paint.primaryText
                hover.mouseOverColor = paint.secondaryText.withAlphaComponent(0.10)
                hover.mouseDownColor = paint.secondaryText.withAlphaComponent(0.16)
                hover.updateTintColor()
            }
            statusPillView?.backgroundColor = paint.secondaryText.withAlphaComponent(0.10)
            backgroundView.borderColor = paint.secondaryText.withAlphaComponent(0.18)
        } else {
            applyChromeColorsFromAssets()
        }
    }

    private func applyChromeColorsFromAssets() {
        backgroundView.backgroundColor = NSColor(named: "FindInPageBackgroundColor", bundle: .main) ?? .quaternaryLabelColor
        focusRingView.sumi_chromeApplyAssetColors()
        textField.textColor = .labelColor
        statusField.textColor = .secondaryLabelColor
        for case let hover as MouseOverButton in [closeButton, nextButton, previousButton] {
            hover.normalTintColor = .secondaryLabelColor
            hover.mouseOverTintColor = .labelColor
            hover.mouseDownTintColor = .labelColor
            hover.mouseOverColor = NSColor.labelColor.withAlphaComponent(0.06)
            hover.mouseDownColor = NSColor.labelColor.withAlphaComponent(0.12)
            hover.updateTintColor()
        }
        statusPillView?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.07)
        backgroundView.borderColor = NSColor.separatorColor.withAlphaComponent(0.45)
        textField.placeholderAttributedString = nil
        textField.placeholderString = Copy.placeholder
    }

    private func syncFocusRingWithFirstResponderIfNeeded() {
        let focused = textField.sumi_chromeIsFirstResponder
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
