# making_music

Turn your Mac keyboard into a playable instrument. Press keys to play riffs, type chord symbols to hit chord changes, and use the on-screen touchpad pad for expressive slides. Piano is the default, with a few guitar‑ish sounds built in.

## Quick Start

```bash
make setup
make run
```

Then:

1. Click the app window.
2. Press `Cmd+Enter` until the status says `ARMED`.
3. In **Keys** mode, press `z x c v b n m , . /` to play notes (the on-screen key map shows what each key plays).
4. Pick a guitar sound from **Instrument** if you want.

## How To Play

### Keys Mode (play like an instrument)

- **What it is:** QWERTY → notes (and optionally power chords).
- **Scale Lock vs All Notes:**
  - **Scale Lock:** quantizes to a scale (good for “rock-safe” playing).
  - **All Notes:** every semitone (better for “I need specific notes”).
- **Range (Row jump / Octave):**
  - **Row jump:** how far each QWERTY row shifts in pitch (lower = less “sharp” top rows).
  - **Octave:** shifts the whole keyboard up/down.
- **Power chords:** toggles root + 5th + octave (more “guitar-ish”).
- **Style:** switch between:
  - **Hold:** key down = note on, key up = note off (best for riffs)
  - **Chug 8ths / 16ths:** hold a key and it auto-repeats on a beat grid at the current BPM (best for rock rhythm)
- **Touchpad Pad:** in Keys mode you can drag to play:
  - left/right = pitch
  - up/down = velocity
  - release = stop (unless sustain is held)

### Text Mode (type sentences → music)

Text mode has two sub-modes:

- **Script (recommended):** type a normal sentence, then press `Cmd+Enter` to play it.
  - The app reads your text at the current **Grid** and **BPM**: `1 character = 1 grid tick`.
  - Playback is deterministic: same text + same chart + same settings = same result.
  - Character identity matters (`a` vs `t`, uppercase accents, punctuation syntax below).
  - You can change **Grid** and **BPM** while it is already playing.
  - Input mode can be switched to **Linear v1** for command-style writing:
    - `letters` melody, `*` full chord, `^` arp up, `v` arp down, `/` next chord
    - `1..5` direct chord tones, `-`/`_` hold, `,` rest, `.` resolve, `!` accent
  - Use **Style** to pick how the sentence is performed (4 options): Ballad Pick / Rock Strum / Power Chug / Synth Pulse.
  - Letters become “picks” inside the current chord; **vowels** tend to pick higher tones.
  - Syntax: `,` rest, `-` hold, `.` resolve (tonic), `!` accent.
  - **Chord advance:** choose whether chords change **every bar** (default) or **on spaces** (word boundaries).
- **Chords:** paste/edit a chord chart like `Em D C G D/F#` (use **Songbook** for starters).
  - Supported: major/minor (`m`/`min`), `sus2`, `sus4`, `5`, `7`, `maj7`, slash bass notes (`D/F#`).
  - `|` works as a bar line and is ignored by the parser.

## Controls (Keyboard)

- `Cmd+Enter`: arm / disarm (start/stop)
- `Ctrl+Opt+Cmd+M`: arm / disarm (works when global listening is enabled)
- `Space` (hold): sustain (Keys mode, and pad sustain)
- `[` / `]`: octave down / up (Keys mode)
- `Tab`: toggle power-chord mode
- `\`: toggle Scale Lock / All Notes
- `Cmd+1..5`: pick scale (Scale Lock mode)
- `Esc`: panic (all notes off)

Keys mode controls in the UI:

- **Preset**: one-click “sounds good” setups
- **Simple / Advanced**: hides/shows extra controls
- **Style**: Hold / Chug 8ths / Chug 16ths
- **BPM**: tempo for Chug
- **Strum**: strum chord hits (most noticeable with guitar-ish instruments)
- **Row jump**: row-to-row pitch spacing (try smaller values if the top rows feel too high)
- **Octave**: same as `[` / `]`, but as a slider

### Practice Songbook (Keys mode)

- Open **Practice…** and pick one of the seven songs.
- The app auto-applies that song’s recommended preset (tone + mapping + rhythm defaults).
- The help panel shows multi-section practice lines with exact keyboard keys, for example:
  - `Em[d]  D[s]  C[a]  G[g]` style chord-to-key hints
  - slash chords include bass/root hints like `D/F#[f→d]`
- Use **Paste chords from Clipboard** to generate practice lines from any chart text.

## Sound (Piano + Guitar‑ish)

- Use the **Instrument** dropdown (or menubar `MM` → **Instrument**) to switch sounds.
- For much better realism, load a SoundFont:
  - Click **SoundFont…** and choose a `.sf2` (General MIDI soundfonts tend to map best).
  - Press **Built-in** to revert to the system sounds.
  - If `SoundFonts/GeneralUser-GS-v1.471.sf2` exists, the app will auto-load it on startup.
- What the guitar options mean:
  - `Guitar (Clean)`: electric guitar with little/no breakup (clearer)
  - `Guitar (Overdriven)`: moderate “crunch” (classic rock)
  - `Guitar (Distortion)`: heavier saturation (more aggressive)

## Song Examples

### “Nothing Else Matters” (typing arpeggio)

1. Choose **Preset → Typing Script (Two-hand Piano)**.
2. In **Text → Chords**, use **Songbook → Nothing Else Matters (Intro pick: Em)**.
3. Switch to **Text → Script**.
4. Set **Style: Ballad Pick**, **Grid: Triplets**, **BPM ~76**.
5. Press `Cmd+Enter` to play.

Tip: use a short sentence with spaces (bass motion), e.g. `trust i seek and i find in you`.

### “Free Bird” (simple chord loop)

**Option A: Keys mode (no Text mode needed)**

1. Set: **All Notes** + **Power chords** + **Instrument: Guitar (Overdriven)**.
2. Use **Row jump** / **Octave** until it feels comfortable.
3. Use the on-screen key map to find and play: `G  D/F#  Em  F  C  D` (repeat in rhythm).

**Option B: Text mode (Script)**

In **Text → Chords**, use **Songbook** (or paste/type):

`G D/F# Em F C D`

Switch to **Text → Script**, set **Style: Rock Strum**, then press `Cmd+Enter` to play; chords will advance every bar by default (or switch chord advance to “On spaces”).

<details>
<summary>Troubleshooting</summary>

**No sound**
- Make sure the app is `ARMED` (`Cmd+Enter`).
- Check macOS output volume.
- Hit `Esc` (panic) once to clear stuck notes.

**Global listening doesn’t work (typing in other apps makes no sound)**
1. Menubar `MM` → **Enable Global Listening**.
2. System Settings → Privacy & Security → Input Monitoring → enable it for your terminal (or the `making_music` app binary).
3. Relaunch the app.

**Typing doesn’t show up**
- Click inside the big text box (it needs focus).
- Make sure you’re in **Text → Script** or **Text → Chords** (not **Keys** mode).

</details>

<details>
<summary>Development</summary>

Interface Contract commands:

```bash
make check
make test
make all
```

</details>
