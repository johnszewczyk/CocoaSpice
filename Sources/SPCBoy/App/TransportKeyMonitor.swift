import AppKit
import SwiftUI

struct TransportKeyMonitor: NSViewRepresentable {
    @Bindable var model: PlayerViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.startMonitoring()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.model = model
        context.coordinator.startMonitoring()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    @MainActor
    final class Coordinator: NSObject {
        private static let mediaKeyEventSubtype = 8
        private static let mediaKeyDownState = 0xA
        private static let playKeyCode = 16
        private static let nextKeyCode = 17
        private static let previousKeyCode = 18

        @Bindable var model: PlayerViewModel
        private var localMonitor: Any?

        init(model: PlayerViewModel) {
            self._model = Bindable(model)
        }

        func startMonitoring() {
            if localMonitor == nil {
                localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.systemDefined]) { [weak self] event in
                    guard let self else { return event }
                    return self.handleMediaKeyEvent(event) ? nil : event
                }
            }
        }

        @discardableResult
        private func handleMediaKeyEvent(_ event: NSEvent) -> Bool {
            guard event.type == .systemDefined,
                  event.subtype.rawValue == Self.mediaKeyEventSubtype else {
                return false
            }

            let keyCode = (event.data1 & 0xFFFF0000) >> 16
            let keyFlags = event.data1 & 0x0000FFFF
            let keyState = (keyFlags & 0xFF00) >> 8
            guard keyState == Self.mediaKeyDownState else { return true }

            switch keyCode {
            case Self.previousKeyCode:
                model.handleMediaPreviousCommand()
            case Self.playKeyCode:
                model.handleMediaPlayPauseCommand()
            case Self.nextKeyCode:
                model.handleMediaNextCommand()
            default:
                return false
            }

            return true
        }

        func stopMonitoring() {
            if let localMonitor {
                NSEvent.removeMonitor(localMonitor)
            }
            localMonitor = nil
        }
    }
}
