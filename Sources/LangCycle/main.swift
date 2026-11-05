import AppKit
import Carbon
import LangCycleCore
import ServiceManagement

/// Settings live in UserDefaults.standard, which is the `com.local.langcycle` domain (the bundle id) — FR-22.
private enum Key {
    static let preset = "hotkeyPreset", hudSize = "hudSize", showHUD = "showHUD"
    static let skipped = "skippedIDs", didShowHelp = "didShowHelp"
    static let nameOverrides = "nameOverrides"  // [layout ID: custom HUD headline]
}

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let defaults = UserDefaults.standard
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let hotkey = Hotkey()
    private let hud = HUD()
    private var lastSelected: String?
    private var lastSelectedTime: TimeInterval?

    private var preset: HotkeyPreset { HotkeyPreset(rawValue: defaults.integer(forKey: Key.preset)) ?? .control }
    private var hudSize: HUDSize { HUDSize(rawValue: defaults.integer(forKey: Key.hudSize)) ?? .medium }
    private var skipped: Set<String> { Set(defaults.stringArray(forKey: Key.skipped) ?? []) }
    private var nameOverrides: [String: String] { defaults.dictionary(forKey: Key.nameOverrides) as? [String: String] ?? [:] }

    /// Applies the user's HUD label overrides, keyed by input source ID.
    private func labeled(_ layouts: [Layout]) -> [Layout] {
        let overrides = nameOverrides
        return layouts.map { layout in
            var layout = layout
            if let custom = overrides[layout.id] { layout.title = custom }
            return layout
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: [Key.preset: HotkeyPreset.control.rawValue, Key.hudSize: HUDSize.medium.rawValue,
                                     Key.showHUD: true])
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        hotkey.onPress = { [weak self] forward in self?.cycle(forward: forward) }
        hotkey.register(preset)

        // .deliverImmediately: an agent app is almost never active, and inactive apps get notifications late.
        let center = DistributedNotificationCenter.default()
        for name in [kTISNotifySelectedKeyboardInputSourceChanged, kTISNotifyEnabledKeyboardInputSourcesChanged] {
            center.addObserver(self, selector: #selector(updateStatusItem), name: Notification.Name(name! as String),
                               object: nil, suspensionBehavior: .deliverImmediately)
        }
        updateStatusItem()

        if !defaults.bool(forKey: Key.didShowHelp) {
            defaults.set(true, forKey: Key.didShowHelp)
            DispatchQueue.main.async { self.showHelp() }
        }
    }

    // MARK: Switching

    private func cycle(forward: Bool) {
        let enabled = labeled(InputSources.enabled())  // re-read on every press: added/removed layouts apply at once
        let cycleLayouts = enabled.filter { !skipped.contains($0.id) }
        let layouts = cycleLayouts.isEmpty ? enabled : cycleLayouts
        let current = InputSources.currentID()
        let now = ProcessInfo.processInfo.systemUptime  // monotonic
        guard let target = nextLayout(in: layouts.map(\.id), lastSelected: lastSelected, lastSelectedTime: lastSelectedTime,
                                      current: current, now: now, direction: forward ? .forward : .backward),
              let layout = layouts.first(where: { $0.id == target }) else { return }
        if target != current { InputSources.select(layout) }
        lastSelected = target
        lastSelectedTime = now
        statusItem.button?.title = layout.code
        if defaults.bool(forKey: Key.showHUD) {
            hud.show(layout, in: layouts, size: hudSize) { [weak self] in self?.hotkey.isHeld(forward: forward) ?? false }
        }
    }

    /// Keeps the menu bar code right however the layout was changed (FR-18).
    @objc private func updateStatusItem() {
        let current = InputSources.currentID()
        statusItem.button?.title = InputSources.enabled().first { $0.id == current }?.code ?? "⌨︎"
    }

    // MARK: Menu (rebuilt every time it opens, so it is always current)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let layouts = InputSources.enabled()
        let current = InputSources.currentID()
        for layout in layouts {
            add(to: menu, "\(layout.name)  (\(layout.code))", #selector(selectLayout(_:)), on: layout.id == current,
                object: layout.id)
        }
        menu.addItem(.separator())
        if hotkey.registrationFailed || Hotkey.systemConflict(preset) {
            add(to: menu, "⚠︎ Shortcut unavailable — disable the system one", #selector(showHelp))
        }
        let hotkeys = submenu(of: menu, "Hotkey")
        for option in HotkeyPreset.allCases {
            add(to: hotkeys, "\(option.title)  (reverse: \(option.reverseTitle))", #selector(setPreset(_:)),
                on: option == preset, tag: option.rawValue)
        }
        let sizes = submenu(of: menu, "HUD Size")
        for size in HUDSize.allCases {
            add(to: sizes, size.title, #selector(setHUDSize(_:)), on: size == hudSize, tag: size.rawValue)
        }
        add(to: menu, "Show HUD", #selector(toggleHUD), on: defaults.bool(forKey: Key.showHUD))
        let skip = submenu(of: menu, "Skip Layouts")
        for layout in layouts {
            add(to: skip, layout.name, #selector(toggleSkip(_:)), on: skipped.contains(layout.id), object: layout.id)
        }
        let labels = submenu(of: menu, "HUD Labels")  // a checkmark marks a renamed layout
        let overrides = nameOverrides
        for layout in labeled(layouts) {
            add(to: labels, "\(layout.title)  (\(layout.name))…", #selector(renameLayout(_:)),
                on: overrides[layout.id] != nil, object: layout.id)
        }
        add(to: menu, "Launch at Login", #selector(toggleLaunchAtLogin), on: SMAppService.mainApp.status == .enabled)
        menu.addItem(.separator())
        add(to: menu, "Setup Help…", #selector(showHelp))
        add(to: menu, "About LangCycle", #selector(showAbout))
        menu.addItem(withTitle: "Quit LangCycle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            .target = NSApp
    }

    @discardableResult
    private func add(to menu: NSMenu, _ title: String, _ action: Selector, on: Bool = false, tag: Int = 0,
                     object: Any? = nil) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        item.tag = tag
        item.representedObject = object
        return item
    }

    private func submenu(of menu: NSMenu, _ title: String) -> NSMenu {
        let submenu = NSMenu()
        menu.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = submenu
        return submenu
    }

    @objc private func selectLayout(_ item: NSMenuItem) {
        guard let layout = InputSources.enabled().first(where: { $0.id == item.representedObject as? String }) else { return }
        InputSources.select(layout)
        lastSelected = layout.id
        lastSelectedTime = ProcessInfo.processInfo.systemUptime
    }

    @objc private func setPreset(_ item: NSMenuItem) {
        defaults.set(item.tag, forKey: Key.preset)
        hotkey.register(preset)
    }

    @objc private func setHUDSize(_ item: NSMenuItem) { defaults.set(item.tag, forKey: Key.hudSize) }

    @objc private func toggleHUD() { defaults.set(!defaults.bool(forKey: Key.showHUD), forKey: Key.showHUD) }

    @objc private func toggleSkip(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        var ids = skipped
        if ids.remove(id) == nil { ids.insert(id) }
        defaults.set(Array(ids), forKey: Key.skipped)
    }

    /// Asks for a custom HUD headline for one layout. Empty text or "Reset to Default" brings back the automatic name.
    @objc private func renameLayout(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String,
              let layout = InputSources.enabled().first(where: { $0.id == id }) else { return }
        let field = NSTextField(string: nameOverrides[id] ?? layout.title)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        activate()  // the app is never active otherwise, and the text field would not get keyboard focus
        let alert = NSAlert()
        alert.messageText = "HUD label for \(layout.name)"
        alert.informativeText = "Shown as the big name in the HUD. The default is “\(layout.title)”."
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Reset to Default")
        alert.addButton(withTitle: "Cancel")

        var custom: String?
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let text = String(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
            custom = text.isEmpty || text == layout.title ? nil : text
        case .alertSecondButtonReturn:
            custom = nil
        default:
            return
        }
        var overrides = nameOverrides
        overrides[id] = custom
        defaults.set(overrides, forKey: Key.nameOverrides)
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            activate()
            NSAlert(error: error).runModal()
        }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    // MARK: Help (FR-10)

    @objc private func showHelp() {
        activate()  // the only time the app takes focus: the user asked for this window
        let alert = NSAlert()
        alert.messageText = "Turn off the macOS input source shortcuts"
        alert.informativeText = """
            macOS handles \(preset.title) itself unless its own shortcut is off, and then LangCycle never sees it.

            Open System Settings → Keyboard → Keyboard Shortcuts… → Input Sources and untick:
              • Select the previous input source
              • Select next source in Input menu
            If Spotlight uses the same keys, untick it under Spotlight too.

            \(preset.title) selects the next layout, \(preset.reverseTitle) the previous one. \
            You can pick another hotkey in the menu bar menu.
            """
        alert.addButton(withTitle: "Open Keyboard Settings")
        alert.addButton(withTitle: "Close")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showAbout() {
        activate()  // otherwise the About window opens behind the frontmost app
        About.show()
    }

    private func activate() {
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
    }
}

// Single instance (FR-21): a second launch quits immediately.
if let bundleID = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
       .contains(where: { $0.processIdentifier != getpid() }) {
    exit(0)
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
