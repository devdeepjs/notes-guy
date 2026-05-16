# Notes Guy

Notes Guy is a local-first macOS app that turns what you read, watch, and listen to into Obsidian-style Markdown notes.

Open an article, video, paper, docs page, code walkthrough, or meeting. Click **Take note now**. When you are done, click **Stop and write**. Notes Guy captures screen context, OCR text, source metadata, captions when available, and audio when permitted, then writes a durable note into your local notes folder.

The goal is not to create a video recap. The goal is to build a personal technical wiki: source-backed concept notes, links, open questions, and future prompts that can keep evolving.

Notes Guy is inspired by Andrej Karpathy's LLM wiki idea: <https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f>.

## Status

This is an early macOS MVP for personal use and source-based distribution.

- Works as a menu bar app named `Notes Guy`.
- Builds with Swift Package Manager.
- Packages into a normal `.app` bundle.
- Stores notes and raw capture artifacts in a user-selected local folder.
- Uses local macOS capture APIs and optional local Codex CLI enrichment.
- Not notarized yet.
- Not an App Store app yet.

## What It Is

Notes Guy is for background note capture while learning.

Typical use cases:

- Watching a YouTube lecture or course video.
- Reading technical blogs, papers, or docs.
- Following a coding tutorial.
- Reviewing interview-prep material.
- Capturing learning from a meeting or walkthrough.

The core loop is:

```text
observe source -> capture evidence -> write Markdown -> enrich wiki -> discuss later -> update notes
```

## What It Is Not

Notes Guy is intentionally small in v1.

- Not a RAG product.
- Not a vector database.
- Not a browser extension.
- Not a meeting bot.
- Not a real-time answer overlay.
- Not an Obsidian plugin.
- Not a cloud sync service.

It writes local Markdown first. Everything else is secondary.

## Features

- Menu bar app with one main action: take notes.
- Configurable notes folder, defaulting to `~/Documents/Notes Guy Vault`.
- Manual `Take note now` flow that works for any visible source.
- Optional proactive prompt when a likely video or learning page is detected.
- Session capture that continues until explicit `Stop and write`.
- Periodic screenshots with duplicate-frame filtering.
- OCR and source-window context capture.
- System audio recording through ScreenCaptureKit when permission is available.
- Microphone fallback when system audio is unavailable.
- Best-effort speech transcription.
- Best-effort browser and YouTube caption extraction.
- Immediate source note writing so a session does not end empty.
- Local wiki seed generation before slower enrichment finishes.
- Optional Codex CLI enrichment for deeper concept notes and cross-links.
- Basic session recovery if the app exits during capture.

## Quick Start

Requirements:

- macOS 15 or newer.
- Xcode command line tools.
- Swift Package Manager.
- Optional: Codex CLI for richer wiki enrichment.

Build and install:

```bash
git clone https://github.com/<your-github-user>/notes-guy.git
cd notes-guy
./scripts/package-macos-app.sh
open "/Applications/Notes Guy.app"
```

The packaging script installs to `/Applications` when possible. If that location is not writable, it installs to `~/Applications`.

For development without packaging:

```bash
swift run notes-guy-desktop
```

Run tests:

```bash
swift test
```

## First Run

1. Open `Notes Guy`.
2. Click the menu bar item.
3. Confirm the notes folder, or choose your Obsidian vault.
4. Grant macOS permissions when needed.
5. Open the source you want to learn from.
6. Click `Take note now`.
7. Read, watch, or listen normally.
8. Click `Stop and write`.
9. Open `Wiki/index.md` in your notes folder.

If you do not want proactive prompts while browsing, turn off `Ask to take notes`. Manual note capture still works.

## Permissions

macOS permissions are tied to the installed app bundle identity:

```text
dev.notesguy.desktop
```

Grant permissions in:

```text
System Settings > Privacy & Security > Screen & System Audio Recording
System Settings > Privacy & Security > Microphone
System Settings > Privacy & Security > Speech Recognition
```

Screen & System Audio Recording is the main permission. It enables screenshots, OCR, and system audio capture.

Microphone is a fallback. Speech Recognition is used for Apple speech transcription when available.

For real use, launch the packaged app from `/Applications/Notes Guy.app` or `~/Applications/Notes Guy.app`. Running the app from Terminal during development can cause macOS to associate permissions with the development binary or Terminal instead of the installed app.

## Notes Folder Layout

By default, Notes Guy creates:

```text
~/Documents/Notes Guy Vault
```

Inside the vault:

```text
Wiki/index.md
Wiki/concepts/
Wiki/guides/
Wiki/sources/
.notes-guy/sessions/
.notes-guy/raw/
```

`Wiki/` contains readable Markdown notes.

`.notes-guy/` contains session metadata, raw screenshots, audio files, transcripts, and processing artifacts. This folder is useful for debugging and later enrichment, but it is not meant to be hand-edited.

## Note Pipeline

1. `Take note now` creates a session and starter note.
2. Notes Guy captures source metadata, OCR text, screenshots, captions, and audio signals while you continue working.
3. `Stop and write` immediately writes a readable source note.
4. Transcription and enrichment can continue after the base note exists.
5. Local enrichment creates seed wiki notes from captured evidence.
6. Optional Codex enrichment can expand notes, connect related concepts, and update the local wiki.

The important rule: stopping a session should leave a useful Markdown note even if audio transcription or Codex enrichment fails.

## Codex Enrichment

Notes Guy can use the local Codex CLI for richer wiki generation.

Check your setup:

```bash
which codex
codex --version
```

If Codex is unavailable, Notes Guy still writes the source note and local seed notes. The Markdown file should include a capture status entry explaining that Codex enrichment did not run.

Codex behavior depends on your local Codex configuration. If your Codex setup calls a hosted model provider, enrichment may send the prompt context to that provider. Raw notes and artifacts still remain in your configured local notes folder.

## Privacy Model

Notes Guy is local-first:

- Notes are Markdown files in a folder you control.
- Raw screenshots, audio, transcripts, and session metadata stay inside that folder.
- The app does not include cloud sync.
- The app does not include a vector database.
- The app does not upload anything by itself outside the optional tools you configure, such as Codex CLI.

Before publishing your own fork, do not commit generated vault data, raw recordings, local app bundles, or planning artifacts. The `.gitignore` is set up to keep those out of git.

## Development

Useful commands:

```bash
swift test
swift run notes-guy
swift run notes-guy-desktop
./scripts/package-macos-app.sh
```

Project layout:

```text
Sources/NotesGuyDesktop/        macOS menu bar app
Sources/NotesGuyCLI/            small CLI entrypoint
Sources/NotesGuyCore/Capture/   screen, audio, OCR, and source context
Sources/NotesGuyCore/Processing/ transcription and caption extraction
Sources/NotesGuyCore/CodexAgent/ Codex CLI enrichment client
Sources/NotesGuyCore/Session/   session model and persistence
Sources/NotesGuyCore/Wiki/      vault bootstrap and Markdown writers
Tests/NotesGuyCoreTests/        unit tests
scripts/                        packaging and icon scripts
packaging/macos/                app plist and icon
```

## Troubleshooting

No note appears:

```text
Check <vault>/Wiki/index.md
Check <vault>/.notes-guy/sessions/
Check <vault>/.notes-guy/raw/
```

The note is weak or says screen capture was skipped:

```text
Confirm Screen & System Audio Recording permission for Notes Guy.
Quit and reopen the installed app after changing permissions.
Start a fresh session from the packaged app, not a debug binary.
```

Codex enrichment failed:

```text
Run `which codex` and `codex --version`.
Confirm Codex works from a normal terminal.
The source note should still exist even when enrichment fails.
```

macOS keeps asking for permission:

```text
Use the packaged app from /Applications or ~/Applications.
Remove old development app entries from the macOS permission list.
Keep the bundle id stable: dev.notesguy.desktop.
```

## Roadmap

See [TODO.md](TODO.md) for the current reliability, capture quality, wiki quality, and packaging roadmap.
