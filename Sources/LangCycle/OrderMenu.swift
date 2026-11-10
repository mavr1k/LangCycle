import AppKit
import LangCycleCore

/// The rows of the "Layout Order" submenu (FR-28). Each row is a view with ▲ ▼ buttons: a click on a view inside a
/// menu item doesn't close the menu, so the user can keep reordering. Rows stay where they are and show different
/// layouts after a move.
final class LayoutOrderRows: NSObject {
    private var layouts: [Layout]
    private var rows: [Row] = []
    private let onChange: ([String]) -> Void

    /// `onChange` receives the new order of all given layouts' IDs after every move.
    init(layouts: [Layout], onChange: @escaping ([String]) -> Void) {
        self.layouts = layouts
        self.onChange = onChange
        super.init()
        rows = layouts.indices.map { index in
            let row = Row(index: index)
            row.up.target = self
            row.up.action = #selector(moveUp(_:))
            row.down.target = self
            row.down.action = #selector(moveDown(_:))
            return row
        }
        refresh()
    }

    func menuItems() -> [NSMenuItem] {
        rows.map { row in
            let item = NSMenuItem()
            item.view = row
            return item
        }
    }

    @objc private func moveUp(_ sender: NSButton) { move(sender, by: movingUp) }

    @objc private func moveDown(_ sender: NSButton) { move(sender, by: movingDown) }

    private func move(_ sender: NSButton, by move: (String, [String]) -> [String]) {
        guard layouts.indices.contains(sender.tag) else { return }
        let ids = move(layouts[sender.tag].id, layouts.map(\.id))
        let byID = Dictionary(layouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        layouts = ids.compactMap { byID[$0] }
        onChange(ids)
        refresh()
    }

    private func refresh() {
        for (row, layout) in zip(rows, layouts) { row.label.stringValue = "\(layout.name)  (\(layout.code))" }
    }

    private final class Row: NSView {
        let label = NSTextField(labelWithString: "")
        let up = Row.arrow("chevron.up", fallback: "▲", tooltip: "Move up")
        let down = Row.arrow("chevron.down", fallback: "▼", tooltip: "Move down")

        init(index: Int) {
            super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
            up.tag = index
            down.tag = index
            label.font = .menuFont(ofSize: 0)
            label.lineBreakMode = .byTruncatingTail
            label.frame = NSRect(x: 14, y: 3, width: 190, height: 18)
            down.frame = NSRect(x: 246, y: 2, width: 24, height: 20)
            up.frame = NSRect(x: 218, y: 2, width: 24, height: 20)
            [label, up, down].forEach(addSubview)
        }

        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

        private static func arrow(_ symbol: String, fallback: String, tooltip: String) -> NSButton {
            let button = NSButton()
            button.isBordered = false
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) {
                button.image = image
            } else {
                button.title = fallback
            }
            button.toolTip = tooltip
            button.setAccessibilityLabel(tooltip)
            return button
        }
    }
}
