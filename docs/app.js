// app.js — Main application: state, keyboard handling, UI, presets.

import {
    NoteMapper, VoiceLeading, SCALES, SCALE_LIST,
    KEY_LAYOUTS, QWERTY_ROWS, CODE_TO_KEY,
    noteName, pitchClassName,
} from './music.js';
import { AudioEngine, INSTRUMENTS, INSTRUMENT_LIST } from './audio.js';

// --- Presets ---

const PRESETS = {
    grandPiano: {
        name: 'Grand Piano',
        instrument: 'grandPiano',
        scale: 'naturalMinor',
        layout: 'melodic',
        voiceLead: true,
        powerChords: false,
    },
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
    babaOrgan: {
        name: "Baba Organ Pulse",
        instrument: 'organ',
        scale: 'major',
        layout: 'typewriterLinear',
        voiceLead: false,
        powerChords: false,
    },
    stairwayAcoustic: {
        name: 'Stairway Acoustic Picker',
        instrument: 'guitarAcoustic',
        scale: 'naturalMinor',
        layout: 'typewriterLinear',
        voiceLead: false,
        powerChords: false,
    },
};

const PRESET_LIST = Object.keys(PRESETS);

// --- Guided song trainer ---

function repeat(items, count) {
    return Array.from({ length: count }, () => items).flat();
}

function keyedSteps(cueText, seeds) {
    const cues = cueText.toLowerCase().replace(/[^a-z0-9]/g, '').split('');
    return seeds.map((seed, index) => ({
        ...seed,
        key: cues[index % cues.length],
        beats: seed.beats ?? 0.5,
        kind: seed.kind ?? 'note',
        accent: seed.accent ?? false,
    }));
}

const SONGS = {
    none: {
        name: 'Song trainer...',
        sections: [],
    },
    babaORiley: {
        name: "Baba O'Riley",
        preset: 'babaOrgan',
        tempoBPM: 118,
        instructions: 'Type the highlighted cue key. Correct keys play the next pulse or chord; wrong keys do nothing.',
        sections: [
            {
                title: 'Keyboard pulse',
                summary: 'F, C, and Bb pulse shapes',
                steps: keyedSteps('babaoriley', repeat([
                    { label: 'F4', notes: [65], accent: true },
                    { label: 'C5', notes: [72] },
                    { label: 'F5', notes: [77] },
                    { label: 'C5', notes: [72] },
                    { label: 'C4', notes: [60], accent: true },
                    { label: 'G4', notes: [67] },
                    { label: 'C5', notes: [72] },
                    { label: 'G4', notes: [67] },
                    { label: 'Bb3', notes: [58], accent: true },
                    { label: 'F4', notes: [65] },
                    { label: 'Bb4', notes: [70] },
                    { label: 'F4', notes: [65] },
                    { label: 'F4', notes: [65], accent: true },
                    { label: 'C5', notes: [72] },
                    { label: 'F5', notes: [77] },
                    { label: 'C5', notes: [72] },
                ], 2)),
            },
            {
                title: 'Big chord landings',
                summary: 'Wide F, C, and Bb hits',
                steps: keyedSteps('babaoriley', [
                    { label: 'F', notes: [53, 60, 65, 69], kind: 'chord', beats: 1, accent: true },
                    { label: 'C', notes: [48, 55, 60, 64], kind: 'chord', beats: 1 },
                    { label: 'Bb', notes: [46, 53, 58, 62], kind: 'chord', beats: 1, accent: true },
                    { label: 'F', notes: [53, 60, 65, 69], kind: 'chord', beats: 1 },
                    { label: 'C', notes: [48, 55, 60, 64], kind: 'chord', beats: 1 },
                    { label: 'Bb', notes: [46, 53, 58, 62], kind: 'chord', beats: 1, accent: true },
                ]),
            },
        ],
    },
    stairwayToHeaven: {
        name: 'Stairway to Heaven',
        preset: 'stairwayAcoustic',
        tempoBPM: 82,
        instructions: 'Type the highlighted cue key. Correct keys play the next picked note or landing chord.',
        sections: [
            {
                title: 'Opening arpeggio walk',
                summary: 'Am, descending bass, F, G, and back to Am',
                steps: keyedSteps('stairwaytoheaven', [
                    { label: 'A3', notes: [57], accent: true },
                    { label: 'C4', notes: [60] },
                    { label: 'E4', notes: [64] },
                    { label: 'A4', notes: [69] },
                    { label: 'G#3', notes: [56], accent: true },
                    { label: 'C4', notes: [60] },
                    { label: 'E4', notes: [64] },
                    { label: 'A4', notes: [69] },
                    { label: 'G3', notes: [55], accent: true },
                    { label: 'C4', notes: [60] },
                    { label: 'E4', notes: [64] },
                    { label: 'G4', notes: [67] },
                    { label: 'F#3', notes: [54], accent: true },
                    { label: 'A3', notes: [57] },
                    { label: 'D4', notes: [62] },
                    { label: 'F#4', notes: [66] },
                    { label: 'F3', notes: [53], accent: true },
                    { label: 'A3', notes: [57] },
                    { label: 'C4', notes: [60] },
                    { label: 'E4', notes: [64] },
                    { label: 'G3', notes: [55], accent: true },
                    { label: 'B3', notes: [59] },
                    { label: 'D4', notes: [62] },
                    { label: 'G4', notes: [67] },
                    { label: 'A3', notes: [57], accent: true },
                    { label: 'C4', notes: [60] },
                    { label: 'E4', notes: [64] },
                    { label: 'A4', notes: [69] },
                ]),
            },
            {
                title: 'Chord landings',
                summary: 'The same walk as slower shapes',
                steps: keyedSteps('stairway', [
                    { label: 'Am', notes: [45, 52, 57, 60, 64], kind: 'chord', beats: 1.25, accent: true },
                    { label: 'G#/Am', notes: [44, 52, 57, 60, 64], kind: 'chord', beats: 1.25 },
                    { label: 'C/G', notes: [43, 52, 55, 60, 64], kind: 'chord', beats: 1.25 },
                    { label: 'D/F#', notes: [42, 57, 62, 66], kind: 'chord', beats: 1.25 },
                    { label: 'Fmaj7', notes: [41, 57, 60, 64], kind: 'chord', beats: 1.25, accent: true },
                    { label: 'G', notes: [43, 55, 59, 62], kind: 'chord', beats: 1.25 },
                    { label: 'Am', notes: [45, 52, 57, 60, 64], kind: 'chord', beats: 1.5, accent: true },
                ]),
            },
        ],
    },
};

const SONG_LIST = Object.keys(SONGS);

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
        this.songId = 'none';
        this.songStepIndex = 0;
        this.trainerFeedback = '';

        this.held = new Set();          // key chars currently down
        this.heldNotes = new Map();     // key → Set<midi>
        this.activeNotes = new Set();   // all midi notes sounding (for viz)

        this._setupUI();
        this._setupKeyboard();
        this._applyPreset('grandPiano');
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

        if (this._handleGuidedKeyDown(e)) {
            return;
        }

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

    _handleGuidedKeyDown(e) {
        const song = this._currentSong();
        if (!song) return false;

        const key = CODE_TO_KEY[e.code];
        if (!key) return false;

        e.preventDefault();

        const step = this._currentSongStep();
        if (!step) return false;

        if (key !== step.key) {
            this.trainerFeedback = `Typed ${key.toUpperCase()}. Next key is ${step.key.toUpperCase()} for ${step.label}.`;
            this._renderTrainer();
            this._renderStatus();
            return true;
        }

        this._playSongStep(step, song);
        this.trainerFeedback = `Played ${step.label}.`;
        this._advanceSongStep();
        this._renderKeyboard();
        this._renderTrainer();
        this._renderStatus();
        return true;
    }

    _currentSong() {
        const song = SONGS[this.songId];
        return song && song.sections.length ? song : null;
    }

    _flatSongSteps(song = this._currentSong()) {
        if (!song) return [];
        return song.sections.flatMap((section, sectionIndex) =>
            section.steps.map((step, sectionStepIndex) => ({
                ...step,
                sectionTitle: section.title,
                sectionIndex,
                sectionStepIndex,
                sectionStepCount: section.steps.length,
            }))
        );
    }

    _currentSongStep() {
        const steps = this._flatSongSteps();
        return steps[this.songStepIndex] ?? null;
    }

    _playSongStep(step, song) {
        const velocity = Math.min(127, step.accent ? 104 : 84);
        const beatMs = 60000 / Math.max(40, song.tempoBPM ?? 100);
        const durationMs = Math.max(90, Math.min(2500, beatMs * Math.max(0.25, step.beats ?? 0.5) * 0.9));

        for (const note of step.notes) {
            this.audio.noteOn(note, velocity);
            this.activeNotes.add(note);
        }

        window.setTimeout(() => {
            for (const note of step.notes) {
                this.audio.noteOff(note);
                this.activeNotes.delete(note);
            }
            this._renderKeyboard();
        }, durationMs);
    }

    _advanceSongStep() {
        const steps = this._flatSongSteps();
        if (!steps.length) {
            this.songStepIndex = 0;
            return;
        }
        this.songStepIndex += 1;
        if (this.songStepIndex >= steps.length) {
            this.songStepIndex = 0;
            this.trainerFeedback = 'Finished. Looping from the top.';
        }
    }

    _songSentence(steps = this._flatSongSteps()) {
        return steps.map(step => step.key).join('');
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
        this._renderTrainer();
    }

    _applySong(id) {
        this.songId = id;
        this.songStepIndex = 0;
        this.trainerFeedback = '';

        const song = SONGS[id];
        if (song?.preset) {
            this._applyPreset(song.preset);
        }

        this._$song.value = id;
        this._renderStatus();
        this._renderKeyboard();
        this._renderTrainer();
    }

    _restartSong() {
        this.songStepIndex = 0;
        this.trainerFeedback = this._currentSong() ? 'Restarted from the top.' : '';
        this._renderStatus();
        this._renderKeyboard();
        this._renderTrainer();
    }

    // --- UI setup ---

    _setupUI() {
        this._$status = document.getElementById('status');
        this._$armBtn = document.getElementById('arm-btn');
        this._$preset = document.getElementById('preset');
        this._$instrument = document.getElementById('instrument');
        this._$scale = document.getElementById('scale');
        this._$layout = document.getElementById('layout');
        this._$song = document.getElementById('song');
        this._$restartSong = document.getElementById('restart-song');
        this._$trainer = document.getElementById('trainer');
        this._$voiceLead = document.getElementById('voice-lead');
        this._$powerChords = document.getElementById('power-chords');
        this._$keyboard = document.getElementById('keyboard');

        // Populate selects
        this._populateSelect(this._$preset, PRESET_LIST.map(k => [k, PRESETS[k].name]));
        this._populateSelect(this._$instrument, INSTRUMENT_LIST.map(k => [k, INSTRUMENTS[k].name]));
        this._populateSelect(this._$scale, SCALE_LIST.map(k => [k, SCALES[k].name]));
        this._populateSelect(this._$layout, Object.keys(KEY_LAYOUTS).map(k => [k, KEY_LAYOUTS[k].name]));
        this._populateSelect(this._$song, SONG_LIST.map(k => [k, SONGS[k].name]));

        // Listeners
        this._$armBtn.addEventListener('click', () => this.toggleArmed());
        this._$preset.addEventListener('change', () => this._applyPreset(this._$preset.value));
        this._$song.addEventListener('change', () => this._applySong(this._$song.value));
        this._$restartSong.addEventListener('click', () => this._restartSong());
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
        this._renderTrainer();
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
        const cueStep = this._currentSongStep();
        for (const ch of Object.keys(this._keyCaps)) {
            const { el, noteEl } = this._keyCaps[ch];
            const midi = this.mapper.midiNote(ch);
            const isCue = cueStep?.key === ch;
            noteEl.textContent = isCue ? cueStep.label : (midi !== null ? pitchClassName(midi) : '');
            el.classList.toggle('active', this.held.has(ch));
            el.classList.toggle('armed', this.armed);
            el.classList.toggle('cue', isCue);
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
        const song = this._currentSong();
        if (song) {
            const step = this._currentSongStep();
            parts.push(`${song.name}: ${step ? `${step.key.toUpperCase()} -> ${step.label}` : 'ready'}`);
        }
        this._$status.textContent = parts.join('  ·  ');
        this._$armBtn.textContent = this.armed ? '⏸ Pause' : '▶ Play';
        this._$armBtn.classList.toggle('armed', this.armed);
    }

    _renderTrainer() {
        const song = this._currentSong();
        if (!song) {
            this._$trainer.innerHTML = `<span class="trainer-muted">Pick Baba O'Riley or Stairway to Heaven from Song, press Play, then type the highlighted key.</span>`;
            return;
        }

        const steps = this._flatSongSteps(song);
        const step = steps[this.songStepIndex];
        if (!step) {
            this._$trainer.textContent = '';
            return;
        }

        const upcoming = steps.slice(this.songStepIndex, this.songStepIndex + 18)
            .map((s, index) => `<span class="${index === 0 ? 'next' : ''}">${s.key.toUpperCase()}:${s.label}</span>`)
            .join('');
        const fullSentence = this._songSentence(steps);
        const remainingSentence = this._songSentence(steps.slice(this.songStepIndex));

        this._$trainer.innerHTML = `
            <div class="trainer-title">${song.name}</div>
            <div class="trainer-line">${song.instructions}</div>
            <div class="trainer-line">No compound keys: type only the letters in the sentence. The note after ':' is what the app plays.</div>
            <div class="trainer-sentence"><span>Full sentence</span><code>${fullSentence}</code></div>
            <div class="trainer-sentence"><span>Remaining</span><code>${remainingSentence}</code></div>
            <div class="trainer-line">Now: ${step.sectionTitle} ${step.sectionStepIndex + 1}/${step.sectionStepCount}</div>
            <div class="trainer-next">Next key <kbd>${step.key.toUpperCase()}</kbd> plays ${step.label}</div>
            <div class="trainer-cues">${upcoming}</div>
            <div class="trainer-feedback">${this.trainerFeedback || '&nbsp;'}</div>
        `;
    }
}

// Boot
window.addEventListener('DOMContentLoaded', () => new App());
