import AppKit
import Foundation
import MakingMusicCore

@MainActor
final class TextMusicPerformer {
    enum Mode: String, CaseIterable {
        case script
        case chords
    }

    enum ScriptStyle: String, CaseIterable {
        case balladPick = "Ballad Pick"
        case rockStrum = "Rock Strum"
        case powerChug = "Power Chug"
        case synthPulse = "Synth Pulse"
    }

    enum ScriptInputMode: String, CaseIterable {
        case sentence = "Sentence"
        case linearV1 = "Linear v1"
    }

    enum ChordPlaybackStyle: String, CaseIterable {
        case stabs = "Stabs"
        case comp = "Two-hand"
    }

    enum TimingGrid: String, CaseIterable {
        case off = "Off"
        case eighths = "8ths"
        case sixteenths = "16ths"
        case triplets = "Triplets"
    }

    enum ChordAdvanceMode: String, CaseIterable {
        case everyBar = "Every bar"
        case onSpaces = "On spaces"
    }

    private let controller: KeystrokeMusicController

    private struct ChartToken: Equatable {
        var chord: ChordSymbol
        var raw: String
        var range: NSRange
    }

    private var chordChartText: String = ""
    private var scriptText: String = ""
    private var scriptCharacters: [Character] = []

    private var chartTokens: [ChartToken] = []
    private var chartIndex: Int = 0

    private var playbackTask: Task<Void, Never>?
    private var playbackGeneration: UInt64 = 0
    private var scriptIndex: Int = 0
    private var tickIndex: Int = 0
    private var virtualTimestamp: TimeInterval = 0
    private var lastMelodyNote: UInt8?
    private var lastMelodyChordIndex: Int?

    var mode: Mode = .script
    var scriptStyle: ScriptStyle = .balladPick
    var scriptInputMode: ScriptInputMode = .sentence
    var chordPlaybackStyle: ChordPlaybackStyle = .comp
    var timingGrid: TimingGrid = .sixteenths
    var chordAdvanceMode: ChordAdvanceMode = .everyBar

    init(controller: KeystrokeMusicController) {
        self.controller = controller
    }

    var chordChartTextForDisplay: String { chordChartText }

    var scriptTextForDisplay: String { scriptText }

    var isPlaying: Bool { playbackTask != nil }

    var highlightedRange: NSRange? {
        switch mode {
        case .script:
            return scriptHighlightedRange
        case .chords:
            return chordHighlightedRange
        }
    }

    private var chordHighlightedRange: NSRange? {
        guard !chartTokens.isEmpty else { return nil }
        return chartTokens[chartIndex].range
    }

    private var scriptHighlightedRange: NSRange? {
        guard !scriptText.isEmpty else { return nil }
        guard scriptIndex >= 0 else { return nil }

        let clampedIndex = min(scriptIndex, max(0, scriptCharacters.count - 1))
        guard let start = scriptText.index(scriptText.startIndex, offsetBy: clampedIndex, limitedBy: scriptText.endIndex) else {
            return nil
        }
        let end = scriptText.index(after: start)
        return NSRange(start..<end, in: scriptText)
    }

    var statusForDisplay: String {
        let grid = "Grid: \(timingGrid.rawValue)@\(controller.tempoBPM)"
        let input = "Input: \(scriptInputMode.rawValue)"
        let style = "Style: \(scriptStyle.rawValue)"
        let chordMode = "Chord: \(chordAdvanceMode.rawValue)"

        if chartTokens.isEmpty {
            return "\(input)   \(style)   \(grid)   \(chordMode)   Chords: (none)"
        }

        let current = chartTokens[chartIndex].raw
        let next = chartTokens[(chartIndex + 1) % chartTokens.count].raw
        return "\(input)   \(style)   \(grid)   \(chordMode)   Chord \(chartIndex + 1)/\(chartTokens.count): \(current)   Next: \(next)"
    }

    func setChordChartText(_ text: String) {
        chordChartText = text
        chartTokens = parseChartTokens(from: text)
        if chartTokens.isEmpty {
            chartIndex = 0
        } else {
            chartIndex = min(max(0, chartIndex), chartTokens.count - 1)
        }
    }

    func setScriptText(_ text: String) {
        scriptText = text
        scriptCharacters = Array(text)
        if scriptCharacters.isEmpty {
            scriptIndex = 0
        } else {
            scriptIndex = min(max(0, scriptIndex), scriptCharacters.count - 1)
        }
    }

    func moveScriptCursorToRecentCharacter(atTextLocation location: Int) {
        guard !scriptCharacters.isEmpty else {
            scriptIndex = 0
            return
        }

        let recentIndex = max(0, location - 1)
        scriptIndex = min(recentIndex, scriptCharacters.count - 1)
    }

    func restart() {
        scriptIndex = 0
        tickIndex = 0
        chartIndex = 0
        virtualTimestamp = 0
        lastMelodyNote = nil
        lastMelodyChordIndex = nil
        playbackGeneration &+= 1
    }

    func updatePlayback(shouldPlay: Bool) {
        if shouldPlay {
            startPlaybackIfNeeded()
        } else {
            stopPlayback()
        }
    }

    func stopPlayback() {
        playbackGeneration &+= 1
        playbackTask?.cancel()
        playbackTask = nil
    }

    private func startPlaybackIfNeeded() {
        guard playbackTask == nil else { return }
        guard controller.isArmed else { return }

        if timingGrid == .off {
            timingGrid = .sixteenths
        }

        restart()

        let generation = playbackGeneration

        playbackTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                guard self.playbackGeneration == generation else { break }
                guard self.controller.isArmed else { break }

                let bpm = max(40, self.controller.tempoBPM)
                let intervalSeconds = self.gridIntervalSeconds(bpm: bpm) ?? (60.0 / Double(bpm) / 4.0)
                self.playScriptTick(intervalSeconds: intervalSeconds)

                try? await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
            }
        }
    }

    private func playScriptTick(intervalSeconds: Double) {
        var baseVelocity: UInt8?
        func velocity(accent: Bool) -> UInt8 {
            if baseVelocity == nil {
                baseVelocity = controller.nextVelocity(timestamp: virtualTimestamp, accent: false)
            }
            let value = Int(baseVelocity ?? 96)
            guard accent else { return UInt8(min(127, value)) }
            return UInt8(min(127, value + 24))
        }

        defer {
            tickIndex += 1
            virtualTimestamp += intervalSeconds
            if !scriptCharacters.isEmpty {
                scriptIndex = (scriptIndex + 1) % scriptCharacters.count
            }
        }

        guard !scriptCharacters.isEmpty else { return }
        guard !chartTokens.isEmpty else { return }

        let barLength = max(1, ticksPerBar())
        let tickInBar = tickIndex % barLength

        let previousChordIndex = chartIndex
        switch chordAdvanceMode {
        case .everyBar:
            chartIndex = (tickIndex / barLength) % chartTokens.count
        case .onSpaces:
            break
        }

        let chord = chartTokens[chartIndex].chord
        if chartIndex != previousChordIndex {
            lastMelodyNote = nil
            lastMelodyChordIndex = nil
            playBassNote(chord: chord, velocity: velocity(accent: false))
        }

        let characterIndex = min(scriptIndex, scriptCharacters.count - 1)
        let character = scriptCharacters[characterIndex]

        if character.isWhitespace {
            switch chordAdvanceMode {
            case .everyBar:
                playBassNote(chord: chord, velocity: velocity(accent: false))
            case .onSpaces:
                playChordHit(chord: chord, velocity: velocity(accent: false), includeBass: true)
                chartIndex = (chartIndex + 1) % chartTokens.count
            }
            return
        }

        if character == "," {
            return
        }

        if character == "-" || (scriptInputMode == .linearV1 && character == "_") {
            return
        }

        let holdChars: Set<Character> = scriptInputMode == .linearV1 ? ["-", "_"] : ["-"]
        let holdTicks = TextRhythm.holdRunLength(after: characterIndex, in: scriptCharacters, holdCharacters: holdChars)
        let holdFloorSeconds = holdDurationFloorSeconds(
            holdTicks: holdTicks,
            tickInBar: tickInBar,
            barLength: barLength,
            intervalSeconds: intervalSeconds
        )

        if scriptInputMode == .linearV1 {
            if playLinearToken(
                character: character,
                chord: chord,
                tickInBar: tickInBar,
                barLength: barLength,
                velocity: velocity,
                intervalSeconds: intervalSeconds,
                holdFloorSeconds: holdFloorSeconds
            ) {
                return
            }
        }

        if character == "." {
            playResolve(velocity: velocity(accent: false), holdFloorSeconds: holdFloorSeconds)
            return
        }

        if character == "!" {
            playChordHit(chord: chord, velocity: velocity(accent: true), includeBass: true, holdFloorSeconds: holdFloorSeconds)
            return
        }

        if isBoundaryPunctuation(character) {
            return
        }

        let accent = isUppercaseLetter(character)
        let velocity = velocity(accent: accent)

        switch scriptStyle {
        case .balladPick:
            playBalladPick(
                character: character,
                chord: chord,
                tickInBar: tickInBar,
                barLength: barLength,
                velocity: velocity,
                intervalSeconds: intervalSeconds,
                holdFloorSeconds: holdFloorSeconds
            )
        case .rockStrum:
            playRockStrum(
                character: character,
                chord: chord,
                tickInBar: tickInBar,
                velocity: velocity,
                intervalSeconds: intervalSeconds,
                holdFloorSeconds: holdFloorSeconds
            )
        case .powerChug:
            playPowerChug(
                character: character,
                chord: chord,
                tickInBar: tickInBar,
                velocity: velocity,
                intervalSeconds: intervalSeconds,
                holdFloorSeconds: holdFloorSeconds
            )
        case .synthPulse:
            playSynthPulse(
                character: character,
                chord: chord,
                tickInBar: tickInBar,
                barLength: barLength,
                velocity: velocity,
                intervalSeconds: intervalSeconds,
                holdFloorSeconds: holdFloorSeconds
            )
        }
    }

    private func playLinearToken(
        character: Character,
        chord: ChordSymbol,
        tickInBar: Int,
        barLength: Int,
        velocity: (Bool) -> UInt8,
        intervalSeconds: Double,
        holdFloorSeconds: Double
    ) -> Bool {
        if character == "/" {
            chartIndex = (chartIndex + 1) % chartTokens.count
            lastMelodyNote = nil
            lastMelodyChordIndex = nil
            let nextChord = chartTokens[chartIndex].chord
            playBassNote(chord: nextChord, velocity: velocity(false), holdFloorSeconds: holdFloorSeconds)
            return true
        }

        if character == "*" {
            playChordHit(chord: chord, velocity: velocity(false), includeBass: true, holdFloorSeconds: holdFloorSeconds)
            return true
        }

        if character == "^" {
            playArpeggio(chord: chord, ascending: true, velocity: velocity(false), intervalSeconds: intervalSeconds, holdFloorSeconds: holdFloorSeconds)
            return true
        }

        if character == "v" {
            playArpeggio(chord: chord, ascending: false, velocity: velocity(false), intervalSeconds: intervalSeconds, holdFloorSeconds: holdFloorSeconds)
            return true
        }

        if character == "." {
            playResolve(velocity: velocity(false), holdFloorSeconds: holdFloorSeconds)
            return true
        }

        if character == "!" {
            playChordHit(chord: chord, velocity: velocity(true), includeBass: true, holdFloorSeconds: holdFloorSeconds)
            return true
        }

        if isBoundaryPunctuation(character) {
            return true
        }

        switch character {
        case "1":
            playBassNote(chord: chord, velocity: velocity(false), holdFloorSeconds: holdFloorSeconds)
            return true
        case "2":
            playIndexedChordTone(chord: chord, index: 1, velocity: velocity(false), intervalSeconds: intervalSeconds, holdFloorSeconds: holdFloorSeconds)
            return true
        case "3":
            playIndexedChordTone(chord: chord, index: 2, velocity: velocity(false), intervalSeconds: intervalSeconds, holdFloorSeconds: holdFloorSeconds)
            return true
        case "4":
            playIndexedChordTone(chord: chord, index: 3, velocity: velocity(false), intervalSeconds: intervalSeconds, holdFloorSeconds: holdFloorSeconds)
            return true
        case "5":
            playChordHit(chord: chord, velocity: velocity(false), includeBass: false, holdFloorSeconds: holdFloorSeconds)
            return true
        default:
            return false
        }
    }

    private func holdDurationFloorSeconds(holdTicks: Int, tickInBar: Int, barLength: Int, intervalSeconds: Double) -> Double {
        guard holdTicks > 0 else { return 0 }

        var ticksToHold = holdTicks + 1
        if chordAdvanceMode == .everyBar, chartTokens.count > 1 {
            ticksToHold = min(ticksToHold, max(1, barLength - tickInBar))
        }

        let floorSeconds = intervalSeconds * Double(ticksToHold) * 1.05
        return floorSeconds
    }

    private func applyHoldDuration(baseDurationSeconds: Double, holdFloorSeconds: Double) -> Double {
        guard holdFloorSeconds > 0 else { return baseDurationSeconds }
        return max(baseDurationSeconds, holdFloorSeconds)
    }

    private func playBassNote(chord: ChordSymbol, velocity: UInt8, holdFloorSeconds: Double = 0) {
        let notes = pickingNotes(for: chord)
        guard let bass = notes.first else { return }
        let duration = applyHoldDuration(baseDurationSeconds: 0.45, holdFloorSeconds: holdFloorSeconds)
        controller.playTransient(notes: [bass], velocity: velocity, durationSeconds: duration)
    }

    private func playChordHit(chord: ChordSymbol, velocity: UInt8, includeBass: Bool, holdFloorSeconds: Double = 0) {
        let notes = chordNotes(for: chord).sorted()
        guard !notes.isEmpty else { return }

        let chordDuration = applyHoldDuration(baseDurationSeconds: 0.30, holdFloorSeconds: holdFloorSeconds)
        let bassDuration = applyHoldDuration(baseDurationSeconds: 0.55, holdFloorSeconds: holdFloorSeconds)

        switch chordPlaybackStyle {
        case .stabs:
            controller.playChordHit(notes: notes, velocity: velocity, durationSeconds: chordDuration)
        case .comp:
            if includeBass, let bass = notes.first {
                controller.playTransient(notes: [bass], velocity: velocity, durationSeconds: bassDuration)
            }

            let chordTones = includeBass ? Array(notes.dropFirst()) : notes
            guard !chordTones.isEmpty else { return }
            controller.playChordHit(notes: chordTones, velocity: velocity, durationSeconds: chordDuration)
        }
    }

    private func playResolve(velocity: UInt8, holdFloorSeconds: Double = 0) {
        let tonic = controller.baseMidiRoot + 12
        guard tonic >= 0 && tonic <= 127 else { return }
        let duration = applyHoldDuration(baseDurationSeconds: 0.45, holdFloorSeconds: holdFloorSeconds)
        controller.playTransient(notes: [UInt8(tonic)], velocity: velocity, durationSeconds: duration)
        controller.setAction("Resolve")
    }

    private func playIndexedChordTone(
        chord: ChordSymbol,
        index: Int,
        velocity: UInt8,
        intervalSeconds: Double,
        holdFloorSeconds: Double
    ) {
        let notes = chordNotes(for: chord).sorted()
        guard !notes.isEmpty else { return }
        let clamped = min(max(0, index), notes.count - 1)
        let note = notes[clamped]
        let baseDuration = min(0.50, max(0.12, intervalSeconds * 1.5))
        let duration = applyHoldDuration(baseDurationSeconds: baseDuration, holdFloorSeconds: holdFloorSeconds)
        controller.playTransient(notes: [note], velocity: velocity, durationSeconds: duration)
    }

    private func playArpeggio(
        chord: ChordSymbol,
        ascending: Bool,
        velocity: UInt8,
        intervalSeconds: Double,
        holdFloorSeconds: Double
    ) {
        let notes = chordNotes(for: chord).sorted()
        guard notes.count >= 2 else {
            if let note = notes.first {
                controller.playTransient(notes: [note], velocity: velocity, durationSeconds: applyHoldDuration(baseDurationSeconds: 0.25, holdFloorSeconds: holdFloorSeconds))
            }
            return
        }

        let playable = Array(notes.prefix(min(4, notes.count)))
        let ordered = ascending ? playable : playable.reversed()
        let generation = playbackGeneration
        let stepSeconds = min(0.045, max(0.012, intervalSeconds * 0.22))
        let baseDuration = min(0.50, max(0.12, intervalSeconds * 1.4))
        let duration = applyHoldDuration(baseDurationSeconds: baseDuration, holdFloorSeconds: holdFloorSeconds)

        for (index, note) in ordered.enumerated() {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let delay = Double(index) * stepSeconds
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                guard self.playbackGeneration == generation else { return }
                self.controller.playTransient(notes: [note], velocity: velocity, durationSeconds: duration)
            }
        }
    }

    private func gridIntervalSeconds(bpm: Int) -> Double? {
        guard timingGrid != .off else { return nil }

        let quarterNoteSeconds = 60.0 / Double(bpm)
        switch timingGrid {
        case .off:
            return nil
        case .eighths:
            return quarterNoteSeconds / 2.0
        case .sixteenths:
            return quarterNoteSeconds / 4.0
        case .triplets:
            return quarterNoteSeconds / 3.0
        }
    }

    // MARK: - Styles

    private enum BalladStep {
        case bass
        case low
        case mid
        case high
    }

    private func playBalladPick(
        character: Character,
        chord: ChordSymbol,
        tickInBar: Int,
        barLength: Int,
        velocity: UInt8,
        intervalSeconds: Double,
        holdFloorSeconds: Double
    ) {
        let step = balladStep(tickInBar: tickInBar, barLength: barLength)
        switch step {
        case .bass:
            guard let bass = chordNotes(for: chord).sorted().first else { return }
            let note: UInt8
            if isVowel(character), bass <= 120 {
                note = bass + 7
            } else {
                note = bass
            }
            let baseDuration = min(0.70, max(0.30, intervalSeconds * 2.4))
            let duration = applyHoldDuration(baseDurationSeconds: baseDuration, holdFloorSeconds: holdFloorSeconds)
            controller.playTransient(notes: [note], velocity: velocity, durationSeconds: duration)
        case .low:
            playBalladMelody(
                character: character,
                chord: chord,
                pool: .low,
                chordIndex: chartIndex,
                velocity: velocity,
                intervalSeconds: intervalSeconds,
                holdFloorSeconds: holdFloorSeconds
            )
        case .mid:
            playBalladMelody(
                character: character,
                chord: chord,
                pool: .mid,
                chordIndex: chartIndex,
                velocity: velocity,
                intervalSeconds: intervalSeconds,
                holdFloorSeconds: holdFloorSeconds
            )
        case .high:
            playBalladMelody(
                character: character,
                chord: chord,
                pool: .high,
                chordIndex: chartIndex,
                velocity: velocity,
                intervalSeconds: intervalSeconds,
                holdFloorSeconds: holdFloorSeconds
            )
        }
    }

    private func playBalladMelody(
        character: Character,
        chord: ChordSymbol,
        pool: PickingPool,
        chordIndex: Int,
        velocity: UInt8,
        intervalSeconds: Double,
        holdFloorSeconds: Double
    ) {
        guard let noteSelection = pickFromPool(character: character, chord: chord, pool: pool) else { return }
        let note = voiceLed(candidate: noteSelection.note, pool: noteSelection.pool, chordIndex: chordIndex)
        let baseDuration = min(0.70, max(0.20, intervalSeconds * 2.2))
        let duration = applyHoldDuration(baseDurationSeconds: baseDuration, holdFloorSeconds: holdFloorSeconds)
        controller.playTransient(notes: [note], velocity: velocity, durationSeconds: duration)
    }

    private func playRockStrum(
        character: Character,
        chord: ChordSymbol,
        tickInBar: Int,
        velocity: UInt8,
        intervalSeconds: Double,
        holdFloorSeconds: Double
    ) {
        let downstroke = tickInBar % 2 == 0

        if isVowel(character) {
            guard let note = pickNote(for: character, chord: chord) else { return }
            let baseDuration = min(0.45, max(0.10, intervalSeconds * 1.4))
            let duration = applyHoldDuration(baseDurationSeconds: baseDuration, holdFloorSeconds: holdFloorSeconds)
            controller.playTransient(notes: [note], velocity: velocity, durationSeconds: duration)
            return
        }

        let notes = chordNotes(for: chord).sorted()
        guard !notes.isEmpty else { return }

        let count = min(3, notes.count)
        let strumNotes: [UInt8]
        if downstroke {
            strumNotes = Array(notes.prefix(count))
        } else {
            strumNotes = Array(notes.suffix(count))
        }
        let baseDuration = max(0.10, intervalSeconds * 0.85)
        let duration = applyHoldDuration(baseDurationSeconds: baseDuration, holdFloorSeconds: holdFloorSeconds)
        controller.playChordHit(notes: strumNotes, velocity: velocity, durationSeconds: duration)
    }

    private func playPowerChug(
        character: Character,
        chord: ChordSymbol,
        tickInBar: Int,
        velocity: UInt8,
        intervalSeconds: Double,
        holdFloorSeconds: Double
    ) {
        _ = tickInBar
        let notes = chordNotes(for: chord).sorted()
        guard !notes.isEmpty else { return }

        let count = min(3, notes.count)
        let chugNotes = Array(notes.prefix(count))
        let baseDuration = max(0.06, intervalSeconds * 0.65)
        let duration = applyHoldDuration(baseDurationSeconds: baseDuration, holdFloorSeconds: holdFloorSeconds)
        controller.playChordHit(notes: chugNotes, velocity: velocity, durationSeconds: duration)
    }

    private func playSynthPulse(
        character: Character,
        chord: ChordSymbol,
        tickInBar: Int,
        barLength: Int,
        velocity: UInt8,
        intervalSeconds: Double,
        holdFloorSeconds: Double
    ) {
        let notes = pickingNotes(for: chord)
        guard notes.count >= 2 else { return }

        let bass = notes[0]
        let melodic = Array(notes.dropFirst())

        let bassStride = max(4, barLength / 4)
        if tickInBar % bassStride == 0 {
            let baseDuration = min(0.35, max(0.10, intervalSeconds * 1.2))
            let duration = applyHoldDuration(baseDurationSeconds: baseDuration, holdFloorSeconds: holdFloorSeconds)
            controller.playTransient(notes: [bass], velocity: velocity, durationSeconds: duration)
            return
        }

        let index = (characterIndex(character) + tickInBar) % melodic.count
        var note = melodic[index]
        if tickInBar % 2 == 1, note <= 115 {
            note = note + 12
        }
        let baseDuration = min(0.40, max(0.10, intervalSeconds * 1.2))
        let duration = applyHoldDuration(baseDurationSeconds: baseDuration, holdFloorSeconds: holdFloorSeconds)
        controller.playTransient(notes: [note], velocity: velocity, durationSeconds: duration)
    }

    private func balladStep(tickInBar: Int, barLength: Int) -> BalladStep {
        if barLength == 12 {
            let pattern: [BalladStep] = [
                .bass, .low, .mid,
                .high, .mid, .low,
                .bass, .low, .mid,
                .high, .mid, .low,
            ]
            return pattern[tickInBar % pattern.count]
        }

        if barLength == 16 {
            let beat: [BalladStep] = [.bass, .low, .mid, .high]
            return beat[tickInBar % beat.count]
        }

        let pattern: [BalladStep] = [.bass, .low, .high, .low]
        return pattern[tickInBar % pattern.count]
    }

    // MARK: - Picking helpers

    private enum PickingPool {
        case low
        case mid
        case high
    }

    private struct PickResult {
        var note: UInt8
        var pool: [UInt8]
    }

    private func pickFromPool(character: Character, chord: ChordSymbol, pool: PickingPool) -> PickResult? {
        let notes = pickingNotes(for: chord)
        guard notes.count >= 2 else { return notes.first.map { PickResult(note: $0, pool: [$0]) } }

        let melodic = Array(notes.dropFirst())
        guard !melodic.isEmpty else { return notes.first.map { PickResult(note: $0, pool: [$0]) } }

        let chosenPool: [UInt8]
        switch pool {
        case .low:
            let count = max(1, melodic.count / 2)
            chosenPool = Array(melodic.prefix(count))
        case .mid:
            let third = max(1, melodic.count / 3)
            let start = third
            let end = min(melodic.count, third * 2)
            chosenPool = Array(melodic[start..<end])
        case .high:
            let count = max(1, melodic.count / 2)
            chosenPool = Array(melodic.suffix(count))
        }

        let index = characterIndex(character) % chosenPool.count
        return PickResult(note: chosenPool[index], pool: chosenPool)
    }

    private func voiceLed(candidate: UInt8, pool: [UInt8], chordIndex: Int) -> UInt8 {
        guard !pool.isEmpty else { return candidate }

        if lastMelodyChordIndex != chordIndex {
            lastMelodyChordIndex = chordIndex
            lastMelodyNote = candidate
            return candidate
        }

        guard let last = lastMelodyNote else {
            lastMelodyNote = candidate
            return candidate
        }

        var best = candidate
        var bestDistance = abs(Int(candidate) - Int(last))
        for note in pool {
            let distance = abs(Int(note) - Int(last))
            if distance < bestDistance {
                best = note
                bestDistance = distance
            }
        }

        // Keep voice leading “gentle”: don’t fight large jumps.
        if bestDistance > 7 {
            lastMelodyNote = candidate
            return candidate
        }

        lastMelodyNote = best
        return best
    }

    private func ticksPerBar() -> Int {
        switch timingGrid {
        case .off:
            return 16
        case .eighths:
            return 8
        case .sixteenths:
            return 16
        case .triplets:
            return 12
        }
    }

    // MARK: - Picking

    private func pickNote(for character: Character, chord: ChordSymbol) -> UInt8? {
        let notes = pickingNotes(for: chord)
        guard notes.count >= 2 else { return notes.first }

        // Keep index 0 as the bass/root; letters live on the “upper strings”.
        let melodic = Array(notes.dropFirst())
        guard !melodic.isEmpty else { return notes.first }

        let pool: [UInt8]
        if isVowel(character) {
            let count = max(1, melodic.count / 2)
            pool = Array(melodic.suffix(count))
        } else {
            let count = max(1, melodic.count - melodic.count / 2)
            pool = Array(melodic.prefix(count))
        }

        let index = characterIndex(character) % pool.count
        return pool[index]
    }

    private func pickingNotes(for chord: ChordSymbol) -> [UInt8] {
        var notes = chordNotes(for: chord).sorted()
        guard notes.count >= 2 else { return notes }

        let upperCopies = notes.dropFirst().compactMap { note -> UInt8? in
            let up = Int(note) + 12
            guard up <= 127 else { return nil }
            return UInt8(up)
        }
        notes.append(contentsOf: upperCopies)
        return notes.uniquedSorted()
    }

    private func characterIndex(_ character: Character) -> Int {
        let lower = String(character).lowercased()
        guard let scalar = lower.unicodeScalars.first, scalar.isASCII else { return 0 }
        let value = Int(scalar.value)

        if value >= 97, value <= 122 { // a-z
            return value - 97
        }
        if value >= 48, value <= 57 { // 0-9
            return 26 + (value - 48)
        }
        return value
    }

    private func isVowel(_ character: Character) -> Bool {
        switch String(character).lowercased() {
        case "a", "e", "i", "o", "u":
            return true
        default:
            return false
        }
    }

    private func isUppercaseLetter(_ character: Character) -> Bool {
        let string = String(character)
        guard string.count == 1 else { return false }
        guard let scalar = string.unicodeScalars.first, scalar.isASCII else { return false }
        let value = Int(scalar.value)
        return value >= 65 && value <= 90
    }

    private func isBoundaryPunctuation(_ character: Character) -> Bool {
        switch character {
        case ",", "?", ";", ":", "|":
            return true
        default:
            return false
        }
    }

    // MARK: - Chord parsing

    private struct ChordSymbol: Equatable {
        enum Quality: Equatable {
            case major
            case minor
            case suspended2
            case suspended4
            case power
        }

        enum Seventh: Equatable {
            case minor7
            case major7
        }

        var root: PitchClass
        var quality: Quality
        var seventh: Seventh?
        var bass: PitchClass?
        var raw: String
    }

    func chordChartFromText(_ text: String) -> String {
        let tokens = chartTokenRanges(from: text)
        guard !tokens.isEmpty else { return "" }

        var result: [String] = []
        result.reserveCapacity(tokens.count)

        for token in tokens {
            if token.raw == "|" {
                result.append("|")
                continue
            }
            let cleaned = cleanChordToken(token.raw)
            guard let chord = parseChordSymbol(cleaned) else { continue }
            result.append(chord.raw)
        }

        return result.joined(separator: " ")
    }

    private func parseChartTokens(from text: String) -> [ChartToken] {
        let tokens = chartTokenRanges(from: text)
        guard !tokens.isEmpty else { return [] }

        var parsed: [ChartToken] = []
        parsed.reserveCapacity(tokens.count)

        for token in tokens {
            if token.raw == "|" { continue }
            let cleaned = cleanChordToken(token.raw)
            guard let chord = parseChordSymbol(cleaned) else { continue }
            parsed.append(ChartToken(chord: chord, raw: chord.raw, range: token.range))
        }

        return parsed
    }

    private func cleanChordToken(_ token: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var start = trimmed.startIndex
        var end = trimmed.endIndex

        while start < end, !isAllowedChordCharacter(trimmed[start]) {
            start = trimmed.index(after: start)
        }
        while end > start {
            let before = trimmed.index(before: end)
            guard !isAllowedChordCharacter(trimmed[before]) else { break }
            end = before
        }

        return String(trimmed[start..<end])
    }

    private func isAllowedChordCharacter(_ character: Character) -> Bool {
        if character == "#" || character == "b" || character == "/" {
            return true
        }
        return character.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }

    private struct RawTokenRange {
        var raw: String
        var range: NSRange
    }

    private func chartTokenRanges(from text: String) -> [RawTokenRange] {
        var ranges: [RawTokenRange] = []

        var tokenStart: String.Index?
        var index = text.startIndex

        func flushToken(endingAt end: String.Index) {
            guard let start = tokenStart else { return }
            let slice = text[start..<end]
            let raw = String(slice)
            let nsRange = NSRange(start..<end, in: text)
            ranges.append(RawTokenRange(raw: raw, range: nsRange))
            tokenStart = nil
        }

        while index < text.endIndex {
            let ch = text[index]
            if ch.isWhitespace {
                flushToken(endingAt: index)
            } else if tokenStart == nil {
                tokenStart = index
            }
            index = text.index(after: index)
        }

        flushToken(endingAt: text.endIndex)
        return ranges
    }

    private func parseChordSymbol(_ token: String) -> ChordSymbol? {
        let raw = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let parts = raw.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        let main = String(parts.first ?? "")
        let bassToken = parts.count == 2 ? String(parts[1]) : nil

        guard let (root, suffix) = parseRootAndSuffix(main) else { return nil }

        var quality: ChordSymbol.Quality = .major
        var seventh: ChordSymbol.Seventh?

        var rest = suffix
        if rest.hasPrefix("maj7") {
            quality = .major
            seventh = .major7
            rest.removeFirst(4)
        } else {
            if rest.hasPrefix("maj") {
                quality = .major
                rest.removeFirst(3)
            } else if rest.hasPrefix("min") {
                quality = .minor
                rest.removeFirst(3)
            } else if rest.hasPrefix("m") {
                quality = .minor
                rest.removeFirst(1)
            } else if rest.hasPrefix("sus2") {
                quality = .suspended2
                rest.removeFirst(4)
            } else if rest.hasPrefix("sus4") {
                quality = .suspended4
                rest.removeFirst(4)
            } else if rest.hasPrefix("sus") {
                quality = .suspended4
                rest.removeFirst(3)
            } else if rest.hasPrefix("5") {
                quality = .power
                rest.removeFirst(1)
            }

            if rest.hasPrefix("maj7") {
                seventh = .major7
                rest.removeFirst(4)
            } else if rest.hasPrefix("7") {
                seventh = .minor7
                rest.removeFirst(1)
            }
        }

        guard rest.isEmpty else { return nil }

        let bass = bassToken.flatMap { token -> PitchClass? in
            let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return nil }
            guard cleaned.count == ChordParsing.pitchClassPrefixLength(cleaned) else { return nil }
            return ChordParsing.parsePitchClassPrefix(cleaned)
        }

        return ChordSymbol(root: root, quality: quality, seventh: seventh, bass: bass, raw: raw)
    }

    private func parseRootAndSuffix(_ token: String) -> (root: PitchClass, suffix: String)? {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let root = ChordParsing.parsePitchClassPrefix(cleaned) else { return nil }
        let consumed = ChordParsing.pitchClassPrefixLength(cleaned)
        guard consumed <= cleaned.count else { return nil }
        let index = cleaned.index(cleaned.startIndex, offsetBy: consumed)
        return (root, String(cleaned[index...]).lowercased())
    }

    private func chordMidiRoot(pitchClass: PitchClass) -> Int {
        let eRaw = PitchClass.e.rawValue
        let delta = (pitchClass.rawValue - eRaw + 12) % 12
        return controller.baseMidiRoot - 12 + delta
    }

    private func chordNotes(for chord: ChordSymbol) -> [UInt8] {
        let rootMidi = chordMidiRoot(pitchClass: chord.root)
        let bassMidi = chord.bass.map { chordMidiRoot(pitchClass: $0) } ?? rootMidi

        if controller.powerChordModeIsOn || chord.quality == .power {
            let notes: [Int] = [bassMidi, rootMidi, rootMidi + 7, rootMidi + 12]
            return notes
                .filter { $0 >= 0 && $0 <= 127 }
                .map { UInt8($0) }
                .uniquedSorted()
        }

        let upperRoot = rootMidi + 12
        var triad: [Int]
        switch chord.quality {
        case .major:
            triad = [0, 4, 7]
        case .minor:
            triad = [0, 3, 7]
        case .suspended2:
            triad = [0, 2, 7]
        case .suspended4:
            triad = [0, 5, 7]
        case .power:
            triad = [0, 7, 12]
        }

        var notes: [Int] = [bassMidi]
        for interval in triad {
            notes.append(upperRoot + interval)
        }

        if let seventh = chord.seventh {
            let interval = seventh == .major7 ? 11 : 10
            notes.append(upperRoot + interval)
        }

        return notes
            .filter { $0 >= 0 && $0 <= 127 }
            .map { UInt8($0) }
            .uniquedSorted()
    }
}

private extension Array where Element == UInt8 {
    func uniquedSorted() -> [UInt8] {
        var seen: Set<UInt8> = []
        var result: [UInt8] = []
        result.reserveCapacity(count)
        for note in self.sorted() {
            if !seen.contains(note) {
                seen.insert(note)
                result.append(note)
            }
        }
        return result
    }
}
