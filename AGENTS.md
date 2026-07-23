# Orchidee

## Working Approach

- Optimize for code ownership and prefer small, reviewable changes.
- Read the existing implementation before proposing structural changes.
- Preserve unrelated user changes and generated work already present.
- Treat repository source files and documentation as authoritative; rendered
  HTML files are derived artifacts.

## Start Here

Before substantial work, read:

1. `README.md`
2. `documentation/project_map.md`
3. `documentation/maintenance_runbook.md`

For analytical or methodological changes, also consult
`documentation/ratb_implementation_decisions.qmd` and
`documentation/ratb_indicator_spec.csv` as relevant.

## Repository Conventions

- Keep reusable implementation logic in `R/` rather than expanding notebook
  chunks unnecessarily.
- Keep operational settings in `config/pipeline.R`.
- Keep optional local run inputs in `data/`; never add patient-derived data to
  Git. Scripts must still accept explicit protected paths outside the checkout.
- Keep reader-facing report exports in `downloads/`.
- Keep generated bundles, caches, audits, local drafts and inspections in
  `outputs/` or the configured external workspace; do not treat them as
  repository source.
- Keep curated source-to-canonical mappings in `dictionaries/`, imported
  reference facts in `ref/`, and project-authored analytical decisions in
  `rules/`. Rouen-only references belong under `ref/rouen/` and must be
  identified as adapter-specific rather than portable handoff requirements.
- Archive snapshots with no active consumer outside the repository.
- Update the corresponding methodological documentation when analytical
  behavior changes.

## Current Operational Boundaries

- `redsan` owns EDSaN retrieval, batching, and PMSI/BIOL normalization.
  ORCHIDEE consumes its outputs and does not maintain a second source client.
- The preferred site handoff contains exactly the six unversioned blocks in
  `documentation/external_bundle/site_handoff_inputs.md`. Version labels apply
  to materialized bundles, not to those site-owned blocks.
- Bundle v3 is the complete durable construction contract. The notebook
  runtime remains on strict `external_bundle_v2`, produced through the closed
  `spares_current` projection when starting from v3.
- `external_bundle_v2` is the only operational notebook input. Completion and
  `chu_native` are retired from the active tree; their last coherent
  implementation is frozen at tag
  `archive/completion-chu-native-2026-07-22`. Restoring either path requires an
  explicit project decision.

## Multi-Agent Collaboration

Several agents (and tools) may work on this repository. Coordination is
deliberately lightweight and Git-native:

- `main` contains accepted work only.
- For a meaningful change, create a `task/<slug>` branch.
- One agent implements the coherent change and commits it with a clear,
  ordinary commit message. No commit-message template or co-author
  attribution is required; the diff and the review carry the signal.
- Another agent reviews the branch diff (`git diff main..task/<slug>`).
- Run the relevant verification (see Rendering And Verification).
- Merge into `main` after maintainer approval.

Notes:

- Worktrees: a fresh worktree does not contain ignored local inputs under
  `data/` or generated outputs. Use worktrees only for genuinely parallel tasks
  that do not need BACT/PMSI inputs, bundles or caches; otherwise use a normal
  `task/<slug>` branch and work sequentially.
- Changes to `AGENTS.md` itself go on their own branch and merge before
  other branches rebase, so the shared contract does not fork.

## Rendering And Verification

- Use `scripts/render_orchidee.ps1` for routine renders.
- Available targets are `memo`, `docs`, `indicators`, and `full`.
- Use `full` after changes to upstream pipeline, raw deduplication, perimeter,
  denominator, or indicator logic; it builds the canonical raw cache and then
  renders the indicator report.
- Do not reintroduce completion or `chu_native` as a fallback or implicit
  operational path.
- Before changing code because a report looks wrong, determine whether the
  issue belongs to the source pipeline, indicator specification, or report
  display layer.
