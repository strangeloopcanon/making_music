import AppKit
import Foundation
import UniformTypeIdentifiers
import MakingMusicCore

final class KeyCaptureView: NSView {
    private let controller: KeystrokeMusicController
    private let textPerformer: TextMusicPerformer

    private enum InputMode: Int {
        case keys = 0
        case text = 1
    }

    private enum UIMode: Int {
        case simple = 0
        case advanced = 1
    }

    private enum Preset: Int {
        case prettyPiano = 1
        case rockGuitar = 2
        case guitarChug = 3
        case chordChartPiano = 4
        case chordChartGuitar = 5
    }

    private enum PracticeSong: Int, CaseIterable {
        case nothingElseMatters
        case freeBird
        case sweetChildOMine
        case novemberRain
        case babaORiley
        case highwayToHell
        case withArmsWideOpen

        var title: String {
            switch self {
            case .nothingElseMatters: return "Nothing Else Matters"
            case .freeBird: return "Free Bird"
            case .sweetChildOMine: return "Sweet Child O' Mine"
            case .novemberRain: return "November Rain"
            case .babaORiley: return "Baba O'Riley"
            case .highwayToHell: return "Highway to Hell"
            case .withArmsWideOpen: return "With Arms Wide Open"
            }
        }

        var recommendedPreset: Preset {
            switch self {
            case .nothingElseMatters: return .rockGuitar
            case .freeBird: return .rockGuitar
            case .sweetChildOMine: return .rockGuitar
            case .novemberRain: return .rockGuitar
            case .babaORiley: return .rockGuitar
            case .highwayToHell: return .guitarChug
            case .withArmsWideOpen: return .rockGuitar
            }
        }
    }

    private struct PracticeSection {
        var title: String
        var chart: String
    }

    private struct PracticePlan {
        var title: String
        var sections: [PracticeSection]
        var showPowerChordTip: Bool
        var recommendedPreset: Preset
    }

    private var inputMode: InputMode = .text
    private var uiMode: UIMode = .simple
    private var practicePlan: PracticePlan?
    private var renderScheduled = false

    // MARK: - Controls

    // Toolbar
    private let inputModeSegmented = NSSegmentedControl(labels: ["Keys", "Text"], trackingMode: .selectOne, target: nil, action: nil)
    private let uiModeSegmented = NSSegmentedControl(labels: ["Simple", "Advanced"], trackingMode: .selectOne, target: nil, action: nil)
    private let presetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let practicePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let armButton = NSButton(checkboxWithTitle: "Play", target: nil, action: nil)
    private let instrumentPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let soundLabel = NSTextField(labelWithString: "")
    private let soundFontButton = NSButton(title: "SoundFont…", target: nil, action: nil)
    private let builtInSoundButton = NSButton(title: "Built-in", target: nil, action: nil)
    
    // Performance
    private let playStyleSegmented = NSSegmentedControl(labels: ["Hold", "Chug 8ths", "Chug 16ths"], trackingMode: .selectOne, target: nil, action: nil)
    private let bpmLabel = NSTextField(labelWithString: "BPM: 140")
    private let bpmStepper = NSStepper()
    private let strumButton = NSButton(checkboxWithTitle: "Strum", target: nil, action: nil)

    // Mapping
    private let modeSegmented = NSSegmentedControl(labels: ["Scale Lock", "All Notes"], trackingMode: .selectOne, target: nil, action: nil)
    private let scalePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let powerChordButton = NSButton(checkboxWithTitle: "Power chords", target: nil, action: nil)

    // Range / Intervals
    private let rowIntervalLabel = NSTextField(labelWithString: "Row jump: 2")
    private let rowIntervalSlider = NSSlider(value: 2, minValue: 0, maxValue: 12, target: nil, action: nil)
    private let octaveLabel = NSTextField(labelWithString: "Octave: +0")
    private let octaveSlider = NSSlider(value: 0, minValue: -2, maxValue: 3, target: nil, action: nil)

    // Views
    private lazy var keyboardMapView = KeyboardMapView(controller: controller)
    private lazy var touchpadPadView = TouchpadPadView(controller: controller)
    private lazy var textComposerView = TextComposerView(controller: controller, performer: textPerformer)

    // Footer
    private let statusLabel = NSTextField(labelWithString: "")
    private let debugLabel = NSTextField(labelWithString: "")
    private let helpScrollView = NSScrollView()
    private let helpTextView = NSTextView()

    private let settingsSeparatorTop = NSBox.separator()
    private let settingsSeparatorBottom = NSBox.separator()
    private let settingsRow = NSStackView()
    private let settingsSeparatorBetweenPerformanceAndMapping = NSBox.separator()
    private let settingsSeparatorBetweenMappingAndRange = NSBox.separator()
    private let performanceGroup = NSStackView()
    private let mappingGroup = NSStackView()
    private let rangeGroup = NSStackView()

    // MARK: - Init

    init(controller: KeystrokeMusicController, textPerformer: TextMusicPerformer) {
        self.controller = controller
        self.textPerformer = textPerformer
        super.init(frame: .zero)
        setupUI()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDidChange(_:)),
            name: .makingMusicStateDidChange,
            object: controller
        )
        render()

        if inputMode == .text {
            DispatchQueue.main.async { [weak self] in
                self?.textComposerView.focus()
            }
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Events

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        switch inputMode {
        case .keys:
            window?.makeFirstResponder(self)
        case .text:
            textComposerView.focus()
        }
        super.mouseDown(with: event)
    }

    @objc private func controllerDidChange(_ notification: Notification) {
        _ = notification
        scheduleRender()
    }

    var isTextInputMode: Bool {
        inputMode == .text
    }

    func focusTextInput() {
        guard isTextInputMode else { return }
        textComposerView.focus()
    }

    // MARK: - Actions

    @objc private func inputModeChanged(_ sender: NSSegmentedControl) {
        _ = sender
        guard let selected = InputMode(rawValue: inputModeSegmented.selectedSegment) else { return }
        setInputMode(selected)
    }

    @objc private func uiModeChanged(_ sender: NSSegmentedControl) {
        _ = sender
        guard let selected = UIMode(rawValue: uiModeSegmented.selectedSegment) else { return }
        setUIMode(selected)
    }

    @objc private func presetChanged(_ sender: NSPopUpButton) {
        _ = sender
        let index = presetPopup.indexOfSelectedItem
        guard index > 0 else { return }
        defer { presetPopup.selectItem(at: 0) }
        applyPreset(index: index)
    }

    @objc private func practiceChanged(_ sender: NSPopUpButton) {
        _ = sender
        let index = practicePopup.indexOfSelectedItem
        guard index > 0 else { return }
        defer { practicePopup.selectItem(at: 0) }
        applyPractice(index: index)
    }

    @objc private func armToggled(_ sender: NSButton) {
        _ = sender
        controller.toggleArmed()
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        _ = sender
        switch modeSegmented.selectedSegment {
        case 0:
            controller.setMappingMode(.musical)
        case 1:
            controller.setMappingMode(.chromatic)
        default:
            break
        }
    }

    @objc private func powerChordsToggled(_ sender: NSButton) {
        _ = sender
        controller.togglePowerChordMode()
    }

    @objc private func instrumentChanged(_ sender: NSPopUpButton) {
        _ = sender
        let index = instrumentPopup.indexOfSelectedItem
        guard index >= 0, index < Instrument.allCases.count else { return }
        controller.setInstrument(Instrument.allCases[index])
    }

    @objc private func soundFontPressed(_ sender: NSButton) {
        _ = sender
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["sf2", "dls"].compactMap { UTType(filenameExtension: $0) }
        panel.message = "Choose a SoundFont (.sf2) or DLS sound bank to improve realism."

        guard let window = window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url else { return }
            let ok = self.controller.setSoundFont(url: url)
            if !ok { self.presentSoundFontLoadFailedAlert() }
        }
    }

    @objc private func useBuiltInSoundPressed(_ sender: NSButton) {
        _ = sender
        let ok = controller.useBuiltInSounds()
        if !ok { presentSoundFontNotSupportedAlert() }
    }

    @objc private func scaleChanged(_ sender: NSPopUpButton) {
        _ = sender
        let index = scalePopup.indexOfSelectedItem
        guard index >= 0, index < controller.availableScales.count else { return }
        controller.setScale(controller.availableScales[index])
    }

    @objc private func playStyleChanged(_ sender: NSSegmentedControl) {
        _ = sender
        switch playStyleSegmented.selectedSegment {
        case 0: controller.setPlayStyle(.hold)
        case 1: controller.setPlayStyle(.chug8)
        case 2: controller.setPlayStyle(.chug16)
        default: break
        }
    }

    @objc private func bpmChanged(_ sender: NSStepper) {
        _ = sender
        controller.setTempoBPM(bpmStepper.integerValue)
    }

    @objc private func strumToggled(_ sender: NSButton) {
        _ = sender
        controller.toggleStrumChords()
    }
    
    @objc private func rowIntervalChanged(_ sender: NSSlider) {
        _ = sender
        controller.setRowOffset(Int(sender.intValue))
    }
    
    @objc private func octaveChanged(_ sender: NSSlider) {
        _ = sender
        controller.setOctave(Int(sender.intValue))
    }

    private func setInputMode(_ mode: InputMode) {
        inputMode = mode
        inputModeSegmented.selectedSegment = mode.rawValue

        switch mode {
        case .keys:
            textComposerView.stopPlayback()
            window?.makeFirstResponder(self)
        case .text:
            textComposerView.focus()
        }

        render()
    }

    private func setUIMode(_ mode: UIMode) {
        uiMode = mode
        uiModeSegmented.selectedSegment = mode.rawValue
        textComposerView.setShowsAdvancedControls(mode == .advanced)
        render()
    }

    private func applyPreset(index: Int) {
        guard let preset = Preset(rawValue: index) else { return }
        applyPreset(preset)
    }

    private func applyPreset(_ preset: Preset) {
        textComposerView.stopPlayback()

        switch preset {
        case .prettyPiano:
            setInputMode(.keys)
            controller.setInstrument(.piano)
            controller.setMappingMode(.musical)
            controller.setScale(.minorPentatonic)
            controller.setPowerChordModeIsOn(false)
            controller.setPlayStyle(.hold)
            controller.setTempoBPM(140)
            controller.setStrumChordsIsOn(false)
            controller.setRowOffset(2)
            controller.setOctave(0)
            controller.setAction("Preset: Pretty Piano.")

        case .rockGuitar:
            setInputMode(.keys)
            controller.setInstrument(.guitarOverdriven)
            controller.setMappingMode(.chromatic)
            controller.setPowerChordModeIsOn(true)
            controller.setPlayStyle(.chug8)
            controller.setTempoBPM(140)
            controller.setStrumChordsIsOn(true)
            controller.setRowOffset(5)
            controller.setOctave(-1)
            controller.setAction("Preset: Rock Guitar.")

        case .guitarChug:
            setInputMode(.keys)
            controller.setInstrument(.guitarDistortion)
            controller.setMappingMode(.chromatic)
            controller.setPowerChordModeIsOn(true)
            controller.setPlayStyle(.chug16)
            controller.setTempoBPM(160)
            controller.setStrumChordsIsOn(false)
            controller.setRowOffset(5)
            controller.setOctave(-1)
            controller.setAction("Preset: Guitar Chug.")

        case .chordChartPiano:
            setInputMode(.text)
            controller.setInstrument(.piano)
            controller.setTempoBPM(120)
            controller.setStrumChordsIsOn(false)
            controller.setOctave(0)
            textPerformer.mode = .script
            textPerformer.chordPlaybackStyle = .comp
            textPerformer.chordAdvanceMode = .everyBar
            controller.setAction("Preset: Typing Script (Two-hand Piano).")

        case .chordChartGuitar:
            setInputMode(.text)
            controller.setInstrument(.guitarOverdriven)
            controller.setTempoBPM(120)
            controller.setStrumChordsIsOn(true)
            controller.setOctave(-1)
            textPerformer.mode = .script
            textPerformer.chordPlaybackStyle = .comp
            textPerformer.chordAdvanceMode = .everyBar
            controller.setAction("Preset: Typing Script (Rock Guitar).")
        }
    }

    private func applyPractice(index: Int) {
        if index == practicePasteFromClipboardIndex() {
            let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
            let extracted = textPerformer.chordChartFromText(clipboard)
            if extracted.isEmpty {
                practicePlan = nil
                controller.setAction("Practice: clipboard had no chords.")
            } else {
                practicePlan = PracticePlan(
                    title: "Clipboard",
                    sections: [PracticeSection(title: "Pasted chord chart", chart: extracted)],
                    showPowerChordTip: true,
                    recommendedPreset: .rockGuitar
                )
                controller.setAction("Practice: pasted chords from clipboard.")
            }
            render()
            return
        }

        if index == practiceClearIndex() {
            practicePlan = nil
            controller.setAction("Practice: cleared.")
            render()
            return
        }

        guard let selection = practiceSelection(forIndex: index) else { return }
        let plan = practicePlan(for: selection)
        practicePlan = plan
        applyPreset(plan.recommendedPreset)
        controller.setAction("Practice: \(selection.title). Preset: \(presetTitle(for: plan.recommendedPreset)).")
        render()
    }

    private func practiceSelection(forIndex index: Int) -> PracticeSong? {
        let firstIndex = practiceFirstSongIndex()
        let songIndex = index - firstIndex
        guard songIndex >= 0, songIndex < PracticeSong.allCases.count else { return nil }
        return PracticeSong.allCases[songIndex]
    }

    private func practiceFirstSongIndex() -> Int { 1 }

    private func practicePasteFromClipboardIndex() -> Int {
        practiceFirstSongIndex() + PracticeSong.allCases.count
    }

    private func practiceClearIndex() -> Int {
        practicePasteFromClipboardIndex() + 1
    }

    private func practicePlan(for song: PracticeSong) -> PracticePlan {
        switch song {
        case .nothingElseMatters:
            return PracticePlan(
                title: song.title,
                sections: [
                    PracticeSection(
                        title: "Intro pick (Power chords OFF)",
                        chart: "E B G B  E B G B"
                    ),
                    PracticeSection(
                        title: "Chord loop A (practice)",
                        chart: "Em D C G  Em D C G"
                    ),
                    PracticeSection(
                        title: "Chord loop B (practice)",
                        chart: "C G D Em  C G D Em"
                    ),
                ],
                showPowerChordTip: true,
                recommendedPreset: song.recommendedPreset
            )

        case .freeBird:
            return PracticePlan(
                title: song.title,
                sections: [
                    PracticeSection(
                        title: "Chord loop A (practice)",
                        chart: "G D/F# Em F C D  G D/F# Em F C D"
                    ),
                    PracticeSection(
                        title: "Chord loop B (practice)",
                        chart: "G D Em  G D Em"
                    ),
                ],
                showPowerChordTip: true,
                recommendedPreset: song.recommendedPreset
            )

        case .sweetChildOMine:
            return PracticePlan(
                title: song.title,
                sections: [
                    PracticeSection(
                        title: "Verse loop (practice)",
                        chart: "D C G D  D C G D"
                    ),
                    PracticeSection(
                        title: "Chorus loop (practice)",
                        chart: "A C D  A C D"
                    ),
                ],
                showPowerChordTip: true,
                recommendedPreset: song.recommendedPreset
            )

        case .novemberRain:
            return PracticePlan(
                title: song.title,
                sections: [
                    PracticeSection(
                        title: "Chord loop A (practice)",
                        chart: "C G Am F  C G Am F"
                    ),
                    PracticeSection(
                        title: "Chord loop B (practice)",
                        chart: "F C G Am  F C G Am"
                    ),
                ],
                showPowerChordTip: false,
                recommendedPreset: song.recommendedPreset
            )

        case .babaORiley:
            return PracticePlan(
                title: song.title,
                sections: [
                    PracticeSection(
                        title: "Main loop (practice)",
                        chart: "F C Bb  F C Bb  F C Bb"
                    ),
                    PracticeSection(
                        title: "Alt loop (practice)",
                        chart: "C Bb F  C Bb F"
                    ),
                ],
                showPowerChordTip: true,
                recommendedPreset: song.recommendedPreset
            )

        case .highwayToHell:
            return PracticePlan(
                title: song.title,
                sections: [
                    PracticeSection(
                        title: "Riff loop (practice)",
                        chart: "A D/F# G D/F# G  A D/F# G D/F# G"
                    ),
                    PracticeSection(
                        title: "Chorus-ish loop (practice)",
                        chart: "D G D A  D G D A"
                    ),
                ],
                showPowerChordTip: true,
                recommendedPreset: song.recommendedPreset
            )

        case .withArmsWideOpen:
            return PracticePlan(
                title: song.title,
                sections: [
                    PracticeSection(
                        title: "Chord loop A (practice)",
                        chart: "C C/B Am | F C | E D | C C/B Am"
                    ),
                    PracticeSection(
                        title: "Chord loop B (practice)",
                        chart: "F C G  F C G"
                    ),
                ],
                showPowerChordTip: false,
                recommendedPreset: song.recommendedPreset
            )
        }
    }

    private struct ParsedChordSymbol {
        var raw: String
        var root: PitchClass
        var bass: PitchClass?
    }

    private func parseChordSymbolForKeys(_ token: String) -> ParsedChordSymbol? {
        guard token.trimmingCharacters(in: .whitespacesAndNewlines) != "|" else { return nil }
        guard let parsed = ChordParsing.parseRootAndBass(token) else { return nil }
        return ParsedChordSymbol(raw: parsed.raw, root: parsed.root, bass: parsed.bass)
    }

    private func keyForPitchClass(_ pitchClass: PitchClass, preferredMidi: Int) -> String? {
        var bestKey: String?
        var bestScore: Int?

        for (rowIndex, row) in KeyLayout.qwertyRows.rows.enumerated() {
            for key in row {
                guard let display = controller.display(forKey: key) else { continue }
                let midi = Int(display.midiNote)
                guard (midi % 12) == pitchClass.rawValue else { continue }

                let score = abs(midi - preferredMidi) * 10 + rowIndex
                if bestScore == nil || score < bestScore! {
                    bestScore = score
                    bestKey = key
                }
            }
        }

        return bestKey
    }

    private func practiceText() -> String {
        guard let plan = practicePlan else {
            return "Pick Practice… to load a multi-section chord sheet with the exact keys to press (or paste chords from Clipboard)."
        }

        var lines: [String] = []
        lines.append("Practice — \(plan.title)")
        lines.append("Preset: \(presetTitle(for: plan.recommendedPreset)) (auto-applied)")
        lines.append("Note: if you see '?' keys, switch to All Notes so every chord exists.")
        if plan.showPowerChordTip {
            lines.append("Tip: Power chords = ON makes one key sound like a guitar chord (turn OFF for single-note riffs/arpeggios).")
        }
        lines.append("")

        for section in plan.sections {
            lines.append(section.title)
            lines.append(practiceLine(fromChart: section.chart))
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func presetTitle(for preset: Preset) -> String {
        switch preset {
        case .prettyPiano:
            return "Pretty Piano (Rock-safe)"
        case .rockGuitar:
            return "Rock Guitar (Crunch)"
        case .guitarChug:
            return "Guitar Chug (16ths)"
        case .chordChartPiano:
            return "Typing Script (Two-hand Piano)"
        case .chordChartGuitar:
            return "Typing Script (Rock Guitar)"
        }
    }

    private func practiceLine(fromChart chart: String) -> String {
        let tokens = chart.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return "" }

        let preferredChordMidi = controller.baseMidiRoot + 12
        let preferredBassMidi = controller.baseMidiRoot

        var rendered: [String] = []
        rendered.reserveCapacity(tokens.count)

        for token in tokens {
            if token == "|" {
                rendered.append("|")
                continue
            }

            if let chord = parseChordSymbolForKeys(token) {
                let rootKey = keyForPitchClass(chord.root, preferredMidi: preferredChordMidi) ?? "?"
                if let bass = chord.bass {
                    let bassKey = keyForPitchClass(bass, preferredMidi: preferredBassMidi) ?? "?"
                    rendered.append("\(chord.raw)[\(bassKey)→\(rootKey)]")
                } else {
                    rendered.append("\(chord.raw)[\(rootKey)]")
                }
            } else if let pc = ChordParsing.parsePitchClassPrefix(token) {
                let key = keyForPitchClass(pc, preferredMidi: preferredChordMidi) ?? "?"
                rendered.append("\(token)[\(key)]")
            } else {
                rendered.append(token)
            }
        }

        return rendered.joined(separator: "  ")
    }

    private func keyboardSpreadName(mode: NoteMappingMode, rowOffset: Int) -> String {
        switch mode {
        case .musical:
            switch rowOffset {
            case 0...1:
                return "Compact"
            case 2...3:
                return "Guitar-ish"
            default:
                return "Wide"
            }
        case .chromatic:
            switch rowOffset {
            case 0...3:
                return "Compact"
            case 4...6:
                return "Guitar-ish"
            default:
                return "Wide"
            }
        }
    }

    // MARK: - UI Setup

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // Configure Controls
        inputModeSegmented.target = self
        inputModeSegmented.action = #selector(inputModeChanged(_:))
        inputModeSegmented.selectedSegment = inputMode.rawValue

        uiModeSegmented.target = self
        uiModeSegmented.action = #selector(uiModeChanged(_:))
        uiModeSegmented.selectedSegment = uiMode.rawValue

        presetPopup.target = self
        presetPopup.action = #selector(presetChanged(_:))
        presetPopup.addItems(withTitles: [
            "Preset…",
            "Pretty Piano (Rock-safe)",
            "Rock Guitar (Crunch)",
            "Guitar Chug (16ths)",
            "Typing Script (Two-hand Piano)",
            "Typing Script (Rock Guitar)",
        ])
        presetPopup.selectItem(at: 0)

        practicePopup.target = self
        practicePopup.action = #selector(practiceChanged(_:))
        practicePopup.addItems(withTitles: ["Practice…"] + PracticeSong.allCases.map { $0.title } + [
            "Paste chords from Clipboard",
            "Clear",
        ])
        practicePopup.selectItem(at: 0)

        armButton.target = self
        armButton.action = #selector(armToggled(_:))

        instrumentPopup.target = self
        instrumentPopup.action = #selector(instrumentChanged(_:))
        instrumentPopup.addItems(withTitles: Instrument.allCases.map(\.rawValue))

        soundLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        soundLabel.textColor = .secondaryLabelColor

        soundFontButton.target = self
        soundFontButton.action = #selector(soundFontPressed(_:))

        builtInSoundButton.target = self
        builtInSoundButton.action = #selector(useBuiltInSoundPressed(_:))

        playStyleSegmented.target = self
        playStyleSegmented.action = #selector(playStyleChanged(_:))

        bpmStepper.minValue = 40
        bpmStepper.maxValue = 240
        bpmStepper.increment = 1
        bpmStepper.target = self
        bpmStepper.action = #selector(bpmChanged(_:))

        strumButton.target = self
        strumButton.action = #selector(strumToggled(_:))

        modeSegmented.target = self
        modeSegmented.action = #selector(modeChanged(_:))

        scalePopup.target = self
        scalePopup.action = #selector(scaleChanged(_:))
        scalePopup.addItems(withTitles: controller.availableScales.map(\.name))

        powerChordButton.target = self
        powerChordButton.action = #selector(powerChordsToggled(_:))

        rowIntervalSlider.numberOfTickMarks = 13
        rowIntervalSlider.allowsTickMarkValuesOnly = true
        rowIntervalSlider.target = self
        rowIntervalSlider.action = #selector(rowIntervalChanged(_:))

        octaveSlider.numberOfTickMarks = 6
        octaveSlider.allowsTickMarkValuesOnly = true
        octaveSlider.target = self
        octaveSlider.action = #selector(octaveChanged(_:))

        rowIntervalLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        rowIntervalLabel.textColor = .secondaryLabelColor

        octaveLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        octaveLabel.textColor = .secondaryLabelColor

        // Layout Groups
        
        // 1. Toolbar
        let toolbarSpacer = NSView()
        toolbarSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        toolbarSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let toolbar = NSStackView(views: [
            inputModeSegmented,
            armButton,
            presetPopup,
            practicePopup,
            uiModeSegmented,
            toolbarSpacer,
            instrumentPopup,
            soundLabel,
            soundFontButton,
            builtInSoundButton,
        ])
        toolbar.orientation = .horizontal
        toolbar.spacing = 12
        toolbar.alignment = .centerY
        toolbar.distribution = .fill

        // 2. Settings Grid
        let performanceTitle = NSTextField(labelWithString: "Performance")
        performanceTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        performanceTitle.textColor = .secondaryLabelColor

        let bpmRow = NSStackView(views: [bpmLabel, bpmStepper])
        bpmRow.orientation = .horizontal
        bpmRow.alignment = .centerY
        bpmRow.spacing = 8

        performanceGroup.orientation = .vertical
        performanceGroup.alignment = .leading
        performanceGroup.spacing = 6
        performanceGroup.addArrangedSubview(performanceTitle)
        performanceGroup.addArrangedSubview(playStyleSegmented)
        performanceGroup.addArrangedSubview(bpmRow)
        performanceGroup.addArrangedSubview(strumButton)
        
        let mappingTitle = NSTextField(labelWithString: "Mapping")
        mappingTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        mappingTitle.textColor = .secondaryLabelColor

        let modeRow = NSStackView(views: [modeSegmented, scalePopup])
        modeRow.orientation = .horizontal
        modeRow.alignment = .centerY
        modeRow.spacing = 8

        mappingGroup.orientation = .vertical
        mappingGroup.alignment = .leading
        mappingGroup.spacing = 6
        mappingGroup.addArrangedSubview(mappingTitle)
        mappingGroup.addArrangedSubview(modeRow)
        mappingGroup.addArrangedSubview(powerChordButton)
        
        let rangeTitle = NSTextField(labelWithString: "Range")
        rangeTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        rangeTitle.textColor = .secondaryLabelColor

        let rowIntervalRow = NSStackView(views: [rowIntervalLabel, rowIntervalSlider])
        rowIntervalRow.orientation = .horizontal
        rowIntervalRow.alignment = .centerY
        rowIntervalRow.spacing = 8

        let octaveRow = NSStackView(views: [octaveLabel, octaveSlider])
        octaveRow.orientation = .horizontal
        octaveRow.alignment = .centerY
        octaveRow.spacing = 8

        rangeGroup.orientation = .vertical
        rangeGroup.alignment = .leading
        rangeGroup.spacing = 6
        rangeGroup.addArrangedSubview(rangeTitle)
        rangeGroup.addArrangedSubview(rowIntervalRow)
        rangeGroup.addArrangedSubview(octaveRow)
        rowIntervalSlider.widthAnchor.constraint(equalToConstant: 100).isActive = true
        octaveSlider.widthAnchor.constraint(equalToConstant: 100).isActive = true

        settingsRow.orientation = .horizontal
        settingsRow.alignment = .top
        settingsRow.spacing = 24
        settingsRow.addArrangedSubview(performanceGroup)
        settingsRow.addArrangedSubview(settingsSeparatorBetweenPerformanceAndMapping)
        settingsRow.addArrangedSubview(mappingGroup)
        settingsRow.addArrangedSubview(settingsSeparatorBetweenMappingAndRange)
        settingsRow.addArrangedSubview(rangeGroup)
        
        // 3. Main Content
        keyboardMapView.translatesAutoresizingMaskIntoConstraints = false
        keyboardMapView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        
        let contentStack = NSStackView(views: [keyboardMapView, touchpadPadView, textComposerView])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12
        textComposerView.isHidden = true
        
        // 4. Footer
        helpScrollView.borderType = .bezelBorder
        helpScrollView.hasVerticalScroller = true
        helpScrollView.drawsBackground = false

        helpTextView.isEditable = false
        helpTextView.isSelectable = true
        helpTextView.drawsBackground = false
        helpTextView.textColor = .labelColor
        helpTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        helpTextView.textContainerInset = NSSize(width: 8, height: 6)
        helpScrollView.documentView = helpTextView

        statusLabel.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        statusLabel.lineBreakMode = .byTruncatingTail

        debugLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        debugLabel.textColor = .secondaryLabelColor
        debugLabel.lineBreakMode = .byTruncatingTail
        
        let footerStack = NSStackView(views: [statusLabel, debugLabel, helpScrollView])
        footerStack.orientation = .vertical
        footerStack.alignment = .leading
        footerStack.spacing = 4
        
        // Main Stack
        let mainStack = NSStackView(views: [toolbar, settingsSeparatorTop, settingsRow, settingsSeparatorBottom, contentStack, footerStack])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            
            helpScrollView.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            helpScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
            
            toolbar.widthAnchor.constraint(equalTo: mainStack.widthAnchor)
        ])
    }

    // MARK: - Render

    private func scheduleRender() {
        guard !renderScheduled else { return }
        renderScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.renderScheduled = false
            self.render()
        }
    }

    private func render() {
        let isKeys = inputMode == .keys
        settingsRow.isHidden = !isKeys
        settingsSeparatorTop.isHidden = !isKeys
        settingsSeparatorBottom.isHidden = !isKeys
        practicePopup.isHidden = !isKeys

        let showsAdvancedControls = uiMode == .advanced
        performanceGroup.isHidden = !showsAdvancedControls
        mappingGroup.isHidden = !showsAdvancedControls
        settingsSeparatorBetweenPerformanceAndMapping.isHidden = !showsAdvancedControls
        settingsSeparatorBetweenMappingAndRange.isHidden = !showsAdvancedControls

        keyboardMapView.isHidden = !isKeys
        touchpadPadView.isHidden = !isKeys
        textComposerView.isHidden = isKeys

        if isKeys {
            keyboardMapView.render()
            touchpadPadView.render()
        } else {
            textComposerView.render()
        }

        // Sync Controls
        inputModeSegmented.selectedSegment = inputMode.rawValue
        uiModeSegmented.selectedSegment = uiMode.rawValue

        soundFontButton.isHidden = uiMode == .simple
        builtInSoundButton.isHidden = uiMode == .simple
        scalePopup.isHidden = uiMode == .simple
        debugLabel.isHidden = uiMode == .simple

        armButton.state = controller.isArmed ? .on : .off
        instrumentPopup.selectItem(at: Instrument.allCases.firstIndex(of: controller.instrument) ?? 0)
        
        playStyleSegmented.selectedSegment = {
            switch controller.playStyle {
            case .hold: return 0
            case .chug8: return 1
            case .chug16: return 2
            }
        }()
        
        bpmLabel.stringValue = "BPM: \(controller.tempoBPM)"
        bpmStepper.integerValue = controller.tempoBPM
        strumButton.state = controller.strumChordsIsOn ? .on : .off
        
        modeSegmented.selectedSegment = controller.mappingMode == .musical ? 0 : 1
        scalePopup.selectItem(at: controller.availableScales.firstIndex(of: controller.currentScale) ?? 0)
        
        modeSegmented.isEnabled = true
        scalePopup.isEnabled = controller.mappingMode == .musical
        powerChordButton.isEnabled = true
        
        powerChordButton.state = controller.powerChordModeIsOn ? .on : .off
        
        let spread = keyboardSpreadName(mode: controller.mappingMode, rowOffset: controller.rowOffset)
        switch controller.mappingMode {
        case .musical:
            rowIntervalLabel.stringValue = "Keyboard spread: \(spread) (\(controller.rowOffset) steps)"
        case .chromatic:
            rowIntervalLabel.stringValue = "Keyboard spread: \(spread) (\(controller.rowOffset) semitones)"
        }
        rowIntervalSlider.integerValue = controller.rowOffset
        
        let octave = controller.octaveOffset >= 0 ? "+\(controller.octaveOffset)" : "\(controller.octaveOffset)"
        octaveLabel.stringValue = "Octave: \(octave)"
        octaveSlider.integerValue = controller.octaveOffset

        soundLabel.stringValue = "Sound: \(controller.soundSourceDisplayName)"
        
        statusLabel.stringValue = controller.statusText
        debugLabel.stringValue = controller.debugText()
        if isKeys {
            helpTextView.string = controller.helpText + "\n\n" + practiceText()
        } else {
            helpTextView.string = textHelpText()
        }
    }
    
    // MARK: - Alerts
    
    private func presentSoundFontNotSupportedAlert() {
        let alert = NSAlert()
        alert.messageText = "SoundFonts not supported"
        alert.informativeText = "SoundFont loading is only available when the built-in sampler output is active."
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func presentSoundFontLoadFailedAlert() {
        let alert = NSAlert()
        alert.messageText = "Couldn’t load SoundFont"
        alert.informativeText = "Try a different .sf2 (General MIDI soundfonts usually work best). You can also press “Built-in” to revert."
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func textHelpText() -> String {
        """
        Text Mode
          Script (Sentence): type a normal sentence.
                 While ARMED: the app plays 1 character per Grid tick inside the current chord.
                 Syntax: ',' rest, '-' hold, '.' resolve, '!' accent.
          Script (Linear v1): deterministic command language for richer piano from linear typing.
                 letters = melody, '*' = full chord, '^' = arp up, 'v' = arp down, '/' = next chord
                 '1..5' = direct chord tones, '_' or '-' = hold, ',' rest, '.' resolve, '!' accent.
                 Style: Ballad Pick (Nothing Else Matters), Rock Strum (Free Bird), Power Chug (AC/DC), Synth Pulse (Baba O'Riley).
                 Use Restart to jump back to the start.
          Chords: paste a chart like Em D C G D/F# (use Songbook).
                 '|' works as a bar line and is ignored by the parser.
                 Chord advance: “Every bar” keeps chords locked to time; “On spaces” follows word boundaries.

        Tip
          Switch back to Keys mode to play riffs (the key map shows the notes).
        """
    }
}

extension NSBox {
    static func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
}
