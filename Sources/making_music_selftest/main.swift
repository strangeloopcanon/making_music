import Foundation
import MakingMusicCore

@inline(__always)
func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

@inline(__always)
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fail("\(message) (actual: \(actual), expected: \(expected))")
    }
}

@inline(__always)
func expectTrue(_ condition: Bool, _ message: String) {
    guard condition else {
        fail(message)
    }
}

let root = RootNote(pitchClass: .e, octave: 3)
expectEqual(root.midiNumber, 52, "RootNote E3 should be MIDI 52")

let musical = NoteMapper(mode: .musical, root: root, scale: .minorPentatonic)
expectEqual(musical.midiNoteNumber(forKey: "z"), 52, "Musical z")
expectEqual(musical.midiNoteNumber(forKey: "x"), 55, "Musical x")
expectEqual(musical.midiNoteNumber(forKey: "c"), 57, "Musical c")
expectEqual(musical.midiNoteNumber(forKey: "v"), 59, "Musical v")
expectEqual(musical.midiNoteNumber(forKey: "b"), 62, "Musical b")
expectEqual(musical.midiNoteNumber(forKey: "n"), 64, "Musical n")

let chromatic = NoteMapper(mode: .chromatic, root: root, scale: .minorPentatonic)
expectEqual(chromatic.midiNoteNumber(forKey: "z"), 52, "Chromatic z")
expectEqual(chromatic.midiNoteNumber(forKey: "x"), 53, "Chromatic x")
expectEqual(chromatic.midiNoteNumber(forKey: "c"), 54, "Chromatic c")

let typewriterMusical = NoteMapper(
    mode: .musical,
    root: root,
    scale: .minorPentatonic,
    keyLayout: .typewriterLinear
)
expectEqual(typewriterMusical.midiNoteNumber(forKey: "a"), 52, "Typewriter a")
expectEqual(typewriterMusical.midiNoteNumber(forKey: "s"), 55, "Typewriter s")
expectEqual(typewriterMusical.midiNoteNumber(forKey: "d"), 57, "Typewriter d")
expectEqual(typewriterMusical.midiNoteNumber(forKey: "f"), 59, "Typewriter f")

// Chord parsing coverage
expectEqual(ChordParsing.parsePitchClassPrefix("C"), .c, "Chord parsing C")
expectEqual(ChordParsing.parsePitchClassPrefix("F#"), .fSharp, "Chord parsing F#")
expectEqual(ChordParsing.parsePitchClassPrefix("Bb"), .aSharp, "Chord parsing Bb")
expectEqual(ChordParsing.pitchClassPrefixLength("A"), 1, "Chord prefix length A")
expectEqual(ChordParsing.pitchClassPrefixLength("F#maj7"), 2, "Chord prefix length F#")

if let parsed = ChordParsing.parseRootAndBass("D/F#") {
    expectEqual(parsed.root, .d, "Slash chord root")
    expectEqual(parsed.bass, .fSharp, "Slash chord bass")
    expectEqual(parsed.raw, "D/F#", "Slash chord raw token")
} else {
    fail("Expected slash chord parsing to succeed")
}

expectTrue(ChordParsing.parseRootAndBass("") == nil, "Empty chord token should fail parsing")

// Text rhythm hold semantics: never wrap across script loop boundary.
expectEqual(TextRhythm.holdRunLength(after: 0, in: Array("a--b-")), 2, "Hold run from first char")
expectEqual(TextRhythm.holdRunLength(after: 3, in: Array("a--b-")), 1, "Hold run near end")
expectEqual(TextRhythm.holdRunLength(after: 2, in: Array("--a")), 0, "Hold run does not wrap")
expectEqual(
    TextRhythm.holdRunLength(after: 0, in: Array("a__b"), holdCharacters: ["-", "_"]),
    2,
    "Hold run supports alternate hold characters"
)

print("ok")
