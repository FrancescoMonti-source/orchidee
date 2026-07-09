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

This diagnostic reads both `data/sir_wide.rds` and `data/ratb_scope_cache`,
so run it in a CHU checkout where both artifacts exist. It stops early with a
clear error if either is missing.

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

1. It derives elementary source blocks from current CHU artifacts, using
   canonical ORCHIDEE values as local labels. The microbiology observations
   and the bacteria, sample-type and antibiotic mappings come from
   `data/sir_wide.rds`; the `unit_mapping` and `denominator_by_year` blocks
   come from the native `data/ratb_scope_cache`.
2. It runs those blocks through
   `scripts/build_external_bundle_from_site_inputs.R` logic and compares the
   rebuilt `sir_wide` with the current artifact.

A `pass` build status means the current canonical microbiology artifact can be
expressed as site handoff inputs, rebuilt, validated and roundtripped without
changing its portable content. The roundtrip compares the v1 `sir_wide`
columns defined by the external contract, so a new portable column is covered
automatically once the contract lists it.

This is not a raw CHU extraction test: it does not verify the original EDSaN /
BIOL label mapping that produced `sir_wide.rds`.

A `build_fail`, `validation_fail` or `roundtrip_mismatch` status is diagnostic
evidence, not a pipeline failure. Read
`outputs/chu_site_inputs/build_attempt.rds` and
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
