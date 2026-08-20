import AppKit
import SwiftUI

struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var debounceInterval: TimeInterval = 0.1
    var initialDebounceInterval: TimeInterval = 0.25

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
            private var lastCommittedText: String
            private var pendingText: String?

            init(_ parent: NativeSearchField) {
                self.parent = parent
                lastCommittedText = parent.text
            }

        func update(parent: NativeSearchField, field: NSSearchField) {
            self.parent = parent
            if parent.text == pendingText {
                debounceWorkItem?.cancel()
                debounceWorkItem = nil
                pendingText = nil
                lastCommittedText = parent.text
                return
            }

            // SwiftUI may update this representable for playback progress,
            // playback progress or other unrelated state while a fast typist's input
            // is still inside the debounce window. In that case the binding
            // intentionally contains the previous committed query; never
            // overwrite AppKit's live editor with that stale value.
            guard parent.text != lastCommittedText else { return }
            debounceWorkItem?.cancel()
            debounceWorkItem = nil
            pendingText = nil
            lastCommittedText = parent.text
            if field.stringValue != parent.text {
                field.stringValue = parent.text
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            let value = field.stringValue
            let priorInput = pendingText ?? lastCommittedText
            let startsNewQuery = priorInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            debounceWorkItem?.cancel()
            pendingText = value
            let workItem = DispatchWorkItem { [weak self] in
                self?.parent.text = value
            }
            debounceWorkItem = workItem
            let interval = startsNewQuery ? parent.initialDebounceInterval : parent.debounceInterval
            if interval <= 0 {
                workItem.perform()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: workItem)
            }
        }
    }
}
