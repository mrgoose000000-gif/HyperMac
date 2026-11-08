import Cocoa
import SwiftUI

// Hallmark · native app list · Theme fonts · pre-emit critique: P4 H4 E4 S5 R5 V4
struct MenuBarAppTable: NSViewRepresentable {
    @ObservedObject var manager: MenuBarHiderManager
    let items: [MenuBarDrawerItem]

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        let app = NSTableColumn(identifier: .init("app"))
        app.resizingMask = .autoresizingMask
        app.minWidth = 100
        table.addTableColumn(app)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.headerView = nil
        table.rowHeight = 44
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.allowsMultipleSelection = false
        table.allowsColumnReordering = false
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.action = #selector(Coordinator.clicked(_:))
        table.setAccessibilityLabel(tr("Ứng dụng Menu Bar", "Menu bar apps"))
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = table
        table.frame = scroll.bounds
        table.autoresizingMask = [.width]
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        (scroll.documentView as? NSTableView)?.reloadData()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: MenuBarAppTable
        init(_ parent: MenuBarAppTable) { self.parent = parent }
        func numberOfRows(in tableView: NSTableView) -> Int { parent.items.count }
        func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
            guard parent.items.indices.contains(row) else { return nil }
            let item = parent.items[row]
            let cell = NSTableCellView()
            let icon = NSImageView()
            icon.image = item.icon
            icon.imageScaling = .scaleProportionallyUpOrDown
            let text = NSTextField(labelWithString: item.name)
            text.font = .systemFont(ofSize: FS.body)
            text.lineBreakMode = .byTruncatingTail
            text.maximumNumberOfLines = 1
            for view in [icon, text] { view.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(view) }
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 24), icon.heightAnchor.constraint(equalToConstant: 24),
                text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            cell.imageView = icon
            cell.textField = text
            return cell
        }
        @objc func clicked(_ table: NSTableView) {
            guard parent.items.indices.contains(table.clickedRow) else { return }
            parent.manager.open(parent.items[table.clickedRow])
        }
    }
}

