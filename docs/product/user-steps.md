# User Steps

This document decomposes Meeting007 v1 requirements into user-visible steps. Use it as the shared product backlog for UX, implementation, and QA.

## Step 1: First Launch

- User goal: understand what the app does and why it is safe to use.
- User action: opens Meeting007 for the first time.
- App response: shows a work screen with recording controls and a short local-first privacy explanation.
- Success result: user understands that audio and transcripts stay on the Mac.
- Acceptance criteria:
  - No account is required.
  - No cloud feature is presented as required.
  - The app explains local-only processing before requesting sensitive permissions.

## Step 2: Grant Recording Permissions

- User goal: allow the app to hear the meeting.
- User action: starts setup for meeting recording.
- App response: requests microphone permission and screen/system audio permission only when needed.
- Success result: app can capture both local voice and meeting audio.
- Acceptance criteria:
  - Permission prompts are tied to a clear user action.
  - User can see which permissions are still missing.
  - User can continue setup after returning from macOS Settings.

## Step 3: Connect Calendar

- User goal: start recordings from real meetings without manually naming everything.
- User action: enables calendar access.
- App response: asks for calendar permission and shows upcoming/current meetings.
- Success result: user can choose the current calendar meeting as recording context.
- Acceptance criteria:
  - Calendar access is optional.
  - Manual recording remains available without calendar access.
  - Meeting title and time are used for transcript metadata.

## Step 4: Start Recording Manually

- User goal: begin capturing a meeting reliably.
- User action: clicks Start in the main app window.
- App response: starts mic and system-audio capture, shows active recording state, and opens the live transcript area.
- Success result: user knows the meeting is being captured.
- Acceptance criteria:
  - Recording can start without a meeting bot.
  - Recording start works even when no calendar event is selected.
  - The UI clearly shows active recording, elapsed time, and current meeting title or quick-note title.
  - Hotkey and menu bar start are not required for the first implementation slice.

First implementation slice:

- The app provides a recording-session shell with a no-op capture driver.
- The app does not request microphone or screen/system-audio permissions yet.
- The app does not create audio files, transcript files, or network calls.
- The purpose is to validate the manual Start/Stop workflow and state model before real capture is added.

## Step 5: See Live Russian Transcript

- User goal: read what was just said while the meeting is still happening.
- User action: speaks or listens during the meeting.
- App response: shows partial Russian transcript text within a few seconds and then stabilizes final segments.
- Success result: user can rely on the transcript for quick context.
- Acceptance criteria:
  - Russian is the default language.
  - Partial text is visually distinct from final text.
  - Finalized text does not jump or rewrite unexpectedly.
  - Local microphone speech is labeled `Me`; system audio is labeled `Others`.

Placeholder implementation slice:

- During recording, the app shows static local Russian mock segments that demonstrate the future live transcript experience.
- Mock segments include `Me` and `Others` labels plus partial/final states.
- The UI clearly says this is a preview, not real audio transcription.
- The app does not capture audio, run STT, save transcript files, or call any network service for this slice.

## Step 6: Copy Recent Context During Meeting

- User goal: quickly react in another app using the latest meeting context.
- User action: clicks Copy Last 5 Minutes in the main app window.
- App response: copies recent transcript text with timestamps and speaker labels.
- Success result: user can paste relevant context into chat, notes, email, or an AI assistant.
- Acceptance criteria:
  - Default recent window is 5 minutes.
  - Copy action works while recording is active.
  - Copied text excludes old transcript content outside the selected window.
  - User gets visible confirmation that text was copied.
  - Hotkey and menu bar copy actions can be added later.

## Step 7: Copy Full Transcript During Meeting

- User goal: export everything captured so far without ending the meeting.
- User action: clicks Copy Full Transcript.
- App response: copies all available transcript segments.
- Success result: user can share or use the current transcript immediately.
- Acceptance criteria:
  - Copy includes stable final segments and can include clearly marked partial segments.
  - Copy action does not stop or slow recording.
  - Copied text includes meeting title when available.

## Step 8: Stop Recording

- User goal: finish capture and produce a final transcript.
- User action: clicks Stop in the main app window.
- App response: stops capture, finalizes pending transcript segments, and shows finalization progress.
- Success result: user sees that the meeting has ended and the transcript is being saved.
- Acceptance criteria:
  - Stopping is explicit and reversible only by starting a new recording.
  - The app does not lose pending partial transcript content.
  - The app remains responsive during finalization.
  - Hotkey and menu bar stop are not required for the first implementation slice.

Completed-session implementation slice:

- After Stop, the app creates a local in-memory completed-session snapshot for the current app run.
- The completed snapshot includes title, start/end time, duration, primary language, quick note, and transcript preview metadata.
- The latest completed session appears in the main work area, and completed recordings appear in a left-side "Recent recordings" tree.
- Multiple completed recordings remain visible newest first until the app closes.
- This slice does not create Markdown files, SQLite records, REST/MCP access, audio files, or durable history.

## Step 9: Save Final Transcript

- User goal: keep the meeting transcript as a file the user owns.
- User action: waits for finalization to finish.
- App response: writes a Markdown transcript and updates the local SQLite index.
- Success result: transcript is available in the app, as a local file, and through local access services.
- Acceptance criteria:
  - Markdown file is created with readable filename based on date and title.
  - Transcript includes timestamps, speaker labels, title, start time, and language.
  - SQLite index contains matching meeting and segment data.
  - No cloud upload is required.

Current status:

- Durable Markdown/SQLite saving is still a future slice.
- The current app can show completed recordings only for the active app process.

## Step 10: Find Past Meetings

- User goal: return to a previous transcript quickly.
- User action: opens Meeting007 and searches or selects a meeting from history.
- App response: shows matching local meetings and transcript preview/details.
- Success result: user can retrieve past transcript content without leaving the app.
- Acceptance criteria:
  - Search works over local indexed transcript text.
  - Meeting list shows date, title, and recording state.
  - Opening a past meeting does not require internet access.

## Step 11: Access Transcript From Other Apps

- User goal: use meeting data from scripts, tools, or AI assistants.
- User action: enables local REST/MCP access and uses a local client.
- App response: serves meeting metadata, transcripts, segments, and search results from localhost.
- Success result: third-party tools can use transcripts without cloud sync.
- Acceptance criteria:
  - Local access is disabled unless user enables it.
  - REST and MCP return the same transcript data as the app.
  - Services bind to localhost only.
  - Access requires a local token.

## Step 12: Control Local Data

- User goal: know what is stored and remove it when needed.
- User action: opens storage/privacy settings.
- App response: shows transcript location, index state, and raw audio retention setting.
- Success result: user controls local meeting data.
- Acceptance criteria:
  - User can open the transcript folder.
  - User can delete a meeting transcript and index entry.
  - Raw audio retention behavior is explicit before any persistent audio storage ships.

## Step 13: Recover From Problems

- User goal: understand and fix common blockers without technical diagnosis.
- User action: sees an error or missing capability.
- App response: explains the problem as a user-impact message with a direct next action.
- Success result: user can recover from missing permissions, unsupported hardware, unavailable model, or capture failure.
- Acceptance criteria:
  - Permission errors explain which user capability is blocked.
  - Unsupported Mac error explains that v1 requires Apple Silicon.
  - Missing local model error offers a clear local installation path.
  - Failures do not silently discard transcript data.

## Step 14: Verify A Meeting End To End

- User goal: trust that Meeting007 worked.
- User action: records a short test meeting, copies recent context, stops recording, and opens the saved transcript.
- App response: produces live transcript, copied text, Markdown file, and local API/MCP visibility.
- Success result: user confirms the core v1 promise.
- Acceptance criteria:
  - Live transcript appears within the target latency.
  - Copy Last 5 Minutes works.
  - Final Markdown matches the app transcript.
  - REST/MCP transcript matches the saved transcript.
  - No data leaves the Mac.
