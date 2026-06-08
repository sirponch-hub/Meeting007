# Testing Strategy

## Test Pyramid

- Automated checks cover transcript domain logic, export, time windows, serialization, and storage mappings.
- Integration tests cover mocked audio chunks through VAD, STT, storage, REST, and MCP.
- Manual QA covers macOS permissions, live capture, Russian speech, and real meeting apps.

## Automated Checks

Required coverage:

- Transcript segment ordering.
- Partial-to-final segment replacement.
- Timestamp formatting.
- Copy full transcript.
- Copy last 5 minutes window selection, formatted clipboard text, metadata header, and live partial markers.
- Markdown export.
- Markdown file writer path, filename, folder creation, temp-file cleanup, and local-only scope.
- Completed-session runtime history after Stop.
- In-memory history deduplication and newest-first ordering.
- SQLite mapping and migrations.
- API response shapes.

## Integration Tests

Use deterministic fixtures:

- Synthetic audio chunks for mic and system lanes.
- Fake local STT engine returning known partial and final segments.
- Temporary SQLite database.
- Temporary Markdown output folder.
- Local API server bound to a random localhost port.

## Audio Fixture Policy

- Do not commit private meeting recordings.
- Do not commit customer, employee, or third-party conversation audio.
- Test fixtures must be synthetic, public-domain, or explicitly approved.
- Keep large model files and generated recordings out of git.

## Manual QA Checklist

- Apple Silicon Mac.
- macOS microphone permission prompt.
- macOS screen/system audio permission prompt.
- Calendar permission prompt.
- Manual start/stop recording.
- Stop recording and verify the completed session appears in recent recordings for the current app run.
- Start/stop a second recording and verify recent recordings stay newest first.
- Relaunch the app and verify prototype recent recordings are not presented as durable history until persistence ships.
- Global hotkey start/stop when that convenience feature is implemented.
- Zoom capture.
- Google Meet capture.
- Microsoft Teams capture.
- Slack huddle/call capture.
- Russian speech live transcription.
- Separate `Me` and `Others` lanes.
- Copy full transcript during active recording.
- Copy last 5 minutes during active recording.
- Verify Copy Last 5 Minutes is disabled before transcript preview text appears.
- Verify Copy Last 5 Minutes puts timestamped `Me`/`Others` transcript text on the clipboard.
- Stop meeting and verify Markdown output.
- Verify Markdown appears under `~/Documents/Meeting007/Transcripts/`.
- Verify Markdown filename is date/title/UUID based and filesystem-safe.
- Verify Markdown contains final Russian segments and excludes partial preview lines.
- Verify no audio, SQLite, REST/MCP, telemetry, or cloud artifacts are created by Markdown export.
- Verify REST transcript matches Markdown.
- Verify MCP transcript matches REST.

## Performance Targets

- Live partial transcript appears within 2-4 seconds of speech.
- Final transcript available within 10 seconds after stop for a 30-60 minute meeting, excluding optional full re-transcription.
- UI remains responsive during active recording.
- Local API responds to transcript reads within 200 ms for normal personal-history sizes.

## Required Before Release

- `swift run Meeting007CoreChecks` passes.
- Manual QA checklist is complete for the release candidate.
- No private audio, transcript, token, model, database, or build artifact is committed.

## Main Branch Gate

Untested work must not enter `main`.

Before merging to `main`, each change must include:

- Automated verification command and result.
- Manual QA result when the change affects capture, permissions, UI, copy actions, local API, MCP, storage, or privacy.
- A clear note when a test is intentionally missing, including the follow-up needed to make the change mergeable.

If the verification story is incomplete, the branch can be used for exploration, but it is not ready for `main`.
