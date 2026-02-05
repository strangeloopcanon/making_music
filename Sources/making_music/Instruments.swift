import Foundation

enum Instrument: String, CaseIterable, Sendable {
    case piano = "Piano"
    case guitarClean = "Guitar (Clean)"
    case guitarOverdriven = "Guitar (Overdriven)"
    case guitarDistortion = "Guitar (Distortion)"

    // AVAudioUnitSampler uses General MIDI program numbers with 0 = Acoustic Grand Piano.
    var midiProgram: UInt8 {
        switch self {
        case .piano:
            return 0
        case .guitarClean:
            return 27 // GM 28: Electric Guitar (clean)
        case .guitarOverdriven:
            return 29 // GM 30: Overdriven Guitar
        case .guitarDistortion:
            return 30 // GM 31: Distortion Guitar
        }
    }
}

protocol InstrumentSelectableOutput: NoteOutput {
    var instrument: Instrument { get }
    func setInstrument(_ instrument: Instrument)
}

protocol SoundFontSelectableOutput: NoteOutput {
    var soundSourceDisplayName: String { get }
    func useBuiltInSounds()
    func setSoundFont(url: URL) throws
}
