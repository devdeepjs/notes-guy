# Notes Guy TODO

This list is intentionally blunt. The current app has the useful shape, but the reliability bar is still the main work.

## Must Fix Before Daily Use

- Make `Stop and write` visibly track each pipeline stage: starter note, transcript/captions, local wiki seed, Codex enrichment, final changed files.
- Add a persistent session activity log in the UI so failures are not hidden inside Markdown comments.
- Make source identity stable across same-tab YouTube navigation, including URL/title changes during an active session.
- Add an explicit "Open latest note" and "Copy latest note path" action after every stop.
- Add a retry button for Codex enrichment on the latest session.
- Make local enrichment strong enough to produce useful concept notes even when Codex is unavailable.
- Add a vault health check that verifies `Wiki/index.md`, `Wiki/concepts/`, and `.notes-guy/sessions/` are writable before starting.

## Capture Quality

- Add real system-audio capture or a documented low-friction fallback.
- Add manual audio/video import for cases where live capture is weak.
- Add OCR/frame text extraction from sampled screen frames.
- Improve frame selection so visual evidence is based on meaningful screen changes, not fixed-time screenshots.
- Store source URL, source title, and active browser tab history per session.
- Add better handling for fullscreen video, browser focus changes, and app switching.

## Wiki Quality

- Keep source session notes separate from durable concept notes.
- Update existing concept notes when a new session covers the same concept.
- Generate navigation-friendly note titles instead of random source titles.
- Maintain topical index pages such as `Wiki/topics/system-design.md`.
- Add backlinks and `Related Concepts` sections without pretending every target already exists.
- Add source anchors with useful timestamps, not transcript spam.
- Add interview/question-answer expansions when the source is clearly interview-prep material.

## UX

- Replace the current utility UI with a tighter menu bar workflow.
- Keep proactive prompting off by default and easy to pause.
- Show one subtle prompt per detected source, not repeated prompts while browsing.
- Make the app installable and launchable without Terminal.
- Add a settings panel for vault path, prompt behavior, capture interval, and enrichment mode.
- Add a compact "Taking notes..." state that does not interrupt fullscreen viewing.

## Packaging And Release

- Keep the public bundle identifier stable after the first public release.
- Add a stable local code-signing setup.
- Add notarization only if this is shared outside the local machine.
- Add a clean uninstall/reset script for permissions, app bundle, and generated support files.
- Add release notes per build.

## Testing

- Keep unit tests focused on source identity, session lifecycle, note writing, and enrichment fallback behavior.
- Add integration tests that simulate two videos in the same browser tab.
- Add a filesystem test that proves `Stop and write` creates a non-empty concept note.
- Add a regression test for "local seed created even when Codex fails."
- Add a manual smoke checklist for the packaged app on macOS.

## Later

- Obsidian plugin integration.
- Automatic source scraping beyond browser/title/caption signals.
- Real RAG/search over the vault.
- Multi-device sync.
- Meeting-specific workflows.
- Shareable packaged installer.
