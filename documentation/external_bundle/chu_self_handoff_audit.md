---
editor_options:
  markdown:
    wrap: 72
---

# CHU Self-Handoff Audit

This maintainer diagnostic checks whether the current CHU artifacts can be
expressed as the same elementary source blocks requested from Rennes or
another hospital data warehouse.

It is not a production path and it does not replace the current CHU workflow.
It writes local artifacts under `outputs/`, which is ignored by Git.

## Command

From the repository root:

```powershell
Rscript scripts/audit_chu_site_handoff.R --force
```

If `Rscript` is not available in `PATH`, use the full local Rscript path.

By default, the script writes:

- `outputs/chu_site_inputs/`
  - `microbiology_observations.rds`
  - `bacteria_mapping.rds`
  - `sample_type_mapping.rds`
  - `antibiotic_mapping.rds`
  - `unit_mapping.rds`
  - `denominator_by_year.rds`
  - `audit_summary.csv`
  - `build_attempt.rds`
- `outputs/chu_site_bundle/`
  - the four internal ORCHIDEE files, only if the build succeeds.

Use custom output directories when needed:

```powershell
Rscript scripts/audit_chu_site_handoff.R `
  outputs/chu_site_inputs `
  outputs/chu_site_bundle `
  --force
```

## How To Read It

The script has two steps.

1. It exports CHU-derived elementary source blocks from existing local
   artifacts in `data/`.
2. It filters the CHU long microbiology rows to antibiotic columns supported
   by the v1 ORCHIDEE contract.
3. It tries to run those blocks through
   `scripts/build_external_bundle_from_site_inputs.R` logic.

A `pass` build status means the CHU-derived blocks satisfy the same handoff
builder expected from an external hospital.

The script also reports source alignment between `data/sir_long` and the
current `data/sir_wide.rds`. If alignment is `mismatch`, the handoff builder
is executable but the generated bundle should not be read as exact
reproduction of the frozen CHU artifact.

A `build_fail` or `validation_fail` status is diagnostic evidence, not a
pipeline failure. Read `outputs/chu_site_inputs/build_attempt.rds` and
`outputs/chu_site_inputs/audit_summary.csv` to identify the mismatch.

Use `--fail-on-build-failure` only when you deliberately want the command to
act as a hard gate.

## Current Boundary To Watch

The `sir_wide` v1 contract allows missing `naturepvt_norm`, because the
current CHU artifact already contains that pattern. The site-input builder
therefore preserves missing sample-type canonical values instead of forcing a
classification.

The audit still reports how many local sample-type mappings are blank. A
passing audit means the interface is executable; it does not mean the
sample-type mapping is complete enough for every by-sample-type analysis.
