# Workstreams

Use this file to keep parallel development coordinated. Every active branch or substantial task should leave enough context for another engineer or agent to continue safely.

Delivery gates and agent roles are defined in `docs/process/agent-workflow.md`.

## Rules

- Record work before or during implementation, not only after.
- Describe work in business and user-experience terms first.
- Link to technical docs or ADRs when implementation details matter.
- Keep status current when a workstream starts, changes direction, is blocked, or completes.
- Do not mark work ready for `main` until verification is documented.
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
- Open decisions: <business/product decisions still needed>
- Handoff notes: <context needed for parallel work>
```

## Current Workstreams

## Configurable Markdown Transcript Folder

- Status: Ready for Review
- Owner: Codex + BA/UX/Architecture/QA agents
- User outcome: User can save new owned Markdown transcripts into the folder where they actually work, such as a local knowledge base or explicitly chosen sync folder.
- Scope: Local folder preference, default folder preservation, native folder picker, write-access validation, reveal/copy/reset actions, new Markdown exports use selected folder, no silent migration of existing files.
- Out of scope: Dedicated Settings window, migrating existing Markdown files, sandbox security-scoped bookmarks, SQLite folder metadata, REST/MCP folder controls, cloud defaults.
- Docs touched: `docs/product/user-steps.md`, `docs/architecture.md`, `docs/security-privacy.md`, `docs/testing.md`, `docs/workstreams.md`.
- Verification: `swift run Meeting007CoreChecks` passed; `swift build --product Meeting007App` passed.
- Gates: BA scope documented; UX implementation complete; architecture boundary documented; automated checks passed; user acceptance pending; merge pending.
- Open decisions: Whether a future migration flow should offer to move old Markdown transcripts after explicit confirmation; whether production sandboxing requires security-scoped bookmarks.
- Handoff notes: The selected path is stored in app preferences through `MarkdownTranscriptFolderSettings`. Changing the folder affects future exports only.

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
