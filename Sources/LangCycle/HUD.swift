import AppKit
import LangCycleCore

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
    private var generation = 0
    /// While the HUD is visible: checks whether the hotkey's keys are still down, and hides it 1 s after they are not.
    private var tracker = HoldTracker(delay: 1)
    private var isHeld: () -> Bool = { false }
    private var poller: Timer?

    init() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false  // the app is never active
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.level = .statusBar
        panel.collectionBehavior = HUD.spaceBehavior

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

    /// Shows `active` (with the whole cycle underneath). The HUD stays while `isHeld()` is true, i.e. while the user
    /// holds a key of the hotkey, and fades out 1 s after the last one is released.
    func show(_ active: Layout, in layouts: [Layout], size: HUDSize, isHeld: @escaping () -> Bool) {
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
        bringToActiveSpace()

        self.isHeld = isHeld
        tracker.reset()
        if poller == nil {
            // .common so it also runs while a menu is open. Only exists while the HUD is visible: idle CPU stays 0.
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.poll() }
            RunLoop.main.add(timer, forMode: .common)
            poller = timer
        }
    }

    /// Puts the panel on the Desktop (Space) that is showing now. A reused window with `.canJoinAllSpaces` is sometimes
    /// left off a Space the system did not attach it to, and then a plain `orderFront` shows nothing there. So the
    /// window is checked, and if it is not on this Space it is taken off screen and ordered in again, which makes
    /// the window server place it afresh. Never makeKey / activate.
    private func bringToActiveSpace() {
        if panel.isVisible && !panel.isOnActiveSpace { panel.orderOut(nil) }
        panel.collectionBehavior = HUD.spaceBehavior
        panel.orderFrontRegardless()
        // isOnActiveSpace is only reliable once the window server has handled the order-in, so look again shortly after.
        let shown = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.generation == shown, self.panel.isVisible, !self.panel.isOnActiveSpace else { return }
            self.panel.orderOut(nil)
            self.panel.orderFrontRegardless()
        }
    }

    private static let spaceBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

    private func poll() {
        guard tracker.update(held: isHeld(), now: ProcessInfo.processInfo.systemUptime) else { return }
        poller?.invalidate()
        poller = nil
        fadeOut(generation)
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
