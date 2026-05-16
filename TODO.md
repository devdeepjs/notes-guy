# Notes Guy Roadmap

Notes Guy is usable as a local macOS learning-note assistant today. This roadmap tracks the next reliability and polish work before a broader public release.

## Near-Term Reliability

- Add a visible session activity log in the menu UI so users can see screenshot, audio, transcript, local seed, and Codex stages without opening Markdown comments.
- Add a `Retry enrichment` action for the latest note.
- Add a packaged-app smoke test checklist that verifies `/Applications/Notes Guy.app`, permissions, one short capture, and note creation.
- Add an integration test that simulates two learning sessions in the same browser tab and verifies that each source note keeps its own URL/title.
- Add a vault health check before starting a session: writable vault, writable `Wiki/`, writable `.notes-guy/raw/`, and valid `Wiki/index.md`.

## Capture Quality

- Improve OCR quality and frame selection so repeated static frames do not crowd the raw folder.
- Persist active browser tab changes during long sessions instead of only recording the source URL at start.
- Add manual import for audio/video/transcript files when live permissions are unavailable.
- Add optional capture interval settings in the UI.
- Add explicit handling for recovered sessions after app relaunch, including whether audio was recoverable.

## Wiki Quality

- Make local fallback source notes more domain-aware beyond the current system-design, Java, and deep-learning seeds.
- Update existing durable concept notes more aggressively when a new session covers the same concept.
- Add source-backed Q&A sections for interview-prep material.
- Add a lightweight `Discussion Log` append flow for pasting later LLM conversations back into an existing note.
- Keep source notes, concept notes, guide notes, and topic notes clearly separated.

## Packaging

- Keep bundle id `dev.notesguy.desktop` stable.
- Add a clean uninstall/reset script for app bundle, Launch Services registration, and generated support files.
- Add signed/notarized release packaging if distributing outside source builds.
- Add screenshots or a short demo GIF to the README.

## Later

- Obsidian plugin integration.
- Browser extension for richer page metadata.
- Optional local search over the vault.
- Multi-device sync through user-owned storage.
