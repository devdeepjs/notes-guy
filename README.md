# Notes Guy

Notes Guy is a local-first macOS note-taking assistant for turning learning sessions into Obsidian-style Markdown. It watches the current learning context, starts an explicit note session, captures useful source signals, writes an immediate wiki seed note, and then asks Codex CLI to enrich that note into durable concept pages.

It is inspired by Andrej Karpathy's LLM wiki idea: plain Markdown files should become a personal, LLM-readable knowledge base that grows from source material, follow-up discussions, and repeated refinement. See Karpathy's gist: <https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f>.

This is not a RAG app, meeting bot, browser extension, or realtime overlay. The MVP loop is:

```text
watch/read/listen -> take notes -> write Markdown -> enrich wiki -> discuss later -> append/update notes
```

## What It Does Today

- Runs as a macOS menu bar app named `Notes Guy`.
- Defaults the notes vault to `~/Documents/Notes Guy Vault` and creates it if missing.
- Can proactively detect browser/video learning context and show a small "Take notes" prompt.
- Starts and stops explicit note sessions.
- Records microphone audio when permission is available.
- Attempts speech transcription and browser/YouTube caption extraction when available.
- Captures screen/source context without repeatedly forcing macOS permission prompts.
- Writes a starter Markdown note immediately, so the session is never empty.
- Writes a local wiki enrichment seed first, then runs Codex CLI for deeper enrichment.
- Creates and updates Obsidian-style files under `Wiki/`.
- Keeps raw artifacts under `.notes-guy/raw/` inside the configured vault.

## Current Note Pipeline

1. `Take notes` creates a session record and starter Markdown note.
2. While the session is active, Notes Guy records observations, transcript/caption signals, and raw artifacts.
3. `Stop and write` finalizes the session note.
4. A fast local enrichment step writes concept-oriented wiki seed notes from the available source text.
5. A slower Codex enrichment step can expand, connect, and improve the wiki using the vault context.

The important behavior is that step 4 should create useful wiki output even when the slower Codex step is still running or fails.

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
open "$HOME/Applications/Notes Guy.app"
```

The script builds the release binary, packages `Notes Guy.app`, installs it into `~/Applications`, and removes the old Desktop app bundle if present.

For local development without packaging:

```bash
swift run notes-guy-desktop
```

Run tests:

```bash
swift test
```

## How To Use

1. Open `Notes Guy` from `~/Applications` or Spotlight.
2. Open the menu bar item named `Notes Guy`.
3. Confirm the notes folder points to `~/Documents/Notes Guy Vault` or your Obsidian vault.
4. Use `Ask to take notes` only when you want proactive prompts.
5. Open the video/article/doc/blog you want to learn from.
6. Click `Take notes`.
7. Watch or read normally.
8. Click `Stop and write`.
9. Open the note path shown by the app, or open `Wiki/index.md` in Obsidian.

If you do not want prompts for normal browsing, turn `Ask to take notes` off. Manual `Take notes` still works.

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

If no note appears after a video, check:

```text
~/Documents/Notes Guy Vault/Wiki/index.md
~/Documents/Notes Guy Vault/.notes-guy/sessions/
```

If the note exists but is weak, check whether the source had captions/transcript text and whether Codex enrichment failed in the capture status block.

If the app keeps saying permission is missing, quit the app, confirm the permission toggle in System Settings, and relaunch the installed app from `~/Applications/Notes Guy.app`.

If you launched from Terminal during development, macOS may associate capture permission with Terminal or the debug binary instead of the installed app. Use the packaged app for real testing.

## Current MVP Boundaries

- macOS only.
- Microphone capture is supported before full system-audio capture.
- Browser captions/transcript signals are best-effort.
- The app is local-first, but Codex enrichment depends on the local Codex CLI configuration.
- It is designed for personal Obsidian-style notes, not polished meeting minutes.
