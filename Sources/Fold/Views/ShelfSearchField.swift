import SwiftUI

struct ShelfSearchField: NSViewRepresentable {
    @Binding var query: String
    let focusRequest: Int
    let submit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Search clips"
        field.setAccessibilityLabel("Search clips")
        field.focusRingType = .default
        field.delegate = context.coordinator
        field.controlSize = .large
        field.sendsSearchStringImmediately = true
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if field.stringValue != query { field.stringValue = query }
        guard coordinator.lastFocusRequest != focusRequest else { return }
        coordinator.lastFocusRequest = focusRequest
        DispatchQueue.main.async {
            guard let window = field.window else { return }
            window.makeFirstResponder(field)
            // Opening the field from a typed letter should append the next letter.
            field.currentEditor()?.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0)
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: ShelfSearchField
        var lastFocusRequest = 0
        init(_ parent: ShelfSearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSSearchField { parent.query = field.stringValue }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            guard command == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.submit()
            return true
        }
    }
}
