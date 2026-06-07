# Prioritized Backlog

This backlog orders v1 work by user value and risk reduction. The first milestone must prove the core promise: a user records a meeting locally, sees usable Russian transcript text, copies recent context, and gets a final owned transcript file.

## Priority Rules

- P0: Without this, the product cannot prove the core local transcript promise.
- P1: Required for a usable v1, but can follow after the core loop works.
- P2: Important for polish, recovery, and daily usefulness.
- P3: Valuable later, not required for first usable v1.

## P0: Core Local Transcript Loop

Goal: user can start a local recording, get transcript segments, copy recent context, stop, and receive a final Markdown transcript.

First implementation slice: manual recording-session shell from the main app window. It intentionally uses a no-op capture driver and does not capture real audio yet.

User steps:

- Step 4: Start Recording Manually.
- Step 5: See Live Russian Transcript.
- Step 6: Copy Recent Context During Meeting.
- Step 8: Stop Recording.
- Step 9: Save Final Transcript.
- Step 14: Verify A Meeting End To End, excluding REST/MCP until P1.

Why first:

- This validates the product's main promise.
- It exposes the highest-risk areas early: audio capture, local STT latency, Russian quality, transcript finalization, and local storage.
- It creates the base data model needed by UI, search, REST, MCP, and QA.

Definition of done:

- Manual start/stop works from the main app window on Apple Silicon.
- Mic and system-audio lanes can be represented as `Me` and `Others`.
- Russian is the default transcription path.
- Copy Last 5 Minutes works while recording.
- Stop creates a Markdown transcript.
- Automated checks cover transcript segment behavior and Markdown export.
- Manual QA confirms no cloud upload is required.

## P1: Usable Personal App

Goal: make the core loop understandable and repeatable for daily personal use.

User steps:

- Step 1: First Launch.
- Step 2: Grant Recording Permissions.
- Step 7: Copy Full Transcript During Meeting.
- Step 10: Find Past Meetings.
- Step 12: Control Local Data.
- Step 13: Recover From Problems.

Convenience improvements:

- Hotkey start/stop.
- Menu bar recording controls.
- Hotkey/menu bar copy actions.

Why second:

- These steps turn the core loop into a product the user can operate without developer help.
- Permission and recovery UX reduce support burden.
- Past-meeting access reinforces the free local ownership promise.

Definition of done:

- First-run flow explains local-only behavior.
- Missing permissions are visible and recoverable.
- Full transcript copy works during active recording.
- Meeting history opens previous local transcripts.
- User can open transcript storage location.
- Product-facing errors explain user impact and next action.

## P1: Local Access Surface

Goal: make transcripts available to other local apps and AI assistants.

User steps:

- Step 11: Access Transcript From Other Apps.
- Step 14: Verify A Meeting End To End, including REST/MCP.

Why P1:

- Local access is part of the product's differentiation, but it depends on stable transcript storage from P0.
- REST and MCP should read the same local source of truth as the app.

Definition of done:

- Local REST can list meetings, fetch a meeting, fetch transcript, fetch segments, and search.
- MCP can list recent meetings, search, fetch meeting metadata, and fetch transcript.
- Services bind to localhost only.
- Local access requires an explicit user enablement and token.
- REST, MCP, app view, and Markdown agree on transcript content.

## P1: Calendar-Assisted Start

Goal: make recording start feel Granola-like without making calendar access mandatory.

User steps:

- Step 3: Connect Calendar.
- Step 4: Start Recording Manually with current meeting context.

Why P1:

- Calendar improves daily UX and file naming.
- Manual start remains the reliable fallback and must ship first.

Definition of done:

- Calendar access is optional.
- Current/upcoming meetings are visible after permission.
- User can start recording from a calendar meeting.
- Meeting title and time populate transcript metadata.
- Manual quick recording still works without calendar access.

## P2: Trust, Recovery, And Data Control

Goal: make the product safe to use in real work situations.

User steps:

- Step 12: Control Local Data.
- Step 13: Recover From Problems.
- Step 14: Verify A Meeting End To End with failure cases.

Why P2:

- These features improve confidence once the core workflow exists.
- They are essential before broader release, but not required to prove the first prototype.

Definition of done:

- User can delete a meeting transcript and index entry.
- Raw audio retention policy is explicit in settings before persistent audio storage ships.
- Unsupported hardware, missing local model, denied permission, and capture failure have clear user-facing recovery paths.
- Failures do not silently discard transcript data.

## P3: Post-V1 Enhancements

Goal: improve productivity after the local transcript foundation is stable.

Candidates:

- AI-generated local summaries.
- Remote speaker diarization beyond `Me` and `Others`.
- Automatic call detection.
- Team sharing.
- Cloud sync.
- Billing.

Why P3:

- These are valuable but can distract from the core promise.
- Some conflict with local-only privacy or introduce major product decisions.
- Each requires a separate BRD update and ADR before implementation.

## Recommended Build Order

1. Transcript/storage core: segments, meeting metadata, Markdown, SQLite contract, copy windows.
2. Manual recording shell: main-window start/stop state, visible recording UX, placeholder/fake transcript source.
3. Local audio capture: microphone and system-audio lanes.
4. Local Russian STT: model install path, VAD chunking, partial/final segment pipeline.
5. Finalization: stop flow, Markdown write, SQLite index update.
6. First-run and permissions UX.
7. Meeting history, full transcript copy, hotkey/menu bar convenience controls.
8. Local REST API.
9. Local MCP server.
10. Calendar-assisted meeting start.
11. Data controls and recovery UX hardening.

## Parallel Workstreams

The backlog can run in parallel after the transcript/storage contract is stable:

- UX workstream: first-run, recording screen, transcript view, copy controls, history.
- Capture/STT workstream: mic/system capture, VAD, local model, Russian benchmarks.
- Storage/API workstream: Markdown, SQLite, REST, MCP.
- QA/privacy workstream: permissions, local-only verification, manual meeting-app checklist.
