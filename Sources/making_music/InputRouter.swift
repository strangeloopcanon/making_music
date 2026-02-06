import AppKit

@MainActor
final class InputRouter {
    private let controller: KeystrokeMusicController
    private weak var keyCaptureView: KeyCaptureView?

    init(controller: KeystrokeMusicController, keyCaptureView: KeyCaptureView) {
        self.controller = controller
        self.keyCaptureView = keyCaptureView
    }

    func routeKeyDown(_ event: NSEvent) -> Bool {
        guard let keyCaptureView else { return false }

        if keyCaptureView.isTextInputMode {
            if isArmToggleKey(event) || isPanicKey(event) {
                controller.handleKeyDown(event)
                return true
            }
            keyCaptureView.focusTextInput()
            return false
        }

        if shouldLetSystemHandleKeyEquivalent(event) {
            return false
        }

        controller.handleKeyDown(event)
        return true
    }

    func routeKeyUp(_ event: NSEvent) -> Bool {
        guard let keyCaptureView else { return false }

        if keyCaptureView.isTextInputMode {
            return false
        }

        controller.handleKeyUp(event)
        return true
    }

    private func isArmToggleKey(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains([.control, .option, .command]), event.keyCode == 46 { return true }
        if event.modifierFlags.contains(.command), event.keyCode == 36 { return true }
        return false
    }

    private func isPanicKey(_ event: NSEvent) -> Bool {
        event.keyCode == 53
    }

    private func shouldLetSystemHandleKeyEquivalent(_ event: NSEvent) -> Bool {
        let keyEquivalentModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard !event.modifierFlags.intersection(keyEquivalentModifiers).isEmpty else { return false }

        if isArmToggleKey(event) { return false }

        if isScaleHotkey(event) { return false }

        return true
    }

    private func isScaleHotkey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }
        guard let key = event.charactersIgnoringModifiers?.lowercased(), let digit = Int(key) else { return false }
        return digit >= 1 && digit <= 5
    }
}
