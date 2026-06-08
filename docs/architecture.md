# Architecture

## System Shape

Meeting007 is a native macOS application with a local processing pipeline and local access services.

```mermaid
flowchart LR
    Mic["Microphone Capture"] --> Mixer["Audio Session Coordinator"]
    System["System Audio Capture"] --> Mixer
    Mixer --> VAD["VAD + Chunker"]
    VAD --> STT["Local STT Engine"]
    STT --> Segments["Transcript Segment Store"]
    Segments --> Markdown["Markdown Exporter"]
    Segments --> SQLite["SQLite Index"]
    SQLite --> REST["Local REST API"]
    SQLite --> MCP["Local MCP Server"]
    SQLite --> UI["SwiftUI App"]
```

## Native App

- Swift and SwiftUI provide the macOS app shell.
- ScreenCaptureKit captures system audio.
- AVAudioEngine/CoreAudio captures microphone audio.
- EventKit provides calendar access after user consent.
- Later convenience layers may add global hotkeys for quick start/stop and copy actions.
- Later convenience layers may add menu bar controls for essential recording state and copy actions.

## Audio Capture

The capture layer keeps audio lanes separate:

- `mic`: local microphone, displayed as `Me`.
- `system`: remote speakers and meeting app audio, displayed as `Others`.

The app should avoid mixing these lanes before transcription unless a fallback path requires it. Keeping lanes separate improves attribution and preserves future diarization options.

## Transcription Pipeline

The STT engine is behind a protocol boundary:

- Input: timestamped audio chunks with lane metadata.
- Output: partial and final transcript segments.
- Default language: Russian.
- Default execution: local Apple Silicon acceleration through a Whisper-family runtime.

The chunker uses VAD to cut speech at natural boundaries. Partial segments may update. Final segments are immutable except for explicit correction/finalization passes.

## Storage

Meeting data has two local forms:

- Markdown files are the durable user-owned transcript format.
- SQLite is the indexed operational store for search, segment retrieval, API responses, and live state.

Current implemented storage boundary:

- `TranscriptFileWriting` is the protocol for durable transcript file persistence.
- `LocalMarkdownTranscriptFileWriter` is the default writer used by the app after Stop.
- `MarkdownTranscriptFileStore` owns folder creation, filename generation, Markdown file writing, and temp-file cleanup.
- Default Markdown folder: `~/Documents/Meeting007/Transcripts/`.
- Markdown export uses a same-folder temp file and then moves/replaces the final Markdown file.
- Markdown files are durable user-owned artifacts; the in-memory recent-recording store remains runtime-only.
- SQLite remains a later storage-index slice and must not be introduced implicitly by Markdown export work.

Meeting IDs are UUIDs. Current Markdown filenames use UTC start time, transliterated title slug, and short UUID:

```text
2026-06-08_14-30_russkaya-vstrecha_a1b2c3d4.md
```

The Markdown file preserves the original meeting title, including Cyrillic text, in front matter and the H1.

## Local REST API

The local REST API is localhost-only by default.

Initial endpoints:

- `GET /v1/meetings`
- `GET /v1/meetings/{id}`
- `GET /v1/meetings/{id}/transcript`
- `GET /v1/meetings/{id}/segments`
- `GET /v1/search?q=...`

All endpoints read from the SQLite index and return data that matches the Markdown transcript source.

## MCP Server

The local MCP server mirrors the REST access model for AI assistants.

Initial tools:

- `list_recent_meetings`
- `search_meetings`
- `get_meeting`
- `get_transcript`

The MCP server must not expose audio files by default.

## Security Boundary

- REST and MCP bind to localhost.
- API tokens are stored in Keychain.
- The app must provide an explicit control for enabling or disabling local access services.
- No cloud path may be introduced without a new ADR and user-facing product decision.
