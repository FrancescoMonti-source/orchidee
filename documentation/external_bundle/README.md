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

## Start here

For Rennes or another hospital HDW team, start with:

`site_handoff_inputs_v1.md`

That document answers the practical first question: which files should the
site prepare, with which columns?

## Which document answers which question?

- `site_handoff_inputs_v1.md`
  - What should an external hospital provide?
  - This is the human-facing onboarding contract.
- `canonical_inputs_v1.md`
  - Where is the boundary between local site adaptation and shared ORCHIDEE
    logic?
- `sir_wide_v1.md`
  - What is the exact schema of the internal microbiology file?
- `sample_scope_reference_v1.md`
  - What is the exact schema of the sample-level TA/DE scope file?
- `denominator_bundle_v1.md`
  - What is the exact schema of the incidence denominator file?

## Main external-site command

```powershell
Rscript `
  scripts/build_external_bundle_from_site_inputs.R `
  <microbiology_observations> `
  <bacteria_mapping> `
  <sample_type_mapping> `
  <antibiotic_mapping> `
  <unit_mapping> `
  <denominator_by_year> `
  <output_bundle_dir> `
  [de_reference] `
  [--force]
```

The command examples and required columns are in `site_handoff_inputs_v1.md`.

## Maintainer-only helpers

These scripts are useful for ORCHIDEE maintainers, but they are not the first
path for a new hospital team:

- `scripts/validate_external_bundle.R`
  - validates an already built ORCHIDEE input bundle.
- `scripts/smoke_external_runtime_inputs.R`
  - checks that a validated bundle can build the downstream RATB inputs.
- `scripts/materialize_external_bundle.R`
  - writes a four-file bundle from current compatible artifacts.
- `scripts/build_external_bundle_from_handoff_inputs.R`
  - builder for the advanced case where a site already has a valid
    `sir_wide.rds`.

## Ownership rule

- Local hospital teams own extraction from their HDW and mapping from local
  labels to ORCHIDEE handoff inputs.
- ORCHIDEE owns validation, downstream scope, deduplication and indicator
  calculation.
- Local QA tables and extraction details are not part of the portable handoff.
