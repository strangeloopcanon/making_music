import AppKit
import Foundation

final class TextComposerView: NSView {
    private let controller: KeystrokeMusicController
    private let performer: TextMusicPerformer

    private let modeSegmented = NSSegmentedControl(labels: ["Script", "Chords"], trackingMode: .selectOne, target: nil, action: nil)
    private let songbookPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let restartButton = NSButton(title: "Restart", target: nil, action: nil)
    private let inputPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let stylePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let chordStyleSegmented = NSSegmentedControl(labels: ["Stabs", "Two-hand"], trackingMode: .selectOne, target: nil, action: nil)
    private let chordAdvancePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let gridPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let tempoLabel = NSTextField(labelWithString: "")
    private let tempoStepper = NSStepper()
    private let legendLabel = NSTextField(labelWithString: "")
    private let chordStatusLabel = NSTextField(labelWithString: "")
    private let chordControlsRow = NSStackView()
    private let scrollView = NSScrollView()
    private let textView: MusicTextView

    private let starterChartText = "Em"
    private let starterScriptText = "trust i seek and i find in you"

    private var showsAdvancedControls: Bool = false {
        didSet { render() }
    }

    init(controller: KeystrokeMusicController, performer: TextMusicPerformer) {
        self.controller = controller
        self.performer = performer
        self.textView = MusicTextView()
        super.init(frame: .zero)
        setupUI()
        render()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func focus() {
        window?.makeFirstResponder(textView)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.textView)
        }
    }

    func setShowsAdvancedControls(_ shows: Bool) {
        showsAdvancedControls = shows
    }

    func stopPlayback() {
        performer.stopPlayback()
    }

    func render() {
        switch performer.mode {
        case .script:
            modeSegmented.selectedSegment = 0
        case .chords:
            modeSegmented.selectedSegment = 1
        }

        switch performer.mode {
        case .script:
            switch performer.scriptInputMode {
            case .sentence:
                legendLabel.stringValue =
                    "Script/Sentence: type normal words. 1 character = 1 Grid tick. Syntax: ',' rest, '-' hold, '.' resolve, '!' accent."
            case .linearV1:
                legendLabel.stringValue =
                    "Script/Linear v1: letters=melody, *=full chord, ^=arp up, v=arp down, /=next chord, 1..5=direct tones, '_'/'-' hold, ',' rest, '.' resolve, '!' accent."
            }
            chordStatusLabel.stringValue = performer.statusForDisplay
        case .chords:
            legendLabel.stringValue =
                "Chords: paste a chord chart like “Em D C G D/F#”. Use Songbook for starters. (Text can include '|' bar lines; unrecognized tokens are ignored.)"
            chordStatusLabel.stringValue = performer.statusForDisplay
        }

        songbookPopup.isHidden = false
        restartButton.isHidden = performer.mode != .script
        inputPopup.isHidden = performer.mode != .script
        stylePopup.isHidden = performer.mode != .script
        chordStyleSegmented.isHidden = !showsAdvancedControls || performer.mode != .script
        chordAdvancePopup.isHidden = !showsAdvancedControls || performer.mode != .script

        chordStatusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        chordStatusLabel.textColor = .secondaryLabelColor
        chordStatusLabel.isHidden = false

        chordControlsRow.isHidden = false

        switch performer.scriptInputMode {
        case .sentence:
            inputPopup.selectItem(at: 0)
        case .linearV1:
            inputPopup.selectItem(at: 1)
        }

        switch performer.scriptStyle {
        case .balladPick:
            stylePopup.selectItem(at: 0)
        case .rockStrum:
            stylePopup.selectItem(at: 1)
        case .powerChug:
            stylePopup.selectItem(at: 2)
        case .synthPulse:
            stylePopup.selectItem(at: 3)
        }

        switch performer.chordPlaybackStyle {
        case .stabs:
            chordStyleSegmented.selectedSegment = 0
        case .comp:
            chordStyleSegmented.selectedSegment = 1
        }

        switch performer.chordAdvanceMode {
        case .everyBar:
            chordAdvancePopup.selectItem(at: 0)
        case .onSpaces:
            chordAdvancePopup.selectItem(at: 1)
        }

        switch performer.timingGrid {
        case .off:
            gridPopup.selectItem(at: 0)
        case .eighths:
            gridPopup.selectItem(at: 1)
        case .sixteenths:
            gridPopup.selectItem(at: 2)
        case .triplets:
            gridPopup.selectItem(at: 3)
        }

        tempoLabel.stringValue = "BPM: \(controller.tempoBPM)"
        tempoStepper.integerValue = controller.tempoBPM

        textView.setHighlightedRange(performer.highlightedRange)

        performer.updatePlayback(shouldPlay: controller.isArmed && performer.mode == .script)
    }

    private func setupUI() {
        modeSegmented.target = self
        modeSegmented.action = #selector(modeChanged(_:))
        modeSegmented.selectedSegment = 0

        songbookPopup.target = self
        songbookPopup.action = #selector(songbookChanged(_:))
        songbookPopup.addItems(withTitles: [
            "Songbook…",
            "Nothing Else Matters (Intro pick: Em)",
            "Nothing Else Matters (Em D C G)",
            "Free Bird (G D/F# Em F C D)",
            "Sweet Child O' Mine (starter loop: D C G D)",
            "November Rain (starter loop: C G Am F)",
            "Baba O'Riley (F C Bb)",
            "Highway to Hell (riff: A D/F# G)",
            "With Arms Wide Open (C C/B Am …)",
            "Pop/Rock I–V–vi–IV (G D Em C)",
            "12-bar Blues (A7 D7 E7)",
            "Paste chords from Clipboard",
            "Clear",
        ])

        chordStyleSegmented.target = self
        chordStyleSegmented.action = #selector(chordStyleChanged(_:))
        chordStyleSegmented.selectedSegment = 1

        inputPopup.target = self
        inputPopup.action = #selector(scriptInputModeChanged(_:))
        inputPopup.addItems(withTitles: [
            "Input: \(TextMusicPerformer.ScriptInputMode.sentence.rawValue)",
            "Input: \(TextMusicPerformer.ScriptInputMode.linearV1.rawValue)",
        ])

        stylePopup.target = self
        stylePopup.action = #selector(styleChanged(_:))
        stylePopup.addItems(withTitles: [
            "Style: \(TextMusicPerformer.ScriptStyle.balladPick.rawValue)",
            "Style: \(TextMusicPerformer.ScriptStyle.rockStrum.rawValue)",
            "Style: \(TextMusicPerformer.ScriptStyle.powerChug.rawValue)",
            "Style: \(TextMusicPerformer.ScriptStyle.synthPulse.rawValue)",
        ])

        chordAdvancePopup.target = self
        chordAdvancePopup.action = #selector(chordAdvanceChanged(_:))
        chordAdvancePopup.addItems(withTitles: [
            "Chord: Every bar",
            "Chord: On spaces",
        ])

        gridPopup.target = self
        gridPopup.action = #selector(gridChanged(_:))
        gridPopup.addItems(withTitles: [
            "Grid: Off",
            "Grid: 8ths",
            "Grid: 16ths",
            "Grid: Triplets",
        ])

        tempoLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tempoLabel.textColor = .secondaryLabelColor

        tempoStepper.minValue = 40
        tempoStepper.maxValue = 240
        tempoStepper.increment = 1
        tempoStepper.target = self
        tempoStepper.action = #selector(tempoChanged(_:))

        legendLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        legendLabel.textColor = .secondaryLabelColor
        legendLabel.lineBreakMode = .byWordWrapping

        chordStatusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        chordStatusLabel.textColor = .secondaryLabelColor
        chordStatusLabel.lineBreakMode = .byWordWrapping

        restartButton.target = self
        restartButton.action = #selector(restartPressed(_:))

        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        textView.isEditable = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .controlBackgroundColor.withAlphaComponent(0.3)
        textView.drawsBackground = true
        textView.insertionPointColor = .controlAccentColor
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        if let font = textView.font {
            textView.typingAttributes = [
                .font: font,
                .foregroundColor: NSColor.labelColor,
            ]
        }
        textView.frame = NSRect(x: 0, y: 0, width: 520, height: 220)

        scrollView.documentView = textView

        if textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            performer.setChordChartText(starterChartText)
            performer.setScriptText(starterScriptText)
            textView.string = performer.scriptTextForDisplay
            textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange(_:)),
            name: NSText.didChangeNotification,
            object: textView
        )

        let topRow = NSStackView(views: [modeSegmented, songbookPopup, restartButton])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 8

        chordControlsRow.orientation = .horizontal
        chordControlsRow.alignment = .centerY
        chordControlsRow.spacing = 8
        chordControlsRow.addArrangedSubview(inputPopup)
        chordControlsRow.addArrangedSubview(stylePopup)
        chordControlsRow.addArrangedSubview(chordStyleSegmented)
        chordControlsRow.addArrangedSubview(chordAdvancePopup)
        chordControlsRow.addArrangedSubview(gridPopup)
        chordControlsRow.addArrangedSubview(tempoLabel)
        chordControlsRow.addArrangedSubview(tempoStepper)

        let stack = NSStackView(views: [topRow, legendLabel, chordStatusLabel, chordControlsRow, scrollView])
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

            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
            scrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 520),
        ])
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        _ = sender
        syncEditorTextToPerformer()
        switch modeSegmented.selectedSegment {
        case 0:
            performer.mode = .script
        case 1:
            performer.mode = .chords
        default:
            performer.mode = .script
        }
        syncPerformerTextToEditor()
        render()
    }

    @objc private func songbookChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard index > 0 else { return }
        defer { sender.selectItem(at: 0) }

        performer.timingGrid = .off

        let chart: String
        switch index {
        case 1:
            performer.scriptStyle = .balladPick
            performer.timingGrid = .triplets
            controller.setTempoBPM(76)
            chart = "Em"
        case 2:
            performer.scriptStyle = .balladPick
            chart = "Em D C G"
        case 3:
            performer.scriptStyle = .rockStrum
            chart = "G D/F# Em F C D"
        case 4:
            performer.scriptStyle = .rockStrum
            chart = "D C G D"
        case 5:
            performer.scriptStyle = .balladPick
            chart = "C G Am F"
        case 6:
            performer.scriptStyle = .synthPulse
            performer.timingGrid = .sixteenths
            controller.setTempoBPM(118)
            chart = "F C Bb"
        case 7:
            performer.scriptStyle = .powerChug
            performer.timingGrid = .eighths
            controller.setTempoBPM(116)
            chart = "A D/F# G D/F# G | E | A D G D"
        case 8:
            performer.scriptStyle = .balladPick
            performer.timingGrid = .eighths
            controller.setTempoBPM(92)
            chart = "C C/B Am | F C | E D | C C/B Am"
        case 9:
            performer.scriptStyle = .rockStrum
            chart = "G D Em C"
        case 10:
            performer.scriptStyle = .rockStrum
            chart = "A7 D7 A7 A7 D7 D7 A7 A7 E7 D7 A7 E7"
        case 11:
            let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
            let extracted = performer.chordChartFromText(clipboard)
            chart = extracted
            if extracted.isEmpty {
                controller.setAction("Clipboard: no chords found.")
            } else {
                controller.setAction("Pasted chords from clipboard.")
            }
        case 12:
            chart = ""
        default:
            chart = ""
        }

        performer.setChordChartText(chart)
        if performer.mode == .chords {
            textView.string = chart
            let end = (chart as NSString).length
            textView.setSelectedRange(NSRange(location: end, length: 0))
            textView.scrollRangeToVisible(NSRange(location: end, length: 0))
        }
        render()
        focus()
    }

    @objc private func styleChanged(_ sender: NSPopUpButton) {
        _ = sender
        switch stylePopup.indexOfSelectedItem {
        case 0:
            performer.scriptStyle = .balladPick
        case 1:
            performer.scriptStyle = .rockStrum
        case 2:
            performer.scriptStyle = .powerChug
        case 3:
            performer.scriptStyle = .synthPulse
        default:
            performer.scriptStyle = .balladPick
        }
        render()
        focus()
    }

    @objc private func scriptInputModeChanged(_ sender: NSPopUpButton) {
        _ = sender
        switch inputPopup.indexOfSelectedItem {
        case 0:
            performer.scriptInputMode = .sentence
        case 1:
            performer.scriptInputMode = .linearV1
        default:
            performer.scriptInputMode = .sentence
        }
        render()
        focus()
    }

    @objc private func chordStyleChanged(_ sender: NSSegmentedControl) {
        _ = sender
        switch chordStyleSegmented.selectedSegment {
        case 0:
            performer.chordPlaybackStyle = .stabs
        case 1:
            performer.chordPlaybackStyle = .comp
        default:
            break
        }
        render()
    }

    @objc private func chordAdvanceChanged(_ sender: NSPopUpButton) {
        _ = sender
        switch chordAdvancePopup.indexOfSelectedItem {
        case 0:
            performer.chordAdvanceMode = .everyBar
        case 1:
            performer.chordAdvanceMode = .onSpaces
        default:
            performer.chordAdvanceMode = .everyBar
        }
        render()
        focus()
    }

    @objc private func gridChanged(_ sender: NSPopUpButton) {
        _ = sender
        switch gridPopup.indexOfSelectedItem {
        case 0:
            performer.timingGrid = .off
        case 1:
            performer.timingGrid = .eighths
        case 2:
            performer.timingGrid = .sixteenths
        case 3:
            performer.timingGrid = .triplets
        default:
            performer.timingGrid = .off
        }
        render()
        focus()
    }

    @objc private func tempoChanged(_ sender: NSStepper) {
        _ = sender
        controller.setTempoBPM(tempoStepper.integerValue)
        render()
        focus()
    }

    @objc private func restartPressed(_ sender: NSButton) {
        _ = sender
        performer.restart()
        controller.setAction("Script: restart.")
        render()
        focus()
    }

    @objc private func textDidChange(_ notification: Notification) {
        _ = notification
        syncEditorTextToPerformer()
        render()
    }

    private func syncEditorTextToPerformer() {
        switch performer.mode {
        case .script:
            performer.setScriptText(textView.string)
        case .chords:
            performer.setChordChartText(textView.string)
        }
    }

    private func syncPerformerTextToEditor() {
        switch performer.mode {
        case .script:
            textView.string = performer.scriptTextForDisplay
        case .chords:
            textView.string = performer.chordChartTextForDisplay
        }
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
    }
}

private final class MusicTextView: NSTextView {
    private var highlightedRange: NSRange?

    init() {
        super.init(frame: .zero, textContainer: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setHighlightedRange(_ range: NSRange?) {
        guard highlightedRange != range else { return }

        if let oldRange = highlightedRange {
            layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: oldRange)
        }
        highlightedRange = range

        if let range {
            let color = NSColor.controlAccentColor.withAlphaComponent(0.22)
            layoutManager?.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range)
        }
    }
}
