import AppKit
import Foundation
import MakingMusicCore

extension Notification.Name {
    static let makingMusicStateDidChange = Notification.Name("making_music.stateDidChange")
}

protocol NoteOutput {
    func noteOn(note: UInt8, velocity: UInt8)
    func noteOff(note: UInt8)
}

struct KeyDisplay: Equatable, Sendable {
    var key: String
    var midiNote: UInt8
    var noteName: String
    var chordLabel: String?
}

final class ConsoleNoteOutput: NoteOutput {
    func noteOn(note: UInt8, velocity: UInt8) {
        print("note_on", "note=\(note)", "velocity=\(velocity)")
    }

    func noteOff(note: UInt8) {
        print("note_off", "note=\(note)")
    }
}

@MainActor
final class KeystrokeMusicController: @unchecked Sendable {
    private let output: NoteOutput
    private static let soundFontDefaultsKey = "making_music.soundFont.path"

    enum PlayStyle: String, CaseIterable, Sendable {
        case hold = "Hold"
        case chug8 = "Chug 8ths"
        case chug16 = "Chug 16ths"
    }

    enum VoiceLeadMode: String, CaseIterable, Sendable {
        case off = "Off"
        case smooth = "Smooth"
    }

    private(set) var isArmed = false { didSet { notifyStateDidChange() } }
    private(set) var sustainIsDown = false { didSet { notifyStateDidChange() } }
    private(set) var powerChordModeIsOn = false { didSet { notifyStateDidChange() } }
    private(set) var instrument: Instrument = .piano { didSet { notifyStateDidChange() } }
    private(set) var soundSourceDisplayName: String = "Built-in" { didSet { notifyStateDidChange() } }
    private(set) var playStyle: PlayStyle = .hold { didSet { notifyStateDidChange() } }
    private(set) var tempoBPM: Int = 140 { didSet { notifyStateDidChange() } }
    private(set) var strumChordsIsOn: Bool = true { didSet { notifyStateDidChange() } }
    private(set) var lastPlayedNote: UInt8? { didSet { notifyStateDidChange() } }
    private(set) var lastVelocity: UInt8 = 96 { didSet { notifyStateDidChange() } }
    private(set) var voiceLeadMode: VoiceLeadMode = .off { didSet { notifyStateDidChange() } }
    private(set) var baseVelocity: UInt8 = 90 { didSet { notifyStateDidChange() } }

    private var noteMapper: NoteMapper { didSet { notifyStateDidChange() } }

    private var heldNotesByKeyCode: [UInt16: Set<UInt8>] = [:]
    private var heldKeyStringByCode: [UInt16: String] = [:]
    private var sustainedNotes: Set<UInt8> = []
    private var padHeldNotes: Set<UInt8> = []
    private var padBaseNote: UInt8?
    private var chugTasksByKeyCode: [UInt16: Task<Void, Never>] = [:]

    private var transientNoteRefCount: [UInt8: Int] = [:]
    private var transientGeneration: UInt64 = 0
    private var stateDidChangeNotificationScheduled = false
    private var lastVoiceLeadNote: UInt8?

    private var lastAction: String = "Click the window, then press Cmd+Enter to arm." { didSet { notifyStateDidChange() } }
    private var lastNoteOnTimestamp: TimeInterval?

    init(output: NoteOutput) {
        self.output = output
        if let selectable = output as? InstrumentSelectableOutput {
            self.instrument = selectable.instrument
        }
        if let selectable = output as? SoundFontSelectableOutput {
            self.soundSourceDisplayName = selectable.soundSourceDisplayName
        }
        self.noteMapper = NoteMapper(
            mode: .musical,
            root: RootNote(pitchClass: .e, octave: 3),
            scale: Scale.builtins.first ?? .minorPentatonic,
            octaveOffset: 0,
            rowOffset: 0,
            keyLayout: .typewriterLinear
        )

        restoreSoundFontIfAvailable()
    }

    private func restoreSoundFontIfAvailable() {
        guard let selectable = output as? SoundFontSelectableOutput else { return }
        guard let path = UserDefaults.standard.string(forKey: Self.soundFontDefaultsKey), !path.isEmpty else {
            useRecommendedSoundFontIfAvailable(selectable: selectable)
            return
        }

        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            UserDefaults.standard.removeObject(forKey: Self.soundFontDefaultsKey)
            soundSourceDisplayName = selectable.soundSourceDisplayName
            return
        }

        do {
            try selectable.setSoundFont(url: url)
            soundSourceDisplayName = selectable.soundSourceDisplayName
        } catch {
            UserDefaults.standard.removeObject(forKey: Self.soundFontDefaultsKey)
            soundSourceDisplayName = selectable.soundSourceDisplayName
        }
    }

    private func useRecommendedSoundFontIfAvailable(selectable: SoundFontSelectableOutput) {
        guard let url = recommendedSoundFontURL(), FileManager.default.fileExists(atPath: url.path) else {
            soundSourceDisplayName = selectable.soundSourceDisplayName
            return
        }

        do {
            try selectable.setSoundFont(url: url)
            UserDefaults.standard.set(url.path, forKey: Self.soundFontDefaultsKey)
            soundSourceDisplayName = selectable.soundSourceDisplayName
            lastAction = "SoundFont: \(url.lastPathComponent)."
        } catch {
            soundSourceDisplayName = selectable.soundSourceDisplayName
        }
    }

    private func recommendedSoundFontURL() -> URL? {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return cwd.appendingPathComponent("SoundFonts/GeneralUser-GS-v1.471.sf2")
    }

    var availableScales: [Scale] {
        Scale.builtins
    }

    var baseMidiRoot: Int {
        noteMapper.root.midiNumber + noteMapper.octaveOffset * 12
    }

    var statusText: String {
        let mode: String
        switch noteMapper.mode {
        case .musical:
            mode = "Scale Lock (\(noteMapper.root.pitchClass) \(noteMapper.scale.name))"
        case .chromatic:
            mode = "All Notes (from \(noteMapper.root.pitchClass))"
        }

        let octave = noteMapper.octaveOffset >= 0 ? "+\(noteMapper.octaveOffset)" : "\(noteMapper.octaveOffset)"
        let layout = "Layout: \(noteMapper.keyLayout.name)"
        let voiceLead = voiceLeadMode == .smooth ? "VL: on" : "VL: off"
        let inst = "Inst: \(instrument.rawValue)"
        let sound = "Sound: \(soundSourceDisplayName)"
        let style = "Style: \(playStyle.rawValue) @\(tempoBPM)"
        let chords = powerChordModeIsOn ? "Power chords: ON" : "Power chords: off"
        let sustain = sustainIsDown ? "Sustain: down" : "Sustain: up"

        let last: String
        if let lastPlayedNote {
            last = "Last: \(noteName(midi: Int(lastPlayedNote))) (\(lastPlayedNote))"
        } else {
            last = "Last: —"
        }

        let armed = isArmed ? "ARMED" : "disarmed"

        return "\(armed) | \(mode) | \(layout) | \(voiceLead) | \(inst) | \(sound) | \(style) | Octave: \(octave) | Vel: \(lastVelocity) | \(chords) | \(sustain) | \(last)"
    }

    var helpText: String {
        """
        Controls
          Cmd+Enter  Arm / disarm (start/stop)
          Ctrl+Opt+Cmd+M  Arm / disarm (global hotkey when global listening is enabled)
          Space      Sustain (hold)
          Touchpad   Use the Touchpad Pad (Keys mode) to play by dragging
          Preset     Use Preset for “sounds good” setups
          UI         Simple hides most buttons; Advanced shows everything
          Style      (Keys) Use Hold / Chug in the UI for auto-repeat rhythm
          SoundFont  Use the SoundFont button to load a high-quality .sf2 for more realistic piano/guitar
          Range      Use Octave in the UI to shift note range
          Shift+key  Temporary octave-up note
          Opt+key    Temporary bass (octave-down) note
          Ctrl+key   Temporary chord hit (root+5th+octave)
          [ / ]      Octave down / up (global offset)
          Tab        Toggle power-chord mode
          \\          Toggle Scale Lock / All Notes
          Cmd+1..5    Pick scale (Scale Lock mode)
          Esc        Panic (all notes off)

        Layout
          Typewriter: keys are mapped linearly in typing order (home row first).
          Melodic: keys ordered by English letter frequency — common letters
            cluster in a narrow pitch range, producing melodic output from natural typing.
          Voice Lead (Smooth): each note snaps to the nearest octave of its pitch class
            relative to the last note you played, keeping the melody tight and singable.

        Playable keys (low → high)
          z x c v b n m , . /
          a s d f g h j k l ; '
          q w e r t y u i o p
          1 2 3 4 5 6 7 8 9 0 - =

        Notes
          Scale Lock constrains notes to a scale so random typing still sounds “rock-safe”.
          All Notes is every semitone from E (more expressive, easier to hit “wrong” notes).

        Example (defaults)
          “Nothing Else Matters” intro pick (Keys mode):
            z(E) v(B) x(G) v(B) n(E) v(B) x(G) v(B)

        Text Mode
          Script: type a normal sentence. When ARMED, the app “reads” it on a beat grid:
                  1 character = 1 Grid tick → picked notes inside the current chord (deterministic; typing speed doesn’t matter).
                  Syntax: ',' rest, '-' hold, '.' resolve, '!' accent.
                  Script Style: Ballad Pick / Rock Strum / Power Chug / Synth Pulse.
          Chords: paste a chord chart like “Em D C G D/F#” (use Songbook for starters).

        Songbook (Text Mode)
          “Nothing Else Matters”:
             Em D C G
          “Free Bird”:
             G D/F# Em F C D
          “Sweet Child O' Mine”:
             D C G D
          “November Rain”:
             C G Am F
          “Baba O'Riley”:
             F C Bb
          “Highway to Hell”:
             A D/F# G
          “With Arms Wide Open”:
             C C/B Am
        """
    }

    func setInstrument(_ instrument: Instrument) {
        guard let selectable = output as? InstrumentSelectableOutput else {
            lastAction = "Instrument switching not supported."
            return
        }

        selectable.setInstrument(instrument)
        self.instrument = instrument
        lastAction = "Instrument: \(instrument.rawValue)."
    }

    @discardableResult
    func useBuiltInSounds() -> Bool {
        guard let selectable = output as? SoundFontSelectableOutput else {
            lastAction = "SoundFont not supported."
            return false
        }

        selectable.useBuiltInSounds()
        UserDefaults.standard.removeObject(forKey: Self.soundFontDefaultsKey)
        soundSourceDisplayName = selectable.soundSourceDisplayName
        lastAction = "Sound: Built-in."
        return true
    }

    @discardableResult
    func setSoundFont(url: URL) -> Bool {
        guard let selectable = output as? SoundFontSelectableOutput else {
            lastAction = "SoundFont not supported."
            return false
        }

        do {
            try selectable.setSoundFont(url: url)
            UserDefaults.standard.set(url.path, forKey: Self.soundFontDefaultsKey)
            soundSourceDisplayName = selectable.soundSourceDisplayName
            lastAction = "SoundFont: \(url.lastPathComponent)."
            return true
        } catch {
            soundSourceDisplayName = selectable.soundSourceDisplayName
            lastAction = "Couldn’t load SoundFont: \(error.localizedDescription)"
            return false
        }
    }

    func setPlayStyle(_ playStyle: PlayStyle) {
        self.playStyle = playStyle
        lastAction = "Style: \(playStyle.rawValue)."
    }

    func setTempoBPM(_ bpm: Int) {
        tempoBPM = max(40, min(240, bpm))
        lastAction = "Tempo: \(tempoBPM) BPM."
    }

    func setMappingMode(_ mode: NoteMappingMode) {
        guard noteMapper.mode != mode else { return }
        noteMapper.mode = mode

        switch mode {
        case .musical:
            lastAction = "Scale Lock on."
        case .chromatic:
            lastAction = "All Notes on."
        }
    }
    
    var octaveOffset: Int {
        noteMapper.octaveOffset
    }
    
    func setOctave(_ octave: Int) {
        let clamped = min(max(octave, -2), 3)
        noteMapper.octaveOffset = clamped
        lastAction = "Octave \(noteMapper.octaveOffset)."
    }

    func shiftOctave(by delta: Int) {
        let clamped = min(max(noteMapper.octaveOffset + delta, -2), 3)
        noteMapper.octaveOffset = clamped
        lastAction = "Octave \(noteMapper.octaveOffset)."
    }

    func toggleStrumChords() {
        strumChordsIsOn.toggle()
        lastAction = strumChordsIsOn ? "Strum on." : "Strum off."
    }

    func setStrumChordsIsOn(_ isOn: Bool) {
        guard strumChordsIsOn != isOn else { return }
        strumChordsIsOn = isOn
        lastAction = strumChordsIsOn ? "Strum on." : "Strum off."
    }

    func setKeyLayout(_ layout: KeyLayout) {
        noteMapper.keyLayout = layout
        lastVoiceLeadNote = nil
        lastAction = "Layout: \(layout.name)."
    }

    var currentKeyLayout: KeyLayout {
        noteMapper.keyLayout
    }

    func setVoiceLeadMode(_ mode: VoiceLeadMode) {
        guard voiceLeadMode != mode else { return }
        voiceLeadMode = mode
        lastVoiceLeadNote = nil
        lastAction = "Voice lead: \(mode.rawValue)."
    }

    func setBaseVelocity(_ velocity: UInt8) {
        let clamped = max(40, min(127, velocity))
        guard baseVelocity != clamped else { return }
        baseVelocity = clamped
        lastAction = "Velocity: \(clamped)."
    }

    func playChordHit(notes: [UInt8], velocity: UInt8, durationSeconds: Double) {
        let sorted = notes.sorted()
        guard strumChordsIsOn, sorted.count > 1, (instrument != .piano || powerChordModeIsOn) else {
            playTransient(notes: sorted, velocity: velocity, durationSeconds: durationSeconds)
            return
        }

        let generation = transientGeneration
        let stepSeconds = 0.012
        for (index, note) in sorted.enumerated() {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let delay = Double(index) * stepSeconds
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                guard self.transientGeneration == generation else { return }
                self.playTransient(notes: [note], velocity: velocity, durationSeconds: durationSeconds)
            }
        }
    }

    func handleKeyDown(_ event: NSEvent) {
        handleKeyDown(
            keyCode: event.keyCode,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags,
            isRepeat: event.isARepeat,
            timestamp: event.timestamp
        )
    }

    func handleKeyUp(_ event: NSEvent) {
        handleKeyUp(
            keyCode: event.keyCode,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags,
            timestamp: event.timestamp
        )
    }

    func handleKeyDown(
        keyCode: UInt16,
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags,
        isRepeat: Bool,
        timestamp: TimeInterval
    ) {
        if isRepeat { return }

        if modifierFlags.contains([.control, .option, .command]), keyCode == 46 {
            toggleArmed()
            return
        }

        if modifierFlags.contains(.command), keyCode == 36 {
            toggleArmed()
            return
        }

        if keyCode == 53 {
            panicNow()
            return
        }

        if keyCode == 49 {
            // Space bar
            sustainIsDown = true
            lastAction = "Sustain down."
            return
        }

        let disallowedModifiersForOctave: NSEvent.ModifierFlags = [.command, .control]
        if modifierFlags.intersection(disallowedModifiersForOctave).isEmpty {
            // Bracket keys sometimes lack reliable characters on global key monitors; keyCode is consistent.
            if keyCode == 33 {
                shiftOctave(by: -1)
                return
            }
            if keyCode == 30 {
                shiftOctave(by: 1)
                return
            }
        }

        if modifierFlags.contains(.command),
           let key = charactersIgnoringModifiers?.lowercased(),
           let scaleIndex = Int(key),
           scaleIndex >= 1,
           scaleIndex <= min(availableScales.count, 5) {
            setScale(availableScales[scaleIndex - 1])
            return
        }

        guard let key = charactersIgnoringModifiers?.lowercased(), !key.isEmpty else { return }

        if key == "[" {
            shiftOctave(by: -1)
            return
        }

        if key == "]" {
            shiftOctave(by: 1)
            return
        }

        if keyCode == 48 {
            togglePowerChordMode()
            return
        }

        if key == "\\" {
            toggleMappingMode()
            return
        }

        if modifierFlags.contains([.command, .control, .option]) { return }

        guard isArmed else { return }
        guard let rawNote = noteMapper.midiNote(forKey: key) else { return }
        if heldNotesByKeyCode[keyCode] != nil { return }
        if chugTasksByKeyCode[keyCode] != nil { return }

        heldKeyStringByCode[keyCode] = key
        let octaveUpModifier = modifierFlags.contains(.shift)
        let chordModifier = modifierFlags.contains(.control)
        let bassModifier = modifierFlags.contains(.option)

        var baseNote = applyVoiceLeading(rawNote)
        if octaveUpModifier, baseNote <= 115 { baseNote += 12 }
        if bassModifier, baseNote >= 12 { baseNote -= 12 }

        switch playStyle {
        case .hold:
            let notesToPlay = notesForPress(baseNote: baseNote, chordModifier: chordModifier)
            heldNotesByKeyCode[keyCode] = notesToPlay

            let velocity = nextVelocity(timestamp: timestamp, accent: false)
            for note in notesToPlay {
                output.noteOn(note: note, velocity: velocity)
            }

            lastPlayedNote = baseNote
            lastVoiceLeadNote = baseNote
            lastAction = "Play \(key) → \(noteName(midi: Int(baseNote)))."
        case .chug8, .chug16:
            startChug(
                keyCode: keyCode,
                key: key,
                octaveUpModifier: octaveUpModifier,
                bassModifier: bassModifier,
                chordModifier: chordModifier,
                timestamp: timestamp
            )
        }
    }

    func handleKeyUp(
        keyCode: UInt16,
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags,
        timestamp: TimeInterval
    ) {
        _ = timestamp
        _ = modifierFlags

        if keyCode == 49 {
            sustainIsDown = false
            releaseSustainedNotesNotHeld()
            lastAction = "Sustain up."
            return
        }

        guard isArmed else { return }

        if let task = chugTasksByKeyCode.removeValue(forKey: keyCode) {
            task.cancel()
            heldKeyStringByCode.removeValue(forKey: keyCode)
            lastAction = "Chug stop."
            notifyStateDidChange()
            return
        }

        guard let notes = heldNotesByKeyCode.removeValue(forKey: keyCode) else { return }
        heldKeyStringByCode.removeValue(forKey: keyCode)

        if sustainIsDown {
            sustainedNotes.formUnion(notes)
        } else {
            for note in notes {
                output.noteOff(note: note)
            }
        }

        notifyStateDidChange()
    }

    func touchpadNoteOn(baseNote: UInt8, velocity: UInt8) {
        guard isArmed else { return }
        padNoteUpdate(baseNote: baseNote, velocity: velocity, allowRestart: true)
    }

    func touchpadNoteUpdate(baseNote: UInt8, velocity: UInt8) {
        guard isArmed else { return }
        padNoteUpdate(baseNote: baseNote, velocity: velocity, allowRestart: false)
    }

    func touchpadNoteOff() {
        guard !padHeldNotes.isEmpty else { return }

        if sustainIsDown {
            sustainedNotes.formUnion(padHeldNotes)
        } else {
            for note in padHeldNotes {
                output.noteOff(note: note)
            }
        }

        padHeldNotes.removeAll()
        padBaseNote = nil
        notifyStateDidChange()
    }

    func debugText() -> String {
        lastAction
    }

    func setAction(_ action: String) {
        guard lastAction != action else { return }
        lastAction = action
    }

    var mappingMode: NoteMappingMode {
        noteMapper.mode
    }

    var currentScale: Scale {
        noteMapper.scale
    }

    var heldKeys: Set<String> {
        Set(heldKeyStringByCode.values)
    }

    func display(forKey key: String) -> KeyDisplay? {
        guard let midiNote = noteMapper.midiNote(forKey: key) else { return nil }

        let noteName = noteName(midi: Int(midiNote))
        let chordLabel: String?
        if powerChordModeIsOn {
            chordLabel = "\(pitchClassName(midi: Int(midiNote)))5"
        } else {
            chordLabel = nil
        }

        return KeyDisplay(key: key, midiNote: midiNote, noteName: noteName, chordLabel: chordLabel)
    }

    func togglePowerChordMode() {
        powerChordModeIsOn.toggle()
        lastAction = powerChordModeIsOn ? "Power chords on." : "Power chords off."
    }

    func setPowerChordModeIsOn(_ isOn: Bool) {
        guard powerChordModeIsOn != isOn else { return }
        powerChordModeIsOn = isOn
        lastAction = powerChordModeIsOn ? "Power chords on." : "Power chords off."
    }

    func toggleMappingMode() {
        let nextMode: NoteMappingMode = noteMapper.mode == .musical ? .chromatic : .musical
        setMappingMode(nextMode)
    }

    func toggleArmed() {
        isArmed.toggle()
        if isArmed {
            lastNoteOnTimestamp = nil
            lastAction = "Armed."
        } else {
            panic()
            lastAction = "Disarmed."
            lastNoteOnTimestamp = nil
        }
    }

    func setScale(_ scale: Scale) {
        noteMapper.scale = scale
        lastAction = "Scale: \(scale.name)."
    }

    func panicNow() {
        panic()
        lastNoteOnTimestamp = nil
        lastAction = "Panic."
    }

    func playTransient(notes: [UInt8], velocity: UInt8, durationSeconds: Double) {
        guard isArmed else { return }
        let duration = max(0.02, min(durationSeconds, 2.5))
        let generation = transientGeneration

        for note in notes {
            let current = transientNoteRefCount[note, default: 0]
            transientNoteRefCount[note] = current + 1
            output.noteOn(note: note, velocity: velocity)
            lastPlayedNote = note

            Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                guard self.transientGeneration == generation else { return }

                let remaining = (self.transientNoteRefCount[note] ?? 1) - 1
                if remaining <= 0 {
                    self.transientNoteRefCount.removeValue(forKey: note)
                    self.output.noteOff(note: note)
                } else {
                    self.transientNoteRefCount[note] = remaining
                }
            }
        }
    }

    func nextVelocity(timestamp: TimeInterval, accent: Bool) -> UInt8 {
        let base = nextVelocity(timestamp: timestamp)
        guard accent else { return base }
        return UInt8(min(127, Int(base) + 24))
    }

    private func applyVoiceLeading(_ rawNote: UInt8) -> UInt8 {
        guard voiceLeadMode == .smooth else { return rawNote }
        return VoiceLeading.smooth(rawNote: rawNote, reference: lastVoiceLeadNote)
    }

    private func notesForPress(baseNote: UInt8, chordModifier: Bool = false) -> Set<UInt8> {
        var notes: Set<UInt8> = [baseNote]
        guard powerChordModeIsOn || chordModifier else { return notes }

        if baseNote <= 120 {
            notes.insert(baseNote + 7)
        }
        if baseNote <= 115 {
            notes.insert(baseNote + 12)
        }
        return notes
    }

    private func releaseSustainedNotesNotHeld() {
        let held = heldNotesByKeyCode.values.reduce(into: Set<UInt8>()) { result, notes in
            result.formUnion(notes)
        }.union(padHeldNotes)

        for note in sustainedNotes.subtracting(held) {
            output.noteOff(note: note)
        }
        sustainedNotes = sustainedNotes.intersection(held)
    }

    private func panic() {
        let notes = heldNotesByKeyCode.values.reduce(into: Set<UInt8>()) { result, notes in
            result.formUnion(notes)
        }.union(sustainedNotes).union(padHeldNotes)

        for task in chugTasksByKeyCode.values {
            task.cancel()
        }
        chugTasksByKeyCode.removeAll()

        transientGeneration &+= 1
        let transientNotes = Set(transientNoteRefCount.keys)

        for note in transientNotes.subtracting(notes) {
            output.noteOff(note: note)
        }
        transientNoteRefCount.removeAll()

        for note in notes {
            output.noteOff(note: note)
        }
        heldNotesByKeyCode.removeAll()
        heldKeyStringByCode.removeAll()
        sustainedNotes.removeAll()
        padHeldNotes.removeAll()
        padBaseNote = nil
        sustainIsDown = false
        lastVoiceLeadNote = nil
    }

    private func startChug(
        keyCode: UInt16,
        key: String,
        octaveUpModifier: Bool,
        bassModifier: Bool,
        chordModifier: Bool,
        timestamp: TimeInterval
    ) {
        guard playStyle != .hold else { return }

        let chugVelocity = UInt8(max(64, Int(nextVelocity(timestamp: timestamp, accent: false))))

        lastAction = "Chug \(key)."
        notifyStateDidChange()

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            var nextTickNanos = DispatchTime.now().uptimeNanoseconds

            chugLoop: while !Task.isCancelled {
                guard self.isArmed else { break }
                guard self.playStyle != .hold else { break chugLoop }

                let intervalSeconds: Double = self.playStyle == .chug8
                    ? (60.0 / Double(self.tempoBPM)) / 2.0
                    : (60.0 / Double(self.tempoBPM)) / 4.0

                let hitDuration = max(0.04, min(0.22, intervalSeconds * 0.55))

                guard let mappedNote = self.noteMapper.midiNote(forKey: key) else { break }
                var baseNote = self.applyVoiceLeading(mappedNote)
                if octaveUpModifier, baseNote <= 115 { baseNote += 12 }
                if bassModifier, baseNote >= 12 { baseNote -= 12 }

                let notes = Array(self.notesForPress(baseNote: baseNote, chordModifier: chordModifier)).sorted()
                if !notes.isEmpty {
                    self.playChordHit(notes: notes, velocity: chugVelocity, durationSeconds: hitDuration)
                    self.lastPlayedNote = baseNote
                    self.lastVoiceLeadNote = baseNote
                }

                let intervalNanos = UInt64(intervalSeconds * 1_000_000_000)
                nextTickNanos += intervalNanos
                let now = DispatchTime.now().uptimeNanoseconds
                if nextTickNanos > now {
                    try? await Task.sleep(nanoseconds: nextTickNanos - now)
                }
            }
        }

        chugTasksByKeyCode[keyCode] = task
    }

    private func padNoteUpdate(baseNote: UInt8, velocity: UInt8, allowRestart: Bool) {
        if !allowRestart, padBaseNote == baseNote { return }

        if !padHeldNotes.isEmpty {
            if sustainIsDown {
                sustainedNotes.formUnion(padHeldNotes)
            } else {
                for note in padHeldNotes {
                    output.noteOff(note: note)
                }
            }
            padHeldNotes.removeAll()
        }

        padBaseNote = baseNote
        let notesToPlay = notesForPress(baseNote: baseNote)
        padHeldNotes = notesToPlay

        lastVelocity = velocity
        for note in notesToPlay {
            output.noteOn(note: note, velocity: velocity)
        }

        lastPlayedNote = baseNote
        lastAction = "Pad → \(noteName(midi: Int(baseNote)))."
        notifyStateDidChange()
    }

    private func nextVelocity(timestamp: TimeInterval) -> UInt8 {
        defer { lastNoteOnTimestamp = timestamp }

        guard let lastNoteOnTimestamp else {
            lastVelocity = baseVelocity
            return lastVelocity
        }

        let delta = max(0, timestamp - lastNoteOnTimestamp)
        let clamped = min(max(delta, 0.03), 0.50)
        let t = (clamped - 0.03) / (0.50 - 0.03)
        // Center dynamics around baseVelocity: fast playing = base+30, slow = base-30
        let velocity = Int(baseVelocity) + 30 - Int((t * 60).rounded())
        lastVelocity = UInt8(max(28, min(127, velocity)))
        return lastVelocity
    }

    private func pitchClassName(midi: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return names[midi % 12]
    }

    private func noteName(midi: Int) -> String {
        let pitchClass = pitchClassName(midi: midi)
        let octave = (midi / 12) - 1
        return "\(pitchClass)\(octave)"
    }

    private func notifyStateDidChange() {
        guard !stateDidChangeNotificationScheduled else { return }
        stateDidChangeNotificationScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stateDidChangeNotificationScheduled = false
            NotificationCenter.default.post(name: .makingMusicStateDidChange, object: self)
        }
    }
}
