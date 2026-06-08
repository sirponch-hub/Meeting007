# Current UI/UX Audit

Status: Fails premium macOS design gate.

This audit evaluates the current Meeting007 main window as a shipping product surface, not as a prototype.

## Verdict

The current UI is functionally useful for P0 development, but it does not yet feel like a premium native macOS productivity app. It looks like feature pieces stacked into a window: sidebar, header, title fields, recording panel, transcript panel, completed summary, and export state.

The product promise is strong: local, Russian-first, user-owned transcripts. The interface does not yet express that promise with enough calm confidence, visual hierarchy, or native interaction quality.

## Highest-Impact Problems

1. **Unclear primary workflow**
   The real workflow is name or start meeting, record, watch/copy transcript, stop, confirm saved file. The current screen splits this across visually equal panels.

2. **Title ownership is still fragile**
   The title field, display title, row title, and Markdown title need to feel like one concept. The user should never wonder where naming happens.

3. **Stop/save confidence is too diagnostic**
   After Stop, the user needs a confident state: recording ended, transcript finalized, Markdown saved locally. Current copy and layout feel like implementation feedback.

4. **Transcript panel still reads as a prototype**
   Mock/preview language is acceptable in development, but it weakens trust in the main product surface.

5. **Sidebar is not yet real navigation**
   Recent recordings are shown, but row selection, current/active state, grouping, and item actions need to feel native and intentional.

6. **Copy actions lack a complete model**
   Copy Last 5 Minutes exists, but copy feedback, full transcript copy, disabled states, and future keyboard/menu behavior need one coherent command model.

7. **Visual hierarchy is too card-like**
   Multiple boxed panels make the app feel assembled feature-by-feature instead of composed as one work surface.

## Target Information Architecture

- **Sidebar:** recent recordings, grouped by Today / Yesterday / Earlier once durable history exists. Active recording pinned at top. Row context menu owns Open, Show in Finder, Copy Path, Rename, Delete later.
- **Main work surface:** selected or active meeting. One title area, one recording status area, one transcript area.
- **Toolbar/header strip:** compact recording status, elapsed time, local-only indicator, primary Start/Stop button.
- **Transcript command bar:** Copy Last 5 Minutes, Copy Full Transcript, future search/filter.
- **Save/status footer:** compact saved Markdown state, path, retry if failed. It should not compete with transcript reading.
- **Settings:** permissions, transcript folder, raw audio retention, REST/MCP access, tokens.

## Immediate Redesign Backlog

### P0: IA Cleanup

- Collapse the large brand header into a compact native toolbar/header strip.
- Make Start/Stop and recording state the dominant first-row workflow.
- Keep exactly one editable meeting title.
- Move quick note into secondary/disclosed UI.
- Keep file actions on sidebar rows, not in the main surface.
- Add row selection in the sidebar and load selected meeting details in the main surface.

### P0: Stop And Save Confidence

- Replace the completed-session card with a compact completion/status area.
- Use clear state progression: `Stopping...`, `Finalizing transcript...`, `Saved locally`.
- If Markdown export fails, show a focused local-file recovery state with retry.
- Keep transcript visible and stable after failure.

### P1: Transcript Surface Upgrade

- Make transcript the visual center of the app.
- Reduce implementation copy like "mock" and "preview" in the main surface.
- Preserve development honesty through subtle labels or dev-only copy, not dominant messaging.
- Keep final lines stable and partial lines subtly distinct.

### P1: Command Model

- Put transcript copy actions in a compact command bar.
- Add Copy Full Transcript beside Copy Last 5 Minutes.
- Make copy confirmation short-lived and inline.
- Keep context actions on rows.

### P1: Native Sidebar

- Add selected row state.
- Add active recording row state.
- Add grouping once persisted history is loaded.
- Context menu: Open, Show in Finder, Copy Path. Hide or disable unavailable actions deliberately.

### P2: Visual Polish

- Reduce boxed card count.
- Use native macOS spacing, materials, row selection, and toolbar proportions.
- Keep color semantic: red for recording/failure, green/check only for saved state, accent for active controls.
- Tighten typography, alignment, focus rings, and empty states.

## Design Acceptance Checks

Future UI work should not pass UX acceptance unless:

- The primary workflow is visually dominant.
- The same concept is not editable in multiple places.
- Sidebar actions are contextual and native.
- Enter, Escape, right-click, copy/paste, and focus behavior are specified.
- The transcript feels like the product artifact being created, not a demo panel.
- The UI can handle real-world out-of-order behavior, especially starting before naming.
- The screen looks composed, dense, calm, and native.
