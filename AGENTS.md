# AI Agent Rules

These rules apply to all AI-assisted work in this repository. Reusable role prompts live in `docs/agents/`. The delivery process is defined in `docs/process/agent-workflow.md`.

## Product Invariants

- Meeting007 is local-first. Do not introduce cloud processing, hosted accounts, telemetry, or remote transcript storage unless a documented ADR explicitly changes this.
- Russian is the primary transcription language for v1. Do not treat Russian as an optional secondary path.
- Transcripts must remain user-owned. Markdown export is a core product surface, not a convenience feature.
- Local REST and MCP access must use the same local source of truth as the app.
- Manual start/stop from the main app window must remain reliable even after calendar integration, hotkeys, or menu bar controls exist.
- User-facing surfaces must meet a premium native macOS product bar. Do not accept student-prototype UI, duplicated controls, random visible buttons, web-form layouts, or non-native interaction behavior.
- Visible macOS UI should follow Apple's Liquid Glass direction where appropriate, using native materials for hierarchy while preserving readability, accessibility, and calm meeting-time behavior.

## Engineering Rules

- Prefer small, testable modules with explicit boundaries.
- Keep capture, transcription, storage, API, MCP, and UI concerns separate.
- Add or update tests for behavior changes.
- Untested work must not be merged into `main`.
- Feature work must happen on a branch after business requirements, UX impact, architecture impact, and acceptance scenarios are documented.
- Feature work must use the specialist subagents defined in `docs/process/agent-workflow.md` before implementation. Do not self-approve BA, UX, architecture, QA, or specialist gates when a matching subagent can be used.
- Code changes must use the Developer subagent before implementation. The Developer subagent must receive the approved requirements, architecture notes, acceptance criteria, and test expectations.
- Code changes must follow TDD/BDD: add or update an automated check before or alongside implementation. If the change cannot be automated yet, document the missing harness, add a manual acceptance checklist before coding, and keep the branch out of `main` unless the user explicitly accepts the test gap.
- macOS development must use the `build-macos-apps` plugin skills when available: `swiftui-patterns`, `liquid-glass`, `swiftpm-macos`, `build-run-debug`, `appkit-interop`, `signing-entitlements`, `test-triage`, and `view-refactor`.
- If the `build-macos-apps` skills are installed locally but not active as callable skills in the session, read and apply their local `SKILL.md` files before macOS UI, build, signing, packaging, or AppKit changes.
- Specialist review is required when work affects audio capture, local STT, privacy/security, CI/build, performance, QA automation, or user-facing documentation.
- Run the relevant verification command before handing work back. If checks cannot run, state why and mark the work as not ready for `main`.
- Do not commit generated build outputs, audio recordings, model files, secrets, tokens, local databases, or user transcripts.
- Do not use destructive git commands unless the user explicitly asks for them.
- Do not rewrite unrelated files or revert user changes.

## Collaboration Rules

- Default to quiet execution. Do not post progress updates, implementation narration, or intermediate reasoning in the user chat unless the user explicitly asks for status/reporting, a decision or permission is required, or the work is blocked.
- When spawning or messaging subagents, include the same quiet-execution rule: subagents must not post progress updates, implementation narration, or intermediate reasoning in their own chats unless user input, permission, or a blocker must be surfaced.
- Subagents should return only the final gate output required for the workflow: recommendation, acceptance status, risks, required tests, documentation updates, and handoff notes.
- Communicate with the user in business-requirement language by default: user outcome, workflow, acceptance criteria, risk, and product tradeoff.
- When a technical decision is needed, translate it into the user experience impact before asking. For example, ask whether transcripts should be available offline forever instead of asking only whether to use Markdown or SQLite.
- Do not assume the user wants low-level implementation detail unless it affects product behavior, privacy, cost, speed, reliability, or future parallel work.
- For user-facing changes, explain choices through convenience, clarity, speed during meetings, trust, privacy, and recovery.
- Keep decisions documented so another engineer or agent can continue without rediscovering context.
- After user acceptance, merge, and final verification, always present the user with the top 3 next backlog options in business language so they can choose the next step.
- For UI changes, challenge weak UX before coding. Translate design concerns into user workflow impact: speed, confidence, discoverability, reduced clutter, native macOS expectations, and fewer mistakes.
- For UI changes, always run the UX Designer subagent and Acceptance/QA subagent before coding. If subagent tooling is unavailable, stop and tell the user the work is blocked by the missing review path instead of implementing from personal judgment.
- When subagents are used, summarize their recommendations in `docs/workstreams.md` or the relevant design/product document before requesting user acceptance.

## Privacy And Security Rules

- Never add automatic upload paths for audio, transcripts, summaries, or debug logs.
- Treat raw audio and transcripts as sensitive private data.
- Keep local service endpoints bound to localhost by default.
- Store API/MCP tokens in Keychain in app code; tests may use in-memory fakes.
- Require an explicit product decision before retaining raw audio by default.

## Testing Expectations

- Automated checks cover transcript segment merging, timestamp formatting, Markdown export, copy-window selection, and API serialization contracts.
- Integration tests cover mocked audio chunks through transcription and storage.
- Manual QA must include Russian speech and mic/system-audio capture on Apple Silicon.
- Every pull request must state which automated checks and manual QA were run.
- Every code workstream must state its TDD/BDD evidence: test/check added first, test/check updated alongside implementation, or documented accepted gap.
- If a change cannot be tested yet, document the missing test harness and keep the change out of `main` until the gap is closed.

## Documentation Expectations

- Follow `docs/process/agent-workflow.md` for BA, architecture, testing, development, acceptance, and merge gates.
- Update `docs/product/BRD.md` when product behavior changes.
- Update `docs/architecture.md` when module boundaries, data flow, APIs, or storage change.
- Add an ADR for decisions that affect privacy, storage, model choice, public API shape, or platform support.
- Update `docs/workstreams.md` when starting, changing, or completing work that another person or agent may touch in parallel.
- Each meaningful change should leave behind enough context to answer: what changed, why it changed, how to verify it, and what remains open.
