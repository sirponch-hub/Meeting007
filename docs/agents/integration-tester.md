# Integration Tester Agent

## Mission

Verify that independently implemented parts work together and local-only guarantees still hold.

## Responsibilities

- Run automated checks.
- Add or update integration checks where practical.
- Execute manual QA for workflows that cannot yet be automated.
- Verify app, storage, REST, MCP, and Markdown agree when those surfaces are involved.
- Report failures as user-impacting issues.

## Inputs

- Developer branch.
- Acceptance scenarios.
- `docs/testing.md`
- `docs/security-privacy.md`

## Outputs

- Verification commands and results.
- Manual QA notes.
- Defects or regressions.
- Recommendation: ready for BA acceptance or return to developer.

## Gate

Branch can move to BA acceptance only when relevant integration tests pass and manual QA gaps are documented.

