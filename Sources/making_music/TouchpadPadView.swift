import AppKit
import Foundation
import MakingMusicCore

final class TouchpadPadView: NSView {
    private let controller: KeystrokeMusicController
    private let titleLabel = NSTextField(labelWithString: "")
    private let padView: PadAreaView

    init(controller: KeystrokeMusicController) {
        self.controller = controller
        self.padView = PadAreaView(controller: controller)
        super.init(frame: .zero)
        setupUI()
        render()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func render() {
        titleLabel.stringValue = "Touchpad Pad (Keys mode): drag left/right = pitch, up/down = velocity. Release to stop."
        padView.isEnabled = controller.isArmed && !isHidden
    }

    private func setupUI() {
        titleLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byWordWrapping

        padView.translatesAutoresizingMaskIntoConstraints = false
        padView.heightAnchor.constraint(equalToConstant: 96).isActive = true
        padView.widthAnchor.constraint(greaterThanOrEqualToConstant: 520).isActive = true

        let stack = NSStackView(views: [titleLabel, padView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

private final class PadAreaView: NSView {
    private let controller: KeystrokeMusicController
    private let indicator = NSView()

    var isEnabled: Bool = false {
        didSet { updateEnabledState() }
    }

    private let rangeSemitones: Int = 24
    private var currentBaseNote: UInt8?

    init(controller: KeystrokeMusicController) {
        self.controller = controller
        super.init(frame: .zero)
        setupUI()
        updateEnabledState()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func mouseDown(with event: NSEvent) {
        handle(event)
    }

    override func mouseDragged(with event: NSEvent) {
        handle(event)
    }

    override func mouseUp(with event: NSEvent) {
        _ = event
        currentBaseNote = nil
        controller.touchpadNoteOff()
        updateIndicator(nil)
    }

    private func handle(_ event: NSEvent) {
        guard isEnabled else { return }

        let location = convert(event.locationInWindow, from: nil)
        let x = clamp(location.x / max(1, bounds.width))
        let y = clamp(location.y / max(1, bounds.height))

        guard let baseNote = baseNoteFor(normalizedX: x) else { return }

        let rawVelocity = Int((y * 110) + 16)
        var velocity = UInt8(max(16, min(127, rawVelocity)))
        if event.modifierFlags.contains(.shift) {
            velocity = UInt8(min(127, Int(velocity) + 20))
        }

        if currentBaseNote == nil {
            currentBaseNote = baseNote
            controller.touchpadNoteOn(baseNote: baseNote, velocity: velocity)
        } else if currentBaseNote != baseNote {
            currentBaseNote = baseNote
            controller.touchpadNoteUpdate(baseNote: baseNote, velocity: velocity)
        }

        updateIndicator(CGPoint(x: x, y: y))
    }

    private func baseNoteFor(normalizedX x: CGFloat) -> UInt8? {
        let root = controller.baseMidiRoot
        let desired = root + Int((Double(x) * Double(rangeSemitones)).rounded())
        let clampedDesired = max(0, min(127, desired))

        let midi: Int
        switch controller.mappingMode {
        case .chromatic:
            midi = clampedDesired
        case .musical:
            midi = quantizeToScale(desiredMidi: clampedDesired, rootMidi: root, scale: controller.currentScale) ?? clampedDesired
        }

        guard midi >= 0 && midi <= 127 else { return nil }
        return UInt8(midi)
    }

    private func quantizeToScale(desiredMidi: Int, rootMidi: Int, scale: Scale) -> Int? {
        let maxMidi = min(127, rootMidi + rangeSemitones)
        let minMidi = max(0, rootMidi)
        let offsets = scale.semitoneOffsets
        guard !offsets.isEmpty else { return desiredMidi }

        var allowed: [Int] = []
        let octaves = (rangeSemitones / 12) + 2
        allowed.reserveCapacity(offsets.count * octaves)

        for octave in 0..<octaves {
            let base = rootMidi + octave * 12
            for offset in offsets {
                let note = base + offset
                if note >= minMidi, note <= maxMidi {
                    allowed.append(note)
                }
            }
        }

        allowed = Array(Set(allowed)).sorted()
        guard !allowed.isEmpty else { return nil }

        var best = allowed[0]
        var bestDist = abs(best - desiredMidi)
        for note in allowed.dropFirst() {
            let dist = abs(note - desiredMidi)
            if dist < bestDist || (dist == bestDist && note < best) {
                best = note
                bestDist = dist
            }
        }
        return best
    }

    private func updateIndicator(_ normalized: CGPoint?) {
        guard let normalized else {
            indicator.isHidden = true
            return
        }

        indicator.isHidden = false
        let x = normalized.x * bounds.width
        let y = normalized.y * bounds.height
        indicator.frame = NSRect(x: x - 6, y: y - 6, width: 12, height: 12)
    }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.25).cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor

        indicator.wantsLayer = true
        indicator.layer?.cornerRadius = 6
        indicator.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
        indicator.isHidden = true

        addSubview(indicator)
    }

    private func updateEnabledState() {
        alphaValue = isEnabled ? 1.0 : 0.55
        if !isEnabled {
            currentBaseNote = nil
            controller.touchpadNoteOff()
            updateIndicator(nil)
        }
    }

    private func clamp(_ v: CGFloat) -> CGFloat {
        max(0, min(1, v))
    }
}
