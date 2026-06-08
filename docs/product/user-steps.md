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

- User goal: start recordings from real meetings without manually naming everything and keep participant context with the transcript.
- User action: explicitly connects Google Calendar.
- App response: requests Google Calendar access and imports relevant current/upcoming event metadata.
- Success result: user can use the current calendar meeting as recording context.
- Acceptance criteria:
  - Calendar access is optional.
  - Manual recording remains available without calendar access.
  - Google Calendar MVP pulls the meeting topic/title.
  - Google Calendar MVP pulls event participants/attendees and stores them as local meeting metadata.
  - Meeting title, participants, and time are used for transcript metadata.
  - The app does not auto-start recording from calendar data in MVP.

Calendar enhancement slice:

- The main screen shows today's meetings after Google Calendar is connected.
- User can start recording from a listed meeting.
- Meeting-start reminders can appear through macOS Notification Center after explicit notification permission.
- Notification timing and quiet-hours behavior should be decided before implementation.

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

First implementation slice:

- The `Transcript` panel includes a visible `Copy Last 5 Minutes` button.
- The button is enabled only while recording is active and transcript preview text exists.
- The copied text comes from the current local preview transcript and includes app name, meeting title, copy window, copied time, language, timestamps, and `Me`/`Others` labels.
- Partial preview lines are copied with a `(live)` marker.
- The app shows a short confirmation after copying, or a stable non-blocking message if clipboard write fails.
- This slice does not add hotkey/menu bar copy actions, full transcript copy, real audio transcription, files, REST/MCP, telemetry, or cloud access.

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
- App response: writes a Markdown transcript to the selected local transcript folder. SQLite indexing comes later.
- Success result: transcript is available as a local Markdown file the user can inspect outside the app.
- Acceptance criteria:
  - Markdown file is created with readable filename based on date and title.
  - Transcript includes timestamps, speaker labels, title, start time, and language.
  - New Markdown exports use the user's selected transcript folder.
  - The default folder remains `~/Documents/Meeting007/Transcripts/` before the user changes it.
  - SQLite index contains matching meeting and segment data when the storage-index slice ships.
  - No cloud upload is required.

Markdown export implementation slice:

- After Stop, the app writes a Markdown file under `~/Documents/Meeting007/Transcripts/`.
- Filename format is `yyyy-MM-dd_HH-mm_<title-slug>_<short-id>.md`.
- Russian titles are transliterated for filesystem-safe filenames; the Markdown title preserves the original text.
- Markdown front matter includes `id`, `title`, `started_at`, `ended_at`, `primary_language`, and `transcript_source: local_preview`.
- Markdown body exports final transcript segments only; partial preview lines are excluded from the final file.
- The completed-session UI shows `Markdown saved locally` and the saved path.
- `Show in Finder` and `Copy path` are available from the completed recording row context menu in the left-side tree.
- If the user started recording before naming the meeting, editing the main `Meeting title` field after Stop and pressing Enter saves the new title and writes a new Markdown export with the updated title.
- This slice does not add SQLite, REST/MCP, audio persistence, cloud sync, telemetry, or real STT.

## Step 10: Choose Transcript Storage Folder

- User goal: keep Markdown transcripts in the personal folder or knowledge base where they belong.
- User action: opens storage settings and changes the Markdown transcript folder.
- App response: shows the current folder, validates write access, and uses the selected folder for future exports.
- Success result: future meeting transcripts are saved where the user expects.
- Acceptance criteria:
  - User can see the current Markdown folder.
  - User can change the folder through a native macOS folder picker.
  - User can reveal the folder in Finder, copy the path, and reset to the default folder.
  - The app validates that it can write to the selected folder before accepting it.
  - Existing Markdown files are not moved silently.
  - If the selected folder becomes unavailable, the app keeps the transcript visible and offers a clear retry/change-folder path.
  - Cloud-synced folders such as iCloud Drive, Dropbox, or Google Drive are allowed only when the user explicitly chooses them.

First implementation slice:

- The main window includes a compact `Settings` disclosure for non-meeting-flow controls.
- Markdown folder controls live inside `Settings`, not in the primary recording/transcript workflow.
- The app shows the active Markdown folder path.
- User can choose a folder through a native macOS folder picker.
- User can reveal the active folder in Finder, copy the folder path, or reset to the default folder.
- The selected folder is stored locally in app preferences and used for new Markdown exports.
- The app validates write access by creating the folder if needed and writing a temporary probe file.
- Existing Markdown transcript files are not moved when the folder changes.
- This slice does not add Markdown migration, sandbox security bookmarks, SQLite storage, REST/MCP folder controls, or a dedicated Settings window.

## Step 11: Migrate Existing Markdown Transcripts

- User goal: move older Markdown transcripts into the currently selected transcript folder when the user wants one organized location.
- User action: starts `Migrate existing Markdown transcripts` from storage settings.
- App response: previews source folders, destination folder, number of files, conflicts, and any files that cannot be moved.
- Success result: user explicitly confirms the migration and old Markdown transcripts are moved safely into the active folder.
- Acceptance criteria:
  - Migration is never triggered automatically by changing the transcript folder.
  - User sees a preview before any file is moved.
  - User explicitly confirms the migration.
  - App avoids silent overwrites when destination filenames already exist.
  - App preserves Markdown file contents and meeting metadata.
  - App reports moved, skipped, conflicted, and failed files.
  - App keeps source files intact until each destination file is written and verified.
  - If migration is interrupted, app shows a recoverable status and does not lose transcript files.
  - Migration remains local-only and does not upload transcripts.

Planned implementation slice:

- Migration starts as a separate storage action after configurable folders are stable.
- The first slice may support migration from known Meeting007 transcript folders only.
- A later slice can add user-selected source folders and SQLite index reconciliation.

## Step 12: Find Past Meetings

- User goal: return to a previous transcript quickly.
- User action: opens Meeting007 and searches or selects a meeting from history.
- App response: shows matching local meetings and transcript preview/details.
- Success result: user can retrieve past transcript content without leaving the app.
- Acceptance criteria:
  - Search works over local indexed transcript text.
  - Meeting list shows date, title, and recording state.
  - Opening a past meeting does not require internet access.

## Step 13: Access Transcript From Other Apps

- User goal: use meeting data from scripts, tools, or AI assistants.
- User action: enables local REST/MCP access and uses a local client.
- App response: serves meeting metadata, transcripts, segments, and search results from localhost.
- Success result: third-party tools can use transcripts without cloud sync.
- Acceptance criteria:
  - Local access is disabled unless user enables it.
  - REST and MCP return the same transcript data as the app.
  - Services bind to localhost only.
  - Access requires a local token.

## Step 14: Control Local Data

- User goal: know what is stored and remove it when needed.
- User action: opens storage/privacy settings.
- App response: shows transcript location, index state, and raw audio retention setting.
- Success result: user controls local meeting data.
- Acceptance criteria:
  - User can open the transcript folder.
  - User can change the Markdown transcript folder for new exports.
  - User can explicitly migrate existing Markdown transcripts when they want old files to follow the active folder.
  - User can delete a meeting transcript and index entry.
  - Raw audio retention behavior is explicit before any persistent audio storage ships.

## Step 15: Recover From Problems

- User goal: understand and fix common blockers without technical diagnosis.
- User action: sees an error or missing capability.
- App response: explains the problem as a user-impact message with a direct next action.
- Success result: user can recover from missing permissions, unsupported hardware, unavailable model, or capture failure.
- Acceptance criteria:
  - Permission errors explain which user capability is blocked.
  - Unsupported Mac error explains that v1 requires Apple Silicon.
  - Missing local model error offers a clear local installation path.
  - Unavailable transcript folder error explains where new Markdown files cannot be saved and how to choose another folder.
  - Migration errors explain which Markdown files moved, which did not, and how to retry safely.
  - Calendar connection errors keep manual recording available.
  - Failures do not silently discard transcript data.

## Step 16: Verify A Meeting End To End

- User goal: trust that Meeting007 worked.
- User action: records a short test meeting, copies recent context, stops recording, and opens the saved transcript.
- App response: produces live transcript, copied text, Markdown file, and local API/MCP visibility.
- Success result: user confirms the core v1 promise.
- Acceptance criteria:
  - Live transcript appears within the target latency.
  - Copy Last 5 Minutes works.
  - Final Markdown matches the app transcript.
  - Final Markdown is saved to the selected transcript folder.
  - Existing Markdown migration, when run, preserves file contents and reports any conflicts.
  - Calendar-connected meetings carry title and participant metadata when the user connected Google Calendar.
  - REST/MCP transcript matches the saved transcript.
  - No data leaves the Mac.
