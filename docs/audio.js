// audio.js — FM-synthesis engine over Web Audio API.
// Polyphonic, with reverb, distortion, and per-instrument presets.

function midiToFreq(midi) {
    return 440 * Math.pow(2, (midi - 69) / 12);
}

function softClipCurve(amount) {
    const k = amount * 100;
    const n = 44100;
    const curve = new Float32Array(n);
    for (let i = 0; i < n; i++) {
        const x = (i * 2) / n - 1;
        curve[i] = ((1 + k) * x) / (1 + k * Math.abs(x));
    }
    return curve;
}

// --- Instrument presets ---

export const INSTRUMENTS = {
    piano: {
        name: 'Piano',
        carrier: 'triangle', fmRatio: 2, fmDepth: 0.7,
        attack: 0.005, decay: 0.5, sustain: 0.25, release: 0.45,
        filterFreq: 5000, filterQ: 0.7,
        distortion: 0, reverb: 0.28,
    },
    electricPiano: {
        name: 'Electric Piano',
        carrier: 'sine', fmRatio: 7, fmDepth: 0.35,
        attack: 0.003, decay: 0.6, sustain: 0.2, release: 0.5,
        filterFreq: 3500, filterQ: 1,
        distortion: 0, reverb: 0.3,
    },
    guitarClean: {
        name: 'Guitar (Clean)',
        carrier: 'sawtooth', fmRatio: 3, fmDepth: 0.15,
        attack: 0.003, decay: 0.2, sustain: 0.35, release: 0.2,
        filterFreq: 3000, filterQ: 2,
        distortion: 0.12, reverb: 0.14,
    },
    guitarOverdriven: {
        name: 'Guitar (Overdriven)',
        carrier: 'sawtooth', fmRatio: 1, fmDepth: 0.4,
        attack: 0.002, decay: 0.15, sustain: 0.5, release: 0.15,
        filterFreq: 2400, filterQ: 3,
        distortion: 0.4, reverb: 0.1,
    },
    guitarDistortion: {
        name: 'Guitar (Distortion)',
        carrier: 'sawtooth', fmRatio: 1, fmDepth: 0.6,
        attack: 0.001, decay: 0.1, sustain: 0.6, release: 0.1,
        filterFreq: 2000, filterQ: 4,
        distortion: 0.6, reverb: 0.08,
    },
    synthPad: {
        name: 'Synth Pad',
        carrier: 'sawtooth', fmRatio: 2, fmDepth: 0.2,
        attack: 0.15, decay: 0.3, sustain: 0.7, release: 0.6,
        filterFreq: 1800, filterQ: 2,
        distortion: 0, reverb: 0.4,
    },
};

export const INSTRUMENT_LIST = Object.keys(INSTRUMENTS);

// --- Voice (single note) ---

class Voice {
    constructor(ctx, midi, velocity, preset, output) {
        this.ctx = ctx;
        this._stopped = false;
        this._output = output;

        const freq = midiToFreq(midi);
        const vel = (velocity / 127) * 0.45;

        // Modulator → carrier (FM pair)
        this._mod = ctx.createOscillator();
        this._mod.type = 'sine';
        this._mod.frequency.value = freq * preset.fmRatio;

        this._modGain = ctx.createGain();
        const depthNow = freq * preset.fmDepth;
        const now = ctx.currentTime;
        this._modGain.gain.setValueAtTime(depthNow * 3, now);
        this._modGain.gain.exponentialRampToValueAtTime(
            Math.max(0.001, depthNow * 0.15),
            now + preset.decay + 0.15
        );

        this._carrier = ctx.createOscillator();
        this._carrier.type = preset.carrier;
        this._carrier.frequency.value = freq;

        // Filter
        this._filter = ctx.createBiquadFilter();
        this._filter.type = 'lowpass';
        this._filter.frequency.value = preset.filterFreq;
        this._filter.Q.value = preset.filterQ;

        // Amplitude envelope
        this._env = ctx.createGain();
        this._env.gain.value = 0;

        // Patch: mod → carrier.freq → filter → envelope → output
        this._mod.connect(this._modGain);
        this._modGain.connect(this._carrier.frequency);
        this._carrier.connect(this._filter);
        this._filter.connect(this._env);
        this._env.connect(this._output);

        this._vel = vel;
        this._preset = preset;
    }

    start() {
        const now = this.ctx.currentTime;
        const { attack, decay, sustain } = this._preset;
        this._env.gain.setValueAtTime(0.0001, now);
        this._env.gain.linearRampToValueAtTime(this._vel, now + attack);
        this._env.gain.linearRampToValueAtTime(this._vel * sustain, now + attack + decay);
        this._mod.start(now);
        this._carrier.start(now);
    }

    release() {
        if (this._stopped) return;
        this._stopped = true;
        const now = this.ctx.currentTime;
        const rel = this._preset.release;
        this._env.gain.cancelScheduledValues(now);
        this._env.gain.setValueAtTime(this._env.gain.value, now);
        this._env.gain.linearRampToValueAtTime(0, now + rel);
        const stop = now + rel + 0.05;
        this._carrier.stop(stop);
        this._mod.stop(stop);
    }

    kill() {
        if (this._stopped) return;
        this._stopped = true;
        try { this._carrier.stop(); } catch (_) { /* */ }
        try { this._mod.stop(); } catch (_) { /* */ }
    }
}

// --- Audio engine ---

export class AudioEngine {
    constructor() {
        this.ctx = null;
        this._voices = new Map();
        this.instrument = 'piano';
    }

    init() {
        if (this.ctx) return;
        this.ctx = new (window.AudioContext || window.webkitAudioContext)();

        // Compressor → destination
        this._comp = this.ctx.createDynamicsCompressor();
        this._comp.threshold.value = -20;
        this._comp.knee.value = 10;
        this._comp.ratio.value = 6;
        this._comp.connect(this.ctx.destination);

        // Master gain
        this._master = this.ctx.createGain();
        this._master.gain.value = 0.55;
        this._master.connect(this._comp);

        // Reverb (convolver with synthesised impulse)
        this._reverb = this._makeReverb(2.2, 2.5);
        this._reverbSend = this.ctx.createGain();
        this._reverbSend.gain.value = 0.28;
        this._reverbSend.connect(this._reverb);
        this._reverb.connect(this._master);

        // Dry
        this._dry = this.ctx.createGain();
        this._dry.gain.value = 0.72;
        this._dry.connect(this._master);

        // Distortion → shared bus
        this._dist = this.ctx.createWaveShaper();
        this._dist.oversample = '4x';
        this._dist.curve = softClipCurve(0);
        this._distOut = this.ctx.createGain();
        this._distOut.gain.value = 1;
        this._dist.connect(this._distOut);
        this._distOut.connect(this._dry);
        this._distOut.connect(this._reverbSend);

        // Voice bus (all notes → dist → dry/reverb → master)
        this._bus = this.ctx.createGain();
        this._bus.gain.value = 1;
        this._bus.connect(this._dist);

        this._applyInstrument();
    }

    resume() {
        if (this.ctx?.state === 'suspended') this.ctx.resume();
    }

    setInstrument(name) {
        this.instrument = name;
        if (this.ctx) this._applyInstrument();
    }

    _applyInstrument() {
        const p = INSTRUMENTS[this.instrument] ?? INSTRUMENTS.piano;
        this._reverbSend.gain.value = p.reverb;
        this._dry.gain.value = 1 - p.reverb;
        this._dist.curve = p.distortion > 0 ? softClipCurve(p.distortion) : softClipCurve(0);
    }

    noteOn(midi, velocity = 80) {
        this.init();
        this.resume();
        this.noteOff(midi);
        const p = INSTRUMENTS[this.instrument] ?? INSTRUMENTS.piano;
        const v = new Voice(this.ctx, midi, velocity, p, this._bus);
        v.start();
        this._voices.set(midi, v);
    }

    noteOff(midi) {
        const v = this._voices.get(midi);
        if (!v) return;
        v.release();
        this._voices.delete(midi);
    }

    panic() {
        for (const v of this._voices.values()) v.kill();
        this._voices.clear();
    }

    _makeReverb(dur, decay) {
        const len = this.ctx.sampleRate * dur;
        const buf = this.ctx.createBuffer(2, len, this.ctx.sampleRate);
        for (let ch = 0; ch < 2; ch++) {
            const d = buf.getChannelData(ch);
            for (let i = 0; i < len; i++) {
                d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, decay);
            }
        }
        const conv = this.ctx.createConvolver();
        conv.buffer = buf;
        return conv;
    }
}
