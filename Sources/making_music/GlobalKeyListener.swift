import AppKit
import Foundation

final class GlobalKeyListener {
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?

    var isEnabled: Bool {
        keyDownMonitor != nil || keyUpMonitor != nil
    }

    func start() {
        guard keyDownMonitor == nil, keyUpMonitor == nil else { return }

        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let charactersIgnoringModifiers = event.charactersIgnoringModifiers
            let modifierFlags = event.modifierFlags
            let isRepeat = event.isARepeat
            let timestamp = event.timestamp

            Task { @MainActor in
                AppRuntime.controller?.handleKeyDown(
                    keyCode: keyCode,
                    charactersIgnoringModifiers: charactersIgnoringModifiers,
                    modifierFlags: modifierFlags,
                    isRepeat: isRepeat,
                    timestamp: timestamp
                )
            }
        }

        keyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { event in
            let keyCode = event.keyCode
            let charactersIgnoringModifiers = event.charactersIgnoringModifiers
            let modifierFlags = event.modifierFlags
            let timestamp = event.timestamp

            Task { @MainActor in
                AppRuntime.controller?.handleKeyUp(
                    keyCode: keyCode,
                    charactersIgnoringModifiers: charactersIgnoringModifiers,
                    modifierFlags: modifierFlags,
                    timestamp: timestamp
                )
            }
        }
    }

    func stop() {
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
        if let monitor = keyUpMonitor {
            NSEvent.removeMonitor(monitor)
            keyUpMonitor = nil
        }
    }

    deinit {
        stop()
    }
}
