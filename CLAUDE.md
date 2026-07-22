@AGENTS.md

## Current Architecture Pointers

For the RATB portability work, prefer the repo-native docs over memory:
`documentation/project_map.md`, `documentation/maintenance_runbook.md`, and
`documentation/external_bundle/`.

Key boundary files:
- `R/ratb_canonical_runtime_helpers.R`: shared HDW-agnostic runtime boundary.
- `R/ratb_operational_input_helpers.R`: strict external-bundle v2 runtime loader.
- `R/external_handoff_helpers.R`: shared six-block bundle construction.
