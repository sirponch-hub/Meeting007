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
