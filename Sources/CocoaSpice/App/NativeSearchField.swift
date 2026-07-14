import AppKit
import SwiftUI

struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var debounceInterval: TimeInterval = 0.1

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField(frame: .zero)
        field.placeholderString = placeholder
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        context.coordinator.update(parent: self, field: nsView)
        nsView.placeholderString = placeholder
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NativeSearchField
        private var debounceWorkItem: DispatchWorkItem?

        init(_ parent: NativeSearchField) {
            self.parent = parent
        }

        func update(parent: NativeSearchField, field: NSSearchField) {
            self.parent = parent
            if field.stringValue != parent.text {
                debounceWorkItem?.cancel()
                debounceWorkItem = nil
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            let value = field.stringValue
            debounceWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.parent.text = value
            }
            debounceWorkItem = workItem
            if parent.debounceInterval <= 0 {
                workItem.perform()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + parent.debounceInterval, execute: workItem)
            }
        }
    }
}
