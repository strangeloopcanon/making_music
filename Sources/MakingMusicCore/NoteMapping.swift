public enum NoteMappingMode: String, CaseIterable, Sendable {
    case musical
    case chromatic
}

public enum PitchClass: Int, CaseIterable, Sendable, CustomStringConvertible {
    case c = 0
    case cSharp = 1
    case d = 2
    case dSharp = 3
    case e = 4
    case f = 5
    case fSharp = 6
    case g = 7
    case gSharp = 8
    case a = 9
    case aSharp = 10
    case b = 11

    public var description: String {
        switch self {
        case .c: return "C"
        case .cSharp: return "C#"
        case .d: return "D"
        case .dSharp: return "D#"
        case .e: return "E"
        case .f: return "F"
        case .fSharp: return "F#"
        case .g: return "G"
        case .gSharp: return "G#"
        case .a: return "A"
        case .aSharp: return "A#"
        case .b: return "B"
        }
    }
}

public struct RootNote: Equatable, Sendable, CustomStringConvertible {
    public var pitchClass: PitchClass
    public var octave: Int

    public init(pitchClass: PitchClass, octave: Int) {
        self.pitchClass = pitchClass
        self.octave = octave
    }

    public var midiNumber: Int {
        // Scientific pitch notation, where C4 = 60 and C-1 = 0.
        (octave + 1) * 12 + pitchClass.rawValue
    }

    public var description: String {
        "\(pitchClass)\(octave)"
    }
}

public struct Scale: Equatable, Sendable {
    public var name: String
    public var semitoneOffsets: [Int]

    public init(name: String, semitoneOffsets: [Int]) {
        self.name = name
        self.semitoneOffsets = semitoneOffsets
    }

    public func pitch(forDegree degree: Int) -> Int {
        guard !semitoneOffsets.isEmpty else { return 0 }
        let count = semitoneOffsets.count
        let octave = degree / count
        let index = degree % count
        // Handle negative degrees correctly
        if index < 0 {
             let wrappedIndex = (index + count) % count
             let wrappedOctave = (degree + 1) / count - 1
             return (wrappedOctave * 12) + semitoneOffsets[wrappedIndex]
        }
        return (octave * 12) + semitoneOffsets[index]
    }

    public static let minorPentatonic = Scale(
        name: "Minor Pentatonic",
        semitoneOffsets: [0, 3, 5, 7, 10]
    )

    public static let blues = Scale(
        name: "Blues",
        semitoneOffsets: [0, 3, 5, 6, 7, 10]
    )

    public static let naturalMinor = Scale(
        name: "Natural Minor",
        semitoneOffsets: [0, 2, 3, 5, 7, 8, 10]
    )

    public static let major = Scale(
        name: "Major",
        semitoneOffsets: [0, 2, 4, 5, 7, 9, 11]
    )

    public static let majorPentatonic = Scale(
        name: "Major Pentatonic",
        semitoneOffsets: [0, 2, 4, 7, 9]
    )

    public static let builtins: [Scale] = [
        .minorPentatonic,
        .blues,
        .naturalMinor,
        .major,
        .majorPentatonic,
    ]
}

public struct KeyLayout: Equatable, Sendable {
    public var name: String
    public var rows: [[String]]
    private var keyToPosition: [String: (row: Int, col: Int)]

    public init(name: String, rows: [[String]]) {
        self.name = name
        self.rows = rows

        var mapping: [String: (row: Int, col: Int)] = [:]
        for (rowIndex, row) in rows.enumerated() {
            for (colIndex, key) in row.enumerated() {
                mapping[key.lowercased()] = (rowIndex, colIndex)
            }
        }
        self.keyToPosition = mapping
    }

    public func position(forKey key: String) -> (row: Int, col: Int)? {
        keyToPosition[key.lowercased()]
    }

    public static let qwertyRows = KeyLayout(
        name: "QWERTY Rows",
        rows: [
            ["z", "x", "c", "v", "b", "n", "m", ",", ".", "/"],
            ["a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'"],
            ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
            ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="]
        ]
    )

    // Linear order optimized for typing flow (home row first).
    // This powers the default "typewriter instrument" behavior.
    public static let typewriterLinear = KeyLayout(
        name: "Typewriter Linear",
        rows: [
            [
                "a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'",
                "q", "w", "e", "r", "t", "y", "u", "i", "o", "p",
                "z", "x", "c", "v", "b", "n", "m", ",", ".", "/",
                "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=",
            ]
        ]
    )

    // Letters ordered by English frequency, then punctuation, then numbers.
    // Common letters cluster in a narrow pitch range, producing melodic
    // output from natural typing when combined with voice-leading.
    public static let melodic = KeyLayout(
        name: "Melodic",
        rows: [
            [
                "e", "t", "a", "o", "i", "n", "s", "h", "r", "d", "l",
                "c", "u", "m", "w", "f", "g", "y", "p", "b", "v", "k",
                "j", "x", "q", "z", ";", "'", ",", ".", "/",
                "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=",
            ]
        ]
    )

    public static func == (lhs: KeyLayout, rhs: KeyLayout) -> Bool {
        lhs.name == rhs.name && lhs.rows == rhs.rows
    }
}

public enum VoiceLeading {
    /// Find the octave of `pitchClass` (0-11) closest to `reference` MIDI note.
    /// Returns a MIDI note number (0-127).
    public static func nearestOctave(pitchClass: Int, to reference: Int) -> Int {
        let pc = ((pitchClass % 12) + 12) % 12
        var best = pc
        var bestDistance = abs(pc - reference)

        var candidate = pc
        while candidate <= 127 {
            let distance = abs(candidate - reference)
            if distance < bestDistance {
                bestDistance = distance
                best = candidate
            }
            candidate += 12
        }

        return max(0, min(127, best))
    }

    /// Voice-lead a raw MIDI note toward `reference` by finding the nearest
    /// octave of the same pitch class. Returns the raw note unchanged if
    /// `reference` is nil.
    public static func smooth(rawNote: UInt8, reference: UInt8?) -> UInt8 {
        guard let ref = reference else { return rawNote }
        let pitchClass = Int(rawNote) % 12
        let result = nearestOctave(pitchClass: pitchClass, to: Int(ref))
        return UInt8(max(0, min(127, result)))
    }
}

public struct NoteMapper: Equatable, Sendable {
    public var mode: NoteMappingMode
    public var root: RootNote
    public var scale: Scale
    public var octaveOffset: Int
    public var rowOffset: Int // In degrees (musical) or semitones (chromatic)
    public var keyLayout: KeyLayout

    public init(
        mode: NoteMappingMode,
        root: RootNote,
        scale: Scale,
        octaveOffset: Int = 0,
        rowOffset: Int = 5, // Default to a "Fourth" (approx 5 semitones or degrees depending on mode)
        keyLayout: KeyLayout = .qwertyRows
    ) {
        self.mode = mode
        self.root = root
        self.scale = scale
        self.octaveOffset = octaveOffset
        self.rowOffset = rowOffset
        self.keyLayout = keyLayout
    }

    public func midiNoteNumber(forKey key: String) -> Int? {
        guard let (row, col) = keyLayout.position(forKey: key) else { return nil }

        let base = root.midiNumber + octaveOffset * 12
        switch mode {
        case .musical:
            // rowOffset is in scale degrees.
            // For a Pentatonic scale (5 notes), a 4th is 3 steps, a 5th is 4 steps, Octave is 5 steps.
            // Let's assume the user passes a reasonable "degree" offset.
            // If rowOffset is 0, it behaves like a really long piano.
            let totalDegree = (row * rowOffset) + col
            return base + scale.pitch(forDegree: totalDegree)
        case .chromatic:
            // rowOffset is in semitones.
            return base + (row * rowOffset) + col
        }
    }

    public func midiNote(forKey key: String) -> UInt8? {
        guard let midi = midiNoteNumber(forKey: key) else { return nil }
        if midi < 0 || midi > 127 { return nil }
        return UInt8(midi)
    }
}
