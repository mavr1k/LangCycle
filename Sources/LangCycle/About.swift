import AppKit

/// Text of the About window. Edit `bio` (and `author`, `links`) to change what people see.
/// The name and the version come from Resources/Info.plist, and the "MIT License" line from its NSHumanReadableCopyright.
enum About {
    static let author = "mavr1k"
    /// One or two sentences about you. Leave empty to show only the name and the links.
    static let bio = ""
    static let links: [(title: String, url: String)] = [
        ("GitHub", "https://github.com/mavr1k"),
        ("LinkedIn", "https://www.linkedin.com/in/mavrosaus/"),
        ("Email", "mailto:hard359@gmail.com"),
    ]

    /// Opens the standard About window. The caller must activate the app first, since it is an agent app.
    static func show() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
        ]

        let credits = NSMutableAttributedString(string: "Made by \(author)", attributes: base)
        if !bio.isEmpty { credits.append(NSAttributedString(string: "\n\n\(bio)", attributes: base)) }
        credits.append(NSAttributedString(string: "\n\n", attributes: base))
        for (index, link) in links.enumerated() {
            if index > 0 { credits.append(NSAttributedString(string: "  ·  ", attributes: base)) }
            var attributes = base
            attributes[.link] = URL(string: link.url)
            credits.append(NSAttributedString(string: link.title, attributes: attributes))
        }
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
