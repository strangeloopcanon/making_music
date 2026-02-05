import AudioToolbox
import AVFoundation
import Foundation

final class SamplerAudioOutput: InstrumentSelectableOutput, SoundFontSelectableOutput {
    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()
    private let equalizer = AVAudioUnitEQ(numberOfBands: 3)
    private let reverb = AVAudioUnitReverb()
    private let distortion = AVAudioUnitDistortion()

    private(set) var instrument: Instrument = .piano
    private var soundFontURL: URL?

    var soundSourceDisplayName: String {
        guard let soundFontURL else { return "Built-in" }
        return soundFontURL.lastPathComponent
    }

    init() throws {
        engine.attach(sampler)
        engine.attach(equalizer)
        engine.attach(distortion)
        engine.attach(reverb)

        configureEQ()

        distortion.loadFactoryPreset(.multiDistortedCubed)
        distortion.wetDryMix = 0

        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 18

        engine.connect(sampler, to: equalizer, format: nil)
        engine.connect(equalizer, to: distortion, format: nil)
        engine.connect(distortion, to: reverb, format: nil)
        engine.connect(reverb, to: engine.mainMixerNode, format: nil)
        engine.mainMixerNode.outputVolume = 0.9

        setInstrument(.piano)
        engine.prepare()
        try engine.start()
    }

    func noteOn(note: UInt8, velocity: UInt8) {
        sampler.startNote(note, withVelocity: velocity, onChannel: 0)
    }

    func noteOff(note: UInt8) {
        sampler.stopNote(note, onChannel: 0)
    }

    func setInstrument(_ instrument: Instrument) {
        self.instrument = instrument
        switch instrument {
        case .piano:
            distortion.wetDryMix = 0
            reverb.wetDryMix = 18
        case .guitarClean:
            distortion.wetDryMix = 18
            reverb.wetDryMix = 10
        case .guitarOverdriven:
            distortion.wetDryMix = 35
            reverb.wetDryMix = 10
        case .guitarDistortion:
            distortion.wetDryMix = 55
            reverb.wetDryMix = 8
        }

        loadCurrentInstrument()
    }

    func useBuiltInSounds() {
        soundFontURL = nil
        loadCurrentInstrument()
    }

    func setSoundFont(url: URL) throws {
        let previous = soundFontURL
        soundFontURL = url
        do {
            try loadSoundBankInstrument(program: instrument.midiProgram)
        } catch {
            soundFontURL = previous
            loadCurrentInstrument()
            throw error
        }
    }

    private func loadCurrentInstrument() {
        do {
            try loadSoundBankInstrument(program: instrument.midiProgram)
        } catch {
            // Fail closed: keep the previous instrument loaded if a custom SoundFont fails.
            // (This avoids silent failure while playing.)
        }
    }

    private func loadSoundBankInstrument(program: UInt8) throws {
        guard let soundBankURL = soundBankURLToUse() else {
            throw NSError(domain: "making_music.soundbank", code: 1, userInfo: [NSLocalizedDescriptionKey: "No sound bank found."])
        }

        try sampler.loadSoundBankInstrument(
            at: soundBankURL,
            program: program,
            bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
            bankLSB: 0
        )
    }

    private func soundBankURLToUse() -> URL? {
        soundFontURL ?? appleGSSoundBankURL()
    }

    private func appleGSSoundBankURL() -> URL? {
        let candidates: [URL] = [
            URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls"),
        ]

        return candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }

    private func configureEQ() {
        equalizer.globalGain = 0

        let lowCut = equalizer.bands[0]
        lowCut.filterType = .highPass
        lowCut.frequency = 60
        lowCut.bypass = false

        let midDip = equalizer.bands[1]
        midDip.filterType = .parametric
        midDip.frequency = 320
        midDip.bandwidth = 1.1
        midDip.gain = -2.0
        midDip.bypass = false

        let presence = equalizer.bands[2]
        presence.filterType = .parametric
        presence.frequency = 2800
        presence.bandwidth = 0.8
        presence.gain = 2.0
        presence.bypass = false
    }
}
