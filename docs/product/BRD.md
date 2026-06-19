# Business Requirements Document

## Product Vision

Meeting007 is a personal, local-first Mac app that records meetings without joining as a bot, creates Russian-first live transcripts, and makes transcripts freely available as local files and local APIs.

## Target User

The v1 target user is one individual on an Apple Silicon Mac who spends time in online meetings and needs immediate access to what was said without sending audio to a cloud service.

## Core Jobs

- Record microphone and system audio from online meetings without a meeting bot.
- Display a useful live transcript during the meeting.
- Copy the latest meeting context quickly while the meeting is still running.
- Save a final transcript after the meeting.
- Let the user choose where owned Markdown transcripts are saved.
- Use Google Calendar meeting context to reduce manual naming and capture participant metadata.
- Let local tools and AI assistants access meeting transcripts through REST and MCP.
- Keep transcripts available for free as user-owned local data.

## V1 User Journeys

Detailed user-step decomposition lives in [User Steps](user-steps.md). Implementation priority lives in [Prioritized Backlog](prioritized-backlog.md).

### Start A Meeting

1. User opens Meeting007.
2. App can use Google Calendar context when calendar access has been granted.
3. User starts recording manually from the main app window, with or without calendar context.
4. App confirms active capture immediately.
5. App starts showing live transcript output as soon as the local live transcription worker has enough speech, without waiting for a final-quality transcription pass.

### Use Transcript During A Meeting

1. User watches partial Russian transcript text appear within a few seconds.
2. Finalized segments become stable and do not jump around.
3. User copies the full transcript or last 5 minutes from visible controls.
4. Copied text includes timestamps and speaker lane labels where available.

### Finish A Meeting

1. User stops recording.
2. App stops capture promptly and keeps the UI responsive.
3. App finalizes pending transcript segments from the local captured-audio session buffer.
4. App writes a Markdown transcript to the user's selected transcript folder and updates the SQLite index.
5. The meeting becomes available through the app, local REST API, and MCP tools.

### Control Transcript Storage

1. User opens storage settings.
2. App shows the current Markdown transcript folder.
3. User can change the folder, reveal it in Finder, copy the path, or reset to the default location.
4. New Markdown exports use the selected folder.
5. Existing transcript files are not moved silently.
6. User can later choose a separate migration flow to move existing Markdown transcripts into the active folder.

### Use Google Calendar Context

MVP:

1. User explicitly connects Google Calendar.
2. App fetches relevant current/upcoming event metadata.
3. App uses the event topic/title as the meeting title.
4. App stores event participants as local meeting metadata.
5. Manual start remains available when calendar access is not connected or no event matches.

Enhancement:

1. Main screen shows today's meetings.
2. User can start a recording from a listed meeting.
3. App can notify the user before a meeting starts through macOS Notification Center after notification permission is granted.

## Functional Requirements

- The app must capture microphone and system audio without a bot participant.
- The app must keep microphone and system audio as separate lanes.
- The app must label local microphone speech as `Me` and remote/system audio as `Others` in v1.
- The first real capture slice must prove local microphone capture with visible `Me` lane activity before real local STT is connected.
- The app must show available microphone inputs in Settings, let the user choose the input used for new recordings, and persist that local selection.
- If the selected microphone is missing or cannot be opened, the app must show a recoverable input error instead of silently recording a different source.
- The app must route live transcript text through a local STT pipeline boundary before the production Whisper runtime is connected.
- The UI must not imply that deterministic STT pipeline text is production Whisper output until real local Whisper runtime ships.
- The app must support Russian as the default transcription language.
- The app must separate local audio capture, live transcription, and final transcript reconciliation into distinct pipeline stages.
- The app must start audio capture immediately when the user presses Start, independent of local STT runtime readiness.
- The app must maintain an ordered local audio session buffer with lane, sequence, sample-start, and sample-end metadata so transcription can recover from local STT delays or failures.
- The app may retain raw audio only as a temporary local session spool needed to prevent transcript loss before finalization; this spool must be deleted after successful final transcript completion unless a separate explicit retention setting is later designed.
- The app must not expose temporary raw audio through Markdown, SQLite transcript records, REST, MCP, logs, debug dumps, telemetry, or cloud services.
- Live transcript output must be treated as draft text until reconciled into committed/final segments.
- Final transcript reconciliation must run separately from the live transcript worker and must not block stopping capture.
- During an active meeting, the app must let the user copy the full finalized transcript captured so far without stopping recording.
- Full transcript copy must not present partial/live text as final transcript content.
- The app must save final transcripts as Markdown.
- The app must let the user configure the Markdown transcript storage folder.
- The app must default Markdown transcript storage to `~/Documents/Meeting007/Transcripts/` until the user chooses another local folder.
- The app must not silently move existing transcript files when the storage folder changes.
- The app must treat migration of existing Markdown transcripts as a separate explicit user-confirmed function.
- Markdown migration must preview what will move, preserve transcript ownership, avoid silent overwrites, and report any files that could not be moved.
- Google Calendar integration MVP must pull meeting title/topic and participants after explicit user connection.
- Google Calendar enhancement must support today's meeting list, start-from-meeting, and pre-meeting Notification Center alerts.
- Manual start/stop must remain reliable without Google Calendar.
- The app must maintain a SQLite index for meetings, segments, timestamps, search, and API access.
- The app must expose localhost-only REST endpoints for meetings and transcripts.
- The app must expose MCP tools for searching and fetching meetings.
- The app must not require an account or subscription for transcript access.

## Non-Functional Requirements

- Live partial transcript should appear within 2-4 seconds of speech on normal Apple Silicon hardware.
- Live preview must expose one replaceable partial segment; an older decode must not overwrite a newer result or appear beside a contradictory final row.
- A transient local decode failure must not stop capture and must clear after the next successful decode in the same session.
- Target live partial transcript should appear within 0.5-1.5 seconds of speech when the local live transcription worker is warm on normal Apple Silicon hardware.
- Pressing Start should not wait for local STT runtime initialization; model warming may improve latency but must not be the only loss-prevention mechanism.
- Pressing Stop should stop capture promptly and must not wait indefinitely for final transcript reconciliation.
- Final transcript should be available within 10 seconds after stopping a 30-60 minute meeting when the finalizer is healthy; if finalization exceeds its deadline, the app must preserve the local spool and surface a recoverable finalization state instead of hanging or discarding transcript data.
- The app must emit local-only latency markers for development/QA measurement: start pressed, first audio frame, live worker ready, first partial, stop pressed, capture stopped, finalization started, and finalization completed or failed.
- The app UI must remain responsive while recording and transcribing.
- The system must work without internet access after local models are installed.
- Data must remain local by default.

## Out Of Scope For V1

- Team workspaces.
- Hosted cloud sync.
- Bot-based meeting attendance.
- Cloud transcription.
- Billing.
- Public web app.
- Automatic call detection.
- AI-generated summaries, unless added later after the transcription pipeline is stable.

## Acceptance Criteria

- User can start and stop recording manually on an Apple Silicon Mac.
- User can see and choose the microphone used for new recordings before starting a meeting.
- User can see live Russian transcript draft text shortly after speech begins while a meeting is active.
- User can copy the last 5 minutes and the full transcript during a meeting.
- Stopping a meeting stops capture promptly, then finalizes from local buffered audio without losing the captured tail.
- Full-spool finalization must include the first and last captured audio ranges even when live transcription starts late or fails temporarily.
- Stopping a meeting creates a Markdown transcript and SQLite index entry after finalization.
- User can choose the folder used for new Markdown transcript exports.
- User can explicitly migrate existing Markdown transcripts to the active transcript folder when that separate function ships.
- Google Calendar MVP can populate title and participants for a recording without making calendar access mandatory.
- REST and MCP can retrieve the same transcript data.
- No audio or transcript data leaves the Mac in the default v1 path.
- Temporary raw audio spools remain local, are not exposed as transcript artifacts, and are removed after successful finalization unless a future explicit retention decision changes that behavior.
