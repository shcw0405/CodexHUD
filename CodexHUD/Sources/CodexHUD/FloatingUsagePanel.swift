import AppKit
import CodexHUDCore

struct FloatingUsageEntry {
    let label: String
    let value: String
    let suffix: String
    let subtitle: String
}

struct FloatingUsageAppearance: Equatable {
    let size: FloatingWindowSize
    let backgroundTone: FloatingTone
    let textTone: FloatingTone
}

final class FloatingUsagePanelController: NSObject {
    /// Invoked when the user clicks the panel's close button so the app can stop
    /// auto-revealing it on the next refresh.
    var onUserClose: (() -> Void)?

    private let panel: NSPanel
    private let contentView = FloatingUsageView(frame: .zero)
    private let closeButton = NSButton(frame: .zero)
    private var entryViews: [FloatingEntryView] = []
    private var appearance = FloatingUsageAppearance(size: .medium, backgroundTone: .medium, textTone: .light)

    override init() {
        self.panel = NSPanel(
            contentRect: NSRect(origin: NSPoint(x: 120, y: 120), size: Self.panelSize(for: .medium, entryCount: 1)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        super.init()
        self.configurePanel()
    }

    func show() {
        self.panel.orderFrontRegardless()
    }

    func hide() {
        self.panel.orderOut(nil)
    }

    func update(entries: [FloatingUsageEntry], appearance: FloatingUsageAppearance) {
        self.appearance = appearance
        self.contentView.backgroundTone = appearance.backgroundTone
        self.applySize(entryCount: entries.count)
        self.syncEntryViews(count: entries.count)

        for (index, entry) in entries.enumerated() {
            self.entryViews[index].update(entry: entry, appearance: appearance, compact: entries.count > 1)
        }
        self.layoutContent(entryCount: entries.count)
        self.contentView.needsDisplay = true
        // Visibility is owned by the caller (so a user-dismissed panel stays
        // hidden across refreshes); updating content must not force it open.
    }

    @objc private func close(_ sender: Any?) {
        self.panel.orderOut(nil)
        self.onUserClose?()
    }

    private func configurePanel() {
        self.panel.isOpaque = false
        self.panel.backgroundColor = .clear
        self.panel.hasShadow = true
        self.panel.level = .floating
        self.panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.panel.isMovableByWindowBackground = true
        self.panel.hidesOnDeactivate = false

        self.contentView.frame = self.panel.contentView?.bounds ?? NSRect(origin: .zero, size: Self.panelSize(for: .medium, entryCount: 1))
        self.contentView.autoresizingMask = [.width, .height]
        self.panel.contentView = self.contentView

        self.closeButton.title = "x"
        self.closeButton.bezelStyle = .regularSquare
        self.closeButton.isBordered = false
        self.closeButton.target = self
        self.closeButton.action = #selector(self.close(_:))
        self.contentView.addSubview(self.closeButton)

        self.positionNearTopRight()
    }

    private func applySize(entryCount: Int) {
        let oldFrame = self.panel.frame
        let newSize = Self.panelSize(for: self.appearance.size, entryCount: entryCount)
        let newOrigin = NSPoint(x: oldFrame.maxX - newSize.width, y: oldFrame.maxY - newSize.height)
        self.panel.setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
        self.contentView.frame = NSRect(origin: .zero, size: newSize)
    }

    private func syncEntryViews(count: Int) {
        while self.entryViews.count < count {
            let view = FloatingEntryView(frame: .zero)
            self.entryViews.append(view)
            self.contentView.addSubview(view, positioned: .below, relativeTo: self.closeButton)
        }
        while self.entryViews.count > count {
            self.entryViews.removeLast().removeFromSuperview()
        }
    }

    private func layoutContent(entryCount: Int) {
        let bounds = self.contentView.bounds
        self.closeButton.frame = NSRect(x: bounds.maxX - 27, y: bounds.maxY - 28, width: 20, height: 20)
        self.closeButton.font = Self.closeButtonFont(for: self.appearance.size)
        self.closeButton.contentTintColor = Self.textColor(for: self.appearance.textTone).withAlphaComponent(0.65)

        guard entryCount > 0 else { return }
        let topPadding: CGFloat = entryCount > 1 ? 12 : 8
        let bottomPadding: CGFloat = entryCount > 1 ? 10 : 8
        let availableHeight = bounds.height - topPadding - bottomPadding
        let rowHeight = availableHeight / CGFloat(entryCount)
        for (index, view) in self.entryViews.enumerated() {
            let y = bottomPadding + rowHeight * CGFloat(entryCount - index - 1)
            view.frame = NSRect(x: 10, y: y, width: bounds.width - 20, height: rowHeight)
        }
    }

    private func positionNearTopRight() {
        guard let screenFrame = NSScreen.main?.visibleFrame else { return }
        let frame = self.panel.frame
        let origin = NSPoint(
            x: screenFrame.maxX - frame.width - 24,
            y: screenFrame.maxY - frame.height - 24)
        self.panel.setFrameOrigin(origin)
    }

    private static func panelSize(for size: FloatingWindowSize, entryCount: Int) -> NSSize {
        switch (size, entryCount > 1) {
        case (.small, false): return NSSize(width: 110, height: 74)
        case (.medium, false): return NSSize(width: 118, height: 76)
        case (.large, false): return NSSize(width: 140, height: 90)
        case (.small, true): return NSSize(width: 128, height: 88)
        case (.medium, true): return NSSize(width: 140, height: 96)
        case (.large, true): return NSSize(width: 164, height: 114)
        }
    }

    fileprivate static func backgroundAlpha(for tone: FloatingTone) -> CGFloat {
        switch tone {
        case .light: return 0.24
        case .medium: return 0.42
        case .dark: return 0.64
        }
    }

    fileprivate static func textColor(for tone: FloatingTone) -> NSColor {
        switch tone {
        case .light: return NSColor.white.withAlphaComponent(0.72)
        case .medium: return NSColor.white.withAlphaComponent(0.86)
        case .dark: return NSColor.white
        }
    }

    fileprivate static func valueFont(for size: FloatingWindowSize, compact: Bool) -> NSFont {
        let fontSize: CGFloat
        switch (size, compact) {
        case (.small, false): fontSize = 26
        case (.medium, false): fontSize = 34
        case (.large, false): fontSize = 42
        case (.small, true): fontSize = 19
        case (.medium, true): fontSize = 26
        case (.large, true): fontSize = 31
        }
        return NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
    }

    fileprivate static func labelFont(for size: FloatingWindowSize, compact: Bool) -> NSFont {
        let fontSize: CGFloat
        switch (size, compact) {
        case (.small, false): fontSize = 9
        case (.medium, false): fontSize = 10
        case (.large, false): fontSize = 12
        case (.small, true): fontSize = 8
        case (.medium, true): fontSize = 10
        case (.large, true): fontSize = 11
        }
        return NSFont.systemFont(ofSize: fontSize, weight: .semibold)
    }

    fileprivate static func suffixFont(for size: FloatingWindowSize, compact: Bool) -> NSFont {
        let fontSize: CGFloat
        switch (size, compact) {
        case (.small, false): fontSize = 12
        case (.medium, false): fontSize = 14
        case (.large, false): fontSize = 17
        case (.small, true): fontSize = 10
        case (.medium, true): fontSize = 12
        case (.large, true): fontSize = 14
        }
        return NSFont.systemFont(ofSize: fontSize, weight: .medium)
    }

    fileprivate static func subtitleFont(for size: FloatingWindowSize) -> NSFont {
        let fontSize: CGFloat
        switch size {
        case .small: fontSize = 8
        case .medium: fontSize = 10
        case .large: fontSize = 12
        }
        return NSFont.systemFont(ofSize: fontSize, weight: .medium)
    }

    private static func closeButtonFont(for size: FloatingWindowSize) -> NSFont {
        let fontSize: CGFloat
        switch size {
        case .small: fontSize = 11
        case .medium: fontSize = 13
        case .large: fontSize = 15
        }
        return NSFont.systemFont(ofSize: fontSize, weight: .medium)
    }
}

private extension NSFont {
    var codexHUDLineHeight: CGFloat {
        ceil(self.ascender - self.descender + self.leading)
    }
}

private final class FloatingEntryView: NSView {
    private var entry = FloatingUsageEntry(label: "", value: "", suffix: "", subtitle: "")
    private var compact = false
    private var usageAppearance = FloatingUsageAppearance(size: .medium, backgroundTone: .medium, textTone: .light)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(entry: FloatingUsageEntry, appearance: FloatingUsageAppearance, compact: Bool) {
        self.entry = entry
        self.compact = compact
        self.usageAppearance = appearance
        self.needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let color = FloatingUsagePanelController.textColor(for: self.usageAppearance.textTone)
        if self.compact {
            self.drawCompact(color: color)
        } else {
            self.drawSingle(color: color)
        }
    }

    private func drawCompact(color: NSColor) {
        let bounds = self.bounds.insetBy(dx: 2, dy: 2)
        let labelFont = FloatingUsagePanelController.labelFont(for: self.usageAppearance.size, compact: true)
        let valueFont = FloatingUsagePanelController.valueFont(for: self.usageAppearance.size, compact: true)
        let suffixFont = FloatingUsagePanelController.suffixFont(for: self.usageAppearance.size, compact: true)

        let labelWidth: CGFloat = self.usageAppearance.size == .small ? 24 : 28
        let suffixWidth: CGFloat = self.entry.suffix.isEmpty ? 0 : (self.usageAppearance.size == .small ? 18 : 22)
        self.drawText(self.entry.label, in: NSRect(x: bounds.minX, y: bounds.midY - labelFont.codexHUDLineHeight / 2, width: labelWidth, height: labelFont.codexHUDLineHeight), font: labelFont, color: color.withAlphaComponent(0.75), alignment: .center)
        self.drawText(self.entry.value, in: NSRect(x: bounds.minX + labelWidth + 2, y: bounds.midY - valueFont.codexHUDLineHeight / 2, width: bounds.width - labelWidth - suffixWidth - 6, height: valueFont.codexHUDLineHeight), font: valueFont, color: color, alignment: .right)
        if !self.entry.suffix.isEmpty {
            self.drawText(self.entry.suffix, in: NSRect(x: bounds.maxX - suffixWidth, y: bounds.midY - suffixFont.codexHUDLineHeight / 2 + 1, width: suffixWidth, height: suffixFont.codexHUDLineHeight), font: suffixFont, color: color.withAlphaComponent(0.85), alignment: .left)
        }
    }

    private func drawSingle(color: NSColor) {
        let bounds = self.bounds.insetBy(dx: 4, dy: 3)
        let labelFont = FloatingUsagePanelController.labelFont(for: self.usageAppearance.size, compact: false)
        let valueFont = FloatingUsagePanelController.valueFont(for: self.usageAppearance.size, compact: false)
        let suffixFont = FloatingUsagePanelController.suffixFont(for: self.usageAppearance.size, compact: false)
        let subtitleFont = FloatingUsagePanelController.subtitleFont(for: self.usageAppearance.size)

        let labelHeight = labelFont.codexHUDLineHeight
        let subtitleHeight = subtitleFont.codexHUDLineHeight
        let topY = bounds.maxY - labelHeight
        self.drawText(self.entry.label, in: NSRect(x: bounds.minX, y: topY, width: bounds.width, height: labelHeight), font: labelFont, color: color.withAlphaComponent(0.75), alignment: .center)
        self.drawText(self.entry.subtitle, in: NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: subtitleHeight), font: subtitleFont, color: color.withAlphaComponent(0.72), alignment: .center)

        let valueHeight = valueFont.codexHUDLineHeight
        let valueY = bounds.minY + subtitleHeight + max(1, (topY - bounds.minY - subtitleHeight - valueHeight) / 2)
        let suffixWidth: CGFloat = self.entry.suffix.isEmpty ? 0 : max(18, suffixFont.pointSize * 1.7)
        let valueRect = NSRect(x: bounds.minX, y: valueY, width: bounds.width - suffixWidth - 2, height: valueHeight)
        self.drawText(self.entry.value, in: valueRect, font: valueFont, color: color, alignment: .right)
        if !self.entry.suffix.isEmpty {
            self.drawText(self.entry.suffix, in: NSRect(x: valueRect.maxX + 2, y: valueY + max(0, (valueHeight - suffixFont.codexHUDLineHeight) / 2) + 1, width: suffixWidth, height: suffixFont.codexHUDLineHeight), font: suffixFont, color: color.withAlphaComponent(0.85), alignment: .left)
        }
    }

    private func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byClipping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        text.draw(in: rect.integral, withAttributes: attributes)
    }
}

private final class FloatingUsageView: NSView {
    var backgroundTone: FloatingTone = .medium

    override var mouseDownCanMoveWindow: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: self.bounds, xRadius: 18, yRadius: 18)
        NSColor.black.withAlphaComponent(FloatingUsagePanelController.backgroundAlpha(for: self.backgroundTone)).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.18).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
