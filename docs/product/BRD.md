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
- Let local tools and AI assistants access meeting transcripts through REST and MCP.
- Keep transcripts available for free as user-owned local data.

## V1 User Journeys

Detailed user-step decomposition lives in [User Steps](user-steps.md). Implementation priority lives in [Prioritized Backlog](prioritized-backlog.md).

### Start A Meeting

1. User opens Meeting007.
2. App shows calendar meetings when calendar access has been granted.
3. User starts recording manually from the main app window.
4. App confirms active capture and starts showing transcript output.

### Use Transcript During A Meeting

1. User watches partial Russian transcript text appear within a few seconds.
2. Finalized segments become stable and do not jump around.
3. User copies the full transcript or last 5 minutes from visible controls.
4. Copied text includes timestamps and speaker lane labels where available.

### Finish A Meeting

1. User stops recording.
2. App finalizes pending transcript segments.
3. App writes a Markdown transcript and updates the SQLite index.
4. The meeting becomes available through the app, local REST API, and MCP tools.

## Functional Requirements

- The app must capture microphone and system audio without a bot participant.
- The app must keep microphone and system audio as separate lanes.
- The app must label local microphone speech as `Me` and remote/system audio as `Others` in v1.
- The app must support Russian as the default transcription language.
- The app must save final transcripts as Markdown.
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
- REST and MCP can retrieve the same transcript data.
- No audio or transcript data leaves the Mac in the default v1 path.
