# ADR 0002: Temporary Local Audio Spool For Loss-Resistant Finalization

## Status

Accepted

## Context

Real app trials showed that using one heavy rolling WhisperKit decode as live preview, stable transcript, and final transcript path does not meet the product bar:

- live transcription can start too late,
- rolling decode failures can leave the transcript in a broken state,
- Stop/finalization can depend on the same fragile live path,
- speech can be lost if local STT is not ready or fails before the tail is finalized.

Meeting007 remains local-first. Audio and transcripts must not leave the Mac by default.

## Decision

Meeting007 may create a temporary local audio spool during an active recording to preserve captured speech until final transcript completion.

The spool is allowed only for loss-resistant local transcription finalization:

- Capture writes ordered audio chunks with lane, sequence, sample-start, and sample-end metadata.
- Live transcription may consume frames from the spool or an equivalent ordered stream.
- Final transcript reconciliation consumes the spool after Stop to recover unfinalized or low-confidence ranges.
- Successful final transcript completion deletes the spool.
- If finalization fails or times out, the spool may remain only for local retry/recovery and must be deleted after recovery or explicit discard.

The spool must not be:

- uploaded,
- exposed through Markdown,
- stored as transcript data in SQLite,
- served through REST or MCP,
- written to logs,
- used for telemetry,
- retained permanently by default.

The first implementation stores the spool under the app-owned
`Application Support/Meeting007/CaptureSpool` directory. Session directories use owner-only
`0700` permissions, spool files use `0600`, and the spool root/session directories are excluded
from backup. Each lane uses append-only Float PCM plus a JSONL metadata journal. A journal entry is
written only after its PCM bytes, so recovery trusts committed metadata and ignores an uncommitted
audio tail after a crash.

Lifecycle latency markers are in-memory, local-only records containing only session ID, event, and
monotonic timestamp. They do not contain audio, transcript text, or filesystem paths.

## Consequences

Positive:

- Start can open capture immediately without waiting for STT readiness.
- Stop can stop capture promptly without waiting indefinitely for final decoding.
- Finalization can recover the captured tail after live STT delay or runtime failure.
- Segment reconciliation can use sample offsets instead of string-prefix heuristics.

Tradeoffs:

- The app now has a sensitive temporary raw-audio privacy boundary.
- Implementation must include deletion, retry, and failure-state behavior.
- QA must verify that temporary audio is not exposed through user-owned transcript surfaces or local APIs.
- The first slice uses POSIX ownership and backup exclusion; stronger at-rest encryption remains an
  explicit follow-up before broader distribution.

## Required Follow-Up

- Add tests that successful finalization deletes the spool.
- Add tests that failed finalization preserves the spool only for local retry/recovery.
- Add privacy tests proving Markdown, SQLite transcript records, REST, MCP, and logs do not expose raw audio.
- Add user-facing recovery behavior for finalization timeout or failure.
- Define automatic orphan-spool discovery and cleanup policy.
