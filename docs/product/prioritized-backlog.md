# Prioritized Backlog

This backlog orders v1 work by user value and risk reduction. The first milestone must prove the core promise: a user records a meeting locally, sees usable Russian transcript text, copies recent context, and gets a final owned transcript file.

## Priority Rules

- P0: Without this, the product cannot prove the core local transcript promise.
- P1: Required for a usable v1, but can follow after the core loop works.
- P2: Important for polish, recovery, and daily usefulness.
- P3: Valuable later, not required for first usable v1.

## P0: Core Local Transcript Loop

Goal: user can start a local recording, get transcript segments, copy recent context, stop, and receive a final Markdown transcript.

Updated priority decision: the current single rolling WhisperKit path is not sufficient for the product bar. The P0 core loop must be rebuilt around a capture-first, loss-resistant local ASR pipeline before more UI convenience or calendar work.

Next required implementation slices:

1. **Local capture session spool and latency markers.**
   - Capture starts immediately on Start.
   - Every audio chunk gets lane, sequence, sample-start, and sample-end metadata.
   - A temporary local session spool preserves captured audio until final transcript completion.
   - Development/QA markers record start pressed, first audio frame, live worker ready, first partial, stop pressed, capture stopped, finalization started, and finalization completed or failed.

2. **Stop/finalization decoupling.**
   - Stop closes capture promptly and never waits indefinitely for transcription.
   - Final transcript reconciliation runs as a separate local finalizer over the captured session spool.
   - If finalization misses its deadline, the app preserves the local spool and shows a recoverable finalization state instead of hanging or discarding data.

3. **Push-driven live transcription worker.**
   - Live transcription receives ordered audio frames or small speech frames as input instead of polling a rolling window timer.
   - Live transcript text is always draft until committed/finalized.
   - The first visible partial target is 0.5-1.5 seconds after speech begins when the local worker is warm.

4. **Segment state machine with sample offsets.**
   - Segments move through `partial`, `committed`, and `final` states.
   - Segment replacement and reconciliation use sample offsets, not UI string-prefix heuristics.
   - Live partial text cannot duplicate committed/final text for the same audio range.

5. **Model split decision.**
   - Use a fast local live path for low-latency drafts.
   - Use a separate local final path for quality and tail recovery.
   - A single heavy rolling decode must not be the only mechanism for live, stable, and final transcript output.

First implementation slice: manual recording-session shell from the main app window. It intentionally uses a no-op capture driver and does not capture real audio yet.

Second implementation slice: live transcript placeholder during recording. It uses local static Russian mock segments to demonstrate `Me`/`Others` and partial/final states without real STT or audio capture.

Third implementation slice: completed-session runtime history after Stop. It saves an immutable local in-memory snapshot for the current app run, shows the latest completed session, and keeps recent recordings newest first without Markdown/SQLite persistence.

Fourth implementation slice: Copy Last 5 Minutes during active recording. It copies the current local preview transcript window from the visible transcript panel with timestamps and speaker labels, without hotkey/menu bar actions yet.

Fifth implementation slice: Markdown transcript export after Stop. It writes the stopped local preview transcript to `~/Documents/Meeting007/Transcripts/`, shows the saved path, and leaves SQLite/API/audio persistence out of scope.

User steps:

- Step 4: Start Recording Manually.
- Step 5: See Live Russian Transcript.
- Step 6: Copy Recent Context During Meeting.
- Step 8: Stop Recording.
- Step 9: Save Final Transcript.
- Step 16: Verify A Meeting End To End, excluding REST/MCP until P1.

Why first:

- This validates the product's main promise.
- It exposes the highest-risk areas early: audio capture, local STT latency, Russian quality, transcript finalization, and local storage.
- It creates the base data model needed by UI, search, REST, MCP, and QA.

Definition of done:

- Manual start/stop works from the main app window on Apple Silicon.
- Mic and system-audio lanes can be represented as `Me` and `Others`.
- Russian is the default transcription path.
- Capture starts immediately and is independent of local STT readiness.
- Temporary local audio spool prevents lost speech before finalization and is deleted after successful final transcript completion unless a future explicit retention setting changes this.
- Live transcript drafts appear from the push-driven live worker without waiting for final reconciliation.
- Stop closes capture promptly and finalization cannot hang the recording controls.
- Final transcript reconciliation can recover the captured tail from the local spool.
- Stop creates a completed-session snapshot visible in the app for the current app run.
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
- Step 10: Choose Transcript Storage Folder.
- Step 12: Find Past Meetings.
- Step 14: Control Local Data.
- Step 15: Recover From Problems.

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
- User can open and change the Markdown transcript storage location for future exports.
- Product-facing errors explain user impact and next action.

## P1: Markdown Transcript Migration

Goal: let the user explicitly move existing owned Markdown transcript files into the active transcript folder after changing storage location.

User steps:

- Step 11: Migrate Existing Markdown Transcripts.
- Step 14: Control Local Data.
- Step 15: Recover From Problems.

Why P1:

- Folder choice controls future exports, but personal archives often need cleanup once the user decides on a permanent folder.
- Migration affects private transcript files and must be deliberate, previewed, and recoverable.

Definition of done:

- Migration is a separate action from folder change.
- User sees source, destination, file count, conflicts, and expected result before confirming.
- App does not silently overwrite files.
- App verifies moved files and reports moved/skipped/failed items.
- Interrupted migration does not lose transcript files.

## P1: Local Access Surface

Goal: make transcripts available to other local apps and AI assistants.

User steps:

- Step 13: Access Transcript From Other Apps.
- Step 16: Verify A Meeting End To End, including REST/MCP.

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
- Google Calendar context reduces mistakes by importing the real meeting topic and participants.
- Manual start remains the reliable fallback and must ship first.

Definition of done:

- Calendar access is optional.
- Google Calendar MVP pulls meeting topic/title and participants after explicit user connection.
- Meeting title, participants, and time populate transcript metadata.
- Manual quick recording still works without calendar access.
- No recording starts automatically from calendar data in MVP.

Enhancement backlog:

- Today's meetings appear on the main screen.
- User can start recording from a listed calendar meeting.
- App can warn before a meeting starts through macOS Notification Center after explicit notification permission.

## P2: Trust, Recovery, And Data Control

Goal: make the product safe to use in real work situations.

User steps:

- Step 14: Control Local Data.
- Step 15: Recover From Problems.
- Step 16: Verify A Meeting End To End with failure cases.

Why P2:

- These features improve confidence once the core workflow exists.
- They are essential before broader release, but not required to prove the first prototype.

Definition of done:

- User can delete a meeting transcript and index entry.
- Raw audio retention policy is explicit in settings before user-retained persistent audio storage ships.
- Temporary raw audio spools created for loss-resistant finalization are local-only, hidden from transcript/API surfaces, and automatically removed after successful finalization.
- User can recover when the selected Markdown folder is missing or not writable.
- User can recover from partial Markdown migration without losing transcript files.
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

1. Loss-resistant local ASR foundation: capture session spool, ordered audio chunk metadata, local-only temporary retention, latency markers.
2. Stop/finalizer separation: prompt capture stop, asynchronous final reconciliation, recoverable finalization state, spool cleanup.
3. Push-driven live transcription worker: warm local live path, first partial target, draft-only live segments.
4. Segment state machine: sample-offset-based `partial`/`committed`/`final` transitions, no duplicate text across overlapping audio ranges.
5. Model strategy: fast live model/path plus separate quality finalizer path, Russian benchmark threshold.
6. Transcript/storage core: meeting metadata, Markdown, SQLite contract, copy windows.
7. Manual recording shell and visible recording UX hardening around the new pipeline.
8. Local audio capture expansion: microphone and system-audio lanes through the new spool contract.
9. First-run, permissions UX, and configurable Markdown transcript folder.
10. Markdown transcript migration for existing files.
11. Meeting history, full transcript copy, hotkey/menu bar convenience controls.
12. Local REST API.
13. Local MCP server.
14. Google Calendar MVP: title/topic and participants.
15. Calendar enhancements: today's meetings, start-from-meeting, Notification Center reminders.
16. Data controls and recovery UX hardening.

## Parallel Workstreams

The backlog can run in parallel after the transcript/storage contract is stable:

- UX workstream: first-run, recording screen, transcript view, copy controls, history.
- Capture/STT workstream: capture session spool, live worker, finalizer, local model strategy, Russian benchmarks.
- Storage/API workstream: Markdown, SQLite, REST, MCP.
- QA/privacy workstream: permissions, local-only verification, manual meeting-app checklist.
