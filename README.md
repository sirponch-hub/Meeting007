# Meeting007

Meeting007 is a local-first macOS meeting transcriber for Apple Silicon.

The product goal is simple: capture meeting audio without a bot, transcribe Russian-first speech as close to realtime as possible, and keep every transcript as user-owned local data. No hosted backend, no account system, and no transcript lock-in are part of v1.

## V1 Scope

- Native macOS app for personal use first.
- Manual meeting start/stop from the main app window.
- Calendar-connected meeting list and "start from current meeting" flow.
- Bot-free microphone and system-audio capture.
- Local-only speech-to-text pipeline.
- Live transcript view with stable final segments and visually distinct partial segments.
- Copy full transcript and copy the last 5 minutes during a meeting.
- Final Markdown transcript plus SQLite index.
- Local REST API and MCP server for third-party tools.

Hotkey and menu bar controls are planned convenience features after the first recording loop is stable.

AI summaries are intentionally out of the first implementation slice. The first production milestone is reliable local capture, realtime Russian transcription, durable storage, and local access.

## Privacy Model

Meeting007 is local-only by default:

- Audio does not leave the Mac.
- Transcripts are stored in user-owned local files.
- API and MCP access bind to localhost only.
- Access tokens are stored in Keychain.
- Cloud transcription, cloud sync, and hosted accounts are not v1 features.

See [Security & Privacy](docs/security-privacy.md) for the detailed policy.

## Repository Layout

- `Sources/Meeting007Core`: testable transcript domain logic.
- `Tests/Meeting007CoreTests`: unit tests for transcript behavior.
- `docs/product/BRD.md`: business requirements.
- `docs/architecture.md`: v1 technical architecture.
- `docs/testing.md`: testing strategy and acceptance checks.
- `docs/security-privacy.md`: local-first security and privacy rules.
- `docs/adr`: architecture decision records.
- `AGENTS.md`: rules for AI-assisted development in this repository.

## Development

This repository starts with a Swift Package for core logic. The native macOS app target will be added after the core transcript and storage contracts stabilize.

```bash
swift run Meeting007CoreChecks
```

Minimum target for v1: Apple Silicon Mac.
