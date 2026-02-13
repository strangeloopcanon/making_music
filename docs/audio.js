// audio.js — FM-synthesis engine over Web Audio API.
// Polyphonic, with 3-band EQ (matching native app), reverb, distortion,
// and per-instrument presets. Piano instruments use dual FM operator
// pairs with detuning for a richer, warmer timbre.

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
// Presets with `rich: true` spawn a second FM carrier-modulator pair
// (4 operators total) for hammer-like attack shimmer and chorus warmth.

export const INSTRUMENTS = {
    grandPiano: {
        name: 'Grand Piano',
        carrier: 'sine', fmRatio: 2, fmDepth: 0.55,
        rich: true, richRatio: 7, richDepth: 0.22, richDetune: 3,
        attack: 0.003, decay: 0.7, sustain: 0.18, release: 0.55,
        filterFreq: 6500, filterQ: 0.5,
        distortion: 0, reverb: 0.32,
    },
    piano: {
        name: 'Piano',
        carrier: 'sine', fmRatio: 2, fmDepth: 0.5,
        rich: true, richRatio: 4, richDepth: 0.14, richDetune: 2,
        attack: 0.004, decay: 0.55, sustain: 0.22, release: 0.45,
        filterFreq: 5500, filterQ: 0.6,
        distortion: 0, reverb: 0.25,
    },
    electricPiano: {
        name: 'Electric Piano',
        carrier: 'sine', fmRatio: 7, fmDepth: 0.3,
        rich: true, richRatio: 14, richDepth: 0.08, richDetune: 4,
        attack: 0.003, decay: 0.65, sustain: 0.18, release: 0.5,
        filterFreq: 4000, filterQ: 0.9,
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
        rich: true, richRatio: 3, richDepth: 0.1, richDetune: 6,
        attack: 0.15, decay: 0.3, sustain: 0.7, release: 0.6,
        filterFreq: 1800, filterQ: 2,
        distortion: 0, reverb: 0.4,
    },
};

export const INSTRUMENT_LIST = Object.keys(INSTRUMENTS);

// --- Voice (single note) ---
// In "rich" mode two FM pairs are created:
//   Pair A (body):   carrier at freq,           mod at freq × fmRatio
//   Pair B (attack): carrier at freq + detune,  mod at freq × richRatio
// Pair B is quieter and its modulation depth decays faster, giving a
// bright hammer-like transient that melts into the warm body.

class Voice {
    constructor(ctx, midi, velocity, preset, output) {
        this.ctx = ctx;
        this._stopped = false;

        const freq = midiToFreq(midi);
        const vel = (velocity / 127) * 0.45;
        const now = ctx.currentTime;

        // Shared lowpass filter
        this._filter = ctx.createBiquadFilter();
        this._filter.type = 'lowpass';
        this._filter.frequency.value = preset.filterFreq;
        this._filter.Q.value = preset.filterQ;
        // Bright attack → darker sustain (mimics piano hammer damping)
        this._filter.frequency.setValueAtTime(preset.filterFreq * 1.6, now);
        this._filter.frequency.exponentialRampToValueAtTime(
            preset.filterFreq, now + preset.decay * 0.6
        );

        // Shared amplitude envelope
        this._env = ctx.createGain();
        this._env.gain.value = 0;
        this._filter.connect(this._env);
        this._env.connect(output);

        this._oscs = [];

        // --- Pair A: body ---
        this._buildPair(ctx, freq, now, preset.carrier,
            freq * preset.fmRatio, freq * preset.fmDepth,
            preset.decay, 0, 1.0);

        // --- Pair B: attack shimmer (rich presets only) ---
        if (preset.rich) {
            this._buildPair(ctx, freq, now, 'sine',
                freq * preset.richRatio, freq * preset.richDepth,
                preset.decay * 0.35, preset.richDetune, 0.35);
        }

        this._vel = vel;
        this._preset = preset;
    }

    // Build one carrier-modulator pair and wire it into this._filter.
    _buildPair(ctx, freq, now, carrType, modFreq, depth, decayTime, detuneCents, level) {
        const mod = ctx.createOscillator();
        mod.type = 'sine';
        mod.frequency.value = modFreq;

        const modGain = ctx.createGain();
        modGain.gain.setValueAtTime(depth * 3.5, now);
        modGain.gain.exponentialRampToValueAtTime(
            Math.max(0.001, depth * 0.1), now + decayTime + 0.15
        );
        mod.connect(modGain);

        const carr = ctx.createOscillator();
        carr.type = carrType;
        carr.frequency.value = freq;
        if (detuneCents) carr.detune.value = detuneCents;
        modGain.connect(carr.frequency);

        if (level < 1.0) {
            const g = ctx.createGain();
            g.gain.value = level;
            carr.connect(g);
            g.connect(this._filter);
        } else {
            carr.connect(this._filter);
        }

        this._oscs.push(mod, carr);
    }

    start() {
        const now = this.ctx.currentTime;
        const { attack, decay, sustain } = this._preset;
        this._env.gain.setValueAtTime(0.0001, now);
        this._env.gain.linearRampToValueAtTime(this._vel, now + attack);
        this._env.gain.linearRampToValueAtTime(this._vel * sustain, now + attack + decay);
        for (const osc of this._oscs) osc.start(now);
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
        for (const osc of this._oscs) osc.stop(stop);
    }

    kill() {
        if (this._stopped) return;
        this._stopped = true;
        for (const osc of this._oscs) {
            try { osc.stop(); } catch (_) { /* already stopped */ }
        }
    }
}

// --- Audio engine ---
// Signal chain (matches native app architecture):
//   Voices → Bus → EQ (3-band) → Distortion → Dry + Reverb → Master → Compressor → Out

export class AudioEngine {
    constructor() {
        this.ctx = null;
        this._voices = new Map();
        this.instrument = 'grandPiano';
    }

    init() {
        if (this.ctx) return;
        this.ctx = new (window.AudioContext || window.webkitAudioContext)();

        // --- Final output ---
        this._comp = this.ctx.createDynamicsCompressor();
        this._comp.threshold.value = -18;
        this._comp.knee.value = 8;
        this._comp.ratio.value = 5;
        this._comp.connect(this.ctx.destination);

        this._master = this.ctx.createGain();
        this._master.gain.value = 0.6;
        this._master.connect(this._comp);

        // --- Reverb (convolver with synthesised room impulse) ---
        this._reverb = this._makeReverb();
        this._reverbSend = this.ctx.createGain();
        this._reverbSend.gain.value = 0.32;
        this._reverbSend.connect(this._reverb);
        this._reverb.connect(this._master);

        // --- Dry path ---
        this._dry = this.ctx.createGain();
        this._dry.gain.value = 0.68;
        this._dry.connect(this._master);

        // --- Distortion ---
        this._dist = this.ctx.createWaveShaper();
        this._dist.oversample = '4x';
        this._dist.curve = softClipCurve(0);
        this._distOut = this.ctx.createGain();
        this._distOut.gain.value = 1;
        this._dist.connect(this._distOut);
        this._distOut.connect(this._dry);
        this._distOut.connect(this._reverbSend);

        // --- 3-band EQ (matching native app) ---
        // Band 1: high-pass at 60 Hz – removes rumble
        this._eqHP = this.ctx.createBiquadFilter();
        this._eqHP.type = 'highpass';
        this._eqHP.frequency.value = 60;
        this._eqHP.Q.value = 0.7;

        // Band 2: parametric dip at 320 Hz, −2 dB – reduces mud
        this._eqMid = this.ctx.createBiquadFilter();
        this._eqMid.type = 'peaking';
        this._eqMid.frequency.value = 320;
        this._eqMid.Q.value = 1.1;
        this._eqMid.gain.value = -2;

        // Band 3: parametric boost at 2.8 kHz, +2 dB – adds presence
        this._eqPres = this.ctx.createBiquadFilter();
        this._eqPres.type = 'peaking';
        this._eqPres.frequency.value = 2800;
        this._eqPres.Q.value = 0.8;
        this._eqPres.gain.value = 2;

        this._eqHP.connect(this._eqMid);
        this._eqMid.connect(this._eqPres);
        this._eqPres.connect(this._dist);

        // --- Voice bus ---
        this._bus = this.ctx.createGain();
        this._bus.gain.value = 1;
        this._bus.connect(this._eqHP);

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
        const p = INSTRUMENTS[this.instrument] ?? INSTRUMENTS.grandPiano;
        this._reverbSend.gain.value = p.reverb;
        this._dry.gain.value = 1 - p.reverb;
        this._dist.curve = p.distortion > 0
            ? softClipCurve(p.distortion)
            : softClipCurve(0);
    }

    noteOn(midi, velocity = 80) {
        this.init();
        this.resume();
        this.noteOff(midi);
        const p = INSTRUMENTS[this.instrument] ?? INSTRUMENTS.grandPiano;
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

    // Synthesise a room impulse response.
    // Longer tail (3 s) with exponential decay and gentle high-frequency
    // roll-off so the reverb sounds warm rather than hissy.
    _makeReverb() {
        const dur = 3.0;
        const rate = this.ctx.sampleRate;
        const len = Math.floor(rate * dur);
        const buf = this.ctx.createBuffer(2, len, rate);

        for (let ch = 0; ch < 2; ch++) {
            const d = buf.getChannelData(ch);
            for (let i = 0; i < len; i++) {
                const t = i / rate;
                const env = Math.exp(-3.5 * t / dur);
                d[i] = (Math.random() * 2 - 1) * env;
            }
            // Three averaging passes → crude lowpass that darkens the tail
            // (real rooms absorb high frequencies over distance).
            for (let pass = 0; pass < 4; pass++) {
                for (let i = 1; i < len - 1; i++) {
                    d[i] = (d[i - 1] + d[i] * 2 + d[i + 1]) * 0.25;
                }
            }
        }

        const conv = this.ctx.createConvolver();
        conv.buffer = buf;
        return conv;
    }
}
