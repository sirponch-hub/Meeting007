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
4. App confirms active capture and starts showing transcript output.

### Use Transcript During A Meeting

1. User watches partial Russian transcript text appear within a few seconds.
2. Finalized segments become stable and do not jump around.
3. User copies the full transcript or last 5 minutes from visible controls.
4. Copied text includes timestamps and speaker lane labels where available.

### Finish A Meeting

1. User stops recording.
2. App finalizes pending transcript segments.
3. App writes a Markdown transcript to the user's selected transcript folder and updates the SQLite index.
4. The meeting becomes available through the app, local REST API, and MCP tools.

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
- The app must route live transcript text through a local STT pipeline boundary before the production Whisper runtime is connected.
- The UI must not imply that deterministic STT pipeline text is production Whisper output until real local Whisper runtime ships.
- The app must support Russian as the default transcription language.
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
- Final transcript should be available within 10 seconds after stopping a 30-60 minute meeting, excluding any optional full re-transcription.
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
- User can see live transcript text while a meeting is active.
- User can copy the last 5 minutes and the full transcript during a meeting.
- Stopping a meeting creates a Markdown transcript and SQLite index entry.
- User can choose the folder used for new Markdown transcript exports.
- User can explicitly migrate existing Markdown transcripts to the active transcript folder when that separate function ships.
- Google Calendar MVP can populate title and participants for a recording without making calendar access mandatory.
- REST and MCP can retrieve the same transcript data.
- No audio or transcript data leaves the Mac in the default v1 path.
