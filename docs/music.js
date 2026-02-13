// music.js — Core music theory, note mapping, and voice-leading.
// Ported from MakingMusicCore (Swift).

const PITCH_CLASS_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

export function noteName(midi) {
    return `${PITCH_CLASS_NAMES[midi % 12]}${Math.floor(midi / 12) - 1}`;
}

export function pitchClassName(midi) {
    return PITCH_CLASS_NAMES[midi % 12];
}

// --- Scales ---

export const SCALES = {
    minorPentatonic: { name: 'Minor Pentatonic', offsets: [0, 3, 5, 7, 10] },
    blues:           { name: 'Blues',             offsets: [0, 3, 5, 6, 7, 10] },
    naturalMinor:    { name: 'Natural Minor',     offsets: [0, 2, 3, 5, 7, 8, 10] },
    major:           { name: 'Major',             offsets: [0, 2, 4, 5, 7, 9, 11] },
    majorPentatonic: { name: 'Major Pentatonic',  offsets: [0, 2, 4, 7, 9] },
};

export const SCALE_LIST = Object.keys(SCALES);

export function scalePitch(scale, degree) {
    const n = scale.offsets.length;
    if (n === 0) return 0;
    const oct = Math.floor(degree / n);
    let idx = degree % n;
    if (idx < 0) idx += n;
    return oct * 12 + scale.offsets[idx];
}

// --- Key layouts ---

export const KEY_LAYOUTS = {
    typewriterLinear: {
        name: 'Typewriter',
        keys: [
            'a','s','d','f','g','h','j','k','l',';',"'",
            'q','w','e','r','t','y','u','i','o','p',
            'z','x','c','v','b','n','m',',','.','/',
            '1','2','3','4','5','6','7','8','9','0','-','=',
        ],
    },
    melodic: {
        name: 'Melodic',
        keys: [
            'e','t','a','o','i','n','s','h','r','d','l',
            'c','u','m','w','f','g','y','p','b','v','k',
            'j','x','q','z',';',"'",',','.','/',
            '1','2','3','4','5','6','7','8','9','0','-','=',
        ],
    },
};

// Physical QWERTY rows (top to bottom) for the keyboard visualisation.
export const QWERTY_ROWS = [
    ['1','2','3','4','5','6','7','8','9','0','-','='],
    ['q','w','e','r','t','y','u','i','o','p'],
    ['a','s','d','f','g','h','j','k','l',';',"'"],
    ['z','x','c','v','b','n','m',',','.','/',],
];

// Map physical event.code → logical key character (immune to Alt/Option diacritics).
export const CODE_TO_KEY = {
    KeyA:'a',KeyB:'b',KeyC:'c',KeyD:'d',KeyE:'e',KeyF:'f',KeyG:'g',KeyH:'h',
    KeyI:'i',KeyJ:'j',KeyK:'k',KeyL:'l',KeyM:'m',KeyN:'n',KeyO:'o',KeyP:'p',
    KeyQ:'q',KeyR:'r',KeyS:'s',KeyT:'t',KeyU:'u',KeyV:'v',KeyW:'w',KeyX:'x',
    KeyY:'y',KeyZ:'z',
    Digit1:'1',Digit2:'2',Digit3:'3',Digit4:'4',Digit5:'5',
    Digit6:'6',Digit7:'7',Digit8:'8',Digit9:'9',Digit0:'0',
    Minus:'-',Equal:'=',
    Semicolon:';',Quote:"'",
    Comma:',',Period:'.',Slash:'/',
    BracketLeft:'[',BracketRight:']',
};

// --- Note mapper ---

export class NoteMapper {
    constructor(opts = {}) {
        this.mode = opts.mode ?? 'musical';           // 'musical' | 'chromatic'
        this.rootPitchClass = opts.rootPitchClass ?? 4; // E
        this.rootOctave = opts.rootOctave ?? 3;
        this.scale = opts.scale ?? SCALES.minorPentatonic;
        this.octaveOffset = opts.octaveOffset ?? 0;
        this.layout = opts.layout ?? KEY_LAYOUTS.typewriterLinear;
        this._buildIndex();
    }

    _buildIndex() {
        this._col = {};
        for (let i = 0; i < this.layout.keys.length; i++) {
            this._col[this.layout.keys[i]] = i;
        }
    }

    get baseMidi() {
        return (this.rootOctave + 1) * 12 + this.rootPitchClass + this.octaveOffset * 12;
    }

    midiNote(key) {
        const col = this._col[key];
        if (col === undefined) return null;
        const base = this.baseMidi;
        const raw = this.mode === 'musical'
            ? base + scalePitch(this.scale, col)
            : base + col;
        return (raw >= 0 && raw <= 127) ? raw : null;
    }

    setLayout(layout) {
        this.layout = layout;
        this._buildIndex();
    }
}

// --- Voice-leading ---

export const VoiceLeading = {
    nearestOctave(pitchClass, ref) {
        const pc = ((pitchClass % 12) + 12) % 12;
        let best = pc, bestD = Math.abs(pc - ref);
        for (let c = pc; c <= 127; c += 12) {
            const d = Math.abs(c - ref);
            if (d < bestD) { bestD = d; best = c; }
        }
        return Math.max(0, Math.min(127, best));
    },
    smooth(raw, ref) {
        if (ref == null) return raw;
        return this.nearestOctave(raw % 12, ref);
    },
};
