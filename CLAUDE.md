@AGENTS.md

## Current Architecture Pointers

For the RATB portability work, prefer the repo-native docs over memory:
`documentation/project_map.md`, `documentation/maintenance_runbook.md`, and
`documentation/external_bundle/`.

Key boundary files:
- `R/ratb_canonical_runtime_helpers.R`: shared HDW-agnostic runtime boundary.
- `R/chu_ratb_scope_adapter.R`: CHU producer for canonical scope/denominator inputs.
- `R/chu_ratb_scope_cache_helpers.R`: CHU cache bridge and notebook compatibility layer.
