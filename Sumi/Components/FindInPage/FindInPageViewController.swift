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
        sumi_chromeAddCursorRect(textActivationRect, cursor: .iBeam)
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

private final class FindInPageFieldEditor: NSTextView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isFieldEditor = true
        drawsBackground = false
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        isFieldEditor = true
        drawsBackground = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isFieldEditor = true
        drawsBackground = false
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        sumi_chromeAddCursorRect(bounds, cursor: .iBeam)
    }

    override func cursorUpdate(with event: NSEvent) {
        super.cursorUpdate(with: event)
        ChromeCursorKind.iBeam.set()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        setIBeamCursorIfMouseInside()
    }

    func invalidateIBeamCursorRects() {
        window?.invalidateCursorRects(for: self)
    }

    func setIBeamCursorIfMouseInside() {
        sumi_chromeSetCursorIfMouseInside(.iBeam)
    }
}

private final class FindInPageTextFieldCell: NSTextFieldCell {
    private let findFieldEditor = FindInPageFieldEditor(frame: .zero)

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        findFieldEditor
    }
}

private final class FindInPageTextField: NSTextField {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        sumi_chromeAddCursorRect(bounds, cursor: .iBeam)
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
    weak var placeholderLabel: NSTextField!
    weak var statusField: NSTextField!
    weak var nextButton: NSButton!
    weak var previousButton: NSButton!

    private var statusPillView: ColorView?
    private var statusPillWidthConstraint: NSLayoutConstraint?
    private weak var textFocusHost: ChromeTextFieldFocusHostView?
    private weak var textActivationBoundaryView: NSView?
    private var modelCancellables = Set<AnyCancellable>()

    private enum Copy {
        static let placeholder: LocalizedStringResource = "Find in page"
        static let statusAccessibilityLabel: LocalizedStringResource = "Find match position"

        static func status(current: UInt, total: UInt) -> String {
            "\(current)/\(total)"
        }

        static func string(_ resource: LocalizedStringResource) -> String {
            String(localized: resource)
        }
    }

    private enum Layout {
        static let statusHorizontalInset: CGFloat = 8
        static let minimumStatusWidth: CGFloat = 52
        static let maximumStatusWidth: CGFloat = 84
    }

    private enum ChromeAction {
        case previous
        case next
        case close

        var title: LocalizedStringResource {
            switch self {
            case .previous:
                return "Previous match"
            case .next:
                return "Next match"
            case .close:
                return "Close find bar"
            }
        }

        var help: LocalizedStringResource {
            switch self {
            case .previous:
                return "Previous match (Shift-Return)"
            case .next:
                return "Next match (Return)"
            case .close:
                return "Close find bar (Escape)"
            }
        }

        var accessibilityIdentifier: String {
            switch self {
            case .previous:
                return "FindInPageController.previousButton"
            case .next:
                return "FindInPageController.nextButton"
            case .close:
                return "FindInPageController.closeButton"
            }
        }
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
        textField.cell = FindInPageTextFieldCell(textCell: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.isEditable = true
        textField.isSelectable = true
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 14)
        textField.lineBreakMode = .byClipping
        textField.cell?.usesSingleLineMode = true
        textField.cell?.isScrollable = true
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let textFocusHost = ChromeTextFieldFocusHostView(textField: textField)
        textFocusHost.translatesAutoresizingMaskIntoConstraints = false
        textFocusHost.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textFocusHost.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let placeholderLabel = NSTextField(labelWithString: Copy.string(Copy.placeholder))
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.font = textField.font
        placeholderLabel.textColor = .placeholderTextColor
        placeholderLabel.lineBreakMode = .byClipping
        placeholderLabel.setAccessibilityElement(false)
        textFocusHost.addSubview(placeholderLabel, positioned: .below, relativeTo: textField)

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
            descriptor: .previous,
            action: #selector(findInPagePrevious(_:))
        )
        let nextButton = makeChromeButton(
            imageName: "Find-Next",
            descriptor: .next,
            action: #selector(findInPageNext(_:))
        )
        let closeButton = makeChromeButton(
            imageName: "Close-Large",
            descriptor: .close,
            action: #selector(findInPageDone(_:))
        )

        let stackView = NSStackView(views: [
            textFocusHost,
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
        stackView.setCustomSpacing(12, after: textFocusHost)
        stackView.setCustomSpacing(8, after: statusPillView)
        stackView.setCustomSpacing(4, after: previousButton)
        stackView.setCustomSpacing(10, after: nextButton)
        backgroundView.addSubview(stackView)

        backgroundView.textField = textField

        self.backgroundView = backgroundView
        self.textField = textField
        self.textFocusHost = textFocusHost
        self.placeholderLabel = placeholderLabel
        self.statusPillView = statusPillView
        self.statusField = statusField
        self.previousButton = previousButton
        self.nextButton = nextButton
        self.closeButton = closeButton
        self.view = backgroundView

        let statusPillWidthConstraint = statusPillView.widthAnchor.constraint(
            equalToConstant: Layout.minimumStatusWidth
        )
        self.statusPillWidthConstraint = statusPillWidthConstraint

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 18),
            stackView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -10),
            stackView.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
            stackView.heightAnchor.constraint(equalToConstant: 28),

            statusPillWidthConstraint,
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

            placeholderLabel.leadingAnchor.constraint(equalTo: textField.leadingAnchor, constant: 2),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textField.trailingAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: textField.centerYAnchor),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureAppKitViewsAfterNibLoad()

        textField.delegate = self

        textField.setAccessibilityIdentifier("FindInPageController.textField")
        textField.setAccessibilityRole(.textField)
        textField.setAccessibilityLabel(Copy.string(Copy.placeholder))
        statusField.setAccessibilityIdentifier("FindInPageController.statusField")
        statusField.setAccessibilityRole(.staticText)
        statusField.setAccessibilityLabel(Copy.string(Copy.statusAccessibilityLabel))

    }

    private func configureAppKitViewsAfterNibLoad() {
        for case let hover as MouseOverButton in [closeButton, nextButton, previousButton] {
            hover.configureAfterNibLoadIfNeeded()
        }
    }

    private func makeChromeButton(
        imageName: String,
        descriptor: ChromeAction,
        action: Selector
    ) -> MouseOverButton {
        let button = MouseOverButton(frame: .zero)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.setButtonType(.momentaryChange)
        button.toolTip = Copy.string(descriptor.help)
        button.setAccessibilityTitle(Copy.string(descriptor.title))
        button.setAccessibilityIdentifier(descriptor.accessibilityIdentifier)
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
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            delegate?.findInPageDone(self)
            return true
        }

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

    func requestTextFocus(generation: UInt) {
        textFocusHost?.requestFocus(id: generation, selectAll: true)
    }

    func cancelPendingTextFocus() {
        textFocusHost?.cancelPendingFocus()
    }

    private func subscribeToModelChanges(model: FindInPageModel?) {
        modelCancellables.removeAll()

        guard let model else { return }

        applyModelState(
            text: model.text,
            matchesFound: model.matchesFound,
            currentSelection: model.currentSelection
        )

        Publishers.CombineLatest(
            model.$text.removeDuplicates(),
            model.$progress.removeDuplicates()
        )
        .sink { [weak self] text, progress in
            self?.applyModelState(
                text: text,
                matchesFound: progress?.matchesFound,
                currentSelection: progress?.currentSelection
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
            return Copy.status(current: currentSelection, total: matchesFound)
        }()
        let contentWidth = ceil(statusField.intrinsicContentSize.width)
            + Layout.statusHorizontalInset * 2
        statusPillWidthConstraint?.constant = min(
            max(contentWidth, Layout.minimumStatusWidth),
            Layout.maximumStatusWidth
        )
    }

    private func updateFieldStates(text: String, matchesFound: UInt?, currentSelection: UInt?) {
        let isEmpty = text.isEmpty
        let canNavigate = matchesFound.map { $0 > 0 } ?? !isEmpty
        let hasStatus = !isEmpty && matchesFound != nil && currentSelection != nil

        statusPillView?.isHidden = !hasStatus
        statusField.isHidden = !hasStatus
        placeholderLabel.isHidden = !isEmpty
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
        if let editor = textField.currentEditor() as? FindInPageFieldEditor {
            editor.invalidateIBeamCursorRects()
            editor.setIBeamCursorIfMouseInside()
        }
    }

    func applyChromeColors(_ paint: FindInPageChromePaint) {
        backgroundView.backgroundColor = paint.shellBackground
        textField.textColor = paint.primaryText
        placeholderLabel.textColor = paint.secondaryText
        statusField.textColor = paint.secondaryText

        for case let hover as MouseOverButton in [closeButton, nextButton, previousButton] {
            hover.normalTintColor = paint.secondaryText
            hover.mouseOverTintColor = paint.primaryText
            hover.mouseDownTintColor = paint.primaryText
            hover.mouseOverColor = paint.secondaryText.withAlphaComponent(0.10)
            hover.mouseDownColor = paint.secondaryText.withAlphaComponent(0.16)
            hover.updateTintColor()
        }
        statusPillView?.backgroundColor = paint.secondaryText.withAlphaComponent(0.10)
        backgroundView.borderColor = paint.shellBorder
    }

}

extension FindInPageViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        model?.find(textField.stringValue)
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        let fieldEditor = obj.userInfo?["NSFieldEditor"] as? FindInPageFieldEditor
            ?? textField.currentEditor() as? FindInPageFieldEditor
        fieldEditor?.invalidateIBeamCursorRects()
        fieldEditor?.setIBeamCursorIfMouseInside()
    }

}
