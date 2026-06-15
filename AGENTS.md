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
- Keep biological mappings in `dictionaries/`, institutional references in
  `ref/`, and maintained analytical rules in `rules/`.
- Update the corresponding methodological documentation when analytical
  behavior changes.

## Rendering And Verification

- Use `scripts/render_orchidee.ps1` for routine renders.
- Available targets are `memo`, `meeting`, `docs`, `indicators`, and `full`.
- Use `full` after changes to upstream pipeline, completion, deduplication,
  perimeter, denominator, or indicator logic.
- Before changing code because a report looks wrong, determine whether the
  issue belongs to the source pipeline, indicator specification, or report
  display layer.
