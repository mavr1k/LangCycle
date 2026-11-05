import AppKit

enum HUDSize: Int, CaseIterable {
    case small, medium, large

    var title: String { ["Small", "Medium", "Large"][rawValue] }
    var minimumSize: NSSize { [NSSize(width: 320, height: 180), NSSize(width: 380, height: 210),
                               NSSize(width: 460, height: 260)][rawValue] }
    var fontSize: CGFloat { [48, 60, 76][rawValue] }
}

/// A panel that can never become key or main, so it never takes focus from the text field being typed in.
private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The large language indicator (FR-11…FR-16). One panel, reused for every switch.
final class HUD {
    private let panel = HUDPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
    private let content = NSStackView()
    private let icon = NSImageView()
    private let code = NSTextField(labelWithString: "")
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let cycle = NSStackView()
    private var iconSize: [NSLayoutConstraint] = []
    private var hideTimer: DispatchWorkItem?
    private var generation = 0

    init() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false  // the app is never active
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active  // otherwise it renders as an inactive window
        background.maskImage = HUD.roundedMask(radius: 24)
        panel.contentView = background

        icon.imageScaling = .scaleProportionallyUpOrDown
        iconSize = [icon.widthAnchor.constraint(equalToConstant: 24), icon.heightAnchor.constraint(equalToConstant: 24)]
        NSLayoutConstraint.activate(iconSize)
        let header = NSStackView(views: [icon, code])
        header.spacing = 8
        code.textColor = .secondaryLabelColor
        subtitle.textColor = .secondaryLabelColor
        cycle.spacing = 6

        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 4
        [header, title, subtitle, cycle].forEach(content.addArrangedSubview)
        content.setCustomSpacing(16, after: subtitle)
        content.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(content)
        NSLayoutConstraint.activate([content.centerXAnchor.constraint(equalTo: background.centerXAnchor),
                                     content.centerYAnchor.constraint(equalTo: background.centerYAnchor)])
    }

    /// Shows `active` (with the whole cycle underneath) and restarts the hide timer.
    func show(_ active: Layout, in layouts: [Layout], size: HUDSize) {
        // Size the card for the widest/tallest layout in the cycle, so it does not resize between presses.
        var fit = NSSize.zero
        for layout in layouts + [active] {
            configure(layout, in: layouts, size: size)
            let candidate = content.fittingSize
            fit = NSSize(width: max(fit.width, candidate.width), height: max(fit.height, candidate.height))
        }
        configure(active, in: layouts, size: size)

        let width = max(size.minimumSize.width, fit.width + 64), height = max(size.minimumSize.height, fit.height + 48)
        let mouse = NSEvent.mouseLocation
        let frame = (NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main)?.frame ?? .zero
        panel.setFrame(NSRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height),
                       display: true)
        panel.invalidateShadow()

        generation += 1
        NSAnimationContext.runAnimationGroup { $0.duration = 0; panel.animator().alphaValue = 1 }  // cancels a fade
        panel.orderFrontRegardless()  // never makeKey / activate
        hideTimer?.cancel()
        let shown = generation
        let timer = DispatchWorkItem { [weak self] in self?.fadeOut(shown) }
        hideTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: timer)
    }

    /// Fills the card's content for `active`, with the whole cycle underneath.
    private func configure(_ active: Layout, in layouts: [Layout], size: HUDSize) {
        let font = size.fontSize
        icon.image = InputSources.icon(for: active)
        icon.isHidden = icon.image == nil
        iconSize.forEach { $0.constant = font * 0.5 }
        code.stringValue = active.code
        code.font = .systemFont(ofSize: font * 0.4, weight: .semibold)
        title.stringValue = active.title
        title.font = .systemFont(ofSize: font, weight: .bold)
        subtitle.stringValue = active.name
        subtitle.font = .systemFont(ofSize: font * 0.3)
        subtitle.isHidden = active.name.caseInsensitiveCompare(active.title) == .orderedSame
        cycle.setViews(layouts.map { HUD.pill($0.code, active: $0.id == active.id, fontSize: font * 0.3) }, in: .center)
    }

    private func fadeOut(_ shown: Int) {
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; panel.animator().alphaValue = 0 },
                                             completionHandler: { [weak self] in
            guard let self, self.generation == shown else { return }  // a newer switch is showing
            self.panel.orderOut(nil)
        })
    }

    private static func pill(_ text: String, active: Bool, fontSize: CGFloat) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: fontSize, weight: active ? .bold : .medium)
        label.textColor = active ? .white : .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.cornerRadius = fontSize * 0.55
        pill.layer?.backgroundColor = active ? NSColor.controlAccentColor.cgColor : nil
        pill.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: fontSize * 0.6),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -fontSize * 0.6),
            label.topAnchor.constraint(equalTo: pill.topAnchor, constant: fontSize * 0.15),
            label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -fontSize * 0.15),
        ])
        return pill
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
