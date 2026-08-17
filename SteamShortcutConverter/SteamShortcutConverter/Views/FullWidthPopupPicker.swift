import AppKit
import SwiftUI

/// A native macOS popup button whose bezel fills the width proposed by SwiftUI.
/// SwiftUI's menu-style Picker keeps an intrinsic-width bezel even when its
/// outer layout frame expands, which produces different widths in table rows.
struct FullWidthPopupPicker<Value: Hashable>: NSViewRepresentable {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    let accessibilityLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.lineBreakMode = .byTruncatingTail
        popup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        popup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.didSelect(_:))
        return popup
    }

    func updateNSView(_ popup: NSPopUpButton, context: Context) {
        context.coordinator.parent = self

        let titles = options.map(title)
        if context.coordinator.options != options || context.coordinator.titles != titles {
            popup.removeAllItems()
            popup.addItems(withTitles: titles)
            context.coordinator.options = options
            context.coordinator.titles = titles
        }

        if let selectedIndex = options.firstIndex(of: selection),
           popup.indexOfSelectedItem != selectedIndex {
            popup.selectItem(at: selectedIndex)
        }

        popup.setAccessibilityLabel(accessibilityLabel)
    }

    final class Coordinator: NSObject {
        var parent: FullWidthPopupPicker
        var options: [Value] = []
        var titles: [String] = []

        init(parent: FullWidthPopupPicker) {
            self.parent = parent
        }

        @objc func didSelect(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            guard options.indices.contains(index) else { return }
            parent.selection = options[index]
        }
    }
}
