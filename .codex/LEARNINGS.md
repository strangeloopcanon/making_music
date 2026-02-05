# Learnings

- `bd init --no-db` works for non-git scratch dirs (creates `.beads/issues.jsonl`).
- CommandLineTools-only setups may not have `XCTest`; use a small self-test executable target instead of `swift test`.
- Swift 6 concurrency checks can reject sending `NSEvent`/captured refs across to `@MainActor`; extract primitive fields and hop to `MainActor` with sendable payloads.
- On macOS 26 / Swift 6.2, `AVAudioUnitDynamicsProcessor` is not available in `AVFoundation`; avoid it and use `AVAudioUnitEQ` + `AVAudioUnitDistortion` + `AVAudioUnitReverb` for a simple “louder/richer” chain.
- Don’t manually forward keyboard events by calling `NSTextView.keyDown(with:)` from a parent view; it can create a responder-chain recursion. Focus the text view and (if needed) replay the `NSEvent` via `window.sendEvent(_:)` on the next run loop.
- When running `bd comments add ...` in a shell, backticks in the comment body will be treated as command substitution; wrap the message in single quotes or escape backticks.
- Gemini CLI: hardcoding a model name like `gemini-1.5-pro` can 404 (`ModelNotFoundError`) depending on account/config; the default model works when unsure.
- macOS 26: avoid building `CharacterSet` via chained `.union()`/`.subtracting()` at runtime (observed bad pointer deref); prefer simple per-character trimming/parsing.
- `swift test` in this environment cannot import `XCTest`; use Swift's `Testing` module (`import Testing`, `@Test`, `#expect`) for package tests.
- This toolchain also lacks the `Testing` module, so the stable fallback is executable self-tests (`swift run making_music_selftest`) with richer assertions.
