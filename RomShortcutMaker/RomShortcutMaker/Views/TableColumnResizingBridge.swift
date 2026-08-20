import AppKit
import SwiftUI

/// SwiftUI's `Table` does not consistently carry its column resizing policy
/// through to the backing `NSTableView`. Keep the public SwiftUI column widths
/// as the source of the constraints, and explicitly enable native drag resizing
/// for the library's content columns.
struct TableColumnResizingBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> ProbeView {
        ProbeView()
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.configureTableSoon()
    }

    final class ProbeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureTableSoon()
        }

        func configureTableSoon() {
            DispatchQueue.main.async { [weak self] in
                self?.configureTable()
            }
        }

        private func configureTable() {
            guard let contentView = window?.contentView,
                  let tableView = contentView.firstTableView(withHeaders: requiredHeaders) else {
                return
            }

            tableView.allowsColumnResizing = true

            for column in tableView.tableColumns {
                switch column.headerCell.stringValue {
                case "Game", "Platform", "Emulator":
                    column.resizingMask = [.userResizingMask, .autoresizingMask]
                default:
                    column.resizingMask = []
                }
            }
        }

        private let requiredHeaders: Set<String> = ["Game", "Platform", "Emulator"]
    }
}

private extension NSView {
    func firstTableView(withHeaders requiredHeaders: Set<String>) -> NSTableView? {
        if let tableView = self as? NSTableView {
            let headers = Set(tableView.tableColumns.map { $0.headerCell.stringValue })
            if requiredHeaders.isSubset(of: headers) {
                return tableView
            }
        }

        for subview in subviews {
            if let tableView = subview.firstTableView(withHeaders: requiredHeaders) {
                return tableView
            }
        }

        return nil
    }
}
