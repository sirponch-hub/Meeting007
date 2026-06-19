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
- Product update: temporary local audio spooling for loss-resistant transcription finalization is allowed as a separate P0 pipeline requirement, but only until successful final transcript completion. See [ADR 0002](adr/0002-temporary-local-audio-spool.md).

ADR 0002 chooses temporary raw-audio retention only for loss-resistant local finalization. Permanent audio retention remains disallowed by default.

Temporary finalization spool policy:

- The spool exists only to prevent transcript loss when live STT starts late, fails, or finalization needs to recover the captured tail.
- The spool must stay local on the Mac and must not contact remote services.
- The spool must not be exposed through Markdown, SQLite transcript records, REST, MCP, logs, telemetry, debug transcript dumps, or user-facing transcript export.
- The spool should be deleted automatically after successful final transcript completion.
- If finalization fails or times out, the spool may be retained only to support a local retry/recovery state and must be deleted after recovery or explicit user discard.
- The implemented spool lives under app-owned `Application Support/Meeting007/CaptureSpool`, is excluded from backup, uses `0700` session directories and `0600` files, and exposes no paths through its public metadata models.
- The spool remains after capture close. It is deleted only after complete-spool finalization succeeds and Markdown is written locally. Decode/finalization/Markdown failure preserves it; orphan recovery/discard UX remains required follow-up work.
- Non-empty captured audio that produces no final transcript text is treated as incomplete finalization and is never a cleanup success.

Current microphone capture and spool slice:

- Microphone capture starts only after the user presses Start.
- The app requests macOS microphone access only when recording is requested.
- Captured audio is normalized to 16 kHz mono Float PCM and written locally to the temporary capture spool before live STT fanout.
- Runtime chunks are cleared on Stop. Temporary spool audio is not written to Markdown, SQLite, logs, REST, MCP, telemetry, or cloud storage.
- VAD emits only in-memory speech windows (`SpeechChunk`) into the local STT boundary and flushes an active speech window on Stop.
- The visible transcript is now fed through the local STT pipeline boundary. The current deterministic Russian transcriber is runtime-only and does not write raw audio, model files, transcript debug dumps, or network payloads.

Current local STT model policy:

- The current model manager pins the Russian production candidate to `large-v3-v20240930_626MB` and treats `tiny` as debug-only.
- The app can show model readiness state in Settings and requires a confirmation sheet before starting model installation.
- Model installer state is separate from meeting recording and transcript export; it may write model markers/files only under app-owned Application Support model storage.
- The production installer may contact HuggingFace only after explicit user consent and only to fetch model metadata/files for `argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_626MB` at the pinned revision.
- Downloaded model files are staged locally, verified with required-file checks and SHA-256, then promoted to the final local model folder. `install.json` is written last and is required for future offline readiness checks.
- Model installation also fetches the local Whisper tokenizer files required for text decoding. A CoreML-only model folder is treated as invalid instead of being shown as ready.
- The app recording flow uses the WhisperKit adapter only with a verified local model directory from `LocalSTTModelStore`.
- The WhisperKit adapter target compiles against the upstream local SDK, but Meeting007 does not call automatic model download from the adapter and keeps `download: false`.
- Meeting007 does not bundle Whisper model files and does not add a Meeting007 cloud transcription path.
- Model download may fetch model artifacts only; it must never upload audio, transcripts, meeting metadata, or debug content.
- If the verified model is missing or invalid, recording may continue but production transcription does not silently fall back to fake transcript text.

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
