# Workstreams

Use this file to keep parallel development coordinated. Every active branch or substantial task should leave enough context for another engineer or agent to continue safely.

Delivery gates and agent roles are defined in `docs/process/agent-workflow.md`.

## Rules

- Record work before or during implementation, not only after.
- Describe work in business and user-experience terms first.
- Link to technical docs or ADRs when implementation details matter.
- Keep status current when a workstream starts, changes direction, is blocked, or completes.
- Do not mark work ready for `main` until verification is documented.
- Do not mark work ready for review until required subagent reviews are complete and summarized.
- UI-affecting work must include UX Designer and Acceptance/QA subagent notes before code is written.
- Code-changing work must include Developer subagent notes and TDD/BDD evidence before it is marked ready for review.
- Revisit skills/MCP needs when a workstream reaches one of the tooling triggers below.
- After an accepted workstream is merged to `main`, show the user the top 3 next backlog options so they can choose the next step.

## Tooling Triggers

Remind the user to consider extra skills or MCP/connectors when these moments arrive:

- GitHub issues, pull requests, or branch protection become active: consider GitHub connector/MCP.
- SQLite storage is implemented: consider SQLite inspection tooling.
- Local REST or Meeting007 MCP is implemented: dogfood it through AI clients.
- UI design moves beyond in-repo wireflows: consider Figma connector/MCP.
- Repeated role workflows become stable across branches: consider promoting `docs/agents/*` into reusable Codex skills.
- CI starts gating `main`: consider CI/GitHub Actions visibility tooling.

## Template

```markdown
## <Workstream Name>

- Status: Planned | In Progress | Blocked | Ready for Review | Done
- Owner: <name or agent>
- User outcome: <what user workflow or requirement improves>
- Scope: <what is included>
- Out of scope: <what should not be changed>
- Docs touched: <BRD, architecture, ADR, testing, privacy, etc.>
- Verification: <commands/manual QA required and latest result>
- Gates: <BA / UX / Architecture / Specialist Reviews / Acceptance Tests / Development / Integration / BA+UX Acceptance / User Acceptance / Merge>
- Subagents: <required roles and status, plus links/summaries of outputs>
- TDD/BDD evidence: <check added first / check updated alongside / documented manual-only gap>
- Open decisions: <business/product decisions still needed>
- Handoff notes: <context needed for parallel work>
```

## Current Workstreams

## Streaming Partials Rolling Buffer Spike

- Status: Ready for Review
- Owner: Codex + Research/Architecture/QA agents
- User outcome: Prove a safer local transcription architecture for fast Russian speech before changing the user-facing transcript experience again.
- Scope: Add backend-only rolling audio buffer, rolling-window decode contract, LocalAgreement-style transcript stabilizer, seam-local rolling hypothesis filtering so overlap/prompt echo is not shown as repeated live text, fake-decoder checks showing partial text can appear before the current VAD final-chunk path, a real WhisperKit rolling-window adapter that can decode rolling windows with committed transcript prompt context, and a manual smoke command for rolling-vs-5s-batch comparison on a local Russian fixture.
- Out of scope: Production WhisperKit streaming, UI changes, debug controls, audio files, raw audio retention after Stop, REST/MCP/SQLite exposure, cloud STT, diarization, and replacement of the current recording flow.
- Docs touched: `docs/workstreams.md`, `docs/testing.md`.
- Verification: `swift run Meeting007CoreChecks` passed; `swift run Meeting007WhisperKitChecks` passed; `swift build --product Meeting007RollingWhisperKitSmoke` passed with sandbox escalation; `swift build --product Meeting007App` passed with sandbox escalation for Swift/clang cache access.
- Gates: Research agent identified current VAD/WhisperKit path as batch, not real-time; architecture/QA agent recommended a backend-only rolling-buffer spike with fake decoder and strict privacy boundaries; follow-up BA/Architecture/Developer agents recommended seam-local deduplication rather than global phrase removal after the user observed repeated rolling output; user acceptance pending.
- Subagents: Research `019ecc5a-4906-7240-8764-bdc6b68e5402`; Architecture/QA `019ecc5e-48db-7111-be9b-bbdd11b19fb3`; BA `019ecf1b-f46a-7db0-871e-e954eb07d5fe`; Rolling architecture/QA `019ecf1c-0e60-7550-8234-68dc86749f15`; Developer/TDD `019ecf1d-4cca-7072-be1f-a64768da7b93`.
- TDD/BDD evidence: Added checks for bounded rolling buffer retention, Stop cleanup, wrong-session rejection, earlier partial output than VAD final chunks, LocalAgreement stable-prefix commits, seam-local prompt echo removal, suffix/prefix rolling overlap merging, real repeated Russian phrase preservation, repeated partial replacement behavior, verified-model rolling adapter construction, missing-model no-engine behavior, rolling prompt/window forwarding, and rolling runtime failure reporting.
- Open decisions: Whether to temporarily retain audio locally until finalization, target rolling window duration, model choice for live preview, and manual Russian fast-speech fixture policy.
- Handoff notes: This spike intentionally does not wire into `Meeting007App`. WhisperKit context is supported through tokenizer-encoded `promptTokens`. Run the manual benchmark with `swift run Meeting007RollingWhisperKitSmoke /path/to/russian-audio.wav`; the command prints only changed rolling live states and 5-second batch output without saving audio or transcript files.

## Wire Real WhisperKit Into Recording Flow

- Status: Ready for Review
- Owner: Codex + BA/UX/Architecture/QA/Developer agents
- User outcome: When the verified Russian model is installed locally, manual recording uses real local WhisperKit transcription instead of deterministic fake transcript text, while Start/Stop remains reliable and missing-model states stay honest.
- Scope: Add verified model directory provider in core, wire `Meeting007App` to `Meeting007WhisperKit`, add a production WhisperKit pipeline factory, build the WhisperKit engine only from a verified local model path, prepare and cache one WhisperKit runtime for the active session, let the user choose the microphone used for new recordings, keep microphone capture non-blocking while STT processes speech chunks, deliver speech chunks to STT in sample-clock FIFO order, add boundary overlap for continuous speech chunks, flush open speech before Stop finalizes STT, keep the transcript view updating while Stop finalizes delayed STT output, tune default VAD for live meetings with quicker speech windows and quieter-speech pickup, preserve `download: false`, remove production fake STT default, install/verify required tokenizer files, surface runtime failures instead of silently returning empty transcripts, keep fake STT for explicit tests/dev injection, and update transcript surface copy from preview/future-slice language to live local transcription language.
- Out of scope: Partial-rich word streaming, Russian quality benchmark thresholds, system-audio transcription, diarization, raw audio retention, REST/MCP changes, model repair/delete UX, cloud STT, telemetry, and hosted backend.
- Docs touched: `docs/architecture.md`, `docs/security-privacy.md`, `docs/testing.md`, `docs/workstreams.md`.
- Verification: `swift run Meeting007CoreChecks` passed; `swift run Meeting007WhisperKitChecks` passed; `swift build --product Meeting007App` passed with sandbox escalation for Swift/clang cache access.
- Gates: BA required real WhisperKit for ready model and no silent fake fallback; UX required honest ready/loading/missing/error states and no fake transcript text in production; architecture required a verified model directory provider and app composition through `Meeting007WhisperKit`; QA required composition, missing model, no auto-download, stop flush, privacy, and manual Russian Apple Silicon checks; Developer/TDD required red checks before implementation.
- Subagents: BA `019eca7f-55e3-7110-8b71-2097183dfba8`, Architecture `019eca7f-7941-7361-8356-ba73a0a1983b`, UX `019eca7f-9086-7fe2-83fb-75d2e7d9eb20`, QA `019eca7f-b0f9-7662-b6d6-634b73f762b3`, Developer/TDD `019eca80-c8aa-74d3-bccb-661a41cd6cbc`.
- TDD/BDD evidence: Added core checks for verified model directory path, corrupt-file rejection, tokenizer-required readiness, tokenizer download manifest, old CoreML-only install rejection, persisted microphone input selection, non-blocking runtime audio capture while STT is slow, ordered STT speech chunk delivery, Stop-time speech flush before STT finalization, live-meeting VAD defaults, continuous fast-speech chunking, and boundary overlap for continuous speech; added WhisperKit checks for verified-directory engine construction, missing-directory no-engine/no-download behavior, production pipeline not emitting fake text when model is missing, runtime failure reporting, Russian defaults, transcript segment mapping, and no audio artifact creation.
- Open decisions: Real-world Russian accuracy threshold, live latency target after SDK load, whether to start STT before opening the microphone so speech during model warmup is not dropped, and whether recording should show a Settings shortcut when the model is missing.
- Handoff notes: The first real wiring emits final speech-window segments through the existing VAD/STT path, so text still appears after speech boundaries rather than word-by-word. The installed model now includes tokenizer files, the local engine prepares/caches the WhisperKit runtime at transcription start instead of rebuilding it per speech chunk, Settings exposes a choose-before-start microphone selector, microphone capture does not wait for slow STT, speech chunks are delivered to STT in FIFO order, continuous hard-cut chunks include a short overlap so boundary words are less likely to disappear, Stop now closes capture before stopping the STT session so the last spoken words can be flushed, the transcript timer stays alive during Stop finalization, and the default VAD now cuts continuous speech at about five seconds instead of waiting for long monologues. Manual QA with real Russian mic speech on Apple Silicon is required before merging to `main`; ordinary checks use fakes and do not require private audio fixtures.

## Real HuggingFace Model Downloader + Checksum

- Status: Ready for Review
- Owner: Codex + BA/UX/Architecture/QA/Developer agents
- User outcome: User can install the real local Russian transcription model from Settings after explicit consent, and Meeting007 verifies the downloaded model before it ever reports local transcription as ready.
- Scope: Add production `HuggingFaceModelDownloader`, pinned `argmaxinc/whisperkit-coreml` source for `openai_whisper-large-v3-v20240930_626MB`, staging folder download, required CoreML/config file validation, per-file SHA-256 calculation, HuggingFace LFS checksum comparison when available, verified `install.json`, app wiring to the real downloader, and offline reuse of existing valid installs without re-download.
- Out of scope: Wiring real WhisperKit into active recording, Russian accuracy benchmark, multi-model picker, model delete/repair UI, resumable downloads after app relaunch, custom model folder setting, raw audio retention, cloud STT, accounts, hosted backend, and diarization.
- Docs touched: `docs/architecture.md`, `docs/security-privacy.md`, `docs/testing.md`, `docs/workstreams.md`.
- Verification: `swift run Meeting007CoreChecks` passed; `swift build --product Meeting007App` passed with sandbox escalation for Swift/clang cache access.
- Gates: BA confirmed Settings-only explicit install, trusted HuggingFace source, no hidden download, and safe failure; UX confirmed no new main UI and user-facing statuses only; architecture required pinned source, staging, manifest/checksum, install marker written last, no WhisperKit auto-download, and no audio upload; QA defined BDD checks for consent, source, progress, checksum, reuse, cancellation, failure safety, and local-first privacy; Developer/TDD defined red checks before implementation; user acceptance pending; merge pending.
- Subagents: BA `019eca3c-866c-7a52-93c5-04d997f9936f`, Architecture `019eca3c-9eba-7eb0-be45-e89701f026cd`, UX `019eca3d-4864-74f1-bceb-5e73ed698579`, QA `019eca3d-7062-7202-bbc0-c04b73e09b99`, Developer/TDD `019eca3f-5ddf-79a1-9781-1f79850988ef`.
- TDD/BDD evidence: Added checks for pinned HuggingFace source, staging-before-promotion, verified manifest writing, checksum mismatch rejection, missing required-file rejection, existing valid install skipping download, wrong policy/language/manifest rejection, progress/failure state, fake STT survival after installer failure, and no audio artifacts.
- Open decisions: Whether to replace short revision `7235bbd` with a full commit SHA from a live metadata lookup before release, whether to add a checked-in signed hash manifest for stronger supply-chain protection, disk-space preflight UX, model delete/repair UX, and real WhisperKit runtime enablement.
- Handoff notes: Ordinary automated checks use fake HuggingFace repository/fetcher fixtures and do not require network or a 626 MB download. The app now uses the real downloader behind the existing confirmation sheet, so manual QA can trigger the large download intentionally from Settings.

## Consented Model Download Installer

- Status: Ready for Review
- Owner: Codex + BA/UX/Architecture/QA/Developer agents
- User outcome: User can start Russian model installation from Settings only after explicit consent, understand local/offline/no-audio-upload implications, and keep recording/fake STT usable if installation fails.
- Scope: Add model installer state machine, app-owned Application Support model store, downloader abstraction, explicit consent sheet, Settings install/progress/failure controls, model readiness marker after successful controlled install, reuse of an existing matching installed model without re-download, and documentation for privacy and verification.
- Out of scope: Real recursive HuggingFace model-folder download, checksum manifest hardening, switching recording flow to real WhisperKit, model deletion, model storage location setting, resume after app restart, raw audio retention, cloud STT, accounts, and hosted backend.
- Docs touched: `docs/architecture.md`, `docs/security-privacy.md`, `docs/testing.md`, `docs/workstreams.md`.
- Verification: `swift run Meeting007CoreChecks` passed after core installer changes. `swift build --product Meeting007App` is pending because sandbox escalation hit the current usage limit; sandbox-only build is blocked by Swift/clang cache permissions, not by project diagnostics.
- Gates: BA required explicit consent, local/offline/no-upload copy, failure-safe recording, and no real transcription claim; UX required Settings-only install, native confirmation sheet, stable progress, and calm main screen; architecture required Application Support model storage, downloader boundary, verified local path before adapter use, and `download:false`; QA required consent/download/failure/no-audio checks; Developer required TDD checks before UI wiring; user acceptance pending; merge pending.
- Subagents: BA, UX Designer, System Architect/Security, Acceptance/QA, and Developer outputs summarized here.
- TDD/BDD evidence: Added checks for no download before consent, cancelling consent, confirmed install request, existing matching model reuse without downloader calls, wrong policy/language/manifest rejection, progress/failure state, ready availability marker, failed install preserving fake STT, cancel clearing pending state, and absence of audio artifacts.
- Open decisions: Real HuggingFace recursive downloader, checksum manifest source, exact verified model folder structure, delete/reinstall UX, disk-space preflight, and app-level switch from fake STT to real WhisperKit.
- Handoff notes: Current production downloader is intentionally unconfigured and returns a controlled failure instead of pretending to install a model. If a matching `install.json` for the current Russian model policy already exists in the app model folder, installer readiness goes straight to Ready and does not call the downloader. This keeps hidden download and verification risks out of `main` until a real manifest/checksum downloader is implemented.

## WhisperKit Real Adapter Dependency Spike

- Status: Ready for Review
- Owner: Codex + BA/UX/Architecture/QA/Developer agents
- User outcome: Meeting007 now proves it can compile a real local WhisperKit adapter behind the existing `SpeechChunk` STT boundary, without changing the meeting-time Start/Stop workflow or introducing cloud transcription.
- Scope: Add SwiftPM dependency on `argmaxinc/argmax-oss-swift`, isolate `WhisperKit` in `Meeting007WhisperKit`, add `WhisperKitSpeechTranscriber` contract adapter, keep Russian default, reject missing model without auto-download, preserve fake STT, and add dedicated adapter checks.
- Out of scope: Consented model installer/download UI, production model path management, real app runtime switch to WhisperKit, Russian accuracy benchmark, latency tuning, system audio STT, diarization, raw audio retention, hosted backend, and cloud fallback.
- Docs touched: `docs/architecture.md`, `docs/security-privacy.md`, `docs/testing.md`, `docs/workstreams.md`.
- Verification: `swift run Meeting007WhisperKitChecks` passed with dependency resolution; final core/app verification pending in this branch.
- Gates: BA accepted dependency spike as proof of local real-STT readiness; UX required no new debug UI and Settings-only model readiness; architecture required isolated target and compile-only boundary; QA required missing-model/no-download, Russian default, `SpeechChunk` boundary, fake fallback, and privacy checks; Developer required TDD checks before implementation; user acceptance pending; merge pending.
- Subagents: BA, UX Designer, System Architect/macOS STT Specialist, Acceptance/QA, and Developer outputs summarized here.
- TDD/BDD evidence: Added `Meeting007WhisperKitChecks` for Russian default, `SpeechChunk` acceptance, missing model without download, transcript segment mapping, fake STT non-regression, and no file persistence in adapter validation.
- Open decisions: Exact model cache path, consented installer UX, checksum/manifest policy, opt-in real model integration harness, app-level runtime switch, and Russian benchmark acceptance threshold.
- Handoff notes: SwiftPM resolved `argmax-oss-swift` at `0.18.0` from the `from: 0.9.0` constraint. This branch compiles the real SDK but uses a fake WhisperKit engine for deterministic checks; do not wire automatic download or cloud fallback into the app.

## PCM/VAD Sample-Bearing Capture

- Status: Ready for Review
- Owner: Codex + BA/UX/Architecture/QA/Developer agents
- User outcome: Spoken Russian microphone audio can now reach the local STT boundary as in-memory speech windows, which is the prerequisite for real WhisperKit transcription of actual mic audio.
- Scope: Add sample-bearing runtime PCM chunks, mono 16 kHz normalization, VAD speech-window chunking, Stop-time speech flush, STT boundary input as `SpeechChunk`, and AVAudioEngine mic emission of in-memory PCM with sample-clock timestamps.
- Out of scope: Real WhisperKit dependency, model download, raw audio file retention, system audio capture, speaker diarization, waveform/debug UI, cloud fallback, telemetry, REST/MCP exposure of samples, and any hosted backend.
- Docs touched: `docs/architecture.md`, `docs/security-privacy.md`, `docs/testing.md`, `docs/workstreams.md`.
- Verification: `swift run Meeting007CoreChecks` passed; `swift build --product Meeting007App` passed with sandbox escalation for Swift module cache access.
- Gates: BA confirmed the user outcome is sample-bearing mic capture for local transcription without raw persistence; UX required no waveform/debug UI and only existing calm listening/quiet status; architecture required PCM normalization, lane preservation, VAD before STT, and sample-clock timing; QA required synthetic PCM/VAD checks, Stop/late-frame behavior, and privacy regression checks; Developer recommended TDD checks before implementation; user acceptance pending; merge pending.
- Subagents: BA, UX Designer, System Architect/macOS STT Specialist, Acceptance/QA, and Developer outputs summarized here.
- TDD/BDD evidence: Added checks for runtime PCM normalization, active-session-only sample buffering, VAD silence suppression, speech chunk emission, short-pause/long-silence boundaries, Stop flush, STT over `SpeechChunk`, and Markdown privacy regression.
- Open decisions: Final production VAD thresholds, WhisperKit adapter package pin, model cache path, real Russian speech acceptance fixture, and system-audio lane normalization.
- Handoff notes: PCM and `SpeechChunk` samples are runtime-only sensitive data. Do not expose them through Markdown, SQLite, REST, MCP, logs, debug descriptions, or files. The next WhisperKit adapter should consume `SpeechChunk` rather than `CapturedAudioChunk`.

## WhisperKit Adapter + Model Manager

- Status: Ready for Review
- Owner: Codex + BA/UX/Architecture/QA/Developer agents
- User outcome: User can see and trust the local Russian model readiness state before production Whisper transcription is enabled, with model setup kept in Settings rather than the live meeting surface.
- Scope: Add pinned Russian Whisper model policy, model availability states, model manager protocol, explicit prepared-artifact install boundary, model-managed STT wrapper, Settings transcription row, disabled download affordance, and documentation for consent/offline/no-upload behavior.
- Out of scope: Adding the WhisperKit SwiftPM dependency, downloading model artifacts, validating checksums, PCM sample capture, VAD, real Russian Whisper transcription, model deletion, model marketplace, cloud fallback, telemetry, raw audio retention, and production accuracy claims.
- Docs touched: `docs/architecture.md`, `docs/security-privacy.md`, `docs/testing.md`, `docs/product/user-steps.md`, `docs/workstreams.md`.
- Verification: `swift run Meeting007CoreChecks` passed; `swift build --product Meeting007App` passed.
- Gates: BA required explicit model download consent and offline-after-install behavior; UX required model controls in Settings with calm main UI; architecture issued no-go for direct WhisperKit over metadata-only `CapturedAudioChunk` and required PCM/VAD prerequisites; QA required privacy/model-state automation plus Russian manual smoke before real runtime enters `main`; Developer recommended model-manager boundary first, real dependency second; user acceptance pending; merge pending.
- Subagents: BA, UX Designer, System Architect/macOS STT Specialist, Acceptance/QA, and Developer outputs summarized here.
- TDD/BDD evidence: Added checks for pinned Russian model policy, missing/invalid model recoverable states, ready-model pass-through, blocking audio processing when model is unavailable, and explicit consent plus prepared local artifact requirement before install.
- Open decisions: Exact installer/download implementation, model cache path, checksum/manifest source, offline network detection, PCM payload type, VAD/chunker, WhisperKit package pin, and Apple Silicon Russian smoke acceptance script.
- Handoff notes: This branch intentionally does not add WhisperKit dependency or network download. Next branch should add PCM/VAD sample-bearing capture or WhisperKit adapter only after those prerequisites are accepted.

## Local STT / Whisper Russian First Slice

- Status: Ready for Review
- Owner: Codex + BA/UX/Architecture/QA/Developer agents
- User outcome: User sees the transcript area fed through a local Russian STT pipeline boundary instead of a standalone mock-preview controller, so copy/export flows can consume the same kind of segments that the real Whisper runtime will produce.
- Scope: Add Russian-first STT session config, local STT pipeline lifecycle, deterministic fake Russian transcriber, missing-model state, stopped-session chunk rejection, UI local-transcription status, and wiring from recording start/stop to STT segments.
- Out of scope: Real WhisperKit adapter, model download, model bundling, model benchmark, PCM sample capture, VAD/chunker, system audio STT, diarization, cloud fallback, raw audio persistence, REST/MCP persistence, and production accuracy claims.
- Docs touched: `docs/architecture.md`, `docs/security-privacy.md`, `docs/testing.md`, `docs/product/BRD.md`, `docs/workstreams.md`.
- Verification: `swift run Meeting007CoreChecks` passed. `swift build --product Meeting007App` passed after code changes; final repeat build after documentation-only updates was blocked by the tool usage limit, not by a project error.
- Gates: BA confirmed local Russian STT user outcome and privacy constraints; UX accepted quiet loading/listening/transcribing/error states; architecture recommended WhisperKit behind `SpeechTranscribing` with model policy as a separate slice; QA defined deterministic fake STT checks plus manual Russian QA for real runtime; Developer recommended a mergeable STT contract/fake-transcriber slice before real runtime dependency; user acceptance pending; merge pending.
- Subagents: BA, UX Designer, System Architect/macOS STT Specialist, Acceptance/QA, and Developer outputs summarized here.
- TDD/BDD evidence: Added checks for Russian default, mic-to-`Me` mapping, partial-to-final stable segment identity, ignoring chunks after Stop, missing model recoverable state, and Markdown export of final STT segments before/alongside implementation.
- Open decisions: Exact WhisperKit model default (`large-v3-v20240930_626MB` vs `large-v3-v20240930_turbo`), model download consent UX, model storage path/checksum policy, PCM sample representation, VAD thresholds, latency budget for acceptance, and whether recording may proceed when the local model is missing.
- Handoff notes: This branch intentionally does not download Whisper models or claim production STT accuracy. Next branch should implement WhisperKit adapter and model manager behind `SpeechTranscribing`, plus PCM/VAD path from `AVAudioEngine`.

## Real Microphone Capture Lane

- Status: Done
- Owner: Codex + BA/UX/Architecture/QA/Developer agents
- User outcome: User can press Start and know Meeting007 is really listening to the Mac microphone as the `Me` lane, while still understanding that visible transcript text is preview-only until local STT ships.
- Scope: Manual Start requests microphone permission when needed, starts an `AVAudioEngine` microphone lane, shows compact `Me` lane status, stops and clears runtime audio on Stop, exposes recoverable permission-denied state, and keeps audio runtime-only.
- Out of scope: Real STT, system audio capture, device picker, raw audio retention, SQLite, REST/MCP, hotkeys/menu bar, cloud fallback, diarization, and calendar-triggered capture.
- Docs touched: `docs/architecture.md`, `docs/security-privacy.md`, `docs/testing.md`, `docs/workstreams.md`.
- Verification: `swift run Meeting007CoreChecks` passed; `swift build --product Meeting007App` passed before acceptance. Final post-merge verification recorded below after both accepted features merged.
- Gates: BA defined user outcome and exclusions; UX accepted compact `Me · Listening/Quiet/Blocked` lane and denied-permission recovery; architecture accepted `RecordingCaptureDriver` as the integration boundary and AVFoundation at the app edge; QA defined lifecycle, permission, no-persistence, and manual Apple Silicon checks; Developer defined TDD slice and fake mic checks; implementation complete; user accepted; merge complete.
- Subagents: BA, UX Designer, System Architect/macOS Audio Specialist, Acceptance/QA, and Developer outputs summarized in this entry. Key shared decision: this slice proves live mic capture without implying real transcription.
- TDD/BDD evidence: Added fake microphone lifecycle checks in `Meeting007CoreChecks` before platform driver verification: start opens mic lane, stop closes it, chunks carry `.mic` metadata, permission failure surfaces stable error, and Markdown export does not create/reference audio artifacts.
- Open decisions: Whether future raw audio retention defaults to keep-local-for-correction or auto-delete after transcript finalization; whether first real STT slice consumes PCM buffers directly or through a VAD/chunker actor.
- Handoff notes: The transcript panel still uses the existing mock Russian preview. Do not connect fake transcript progress to mic level; that would make users think real audio is being transcribed.

## Copy Full Transcript During Meeting

- Status: Done
- Owner: Codex + BA/UX/Architecture/QA/Developer agents
- User outcome: User can copy the full finalized transcript captured so far during an active meeting without stopping recording or waiting for Markdown export.
- Scope: Add `Copy Full Transcript` in the transcript panel beside `Copy Last 5 Minutes`, copy finalized current-meeting transcript lines with local metadata header, show quiet clipboard feedback, keep recording and preview running, and keep all behavior local clipboard only.
- Out of scope: Hotkey/menu command, menu bar action, completed-session copy, Markdown export changes, REST/MCP, SQLite, real STT/audio changes, cloud sync, telemetry, and raw audio/storage changes.
- Docs touched: `docs/product/BRD.md`, `docs/product/user-steps.md`, `docs/testing.md`, `docs/workstreams.md`.
- Verification: `swift run Meeting007CoreChecks` passed; `swift build --product Meeting007App` passed before acceptance. Final post-merge verification recorded below after both accepted features merged.
- Gates: BA accepted finalized-only full transcript copy to preserve trust; UX accepted one compact transcript-panel copy row with clear labels; architecture accepted core formatter plus app clipboard command with no storage/API changes; QA defined disabled/active/failure/no-side-effect checks; Developer defined TDD checks and app integration points; user accepted; merge complete.
- Subagents: BA, UX Designer, System Architect, Acceptance/QA, and Developer outputs summarized here. Architecture/Developer suggested partial inclusion for live copy; BA/product decision for this slice is finalized-only because `Full Transcript` should not spread unstable partial text as trusted content.
- TDD/BDD evidence: Added core checks for full transcript metadata, inclusion of old and recent final segments, exclusion of partial/live text, and empty/partial-only transcript behavior before wiring the UI action.
- Open decisions: Whether a future separate `Copy Live Transcript` command should include partial text; whether full-copy should become available for completed sessions/history when durable transcript browsing ships.
- Handoff notes: `Copy Last 5 Minutes` remains the live-context action and keeps partial `(live)` lines. `Copy Full Transcript` is the safer stable transcript action.

## Process Guardrail: Mandatory Subagent Gates

- Status: Ready for Review
- Owner: Codex
- User outcome: Prevent future work from bypassing the agreed BA, UX, architecture, QA, and specialist review flow.
- Scope: Repository rules now require relevant subagents before implementation, especially UX Designer and Acceptance/QA for UI changes; workstreams must record required subagent roles and status.
- Scope update: code-changing work also requires Developer subagent notes and TDD/BDD evidence before ready-for-review.
- Out of scope: Changing product behavior or app code.
- Docs touched: `AGENTS.md`, `docs/process/agent-workflow.md`, `docs/workstreams.md`.
- Verification: Documentation-only change; repository rules reviewed locally.
- Gates: Process update drafted; user acceptance pending; merge pending.
- Subagents: Not required for this meta-process rule update; the purpose is to make future product work require them.
- TDD/BDD evidence: Documentation-only process update; no app code changed.
- Open decisions: Whether to promote the role prompts in `docs/agents/` into reusable Codex skills later.
- Handoff notes: If future required subagent tooling is unavailable, mark the workstream blocked and ask the user before implementing.

## Configurable Markdown Transcript Folder

- Status: Ready for Review
- Owner: Codex + BA/UX/Architecture/QA agents
- User outcome: User can save new owned Markdown transcripts into the folder where they actually work, such as a local knowledge base or explicitly chosen sync folder.
- Scope: Local folder preference inside a separate sidebar-driven `Settings` mode, default folder preservation, native folder picker, write-access validation, reveal/copy/reset actions, new Markdown exports use selected folder, no silent migration of existing files.
- Out of scope: Dedicated Settings window, migrating existing Markdown files, sandbox security-scoped bookmarks, SQLite folder metadata, REST/MCP folder controls, cloud defaults.
- Docs touched: `docs/product/user-steps.md`, `docs/architecture.md`, `docs/security-privacy.md`, `docs/testing.md`, `docs/workstreams.md`.
- Verification: `swift run Meeting007CoreChecks` passed; `swift build --product Meeting007App` passed.
- Gates: BA scope documented; UX implementation complete; architecture boundary documented; automated checks passed; user acceptance pending; merge pending.
- Open decisions: Whether the first migration slice only moves known Meeting007 folders or also supports user-selected source folders; whether production sandboxing requires security-scoped bookmarks.
- Handoff notes: The selected path is stored in app preferences through `MarkdownTranscriptFolderSettings`. Changing the folder affects future exports only. Folder controls belong in the sidebar-driven `Settings` mode, not the primary recording/transcript flow.

## Premium UI IA Cleanup

- Status: Done
- Owner: Codex + UX Designer agent
- User outcome: Make the main window feel like a calm native macOS work surface where recording state, meeting title, transcript, and recent recordings have clear hierarchy.
- Scope: Compact top recording strip, single editable meeting title in the header, icon-only start/stop control with tooltip and accessibility label, disclosed quick note, active recording row pinned in the left tree, reduced card-like main layout.
- Out of scope: Full visual redesign, durable sidebar selection/navigation, Copy Full Transcript, configurable transcript folder UI, real audio/STT, menu bar controls, hotkeys.
- Docs touched: `docs/workstreams.md`.
- Verification: `swift run Meeting007CoreChecks` passed; `swift build --product Meeting007App` passed after merge to `main`.
- Gates: UX implementation complete; automated checks passed; user accepted; merge complete.
- Open decisions: Whether the active recording row should become selectable before durable history exists; exact icon style for future Liquid Glass toolbar once the app targets the latest macOS SDK.
- Handoff notes: Start/Stop is intentionally icon-only in the visible UI, with `record.circle` for start and `stop.circle.fill` for stop. Accessible labels and hover help preserve discoverability without adding visible text buttons.

## Requirements: Configurable Markdown Storage And Google Calendar Context

- Status: Done
- Owner: Codex + BA/UX/Architecture/QA agents
- User outcome: User can decide where owned Markdown transcripts are saved, and Google Calendar can reduce manual meeting setup by importing meeting title/topic and participants.
- Scope: Product requirements, user steps, backlog priority, architecture boundary, privacy rules, testing expectations, and workstream handoff notes for configurable Markdown storage and Google Calendar MVP/enhancements.
- Out of scope: Implementing folder picker, OAuth, Google Calendar API calls, Notification Center reminders, SQLite schema changes, REST/MCP calendar exposure, or UI code.
- Docs touched: `docs/product/BRD.md`, `docs/product/user-steps.md`, `docs/product/prioritized-backlog.md`, `docs/architecture.md`, `docs/security-privacy.md`, `docs/testing.md`, `docs/workstreams.md`.
- Verification: `swift run Meeting007CoreChecks` passed; `swift build --product Meeting007App` passed after merge to `main`.
- Gates: BA requirements drafted; UX impact documented; architecture impact documented; QA expectations documented; user accepted; merge complete.
- Open decisions: Notification reminder timing; whether participant emails are shown in UI by default or hidden behind details; whether future folder migration should move old Markdown files after explicit confirmation.
- Handoff notes: Google Calendar MVP means title/topic and participants only. Today's meeting list, start-from-meeting, and Notification Center warnings are enhancement items. Manual start remains mandatory fallback.

## Premium UI/UX Audit

- Status: Done
- Owner: Codex + UX Designer agent
- User outcome: Raise Meeting007's interface bar from functional prototype to premium native macOS product quality.
- Scope: Audit current UI against `docs/design-quality-gate.md`, identify top UX/UI problems, define target information architecture, propose phased redesign backlog.
- Out of scope: Implementing UI code changes in this workstream.
- Docs touched: `docs/design/current-ui-ux-audit.md`, `docs/design-quality-gate.md`, `docs/agents/ux-designer.md`, `docs/process/agent-workflow.md`, `AGENTS.md`.
- Verification: `swift run Meeting007CoreChecks` passed; `swift build --product Meeting007App` passed after merge to `main`.
- Gates: UX audit completed; user accepted; merge complete.
- Open decisions: Choose the first redesign implementation slice.
- Handoff notes: Current UI fails the premium design gate. The recommended first implementation slice is IA Cleanup: compact toolbar/header, dominant recording row, one title field, sidebar selection, and reduced card-like layout.

## Markdown Transcript Export After Stop

- Status: Done
- Owner: Codex + BA/UX/Architecture/QA agents
- User outcome: After stopping a recording, the user owns a local Markdown transcript file and can see exactly where it was saved.
- Scope: Local Markdown file writer, `~/Documents/Meeting007/Transcripts/` default folder, date/title/UUID filename, UTF-8 Markdown generated from stopped preview transcript, `transcript_source: local_preview` metadata, saved-path UI, post-stop title edit from the main title field with Enter-to-save and re-export, left-row context menu actions for `Show in Finder` and `Copy path`, retry on export failure.
- Out of scope: SQLite, REST/MCP, search, real microphone/system audio capture, real STT, raw audio persistence, cloud sync, telemetry, configurable export folder.
- Docs touched: `docs/product/user-steps.md`, `docs/product/prioritized-backlog.md`, `docs/architecture.md`, `docs/testing.md`, `docs/security-privacy.md`, `docs/workstreams.md`.
- Verification: `swift run Meeting007CoreChecks` passed; `swift build --product Meeting007App` passed after merge to `main`.
- Gates: BA accepted local Markdown ownership scope; UX accepted non-modal saved-path/retry UI plus main-title Enter-to-save and left-row context menu actions; Architecture accepted `TranscriptFileWriting` boundary and architecture docs; QA accepted writer checks and scoped residual risk; user accepted; merge complete.
- Open decisions: Later storage-index slice will add SQLite; settings can later make export folder configurable.
- Handoff notes: This first slice exports final segments from the current local preview transcript. Partial preview lines remain visible in app/copy flows but are excluded from final Markdown. If the user names the meeting after Stop in the main title field and presses Enter, the app saves a new Markdown export with the updated title and updates the visible saved path.

## Copy Last 5 Minutes

- Status: Done
- Owner: Codex + BA/UX/QA agents
- User outcome: During a meeting, the user can copy recent transcript context without stopping recording or leaving the transcript surface.
- Scope: Visible `Copy Last 5 Minutes` control in the transcript panel, 5-minute transcript window formatting, metadata header, `(live)` marker for partial lines, macOS clipboard write, copy confirmation/failure message, disabled state before transcript text exists, local mock transcript source only.
- Out of scope: Hotkey/menu bar copy actions, Copy Full Transcript, real microphone/system audio capture, real STT, Markdown/SQLite persistence, REST/MCP exposure, telemetry, cloud access.
- Docs touched: `docs/product/user-steps.md`, `docs/product/prioritized-backlog.md`, `docs/testing.md`, `docs/workstreams.md`.
- Verification: `swift run Meeting007CoreChecks` passed; `swift build --product Meeting007App` passed after merge to `main`.
- Gates: BA accepted scope and implementation; UX accepted visible transcript-header control, disabled state, metadata payload, and feedback; QA accepted core coverage and scoped residual risk; user accepted; merge complete.
- Open decisions: Full transcript copy and hotkey/menu bar copy actions remain later backlog items.
- Handoff notes: This first slice copies from the local preview transcript, not real audio transcription.

## Completed Session Runtime History

- Status: Done
- Owner: Codex + BA/UX/Architecture/QA agents
- User outcome: After stopping a recording, the user can see that the meeting was completed and can return to its local transcript preview during the current app run.
- Scope: Immutable completed-session snapshot, in-memory recent recording store, latest completed-session summary, left-side newest-first recent recordings tree, quick-note preservation, transcript preview metadata.
- Out of scope: SQLite, Markdown file creation, durable history after app relaunch, REST/MCP exposure, search, raw audio retention, cloud sync, telemetry, hotkey/menu bar controls.
- Docs touched: `docs/product/user-steps.md`, `docs/product/prioritized-backlog.md`, `docs/workstreams.md`.
- Verification: `swift run Meeting007CoreChecks` passed; `swift build --product Meeting007App` passed after merge to `main`.
- Gates: BA accepted runtime-only completed-session scope and post-build implementation; UX accepted completed-session summary and recent recordings list after `Started` metadata was added; user requested the recent recordings placement as a left-side tree; architecture accepted app-level snapshot orchestration with an in-memory store; QA accepted automated coverage for the slice; security/privacy review is lightweight because no files/network/audio persistence were added; acceptance checks implemented in `Meeting007CoreChecks`; development complete; integration passed after sidebar revision; user accepted; merge complete.
- Open decisions: Durable Markdown/SQLite storage, app relaunch history, search, and local API/MCP remain future work.
- Handoff notes: This history disappears when the app process exits. Product copy must keep saying this is local and temporary until persistent storage ships.

## Live Transcript Placeholder

- Status: Done
- Owner: Codex + BA/UX/Architecture/QA agents
- User outcome: User sees how live transcript will feel during recording: Russian mock segments appear with `Me`/`Others` labels and clear partial/final states.
- Scope: Local fake transcript preview during active recording, deterministic Russian mock segments, partial-to-final replacement, preview disclosure, retained preview after Stop.
- Out of scope: Real microphone/system audio capture, STT, model choice, persistence, Markdown files, SQLite, REST, MCP, copy/export, hotkeys, menu bar controls.
- Docs touched: `docs/product/user-steps.md`, `docs/product/prioritized-backlog.md`, `docs/workstreams.md`.
- Verification: `swift run Meeting007CoreChecks` passed; `swift build --product Meeting007App` passed; user accepted the live transcript preview.
- Gates: BA accepted mock preview scope; UX accepted preview disclosure and partial/final states; architecture accepted reuse of `TranscriptSegment`/`MeetingTranscript` with fake provider boundary; specialist review not required because real audio/STT/files/network are out of scope; acceptance checks implemented in `Meeting007CoreChecks`; development complete; integration passed at package build level; BA+UX accepted; user accepted; merge complete after this workstream update reaches `main`.
- Open decisions: Real STT engine, transcript persistence, copy/export, and REST/MCP remain future work.
- Handoff notes: This preview uses static Russian fake text only. It does not request permissions, capture audio, create transcript files, or expose transcript data through API/MCP.

## Manual Recording Shell

- Status: Done
- Owner: Codex + BA/UX/Architecture/QA agents
- User outcome: User can start and stop a local recording session from the main app window and clearly see recording state before real audio capture/STT are added.
- Scope: Main-window Start/Stop workflow, recording session state machine, no-op capture driver boundary, elapsed timer, meeting title, quick note, transcript placeholder.
- Out of scope: Real microphone/system audio capture, microphone permission prompts, STT, calendar, hotkeys, menu bar controls, Markdown export, SQLite, REST, MCP.
- Docs touched: `docs/product/user-steps.md`, `docs/product/prioritized-backlog.md`, `docs/workstreams.md`.
- Verification: `swift run Meeting007CoreChecks` passed; `swift build --product Meeting007App` passed; user accepted the main-window Start/Stop shell.
- Gates: BA accepted shell scope; UX accepted main-window flow; architecture accepted state shell/no-op capture boundary; specialist review not required because real audio capture/STT/privacy-sensitive data are out of scope; acceptance checks implemented in `Meeting007CoreChecks`; development complete; integration passed at package build level; BA+UX accepted; user accepted; merge complete after this workstream update reaches `main`.
- Open decisions: Real audio capture permissions and raw audio retention remain future decisions.
- Handoff notes: This work intentionally does not request microphone/screen permissions, create audio/transcript files, or touch network/cloud paths. User acceptance should check the main window Start/Stop flow only.

## Project Foundation

- Status: In Progress
- Owner: Codex
- User outcome: Establish rules, requirements, architecture, and a testable transcript core so future app work can proceed in parallel.
- Scope: Repository rules, business requirements, architecture docs, privacy docs, testing docs, Swift package core transcript behavior.
- Out of scope: Full native macOS app, real audio capture, local STT runtime, SQLite implementation, REST/MCP server implementation.
- Docs touched: `AGENTS.md`, `README.md`, `docs/product/BRD.md`, `docs/product/user-steps.md`, `docs/product/prioritized-backlog.md`, `docs/architecture.md`, `docs/testing.md`, `docs/security-privacy.md`, `docs/adr/0001-local-first-macos.md`.
- Verification: `swift run Meeting007CoreChecks` passed after project foundation changes. Backlog documentation changes require doc review only.
- Gates: BA in progress; UX baseline documented in user steps/backlog; architecture baseline documented; specialist reviews not started; acceptance checks partially documented; development foundation done; integration not started; BA+UX acceptance pending; user acceptance pending; merge pending.
- Open decisions: Raw audio retention default; exact local STT runtime/model; REST token lifecycle; calendar metadata retention.
- Handoff notes: V1 is personal-use, Apple Silicon only, Russian-first, local-only, with Markdown plus SQLite as the intended storage model. Remind the user about skills/MCP when tooling triggers become relevant.
