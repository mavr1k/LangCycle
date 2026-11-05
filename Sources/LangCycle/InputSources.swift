import AppKit
import Carbon
import LangCycleCore

/// An enabled keyboard layout. Identity is always the input source ID (names can repeat).
struct Layout {
    let source: TISInputSource
    let id: String
    let name: String   // kTISPropertyLocalizedName, e.g. "Russian – PC"
    var title: String  // HUD headline: language name in that language, e.g. "Русский", or the user's override
    let code: String   // e.g. "РУ"
}

/// Thin wrapper over Text Input Sources. Call on the main thread only.
enum InputSources {
    private static var iconCache: [String: NSImage] = [:]

    private static func property<T>(_ source: TISInputSource, _ key: CFString) -> T? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue() as? T
    }

    /// Enabled, selectable keyboard layouts in system order (FR-2).
    static func enabled() -> [Layout] {
        let filter = [kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource as Any,
                      kTISPropertyInputSourceIsSelectCapable: true] as CFDictionary
        let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] ?? []
        return sources.map { source in
            let id: String = property(source, kTISPropertyInputSourceID) ?? "?"
            let name: String = property(source, kTISPropertyLocalizedName) ?? id
            let languages: [String] = property(source, kTISPropertyInputSourceLanguages) ?? []
            return Layout(source: source, id: id, name: name,
                          title: languages.first.flatMap(nativeName(language:)) ?? name,
                          code: shortCode(languages: languages, fallbackName: name))
        }
    }

    static func currentID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return property(source, kTISPropertyInputSourceID)
    }

    static func select(_ layout: Layout) {
        TISSelectInputSource(layout.source)
    }

    /// The layout's icon, if it has an image URL (input methods usually do; Apple's plain layouts don't —
    /// their IconRef is the same generic keyboard glyph for every layout, so it is not used).
    static func icon(for layout: Layout) -> NSImage? {
        if let cached = iconCache[layout.id] { return cached }
        let url: NSURL? = property(layout.source, kTISPropertyIconImageURL)
        let image = url.flatMap { NSImage(contentsOf: $0 as URL) }
        iconCache[layout.id] = image
        return image
    }
}
