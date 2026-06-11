# Security And Privacy

## Privacy Position

Meeting007 is local-first and local-only in v1. The default product path must not send audio, transcripts, summaries, prompts, or meeting metadata to any remote service.

## Sensitive Data

The following data is sensitive:

- Raw microphone audio.
- Raw system audio.
- Partial and final transcripts.
- Meeting titles and calendar metadata.
- Meeting participants imported from calendar events.
- Speaker labels.
- Local API/MCP tokens.
- Google Calendar OAuth tokens.
- Debug logs that include transcript or audio-derived text.

## Permissions

Request permissions only when needed:

- Microphone: when recording is first requested.
- Screen/system audio: when system audio capture is first requested.
- Calendar: when the user enables calendar-connected meeting start.
- Notifications: when the user enables meeting-start reminders.
- Accessibility/global hotkey permissions: when hotkeys are enabled.

Permission screens must explain why the permission is needed and what data remains local.

## Audio Retention

V1 must make audio retention explicit before implementation:

- Option A: keep local audio for correction/debug until user deletes it.
- Option B: delete raw audio after transcript finalization.

The default must be chosen by product decision before raw audio persistence ships. Until then, implementation should avoid persistent raw audio by default.

Current microphone capture slice:

- Microphone capture starts only after the user presses Start.
- The app requests macOS microphone access only when recording is requested.
- Captured audio stays in process memory as runtime chunks for future local STT.
- Runtime chunks are cleared on Stop and are not written to Markdown, SQLite, logs, REST, MCP, telemetry, cloud storage, or raw audio files.
- The visible transcript remains marked as local preview until real local STT ships.

## Runtime Transcript History

Prototype completed-session history may keep transcript preview text in memory during the current app process. This is acceptable only when:

- No transcript preview text is written to SQLite, logs, REST, MCP, telemetry, or cloud services.
- The UI clearly avoids implying durable history before Markdown/SQLite persistence ships.
- A fresh app process starts with an empty runtime history unless durable storage has been explicitly implemented and reviewed.

## Markdown Transcript Files

Markdown transcript export is a local-only user-owned artifact.

- Default folder: `~/Documents/Meeting007/Transcripts/`.
- User-selected folders are allowed for new Markdown exports after explicit user choice.
- Existing Markdown transcripts must not be moved silently when the folder changes.
- Moving existing Markdown transcripts requires a separate explicit migration action and user confirmation.
- Cloud-synced folders must not become the default; they are acceptable only when the user intentionally selects one.
- The selected folder path is stored locally in app preferences.
- Folder validation may create the selected folder and a temporary probe file, then remove the probe file.
- Export writes UTF-8 Markdown files only.
- Export must not create raw audio, SQLite, REST/MCP, telemetry, cloud, or hosted-account side effects.
- Partial preview lines are excluded from the final Markdown file unless a future product decision changes export semantics.
- The UI must show the saved local path and make clear the file was generated from the current local transcript preview.
- Migration must remain local-only, avoid silent overwrites, and keep source files until the destination copy is verified.

## Google Calendar

Google Calendar integration is optional and local-first.

- Do not connect Google Calendar unless the user explicitly enables it.
- Request only the scopes needed to read event title/topic, time, and participants.
- Store Google OAuth tokens in Keychain.
- Store imported calendar metadata locally with the meeting record.
- Manual recording must remain available when Google Calendar is disconnected, denied, expired, or unavailable.
- Do not upload calendar event data, participant lists, transcripts, or derived summaries to a hosted Meeting007 service in v1.
- Before exposing participant metadata through REST or MCP, confirm that the local access permission model makes this visible to the user.

## Local API And MCP

- Bind to `127.0.0.1` or `localhost` by default.
- Do not listen on external interfaces in v1.
- Require a local access token.
- Store tokens in Keychain in app code.
- Provide a user-visible setting to disable local services.

## Logging

- Logs must not include raw audio.
- Logs must not include full transcript text by default.
- Error logs may include meeting IDs and non-sensitive status codes.
- Debug transcript logging requires an explicit developer-only flag and must not be enabled in release builds.

## Threat Model

Primary risks:

- Accidental cloud upload.
- Local endpoint exposed beyond localhost.
- Sensitive transcript text written to logs.
- Raw audio retained without user consent.
- Google Calendar tokens or participant metadata exposed through logs, files, or local APIs without clear consent.
- User-selected transcript folder unavailable during finalization.
- Permission prompts that obscure what is being captured.

Mitigations:

- Local-only ADR and code review rule.
- Keychain-backed local tokens.
- Localhost binding tests.
- Logging tests where practical.
- Clear first-run permission UX.
- Keychain storage for Google Calendar tokens.
- Recoverable transcript export errors with clear change-folder action.
