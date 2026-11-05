import AppKit
import Carbon

enum HotkeyPreset: Int, CaseIterable {
    case control, option, command

    var title: String { ["⌃Space", "⌥Space", "⌘Space"][rawValue] }
    var reverseTitle: String { ["⌃⇧Space", "⌥⇧Space", "⌘⇧Space"][rawValue] }
    fileprivate var carbonModifiers: UInt32 { UInt32([controlKey, optionKey, cmdKey][rawValue]) }
    /// Modifier mask as stored in com.apple.symbolichotkeys (NSEvent flag values).
    fileprivate var cocoaModifiers: Int { [1 << 18, 1 << 19, 1 << 20][rawValue] }
    fileprivate var modifierFlag: NSEvent.ModifierFlags { [.control, .option, .command][rawValue] }
}

/// Carbon global hotkeys (FR-7): no Accessibility permission needed, and the key is consumed.
/// Registers the preset (forward) and preset + ⇧ (backward).
final class Hotkey {
    var onPress: ((_ forward: Bool) -> Void)?
    private(set) var registrationFailed = false
    private var refs: [EventHotKeyRef] = []
    private var down = Set<UInt32>()
    private var preset = HotkeyPreset.control

    init() {
        let types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            Unmanaged<Hotkey>.fromOpaque(context).takeUnretainedValue().handle(id: hotKeyID.id, pressed: pressed)
            return noErr
        }, types.count, types, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    /// One physical press = one switch (FR-5): presses while the key is still held (auto-repeat) are ignored.
    private func handle(id: UInt32, pressed: Bool) {
        guard pressed else { down.remove(id); return }
        // Still down and Space physically held → auto-repeat. If Space is up, a release was missed: count it.
        if down.contains(id) && CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Space)) { return }
        down.insert(id)
        onPress?(id == 1)
    }

    /// True while any key of the combination that was just used is still down: its modifier (plus ⇧ for the
    /// reverse hotkey) or Space. The HUD stays visible as long as this is true. Needs no permission:
    /// modifiers come from `NSEvent.modifierFlags`, and Space counts only while Carbon has not reported its release.
    func isHeld(forward: Bool) -> Bool {
        let modifiers = forward ? preset.modifierFlag : preset.modifierFlag.union(.shift)
        let spaceDown = down.contains(forward ? 1 : 2)
            && CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Space))
        return spaceDown || !NSEvent.modifierFlags.isDisjoint(with: modifiers)
    }

    func register(_ preset: HotkeyPreset) {
        self.preset = preset
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        down = []
        registrationFailed = false
        for (id, extra) in [(UInt32(1), UInt32(0)), (UInt32(2), UInt32(shiftKey))] {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(kVK_Space), preset.carbonModifiers | extra,
                                             EventHotKeyID(signature: 0x4C_43_59_43 /* LCYC */, id: id),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs.append(ref) } else { registrationFailed = true }
        }
    }

    /// True if an enabled macOS shortcut uses our key combination (FR-9). Registration still succeeds in that
    /// case, but the system handles the key first and the app never sees it.
    static func systemConflict(_ preset: HotkeyPreset) -> Bool {
        let domain = "com.apple.symbolichotkeys" as CFString
        CFPreferencesAppSynchronize(domain)
        var hotkeys = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any] ?? [:]
        // Entries that were never changed are absent but active with their defaults:
        // 60 = "Select the previous input source" (⌃Space), 64 = Spotlight (⌘Space).
        for (key, mask) in [("60", 1 << 18), ("64", 1 << 20)] where hotkeys[key] == nil {
            hotkeys[key] = ["enabled": true, "value": ["parameters": [32, 49, mask]]]
        }
        let ours = [preset.cocoaModifiers, preset.cocoaModifiers | 1 << 17]
        return hotkeys.values.contains { entry in
            guard let entry = entry as? [String: Any], entry["enabled"] as? Bool == true,
                  let parameters = (entry["value"] as? [String: Any])?["parameters"] as? [Int],
                  parameters.count == 3 else { return false }
            return parameters[1] == kVK_Space && ours.contains(parameters[2])
        }
    }
}
