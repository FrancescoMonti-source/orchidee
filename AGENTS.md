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
- Keep internal generated artifacts and caches in `data/`.
- Keep reader-facing report exports in `downloads/`.
- Keep local drafts, inspections, and temporary artifacts in `outputs/`;
  do not treat `outputs/` as a canonical source.
- Keep biological mappings in `dictionaries/`, institutional references in
  `ref/`, and maintained analytical rule tables in `rules/` when they exist.
- Update the corresponding methodological documentation when analytical
  behavior changes.

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

- Worktrees: a fresh worktree does not contain `data/` (gitignored but
  required for renders). Use worktrees only for genuinely parallel tasks
  that do not need `sir_wide.rds`, PMSI inputs, or caches; otherwise use a
  normal `task/<slug>` branch and work sequentially.
- Changes to `AGENTS.md` itself go on their own branch and merge before
  other branches rebase, so the shared contract does not fork.

## Rendering And Verification

- Use `scripts/render_orchidee.ps1` for routine renders.
- Available targets are `memo`, `meeting`, `docs`, `indicators`, and `full`.
- Use `full` after changes to upstream pipeline, completion, deduplication,
  perimeter, denominator, or indicator logic.
- Before changing code because a report looks wrong, determine whether the
  issue belongs to the source pipeline, indicator specification, or report
  display layer.
