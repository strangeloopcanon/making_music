import AppKit

final class KeyRoutingWindow: NSWindow {
    var inputRouter: InputRouter?

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            if inputRouter?.routeKeyDown(event) == true { return }
        case .keyUp:
            if inputRouter?.routeKeyUp(event) == true { return }
        default:
            break
        }

        super.sendEvent(event)
    }
}

