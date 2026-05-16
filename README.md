# Notes Guy

Notes Guy is a local-first macOS note-taking assistant for turning anything you are learning on screen into Obsidian-style Markdown. Start a note, read or watch normally, then stop when you are done. Notes Guy captures screen frames, OCR text, source URLs/titles, captions when available, and audio when permitted, then writes a source note plus durable wiki pages.

It is inspired by Andrej Karpathy's LLM wiki idea: plain Markdown files should become a personal, LLM-readable knowledge base that grows from source material, follow-up discussions, and repeated refinement. See Karpathy's gist: <https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f>.

This is not a RAG app, meeting bot, browser extension, or realtime overlay. The MVP loop is:

```text
read/watch/listen -> take notes -> write Markdown -> enrich wiki -> discuss later -> append/update notes
```

## What It Does Today

- Runs as a macOS menu bar app named `Notes Guy`.
- Defaults the notes vault to `~/Documents/Notes Guy Vault` and creates it if missing.
- Starts and stops explicit note sessions from the menu bar.
- Captures screenshots and OCR text during a session until you click `Stop and write`.
- Records system audio through ScreenCaptureKit when screen/system-audio permission is available.
- Falls back to microphone recording when system audio is unavailable.
- Attempts speech transcription and browser/YouTube caption extraction when available.
- Captures screen/source context without repeatedly forcing macOS permission prompts.
- Writes a source Markdown note immediately, so the session is never empty.
- Writes a local wiki enrichment seed first, then runs Codex CLI for deeper enrichment.
- Creates and updates Obsidian-style files under `Wiki/`.
- Keeps raw artifacts under `.notes-guy/raw/` inside the configured vault.

## Current Note Pipeline

1. `Take notes` creates a session record and starter Markdown note.
2. While the session is active, Notes Guy records observations, transcript/caption signals, and raw artifacts.
3. `Stop and write` immediately writes a readable source note from captured screen/source context.
4. Audio transcription continues in the background and can trigger another enrichment pass when it finishes.
5. A fast local enrichment step writes concept-oriented wiki seed notes from the available source text.
6. A slower Codex enrichment step can expand, connect, and improve the wiki using the vault context.

The important behavior is that `Stop and write` does not wait on slow audio or Codex work before leaving you with a Markdown note.

## Where Notes Go

Default vault:

```text
~/Documents/Notes Guy Vault
```

Important paths inside the vault:

```text
Wiki/index.md
Wiki/concepts/
Wiki/guides/
Wiki/sources/
.notes-guy/sessions/
.notes-guy/raw/
```

The vault path is configurable from the app UI. Do not point the vault at the source repo unless you intentionally want generated notes beside the code.

## Install And Run

Build and install the macOS app:

```bash
cd /path/to/notes-guy
./scripts/package-macos-app.sh
open "/Applications/Notes Guy.app"
```

The script builds the release binary and installs `Notes Guy.app` into `/Applications` when writable. If `/Applications` is not writable, it falls back to `~/Applications`.

For local development without packaging:

```bash
swift run notes-guy-desktop
```

Run tests:

```bash
swift test
```

## How To Use

1. Open `Notes Guy` from `/Applications` or Spotlight.
2. Open the menu bar item named `Notes Guy`.
3. Confirm the notes folder points to `~/Documents/Notes Guy Vault` or your Obsidian vault.
4. Open the video, article, paper, docs page, code walkthrough, or meeting you want to learn from.
5. Click `Take note now`.
6. Watch, read, or work normally. The session keeps running until you stop it.
7. Click `Stop and write note`.
8. Open the note path shown by the app, or open `Wiki/index.md` in Obsidian.

`Ask to take notes` is optional. Keep it off if you do not want proactive prompts while browsing. Manual `Take note now` still works.

## Permissions

macOS permissions are tied to the app bundle identity:

```text
dev.notesguy.desktop
```

Grant permissions to `Notes Guy` in:

```text
System Settings -> Privacy & Security -> Screen & System Audio Recording
System Settings -> Privacy & Security -> Microphone
System Settings -> Privacy & Security -> Speech Recognition
```

Screen & System Audio Recording is the important permission for screenshots, OCR, and system audio. Microphone is only a fallback.

If macOS shows an older local development name, remove that old app from the permission list and grant access to the installed `Notes Guy.app`.

Notes Guy tries to check permission state before capturing. If permission is missing, it should record that fact in the note instead of repeatedly opening system prompts.

## Codex Enrichment

The richer wiki pass uses local Codex CLI. Make sure `codex` is available in the shell environment used by the app.

Quick check:

```bash
which codex
codex --version
```

If Codex is not available, the app should still keep the starter note and local wiki seed. The note should show a capture status entry explaining that Codex enrichment failed.

## Project Layout

```text
Sources/NotesGuyDesktop/   macOS menu bar app
Sources/NotesGuyCLI/       small CLI entrypoint
Sources/NotesGuyCore/Capture/     screen/audio/context capture models and services
Sources/NotesGuyCore/Processing/  transcription and caption extraction
Sources/NotesGuyCore/CodexAgent/  Codex CLI enrichment client and contracts
Sources/NotesGuyCore/Session/     session model and persistence
Sources/NotesGuyCore/Wiki/        vault bootstrap, note writers, enrichment seed writer
Tests/NotesGuyCoreTests/          focused unit coverage
scripts/                          packaging and icon scripts
packaging/macos/                  app plist and icon assets
```

## Troubleshooting

If no note appears after a session, check:

```text
~/Documents/Notes Guy Vault/Wiki/index.md
~/Documents/Notes Guy Vault/.notes-guy/sessions.json
~/Documents/Notes Guy Vault/.notes-guy/log.md
```

If the note exists but is weak, check whether screen permission was granted and whether raw screenshots/frames exist under `.notes-guy/raw/<session-id>/`.

If the app keeps saying permission is missing, quit the app, confirm the permission toggle in System Settings, and relaunch the installed app from `/Applications/Notes Guy.app`.

If you launched from Terminal during development, macOS may associate capture permission with Terminal or the debug binary instead of the installed app. Use the packaged app for real testing.

## Current MVP Boundaries

- macOS only.
- System audio capture uses ScreenCaptureKit and requires Screen & System Audio Recording permission.
- Microphone capture is a fallback.
- Browser captions/transcript signals are best-effort.
- The app is local-first, but Codex enrichment depends on the local Codex CLI configuration.
- It is designed for personal Obsidian-style notes, not polished meeting minutes.
