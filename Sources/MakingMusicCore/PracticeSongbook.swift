import Foundation

public enum PracticeTone: String, Sendable {
    case piano
    case acousticGuitar
    case organ
    case overdrivenGuitar
    case distortionGuitar
}

public struct PracticeStep: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case note
        case chord
    }

    public var cueKey: String
    public var label: String
    public var midiNotes: [UInt8]
    public var beats: Double
    public var kind: Kind
    public var accent: Bool

    public init(
        cueKey: String,
        label: String,
        midiNotes: [UInt8],
        beats: Double = 0.5,
        kind: Kind = .note,
        accent: Bool = false
    ) {
        self.cueKey = cueKey
        self.label = label
        self.midiNotes = midiNotes
        self.beats = beats
        self.kind = kind
        self.accent = accent
    }
}

public struct PracticeArrangementSection: Equatable, Sendable {
    public var title: String
    public var summary: String
    public var steps: [PracticeStep]

    public init(title: String, summary: String, steps: [PracticeStep]) {
        self.title = title
        self.summary = summary
        self.steps = steps
    }

    public var cueSentence: String {
        steps.map(\.cueKey).joined()
    }
}

public struct PracticeArrangement: Equatable, Sendable {
    public var id: String
    public var title: String
    public var recommendedTone: PracticeTone
    public var tempoBPM: Int
    public var instructions: String
    public var sections: [PracticeArrangementSection]

    public init(
        id: String,
        title: String,
        recommendedTone: PracticeTone,
        tempoBPM: Int,
        instructions: String,
        sections: [PracticeArrangementSection]
    ) {
        self.id = id
        self.title = title
        self.recommendedTone = recommendedTone
        self.tempoBPM = tempoBPM
        self.instructions = instructions
        self.sections = sections
    }

    public var cueSentence: String {
        sections.flatMap(\.steps).map(\.cueKey).joined()
    }
}

public enum PracticeSongbook {
    public static let arrangements: [PracticeArrangement] = [
        babaORiley,
        stairwayToHeaven,
    ]

    public static func arrangement(id: String) -> PracticeArrangement? {
        arrangements.first { $0.id == id }
    }

    public static let babaORiley = PracticeArrangement(
        id: "baba-o-riley",
        title: "Baba O'Riley",
        recommendedTone: .organ,
        tempoBPM: 118,
        instructions: "Type the cue letters in order. The app turns each correct key into the next pulse or chord.",
        sections: [
            PracticeArrangementSection(
                title: "Keyboard pulse",
                summary: "A four-chord pulse built from F, C, and Bb shapes.",
                steps: keyedSteps(
                    cueText: "babaoriley",
                    seeds: repeated([
                        .note("F4", [midi(.f, 4)], accent: true),
                        .note("C5", [midi(.c, 5)]),
                        .note("F5", [midi(.f, 5)]),
                        .note("C5", [midi(.c, 5)]),
                        .note("C4", [midi(.c, 4)], accent: true),
                        .note("G4", [midi(.g, 4)]),
                        .note("C5", [midi(.c, 5)]),
                        .note("G4", [midi(.g, 4)]),
                        .note("Bb3", [midi(.aSharp, 3)], accent: true),
                        .note("F4", [midi(.f, 4)]),
                        .note("Bb4", [midi(.aSharp, 4)]),
                        .note("F4", [midi(.f, 4)]),
                        .note("F4", [midi(.f, 4)], accent: true),
                        .note("C5", [midi(.c, 5)]),
                        .note("F5", [midi(.f, 5)]),
                        .note("C5", [midi(.c, 5)]),
                    ], count: 2)
                )
            ),
            PracticeArrangementSection(
                title: "Big chord landings",
                summary: "Use this after the pulse when you want the wide rock-band hits.",
                steps: keyedSteps(
                    cueText: "babaoriley",
                    seeds: [
                        .chord("F", [midi(.f, 3), midi(.c, 4), midi(.f, 4), midi(.a, 4)], beats: 1.0, accent: true),
                        .chord("C", [midi(.c, 3), midi(.g, 3), midi(.c, 4), midi(.e, 4)], beats: 1.0),
                        .chord("Bb", [midi(.aSharp, 2), midi(.f, 3), midi(.aSharp, 3), midi(.d, 4)], beats: 1.0, accent: true),
                        .chord("F", [midi(.f, 3), midi(.c, 4), midi(.f, 4), midi(.a, 4)], beats: 1.0),
                        .chord("C", [midi(.c, 3), midi(.g, 3), midi(.c, 4), midi(.e, 4)], beats: 1.0),
                        .chord("Bb", [midi(.aSharp, 2), midi(.f, 3), midi(.aSharp, 3), midi(.d, 4)], beats: 1.0, accent: true),
                    ]
                )
            ),
        ]
    )

    public static let stairwayToHeaven = PracticeArrangement(
        id: "stairway-to-heaven",
        title: "Stairway to Heaven",
        recommendedTone: .acousticGuitar,
        tempoBPM: 82,
        instructions: "Type the cue letters in order. Each correct key plays the next picked note or landing chord.",
        sections: [
            PracticeArrangementSection(
                title: "Opening arpeggio walk",
                summary: "A slow picked walk through Am, descending bass, F, G, and back to Am.",
                steps: keyedSteps(
                    cueText: "stairwaytoheaven",
                    seeds: [
                        .note("A3", [midi(.a, 3)], accent: true),
                        .note("C4", [midi(.c, 4)]),
                        .note("E4", [midi(.e, 4)]),
                        .note("A4", [midi(.a, 4)]),
                        .note("G#3", [midi(.gSharp, 3)], accent: true),
                        .note("C4", [midi(.c, 4)]),
                        .note("E4", [midi(.e, 4)]),
                        .note("A4", [midi(.a, 4)]),
                        .note("G3", [midi(.g, 3)], accent: true),
                        .note("C4", [midi(.c, 4)]),
                        .note("E4", [midi(.e, 4)]),
                        .note("G4", [midi(.g, 4)]),
                        .note("F#3", [midi(.fSharp, 3)], accent: true),
                        .note("A3", [midi(.a, 3)]),
                        .note("D4", [midi(.d, 4)]),
                        .note("F#4", [midi(.fSharp, 4)]),
                        .note("F3", [midi(.f, 3)], accent: true),
                        .note("A3", [midi(.a, 3)]),
                        .note("C4", [midi(.c, 4)]),
                        .note("E4", [midi(.e, 4)]),
                        .note("G3", [midi(.g, 3)], accent: true),
                        .note("B3", [midi(.b, 3)]),
                        .note("D4", [midi(.d, 4)]),
                        .note("G4", [midi(.g, 4)]),
                        .note("A3", [midi(.a, 3)], accent: true),
                        .note("C4", [midi(.c, 4)]),
                        .note("E4", [midi(.e, 4)]),
                        .note("A4", [midi(.a, 4)]),
                    ]
                )
            ),
            PracticeArrangementSection(
                title: "Chord landings",
                summary: "The same movement as bigger, slower shapes once the picking pattern is under your fingers.",
                steps: keyedSteps(
                    cueText: "stairway",
                    seeds: [
                        .chord("Am", [midi(.a, 2), midi(.e, 3), midi(.a, 3), midi(.c, 4), midi(.e, 4)], beats: 1.25, accent: true),
                        .chord("G#/Am", [midi(.gSharp, 2), midi(.e, 3), midi(.a, 3), midi(.c, 4), midi(.e, 4)], beats: 1.25),
                        .chord("C/G", [midi(.g, 2), midi(.e, 3), midi(.g, 3), midi(.c, 4), midi(.e, 4)], beats: 1.25),
                        .chord("D/F#", [midi(.fSharp, 2), midi(.a, 3), midi(.d, 4), midi(.fSharp, 4)], beats: 1.25),
                        .chord("Fmaj7", [midi(.f, 2), midi(.a, 3), midi(.c, 4), midi(.e, 4)], beats: 1.25, accent: true),
                        .chord("G", [midi(.g, 2), midi(.g, 3), midi(.b, 3), midi(.d, 4)], beats: 1.25),
                        .chord("Am", [midi(.a, 2), midi(.e, 3), midi(.a, 3), midi(.c, 4), midi(.e, 4)], beats: 1.5, accent: true),
                    ]
                )
            ),
        ]
    )

    private enum Pitch: Int {
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
    }

    private struct StepSeed {
        var label: String
        var midiNotes: [UInt8]
        var beats: Double
        var kind: PracticeStep.Kind
        var accent: Bool

        static func note(_ label: String, _ midiNotes: [UInt8], beats: Double = 0.5, accent: Bool = false) -> StepSeed {
            StepSeed(label: label, midiNotes: midiNotes, beats: beats, kind: .note, accent: accent)
        }

        static func chord(_ label: String, _ midiNotes: [UInt8], beats: Double = 1.0, accent: Bool = false) -> StepSeed {
            StepSeed(label: label, midiNotes: midiNotes, beats: beats, kind: .chord, accent: accent)
        }
    }

    private static func midi(_ pitch: Pitch, _ octave: Int) -> UInt8 {
        UInt8((octave + 1) * 12 + pitch.rawValue)
    }

    private static func repeated(_ seeds: [StepSeed], count: Int) -> [StepSeed] {
        guard count > 0 else { return [] }
        return (0..<count).flatMap { _ in seeds }
    }

    private static func keyedSteps(cueText: String, seeds: [StepSeed]) -> [PracticeStep] {
        let cueKeys = cueText.lowercased().unicodeScalars.compactMap { scalar -> String? in
            guard CharacterSet.alphanumerics.contains(scalar) else { return nil }
            return String(Character(scalar))
        }
        guard !cueKeys.isEmpty else { return [] }

        return seeds.enumerated().map { index, seed in
            PracticeStep(
                cueKey: cueKeys[index % cueKeys.count],
                label: seed.label,
                midiNotes: seed.midiNotes,
                beats: seed.beats,
                kind: seed.kind,
                accent: seed.accent
            )
        }
    }
}
