# Design Quality Gate

Meeting007 UI should be judged as a shipping native macOS product, not as a prototype. Use this gate before development starts and again before user acceptance.

## Design Principles

- The app is a work surface for live meetings, not a landing page.
- The left side owns navigation and meeting history.
- The main surface owns the active or selected meeting.
- Row-specific actions live on rows, usually through context menus.
- Global fields are not duplicated in detail panels.
- Enter commits the field the user is editing.
- File actions use macOS-native behavior: Show in Finder, copy path, selectable paths.
- Privacy copy appears at the moment it builds trust, not as repeated decoration.
- Layout should be dense, aligned, and calm.
- The user should never need to understand implementation details to operate the app.
- The visual language should adopt Apple's Liquid Glass design direction where available and appropriate, using it for navigation, controls, and layered surfaces without reducing transcript readability.

## Liquid Glass Requirements

Meeting007 should follow Apple's current Human Interface Guidelines for Liquid Glass on macOS.

Reference sources:

- Apple Human Interface Guidelines: Materials, including Liquid Glass guidance.
- Apple Developer Technology Overview: Liquid Glass.
- Apple Developer Technology Overview: Adopting Liquid Glass.

Use Liquid Glass as a system material strategy, not as decoration:

- Apply glass/material treatment primarily to top-level navigation, toolbar/header surfaces, sidebars, command bars, and floating controls.
- Keep transcript content and dense text on high-readability surfaces. Do not put long transcript text directly on visually busy translucent glass.
- Preserve hierarchy between content and controls: meeting/transcript content is primary; glass controls support it.
- Respect macOS accessibility settings including Reduce Transparency, Increase Contrast, and reduced motion.
- Maintain readable contrast in all states: idle, recording, copied, stopped, saved, failed, disabled, selected row, and hover/focus.
- Use system materials and native SwiftUI/AppKit APIs before custom blur, opacity, gradients, or fake glass.
- Do not create decorative bokeh, glass blobs, or translucent panels that do not serve navigation, command, or status hierarchy.
- Keep motion subtle and purposeful. Liquid movement must never distract during a meeting.
- Test both light and dark appearance.
- If a Liquid Glass treatment harms legibility or calmness, use a more opaque/thick material or plain surface.

## Pass Criteria

A design passes only if all are true:

- The user's real-world workflow is described, including out-of-order behavior.
- Primary action, secondary actions, and contextual actions are separated.
- Information architecture is explicit: sidebar, main surface, detail/status area, context menus, settings.
- The screen has one clear visual hierarchy.
- Every visible control has a reason to be visible at that moment.
- The same concept is edited in only one place.
- Empty, active, success, failure, and recovery states are defined.
- Keyboard, focus, right-click, copy/paste, and file actions are specified where relevant.
- Liquid Glass/material behavior is specified for sidebar, toolbar, command bar, and content surfaces.
- Accessibility fallbacks for transparency, contrast, and motion are specified.
- The design can be manually accepted by looking at exact screen areas and expected states.
- The implementation can be documented for parallel work without ambiguity.

## Automatic Rejection

Reject the design before development if any are true:

- It looks like a form pasted into a window.
- Controls are scattered because they were added one feature at a time.
- A secondary action is more visually prominent than the user's main workflow.
- A row-specific action is placed as a global button without a strong reason.
- A field or action is duplicated in multiple places.
- The design requires explanatory text to compensate for poor placement.
- The UI exposes future architecture before it exists.
- The user can complete a natural workflow in the wrong order and get stuck.
- The design ignores expected macOS behavior.
- It uses Liquid Glass as decoration instead of hierarchy.
- It places dense transcript text on low-contrast translucent material.
- It fails Reduce Transparency, Increase Contrast, or dark/light appearance checks.
- The designer cannot explain why the result would feel premium, calm, and inevitable.

## Review Prompt

For UX acceptance, answer:

```text
1. What is the user's real workflow?
2. What is the information architecture?
3. What are the primary, secondary, and contextual actions?
4. What native macOS behaviors are required?
5. What visual hierarchy makes the screen scannable?
6. What did we remove or hide to keep the interface calm?
7. What amateur/prototype pattern did we avoid?
8. Where is Liquid Glass used, and why is it appropriate there?
9. How does the design preserve accessibility and transcript readability?
10. What exact manual checks should the user perform?
```
