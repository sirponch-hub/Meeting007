# Testing Strategy

## Test Pyramid

- Automated checks cover transcript domain logic, export, time windows, serialization, and storage mappings.
- Integration tests cover mocked audio chunks through VAD, STT, storage, REST, and MCP.
- Manual QA covers macOS permissions, live capture, Russian speech, and real meeting apps.

## Automated Checks

Required coverage:

- Transcript segment ordering.
- Partial-to-final segment replacement.
- Timestamp formatting.
- Copy full finalized transcript during an active meeting, including metadata header, chronological final segments, Russian text preservation, and exclusion of partial/live text.
- Copy last 5 minutes window selection, formatted clipboard text, metadata header, and live partial markers.
- Markdown export.
- Markdown file writer path, filename, folder creation, temp-file cleanup, and local-only scope.
- Markdown transcript folder setting, default folder behavior, selected-folder persistence, write-access validation, and recoverable unavailable-folder errors.
- Microphone recording lifecycle with fake capture: Start opens one mic lane, Stop closes it, late chunks are rejected, chunks remain session/lane/timing aware, selected microphone UID persists locally, sample-bearing PCM stays in memory, and microphone start failures surface stable user-facing errors.
- Runtime-only audio behavior: PCM is downmixed/resampled to mono 16 kHz, runtime chunks do not create raw audio files, Stop clears buffers, and Markdown export does not reference audio artifacts or sample metadata.
- VAD behavior: silence-only chunks are suppressed, speech-positive chunks create `SpeechChunk` utterances, short pauses stay inside one utterance, long silence separates utterances, and Stop flushes open speech deterministically.
- Local STT pipeline behavior: Russian default configuration, `SpeechChunk` input, mic-to-`Me` lane mapping, partial-to-final updates with stable segment identity, stopped-session chunk rejection, missing-model recoverable state, and exportability of final STT segments.
- Local STT model manager behavior: pinned Russian model policy, missing/invalid/downloading/download-failed recoverable states, verified local model directory only after manifest/file/SHA checks, ready-model pass-through, explicit prepared-artifact install boundary, and no automatic model download from core checks.
- Local STT model installer behavior: no download before explicit consent, cancel consent without side effects, confirmed install starts one controlled downloader request, progress/failure states are visible, successful install marks model readiness, existing verified installs skip download, installer failure leaves fake STT usable, and no raw audio artifacts are created.
- HuggingFace model downloader behavior: pinned Russian source, required WhisperKit CoreML/config/tokenizer entries, staging-before-promotion, per-file SHA-256 manifest writing, checksum mismatch rejection, missing required-file rejection, and offline reuse from `install.json` without network calls.
- WhisperKit adapter behavior: isolated SwiftPM adapter target compiles against the real `WhisperKit` product, defaults to Russian, accepts only normalized `SpeechChunk` input, builds the production engine only from a verified local model directory, returns stable missing-model state without automatic download, maps engine output to transcript segments, exposes runtime failures, and preserves fake STT checks.
- App transcription composition behavior: production recording uses the WhisperKit pipeline factory and must not emit deterministic fake transcript text when the model is missing or invalid.
- Completed-session runtime history after Stop.
- In-memory history deduplication and newest-first ordering.
- Google Calendar event mapping from title/topic, time, and participants into local meeting metadata using mocked provider fixtures.
- SQLite mapping and migrations.
- API response shapes.

## Integration Tests

Use deterministic fixtures:

- Synthetic audio chunks for mic and system lanes.
- Synthetic PCM frames for VAD and sample-clock timing.
- Fake local STT engine returning known partial and final segments.
- Fake WhisperKit transcription engine for adapter contract checks without model files.
- Fake HuggingFace repository and file fetcher for installer checks without network or a 626 MB model download.
- Optional local WhisperKit model path for manual spike proof; ordinary checks must not require downloading or committing model files.
- Temporary SQLite database.
- Temporary Markdown output folder.
- Fake transcript-folder settings store.
- Fake Google Calendar provider returning deterministic event metadata.
- Local API server bound to a random localhost port.

## Audio Fixture Policy

- Do not commit private meeting recordings.
- Do not commit customer, employee, or third-party conversation audio.
- Test fixtures must be synthetic, public-domain, or explicitly approved.
- Keep large model files and generated recordings out of git.

## Manual QA Checklist

- Apple Silicon Mac.
- macOS microphone permission prompt.
- macOS screen/system audio permission prompt.
- Calendar permission prompt.
- Google Calendar connection flow.
- Notification permission prompt when meeting reminders are implemented.
- Manual start/stop recording.
- Start recording from fresh microphone permission state and verify macOS asks for access.
- Grant microphone access and verify the mic lane shows activity while speaking.
- Open Settings, verify available microphone inputs appear under Audio Input, choose the intended microphone, and verify the main mic lane names that input before recording.
- Start recording with the selected microphone and verify the mic lane level responds to that physical input.
- Disconnect or make the selected microphone unavailable and verify the app shows a recoverable input error instead of silently using another microphone.
- Speak Russian into the microphone and verify live transcript text appears only after speech is detected.
- With the verified Russian model installed, verify transcript text reflects actual spoken Russian rather than the old deterministic fake phrase.
- With the model missing or corrupted, verify recording remains controllable and the transcript panel says transcription is unavailable without fake transcript text.
- Sit quietly for several seconds and verify silence does not create new transcript text.
- Stop while speaking and verify the last spoken phrase is not silently lost by the capture/VAD boundary.
- Deny microphone access and verify the app shows a recoverable blocked state without starting fake transcript preview.
- Stop recording and verify mic activity stops.
- Start/Stop recording multiple times and verify no duplicate mic activity indicators or stale recording states remain.
- Verify no `.wav`, `.caf`, `.m4a`, `.pcm`, `.aiff`, `.flac`, or `.mp3` artifacts are created in the transcript folder or app-specific Meeting007 temp/output folders by the mic capture slice.
- Stop recording and verify the completed session appears in recent recordings for the current app run.
- Start/stop a second recording and verify recent recordings stay newest first.
- Relaunch the app and verify prototype recent recordings are not presented as durable history until persistence ships.
- Global hotkey start/stop when that convenience feature is implemented.
- Zoom capture.
- Google Meet capture.
- Microsoft Teams capture.
- Slack huddle/call capture.
- Russian speech live transcription.
- Separate `Me` and `Others` lanes.
- Copy full transcript during active recording.
- Copy last 5 minutes during active recording.
- Verify Copy Last 5 Minutes is disabled before transcript preview text appears.
- Verify Copy Last 5 Minutes puts timestamped `Me`/`Others` transcript text on the clipboard.
- Stop meeting and verify Markdown output.
- Verify Markdown appears under `~/Documents/Meeting007/Transcripts/`.
- Change Markdown transcript folder and verify new exports use the selected folder.
- Verify existing Markdown transcripts are not moved silently after changing the folder.
- Verify Markdown migration is a separate action and requires explicit confirmation when implemented.
- Verify Markdown migration reports moved, skipped, conflicted, and failed files when implemented.
- Verify interrupted Markdown migration does not lose transcript files when implemented.
- Verify unavailable or read-only transcript folder shows a recoverable error and does not discard transcript text.
- Verify Markdown filename is date/title/UUID based and filesystem-safe.
- Verify Markdown contains final Russian segments and excludes partial preview lines.
- Verify a meeting can be named after Stop from the main `Meeting title` field by pressing Enter, and the re-exported Markdown uses the updated title.
- Verify `Show in Finder` and `Copy path` are available from the left recent-recordings row context menu.
- Verify `Transcript folder` shows the active Markdown folder path.
- Verify changing `Transcript folder` affects the next Markdown export.
- Verify reset returns new exports to `~/Documents/Meeting007/Transcripts/`.
- Verify no audio, SQLite, REST/MCP, telemetry, or cloud artifacts are created by Markdown export.
- In Settings, install the Russian model after explicit confirmation and verify progress moves through download/verify/install to Ready.
- Relaunch the app after a successful model install and verify Settings shows Ready without starting another download.
- Corrupt or remove one local model file in the app model folder and verify the model is no longer shown as Ready.
- Verify REST transcript matches Markdown.
- Verify MCP transcript matches REST.
- Connect Google Calendar and verify meeting title/topic and participants are imported into local meeting metadata.
- Verify manual recording still works when Google Calendar is disconnected, denied, expired, or unavailable.
- When calendar enhancements ship, verify today's meetings appear on the main screen, start-from-meeting uses the selected event, and Notification Center reminders appear only after permission.

## Performance Targets

- Live partial transcript appears within 2-4 seconds of speech.
- Final transcript available within 10 seconds after stop for a 30-60 minute meeting, excluding optional full re-transcription.
- UI remains responsive during active recording.
- Local API responds to transcript reads within 200 ms for normal personal-history sizes.

## Required Before Release

- `swift run Meeting007CoreChecks` passes.
- Manual QA checklist is complete for the release candidate.
- No private audio, transcript, token, model, database, or build artifact is committed.

## Main Branch Gate

Untested work must not enter `main`.

Before merging to `main`, each change must include:

- Automated verification command and result.
- Manual QA result when the change affects capture, permissions, UI, copy actions, local API, MCP, storage, or privacy.
- A clear note when a test is intentionally missing, including the follow-up needed to make the change mergeable.

If the verification story is incomplete, the branch can be used for exploration, but it is not ready for `main`.
