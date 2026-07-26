//
//  CommandPaletteTextField.swift
//  Sumi
//
//

import AppKit
import SwiftUI

struct CommandPaletteTextField: NSViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let font: NSFont
    let primaryColor: NSColor
    let focusRequestID: UInt
    let focusSelectAll: Bool
    let onTab: () -> Bool
    let onReturn: () -> Void
    let onMoveSelection: (Int) -> Void
    let onEscape: () -> Void
    let onDeleteAtEmptySiteSearch: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> CommandPaletteTextFieldView {
        let view = CommandPaletteTextFieldView()
        view.textField.delegate = context.coordinator
        context.coordinator.configure(
            onTab: onTab,
            onReturn: onReturn,
            onMoveSelection: onMoveSelection,
            onEscape: onEscape,
            onDeleteAtEmptySiteSearch: onDeleteAtEmptySiteSearch
        )
        update(view, context: context)
        return view
    }

    func updateNSView(_ nsView: CommandPaletteTextFieldView, context: Context) {
        nsView.textField.delegate = context.coordinator
        context.coordinator.configure(
            onTab: onTab,
            onReturn: onReturn,
            onMoveSelection: onMoveSelection,
            onEscape: onEscape,
            onDeleteAtEmptySiteSearch: onDeleteAtEmptySiteSearch
        )
        update(nsView, context: context)
    }

    private func update(_ nsView: CommandPaletteTextFieldView, context _: Context) {
        nsView.configure(
            text: text,
            font: font,
            primaryColor: primaryColor
        )

        nsView.wantsTextFocus = isFocused.wrappedValue
        nsView.requestFocus(id: focusRequestID, selectAll: focusSelectAll)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String
        private var onTab: () -> Bool = { false }
        private var onReturn: () -> Void = { /* No-op. */ }
        private var onMoveSelection: (Int) -> Void = { _ in /* No-op. */ }
        private var onEscape: () -> Void = { /* No-op. */ }
        private var onDeleteAtEmptySiteSearch: () -> Bool = { false }

        init(text: Binding<String>) {
            _text = text
        }

        func configure(
            onTab: @escaping () -> Bool,
            onReturn: @escaping () -> Void,
            onMoveSelection: @escaping (Int) -> Void,
            onEscape: @escaping () -> Void,
            onDeleteAtEmptySiteSearch: @escaping () -> Bool
        ) {
            self.onTab = onTab
            self.onReturn = onReturn
            self.onMoveSelection = onMoveSelection
            self.onEscape = onEscape
            self.onDeleteAtEmptySiteSearch = onDeleteAtEmptySiteSearch
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text = textField.stringValue
        }

        func control(
            _: NSControl,
            textView _: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                onMoveSelection(-1)
                return true
            case #selector(NSResponder.moveDown(_:)):
                onMoveSelection(1)
                return true
            case #selector(NSResponder.moveRight(_:)):
                return false
            case #selector(NSResponder.moveLeft(_:)):
                return false
            case #selector(NSResponder.insertTab(_:)):
                return onTab()
            case #selector(NSResponder.insertNewline(_:)):
                onReturn()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                onEscape()
                return true
            case #selector(NSResponder.deleteBackward(_:)),
                 #selector(NSResponder.deleteForward(_:)):
                return onDeleteAtEmptySiteSearch()
            default:
                return false
            }
        }
    }
}

final class CommandPaletteTextFieldView: ChromeTextFieldFocusHostView {
    // Focus-maintenance hint only. Explicit focus requests (requestFocus)
    // are authoritative and must not be gated on this: the SwiftUI FocusState
    // backing it has no .focused() anchor, so it can stay false forever.

    init() {
        super.init(textField: NSTextField())
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = true

        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.lineBreakMode = .byClipping
        textField.maximumNumberOfLines = 1
        textField.usesSingleLineMode = true
        textField.setAccessibilityIdentifier("command-palette-input")
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    func configure(
        text: String,
        font: NSFont,
        primaryColor: NSColor
    ) {
        textField.font = font
        textField.textColor = primaryColor
        if let editor = textField.currentEditor() as? NSTextView {
            if editor.string != text {
                editor.string = text
            }
            textField.stringValue = text
            return
        }

        if textField.stringValue != text {
            textField.stringValue = text
        }
    }
}
