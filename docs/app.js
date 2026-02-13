// app.js — Main application: state, keyboard handling, UI, presets.

import {
    NoteMapper, VoiceLeading, SCALES, SCALE_LIST,
    KEY_LAYOUTS, QWERTY_ROWS, CODE_TO_KEY,
    noteName, pitchClassName,
} from './music.js';
import { AudioEngine, INSTRUMENTS, INSTRUMENT_LIST } from './audio.js';

// --- Presets ---

const PRESETS = {
    melodicPiano: {
        name: 'Melodic Piano',
        instrument: 'piano',
        scale: 'naturalMinor',
        layout: 'melodic',
        voiceLead: true,
        powerChords: false,
    },
    melodicRock: {
        name: 'Melodic Rock',
        instrument: 'guitarOverdriven',
        scale: 'blues',
        layout: 'melodic',
        voiceLead: true,
        powerChords: true,
    },
    prettyPiano: {
        name: 'Pretty Piano',
        instrument: 'piano',
        scale: 'majorPentatonic',
        layout: 'typewriterLinear',
        voiceLead: false,
        powerChords: false,
    },
    rockGuitar: {
        name: 'Rock Guitar',
        instrument: 'guitarDistortion',
        scale: 'minorPentatonic',
        layout: 'typewriterLinear',
        voiceLead: false,
        powerChords: true,
    },
    electricPiano: {
        name: 'Electric Piano',
        instrument: 'electricPiano',
        scale: 'major',
        layout: 'melodic',
        voiceLead: true,
        powerChords: false,
    },
    synthPad: {
        name: 'Synth Pad',
        instrument: 'synthPad',
        scale: 'naturalMinor',
        layout: 'melodic',
        voiceLead: true,
        powerChords: false,
    },
};

const PRESET_LIST = Object.keys(PRESETS);

// --- App ---

class App {
    constructor() {
        this.audio = new AudioEngine();
        this.mapper = new NoteMapper();

        this.armed = false;
        this.voiceLead = false;
        this.powerChords = false;
        this.lastVLNote = null;
        this.octaveOffset = 0;

        this.held = new Set();          // key chars currently down
        this.heldNotes = new Map();     // key → Set<midi>
        this.activeNotes = new Set();   // all midi notes sounding (for viz)

        this._setupUI();
        this._setupKeyboard();
        this._applyPreset('melodicPiano');
    }

    // --- Keyboard handling ---

    _setupKeyboard() {
        document.addEventListener('keydown', e => this._onKeyDown(e));
        document.addEventListener('keyup', e => this._onKeyUp(e));
    }

    _onKeyDown(e) {
        if (e.repeat) return;

        // Always handle these regardless of arm state
        if (e.code === 'Enter') {
            e.preventDefault();
            this.toggleArmed();
            return;
        }
        if (e.code === 'Escape') {
            e.preventDefault();
            this.panic();
            return;
        }
        if (e.code === 'BracketLeft') {
            e.preventDefault();
            this._shiftOctave(-1);
            return;
        }
        if (e.code === 'BracketRight') {
            e.preventDefault();
            this._shiftOctave(1);
            return;
        }

        if (!this.armed) return;

        // Resolve physical key → character
        const key = CODE_TO_KEY[e.code];
        if (!key) return;
        if (this.held.has(key)) return;

        const rawNote = this.mapper.midiNote(key);
        if (rawNote === null) return;

        e.preventDefault();

        // Voice-leading
        let note = this.voiceLead
            ? VoiceLeading.smooth(rawNote, this.lastVLNote)
            : rawNote;

        // Modifiers
        if (e.shiftKey && note <= 115) note += 12;
        if (e.altKey   && note >= 12)  note -= 12;

        // Build chord
        const notes = new Set([note]);
        if (this.powerChords || e.ctrlKey || e.metaKey) {
            if (note <= 120) notes.add(note + 7);  // fifth
            if (note <= 115) notes.add(note + 12);  // octave
        }

        // Velocity from typing cadence
        const vel = this._velocity();

        this.held.add(key);
        this.heldNotes.set(key, notes);
        for (const n of notes) {
            this.audio.noteOn(n, vel);
            this.activeNotes.add(n);
        }
        this.lastVLNote = note;
        this._renderKeyboard();
    }

    _onKeyUp(e) {
        const key = CODE_TO_KEY[e.code];
        if (!key || !this.held.has(key)) return;

        const notes = this.heldNotes.get(key);
        if (notes) {
            for (const n of notes) {
                this.audio.noteOff(n);
                this.activeNotes.delete(n);
            }
        }
        this.held.delete(key);
        this.heldNotes.delete(key);
        this._renderKeyboard();
    }

    _lastTs = performance.now();

    _velocity() {
        const now = performance.now();
        const delta = now - this._lastTs;
        this._lastTs = now;
        // Fast typing → louder, slow → softer, centred around 85
        const speed = Math.max(0, Math.min(1, 1 - delta / 400));
        return Math.round(65 + speed * 50);
    }

    // --- State ---

    toggleArmed() {
        this.armed = !this.armed;
        if (!this.armed) this.panic();
        this.audio.init();
        this.audio.resume();
        this._renderStatus();
        this._renderKeyboard();
    }

    panic() {
        this.audio.panic();
        this.held.clear();
        this.heldNotes.clear();
        this.activeNotes.clear();
        this.lastVLNote = null;
        this._renderKeyboard();
    }

    _shiftOctave(dir) {
        this.octaveOffset = Math.max(-3, Math.min(3, this.octaveOffset + dir));
        this.mapper.octaveOffset = this.octaveOffset;
        this._renderStatus();
        this._renderKeyboard();
    }

    // --- Preset / control changes ---

    _applyPreset(id) {
        const p = PRESETS[id];
        if (!p) return;

        this.audio.setInstrument(p.instrument);
        this.mapper.scale = SCALES[p.scale];
        this.mapper.setLayout(KEY_LAYOUTS[p.layout]);
        this.voiceLead = p.voiceLead;
        this.powerChords = p.powerChords;
        this.lastVLNote = null;

        // Sync controls
        this._$preset.value = id;
        this._$instrument.value = p.instrument;
        this._$scale.value = p.scale;
        this._$layout.value = p.layout;
        this._$voiceLead.checked = p.voiceLead;
        this._$powerChords.checked = p.powerChords;

        this._renderStatus();
        this._renderKeyboard();
    }

    // --- UI setup ---

    _setupUI() {
        this._$status = document.getElementById('status');
        this._$armBtn = document.getElementById('arm-btn');
        this._$preset = document.getElementById('preset');
        this._$instrument = document.getElementById('instrument');
        this._$scale = document.getElementById('scale');
        this._$layout = document.getElementById('layout');
        this._$voiceLead = document.getElementById('voice-lead');
        this._$powerChords = document.getElementById('power-chords');
        this._$keyboard = document.getElementById('keyboard');

        // Populate selects
        this._populateSelect(this._$preset, PRESET_LIST.map(k => [k, PRESETS[k].name]));
        this._populateSelect(this._$instrument, INSTRUMENT_LIST.map(k => [k, INSTRUMENTS[k].name]));
        this._populateSelect(this._$scale, SCALE_LIST.map(k => [k, SCALES[k].name]));
        this._populateSelect(this._$layout, Object.keys(KEY_LAYOUTS).map(k => [k, KEY_LAYOUTS[k].name]));

        // Listeners
        this._$armBtn.addEventListener('click', () => this.toggleArmed());
        this._$preset.addEventListener('change', () => this._applyPreset(this._$preset.value));
        this._$instrument.addEventListener('change', () => {
            this.audio.setInstrument(this._$instrument.value);
        });
        this._$scale.addEventListener('change', () => {
            this.mapper.scale = SCALES[this._$scale.value];
            this.lastVLNote = null;
            this._renderKeyboard();
        });
        this._$layout.addEventListener('change', () => {
            this.mapper.setLayout(KEY_LAYOUTS[this._$layout.value]);
            this.lastVLNote = null;
            this._renderKeyboard();
        });
        this._$voiceLead.addEventListener('change', () => {
            this.voiceLead = this._$voiceLead.checked;
            this.lastVLNote = null;
        });
        this._$powerChords.addEventListener('change', () => {
            this.powerChords = this._$powerChords.checked;
        });

        this._buildKeyboard();
        this._renderStatus();
    }

    _populateSelect(el, items) {
        el.innerHTML = '';
        for (const [value, label] of items) {
            const opt = document.createElement('option');
            opt.value = value;
            opt.textContent = label;
            el.appendChild(opt);
        }
    }

    // --- Keyboard visualisation ---

    _buildKeyboard() {
        this._$keyboard.innerHTML = '';
        this._keyCaps = {};

        const ROW_OFFSETS = [0, 0.5, 0.8, 1.3]; // em-based stagger

        for (let r = 0; r < QWERTY_ROWS.length; r++) {
            const row = document.createElement('div');
            row.className = 'kb-row';
            row.style.paddingLeft = `${ROW_OFFSETS[r] * 3.4}rem`;

            for (const ch of QWERTY_ROWS[r]) {
                const cap = document.createElement('div');
                cap.className = 'key-cap';
                cap.dataset.key = ch;

                const label = document.createElement('span');
                label.className = 'key-label';
                label.textContent = ch.length === 1 ? ch.toUpperCase() : ch;

                const noteLabel = document.createElement('span');
                noteLabel.className = 'key-note';

                cap.appendChild(label);
                cap.appendChild(noteLabel);
                row.appendChild(cap);

                this._keyCaps[ch] = { el: cap, noteEl: noteLabel };
            }
            this._$keyboard.appendChild(row);
        }
    }

    _renderKeyboard() {
        for (const ch of Object.keys(this._keyCaps)) {
            const { el, noteEl } = this._keyCaps[ch];
            const midi = this.mapper.midiNote(ch);
            noteEl.textContent = midi !== null ? pitchClassName(midi) : '';
            el.classList.toggle('active', this.held.has(ch));
            el.classList.toggle('armed', this.armed);
        }
    }

    _renderStatus() {
        const parts = [];
        if (this.armed) {
            parts.push('Playing');
        } else {
            parts.push('Paused — press Enter or click Play');
        }
        if (this.octaveOffset !== 0) {
            parts.push(`Oct ${this.octaveOffset > 0 ? '+' : ''}${this.octaveOffset}`);
        }
        this._$status.textContent = parts.join('  ·  ');
        this._$armBtn.textContent = this.armed ? '⏸ Pause' : '▶ Play';
        this._$armBtn.classList.toggle('armed', this.armed);
    }
}

// Boot
window.addEventListener('DOMContentLoaded', () => new App());
