import AppKit
import Foundation
import MakingMusicCore

final class KeyboardMapView: NSView {
    private let controller: KeystrokeMusicController
    private var capsByKey: [String: KeyCapView] = [:]

    init(controller: KeystrokeMusicController) {
        self.controller = controller
        super.init(frame: .zero)
        setupUI()
        render()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func render() {
        let held = controller.heldKeys

        for (key, cap) in capsByKey {
            if let display = controller.display(forKey: key) {
                cap.update(noteName: display.noteName, chordLabel: display.chordLabel, isHeld: held.contains(key))
            } else {
                cap.update(noteName: "—", chordLabel: nil, isHeld: false)
            }
        }
    }

    private func setupUI() {
        let keyLayoutRows = KeyLayout.qwertyRows.rows
        // KeyLayout rows are ordered Bottom -> Top (z, a, q, 1).
        // We want to display Top -> Bottom (1, q, a, z).
        
        let rowIndents: [Int: CGFloat] = [
            3: 0,  // 1 row
            2: 18, // q row
            1: 36, // a row
            0: 54  // z row
        ]

        let outer = NSStackView()
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 8
        outer.translatesAutoresizingMaskIntoConstraints = false

        for (rowIndex, keys) in keyLayoutRows.enumerated().reversed() {
            let rowStack = NSStackView()
            rowStack.orientation = .horizontal
            rowStack.alignment = .centerY
            rowStack.spacing = 6

            let indent = rowIndents[rowIndex] ?? 0
            if indent > 0 {
                let spacer = NSView()
                spacer.translatesAutoresizingMaskIntoConstraints = false
                spacer.widthAnchor.constraint(equalToConstant: indent).isActive = true
                rowStack.addArrangedSubview(spacer)
            }

            for key in keys {
                let cap = KeyCapView(key: key)
                capsByKey[key] = cap
                rowStack.addArrangedSubview(cap)
            }

            outer.addArrangedSubview(rowStack)
        }

        addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: leadingAnchor),
            outer.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            outer.topAnchor.constraint(equalTo: topAnchor),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

private final class KeyCapView: NSView {
    private let key: String

    private let keyLabel = NSTextField(labelWithString: "")
    private let noteLabel = NSTextField(labelWithString: "")
    private let chordLabel = NSTextField(labelWithString: "")

    init(key: String) {
        self.key = key
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 56).isActive = true
        heightAnchor.constraint(equalToConstant: 46).isActive = true
        setupUI()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(noteName: String, chordLabel: String?, isHeld: Bool) {
        noteLabel.stringValue = noteName
        self.chordLabel.stringValue = chordLabel ?? ""

        if isHeld {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
            layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor
        } else {
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55).cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1

        keyLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        keyLabel.textColor = .secondaryLabelColor
        keyLabel.stringValue = key.uppercased()

        noteLabel.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        noteLabel.textColor = .labelColor

        chordLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        chordLabel.textColor = .secondaryLabelColor

        let labels = NSStackView(views: [noteLabel, chordLabel])
        labels.orientation = .vertical
        labels.alignment = .centerX
        labels.spacing = 2
        labels.translatesAutoresizingMaskIntoConstraints = false

        addSubview(keyLabel)
        addSubview(labels)

        keyLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            keyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            keyLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),

            labels.centerXAnchor.constraint(equalTo: centerXAnchor),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 2),
        ])

        update(noteName: "—", chordLabel: nil, isHeld: false)
    }
}

