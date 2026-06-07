# Security And Privacy

## Privacy Position

Meeting007 is local-first and local-only in v1. The default product path must not send audio, transcripts, summaries, prompts, or meeting metadata to any remote service.

## Sensitive Data

The following data is sensitive:

- Raw microphone audio.
- Raw system audio.
- Partial and final transcripts.
- Meeting titles and calendar metadata.
- Speaker labels.
- Local API/MCP tokens.
- Debug logs that include transcript or audio-derived text.

## Permissions

Request permissions only when needed:

- Microphone: when recording is first requested.
- Screen/system audio: when system audio capture is first requested.
- Calendar: when the user enables calendar-connected meeting start.
- Accessibility/global hotkey permissions: when hotkeys are enabled.

Permission screens must explain why the permission is needed and what data remains local.

## Audio Retention

V1 must make audio retention explicit before implementation:

- Option A: keep local audio for correction/debug until user deletes it.
- Option B: delete raw audio after transcript finalization.

The default must be chosen by product decision before raw audio persistence ships. Until then, implementation should avoid persistent raw audio by default.

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
- Permission prompts that obscure what is being captured.

Mitigations:

- Local-only ADR and code review rule.
- Keychain-backed local tokens.
- Localhost binding tests.
- Logging tests where practical.
- Clear first-run permission UX.

