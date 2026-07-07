---
editor_options:
  markdown:
    wrap: 72
---

# External Bundle Documentation

This folder documents how another hospital can connect local data to the
ORCHIDEE RATB core.

This file is only an index. It should not duplicate the detailed contract.
When details differ, the contract files below are authoritative.

## Which document answers which question?

- `site_handoff_inputs_v1.md`
  - What should Rennes, or another hospital HDW team, provide?
  - This is the human-facing onboarding contract.
- `canonical_inputs_v1.md`
  - Where is the boundary between local site adaptation and shared ORCHIDEE
    runtime logic?
- `sir_wide_v1.md`
  - What is the exact schema of the canonical microbiology artifact?
- `sample_scope_reference_v1.md`
  - What is the exact schema of the sample-level TA/DE scope reference?
- `denominator_bundle_v1.md`
  - What is the exact schema of the incidence denominator bundle?

## Current operating model

A site external to the CHU should not reproduce the CHU raw extraction path.
It should provide elementary, hospital-owned inputs described in
`site_handoff_inputs_v1.md`.

ORCHIDEE then derives the canonical runtime bundle:

- `sir_wide.rds`
- `sir_wide_meta.rds`
- `sample_scope_reference.rds`
- `denominator_bundle.rds`

That bundle is validated before it crosses into the shared RATB runtime.

The full external notebook execution mode is not wired yet. The current
external contract is executable up to a validated bundle and runtime smoke
check.

## Main scripts

- `scripts/build_external_bundle_from_site_inputs.R`
  - preferred builder from elementary site inputs.
- `scripts/build_external_bundle_from_handoff_inputs.R`
  - compatibility builder when a site already has a canonical `sir_wide.rds`.
- `scripts/validate_external_bundle.R`
  - strict validator for the four-file canonical bundle.
- `scripts/smoke_external_runtime_inputs.R`
  - checks that a validated bundle can build the downstream RATB runtime
    inputs.
- `scripts/materialize_external_bundle.R`
  - writes a preferred four-file bundle from compatible current artifacts.

For command examples and required columns, use `site_handoff_inputs_v1.md`.

## Ownership rule

- Local hospital teams own extraction from their HDW and mapping from local
  labels to ORCHIDEE handoff inputs.
- ORCHIDEE owns the canonical target schema, validation, downstream scope,
  deduplication and indicator calculation.
- CHU-specific QA tables and extraction details are not part of the portable
  contract.
