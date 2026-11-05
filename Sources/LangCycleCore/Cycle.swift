import Foundation

public enum Direction { case forward, backward }

/// Picks the layout to switch to (FR-4). Pure, so it can be unit tested.
///
/// The starting point is the layout this app selected last, if that happened within `window` seconds:
/// right after `TISSelectInputSource` the system may still report the old layout, so fast repeated presses
/// must not trust `current`. Otherwise it is the real `current` layout, which also covers changes made by
/// other means (menu, mouse, another shortcut). The result never depends on modifier state or history.
public func nextLayout(in layouts: [String], lastSelected: String?, lastSelectedTime: TimeInterval?,
                       current: String?, now: TimeInterval, direction: Direction,
                       window: TimeInterval = 0.8) -> String? {
    guard !layouts.isEmpty else { return nil }
    var base = current
    if let last = lastSelected, let time = lastSelectedTime, now >= time, now - time <= window, layouts.contains(last) {
        base = last
    }
    guard let base, let index = layouts.firstIndex(of: base) else {
        // Current layout is not in the cycle (skipped, or a non-keyboard input method).
        return direction == .forward ? layouts.first : layouts.last
    }
    let step = direction == .forward ? 1 : layouts.count - 1
    return layouts[(index + step) % layouts.count]
}

/// Cyrillic-script languages are shown in their own script.
private let nativeCodes = ["uk": "УК", "ru": "РУ", "be": "БЕ", "bg": "БГ", "sr": "СР", "mk": "МК"]

/// Short code for the menu bar and HUD: the first language, 2 letters, uppercased (`EN`, `DE`, `УК`).
public func shortCode(languages: [String], fallbackName: String) -> String {
    guard let tag = languages.first, !tag.isEmpty else { return String(fallbackName.prefix(2)).uppercased() }
    let language = String(tag.prefix { $0 != "-" && $0 != "_" }).lowercased()
    if !tag.contains("Latn"), let native = nativeCodes[language] { return native }
    return String(language.prefix(2)).uppercased()
}

/// The language's name in that language ("Українська", "English", "Deutsch"), or nil if unknown.
public func nativeName(language: String) -> String? {
    let locale = Locale(identifier: language)
    guard let name = locale.localizedString(forLanguageCode: language), !name.isEmpty else { return nil }
    return name.prefix(1).uppercased(with: locale) + name.dropFirst()
}
