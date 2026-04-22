import AppKit
import SwiftUI

// Adapted from DuckDuckGo macOS `TabTitleView` and related animation helpers.
// Upstream reference in this workspace is Apache-2.0 licensed.

struct SumiTabTitleLabel: View {
    let title: String
    var font: NSFont = .systemFont(ofSize: 13, weight: .medium)
    var textColor: Color = .primary
    var fadeWidth: CGFloat = 32
    var trailingFadePadding: CGFloat = 0
    var animated: Bool = true
    var height: CGFloat = 16

    var body: some View {
        SumiTabTitleRepresentable(
            title: title,
            font: font,
            textColor: textColor,
            fadeWidth: fadeWidth,
            trailingFadePadding: trailingFadePadding,
            animated: animated,
            height: height
        )
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
        .clipped()
        .accessibilityLabel(title)
    }
}

private struct SumiTabTitleRepresentable: NSViewRepresentable {
    let title: String
    let font: NSFont
    let textColor: Color
    let fadeWidth: CGFloat
    let trailingFadePadding: CGFloat
    let animated: Bool
    let height: CGFloat

    func makeNSView(context _: Context) -> SumiTabTitleView {
        let view = SumiTabTitleView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: SumiTabTitleView,
        context _: Context
    ) -> CGSize? {
        CGSize(
            width: proposal.width ?? nsView.fittingSize.width,
            height: proposal.height ?? height
        )
    }

    func updateNSView(_ nsView: SumiTabTitleView, context _: Context) {
        nsView.apply(
            title: title,
            font: font,
            textColor: NSColor(textColor),
            fadeWidth: fadeWidth,
            trailingFadePadding: trailingFadePadding,
            animated: animated
        )
    }
}

enum SumiTabTitleAnimation {
    static let fadeAndSlideOutKey = "fadeOutAndSlide"
    static let slideInKey = "slideIn"
    static let alphaKey = "alpha"
    static let duration: TimeInterval = 0.2
    static let previousTitleAlpha = Float(0.6)
    static let slidingOutStartX = CGFloat(0)
    static let slidingOutLastX = CGFloat(-4)
    static let slidingInStartX = CGFloat(-4)
    static let slidingInLastX = CGFloat(0)
}

final class SumiTabTitleView: NSView {
    private lazy var titleTextField: NSTextField = buildTitleTextField()
    private lazy var previousTextField: NSTextField = buildTitleTextField()
    private var fadeWidth: CGFloat = 32
    private var trailingFadePadding: CGFloat = 0

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 16)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupSubviews()
        setupLayer()
        setupConstraints()
        setupTextFields()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        applyTrailingFadeMask(width: fadeWidth, trailingPadding: trailingFadePadding)
    }

    func apply(
        title: String,
        font: NSFont,
        textColor: NSColor,
        fadeWidth: CGFloat,
        trailingFadePadding: CGFloat,
        animated: Bool
    ) {
        self.fadeWidth = fadeWidth
        self.trailingFadePadding = trailingFadePadding
        titleTextField.font = font
        previousTextField.font = font
        titleTextField.textColor = textColor
        previousTextField.textColor = textColor
        applyTrailingFadeMask(width: fadeWidth, trailingPadding: trailingFadePadding)
        displayTitleIfNeeded(title: title, animated: animated)
    }
}

private extension SumiTabTitleView {
    func displayTitleIfNeeded(title: String, animated: Bool = true) {
        let previousTitle = titleTextField.stringValue
        guard title != previousTitle else {
            return
        }

        titleTextField.stringValue = title
        previousTextField.stringValue = previousTitle

        guard animated, shouldAnimateTransition(to: title, from: previousTitle) else {
            return
        }

        transitionToLatestTitle(fadeInTitle: true)
    }

    func setupSubviews() {
        addSubview(previousTextField)
        addSubview(titleTextField)
    }

    func setupLayer() {
        wantsLayer = true
    }

    func setupConstraints() {
        titleTextField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleTextField.topAnchor.constraint(equalTo: topAnchor),
            titleTextField.bottomAnchor.constraint(equalTo: bottomAnchor),
            titleTextField.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleTextField.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        previousTextField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            previousTextField.topAnchor.constraint(equalTo: topAnchor),
            previousTextField.bottomAnchor.constraint(equalTo: bottomAnchor),
            previousTextField.leadingAnchor.constraint(equalTo: leadingAnchor),
            previousTextField.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    func setupTextFields() {
        titleTextField.textColor = .labelColor
        previousTextField.textColor = .labelColor
    }

    func buildTitleTextField() -> NSTextField {
        let textField = NSTextField()
        textField.wantsLayer = true
        textField.isEditable = false
        textField.alignment = .left
        textField.drawsBackground = false
        textField.isBordered = false
        textField.isBezeled = false
        textField.isSelectable = false
        textField.font = .systemFont(ofSize: 13)
        textField.lineBreakMode = .byClipping
        if let cell = textField.cell as? NSTextFieldCell {
            cell.lineBreakMode = .byClipping
            cell.wraps = false
            cell.usesSingleLineMode = true
            cell.truncatesLastVisibleLine = false
        }
        return textField
    }

    func shouldAnimateTransition(to title: String, from previousTitle: String) -> Bool {
        title != previousTitle && previousTitle.isEmpty == false
    }
}

private extension SumiTabTitleView {
    func transitionToLatestTitle(fadeInTitle: Bool) {
        CATransaction.begin()

        dismissPreviousTitle()
        presentCurrentTitle()

        if fadeInTitle {
            transitionTitleToAlpha(toAlpha: titleTextField.alphaValue, fromAlpha: 0)
        }

        CATransaction.commit()
    }

    func dismissPreviousTitle() {
        guard let previousTitleLayer = previousTextField.layer else {
            return
        }

        let animationGroup = CAAnimationGroup()
        animationGroup.animations = [
            CABasicAnimation.buildFadeOutAnimation(
                duration: SumiTabTitleAnimation.duration,
                fromAlpha: SumiTabTitleAnimation.previousTitleAlpha
            ),
            CASpringAnimation.buildTranslationXAnimation(
                duration: SumiTabTitleAnimation.duration,
                fromValue: SumiTabTitleAnimation.slidingOutStartX,
                toValue: SumiTabTitleAnimation.slidingOutLastX
            )
        ]

        previousTitleLayer.opacity = 0
        previousTitleLayer.add(animationGroup, forKey: SumiTabTitleAnimation.fadeAndSlideOutKey)
    }

    func presentCurrentTitle() {
        guard let titleLayer = titleTextField.layer else {
            return
        }

        let slideAnimation = CASpringAnimation.buildTranslationXAnimation(
            duration: SumiTabTitleAnimation.duration,
            fromValue: SumiTabTitleAnimation.slidingInStartX,
            toValue: SumiTabTitleAnimation.slidingInLastX
        )
        titleLayer.add(slideAnimation, forKey: SumiTabTitleAnimation.slideInKey)
    }

    func transitionTitleToAlpha(toAlpha: CGFloat, fromAlpha: CGFloat) {
        guard let titleLayer = titleTextField.layer else {
            return
        }

        let animation = CABasicAnimation.buildFadeAnimation(
            duration: SumiTabTitleAnimation.duration,
            fromAlpha: Float(fromAlpha),
            toAlpha: Float(toAlpha)
        )
        titleLayer.add(animation, forKey: SumiTabTitleAnimation.alphaKey)
    }
}

private extension NSView {
    func applyTrailingFadeMask(width: CGFloat, trailingPadding: CGFloat) {
        guard let layer else {
            return
        }

        guard layer.bounds.width > 0 else {
            return
        }

        if layer.mask == nil {
            let maskGradientLayer = CAGradientLayer()
            layer.mask = maskGradientLayer
            maskGradientLayer.colors = [NSColor.white.cgColor, NSColor.clear.cgColor]
        }

        guard let mask = layer.mask as? CAGradientLayer else {
            return
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(0)

        mask.frame = layer.bounds

        let availableWidth = max(mask.bounds.width - trailingPadding, 0)
        let safeWidth = min(width, availableWidth)
        let startPointX = mask.bounds.width > 0
            ? (mask.bounds.width - (trailingPadding + safeWidth)) / mask.bounds.width
            : 1
        let endPointX = mask.bounds.width > 0
            ? (mask.bounds.width - trailingPadding) / mask.bounds.width
            : 1

        mask.startPoint = CGPoint(x: startPointX, y: 0.5)
        mask.endPoint = CGPoint(x: endPointX, y: 0.5)

        CATransaction.commit()
    }
}

private extension CABasicAnimation {
    static func buildFadeOutAnimation(
        duration: TimeInterval,
        timingFunctionName: CAMediaTimingFunctionName = .easeInEaseOut,
        fromAlpha: Float? = nil
    ) -> CABasicAnimation {
        buildFadeAnimation(
            duration: duration,
            timingFunctionName: timingFunctionName,
            fromAlpha: fromAlpha,
            toAlpha: 0
        )
    }

    static func buildFadeAnimation(
        duration: TimeInterval,
        timingFunctionName: CAMediaTimingFunctionName = .easeInEaseOut,
        fromAlpha: Float? = nil,
        toAlpha: Float
    ) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: #keyPath(CALayer.opacity))
        animation.duration = duration
        animation.fromValue = fromAlpha
        animation.toValue = toAlpha
        animation.timingFunction = CAMediaTimingFunction(name: timingFunctionName)
        return animation
    }
}

private extension CASpringAnimation {
    static func buildTranslationXAnimation(
        duration: TimeInterval,
        timingFunctionName: CAMediaTimingFunctionName = .easeInEaseOut,
        fromValue: CGFloat,
        toValue: CGFloat
    ) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: "transform.translation.x")
        animation.fromValue = fromValue
        animation.toValue = toValue
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: timingFunctionName)
        return animation
    }
}
