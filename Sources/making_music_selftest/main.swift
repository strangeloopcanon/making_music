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

// Melodic layout: keys ordered by English letter frequency.
let melodicMusical = NoteMapper(
    mode: .musical,
    root: root,
    scale: .naturalMinor,
    keyLayout: .melodic
)
// E natural minor: E F# G A B C D = offsets [0, 2, 3, 5, 7, 8, 10]
expectEqual(melodicMusical.midiNoteNumber(forKey: "e"), 52, "Melodic e (degree 0, E3)")
expectEqual(melodicMusical.midiNoteNumber(forKey: "t"), 54, "Melodic t (degree 1, F#3)")
expectEqual(melodicMusical.midiNoteNumber(forKey: "a"), 55, "Melodic a (degree 2, G3)")
expectEqual(melodicMusical.midiNoteNumber(forKey: "o"), 57, "Melodic o (degree 3, A3)")
expectEqual(melodicMusical.midiNoteNumber(forKey: "i"), 59, "Melodic i (degree 4, B3)")
expectEqual(melodicMusical.midiNoteNumber(forKey: "n"), 60, "Melodic n (degree 5, C4)")
expectEqual(melodicMusical.midiNoteNumber(forKey: "s"), 62, "Melodic s (degree 6, D4)")
expectEqual(melodicMusical.midiNoteNumber(forKey: "h"), 64, "Melodic h (degree 7, E4)")

// Voice-leading: nearest octave of a pitch class to a reference note.
expectEqual(VoiceLeading.nearestOctave(pitchClass: 4, to: 60), 64, "VL: E nearest to C4=60 → E4=64")
expectEqual(VoiceLeading.nearestOctave(pitchClass: 4, to: 50), 52, "VL: E nearest to D3=50 → E3=52")
expectEqual(VoiceLeading.nearestOctave(pitchClass: 4, to: 64), 64, "VL: E nearest to E4=64 → E4=64")
expectEqual(VoiceLeading.nearestOctave(pitchClass: 0, to: 60), 60, "VL: C nearest to C4=60 → C4=60")
expectEqual(VoiceLeading.nearestOctave(pitchClass: 7, to: 52), 55, "VL: G nearest to E3=52 → G3=55")

// Voice-leading smooth helper.
expectEqual(VoiceLeading.smooth(rawNote: 79, reference: 55), 55, "VL smooth: raw G5=79 → G3=55 near ref 55")
expectEqual(VoiceLeading.smooth(rawNote: 52, reference: nil), 52, "VL smooth: nil reference returns raw")

print("ok")
