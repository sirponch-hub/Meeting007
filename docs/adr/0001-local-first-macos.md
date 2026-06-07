# ADR 0001: Local-First macOS Architecture

## Status

Accepted

## Context

Meeting007 should provide Granola-like meeting transcription while avoiding bot participants, cloud transcription, hosted accounts, and transcript lock-in. The first user is a single Apple Silicon Mac user, and Russian transcription quality is a primary requirement.

## Decision

V1 will be a native macOS Apple Silicon application with local-only capture, local-only transcription, local Markdown transcript files, a SQLite index, and localhost-only REST/MCP access.

The app will use:

- Swift/SwiftUI for the macOS shell.
- ScreenCaptureKit for system audio capture.
- AVAudioEngine/CoreAudio for microphone capture.
- A local STT engine behind a protocol abstraction.
- Markdown as the user-owned transcript format.
- SQLite as the operational index.

## Consequences

Positive:

- Strong privacy posture.
- No transcript lock-in.
- Works without a meeting bot.
- Local API/MCP can serve user-owned meeting history.
- Apple Silicon acceleration can support low-latency transcription.

Negative:

- V1 targets Apple Silicon only.
- Local models increase app size and setup complexity.
- Russian accuracy and latency must be benchmarked on-device.
- Team collaboration and cloud sync are out of scope.

## Follow-Up Decisions

- Choose the default raw audio retention policy.
- Choose the exact local STT runtime and model.
- Define REST authentication token lifecycle.
- Define calendar metadata retention rules.

