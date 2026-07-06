---
editor_options:
  markdown:
    wrap: 72
---

# External Input Bundle for Orchidee

This folder documents the external input contract for Orchidee.

The goal is to make the shared downstream core reusable by another
hospital without requiring that hospital to reproduce the CHU raw
extraction path.

For now, this is not a full external execution mode:
- the main notebooks do not branch between internal and external bundles
- the CHU path still produces the rich native QA cache used by the
  notebook
- the CHU path now produces canonical `sample_scope_reference` and
  `denominator_bundle` objects
- the notebook applies those canonical objects through the shared runtime
  helper to build scoped microbiology rows and the incidence denominator table

## Future operating model

Another hospital should not be asked to reproduce the full Orchidee raw
extraction pipeline.

The machine/runtime boundary remains the canonical bundle made of:
- `sir_wide.rds`
- `sir_wide_meta.rds`
- `sample_scope_reference.rds`
- `denominator_bundle.rds`

Once those artifacts match the contract, the shared Orchidee downstream
core can be plugged later without changing the artifact contract again.

For onboarding, a site does not need to hand-author all four files. The
handoff layer described in `site_handoff_inputs_v1.md` starts one level
upstream: the site provides simpler local blocks, then ORCHIDEE derives
`sir_wide.rds`, `sir_wide_meta.rds`, `sample_scope_reference.rds`, and
`denominator_bundle.rds`.

If a site already has a canonical `sir_wide.rds`, the older prebuilt
microbiology path remains available as a compatibility shortcut.

## Minimum site handoff checklist

For a new hospital, the practical handoff question is: can the local team
produce these elementary blocks with the expected grain and meaning?

- microbiology observations
  - long S/I/R result table at sample / bacterium / antibiotic grain;
  - diagnostic/non-screening scope made explicit with
    `ratb_diagnostic_scope`;
  - broad enough to let ORCHIDEE apply the RATB TA/DE scope, not
    pre-filtered to hide out-of-scope rows.
- microbiology mapping dictionaries
  - local bacteria, sample-type and antibiotic labels mapped to ORCHIDEE
    canonical values.
- unit / structure / TA-DE mapping
  - one row per sample unit `SEJUF`, with TA/DE information.
- annual denominator table
  - PMSI/activity hospital nights for the RATB TA/DE perimeter, computed
    independently from microbiology rows.

ORCHIDEE turns those blocks into the canonical runtime bundle and validates
that bundle before it crosses into the shared downstream core.

## Normalization philosophy

Orchidee owns the canonical target schema.

Each hospital owns its own raw-to-canonical mapping layer upstream.
That means:
- local raw values do not need to match Orchidee raw inputs
- local raw values do need to be mapped into Orchidee's canonical
  normalized schema
- hospitals should not edit Orchidee core dictionaries just to fit local
  raw exports

The intended split is:
- local adapter layer at each hospital
- shared Orchidee core downstream of canonical artifacts

## Documents in this folder

- `site_handoff_inputs_v1.md`
  - human-facing input blocks expected from a new hospital before ORCHIDEE
    derives the four runtime artifacts and assembles a strict canonical
    bundle
- `canonical_inputs_v1.md`
  - boundary between site-specific adapter work and shared ORCHIDEE core
- `sir_wide_v1.md`
  - exact v1 compatibility contract for the microbiology artifact
- `sample_scope_reference_v1.md`
  - v1 contract for the sample-level RATB TA/DE scope reference
- `denominator_bundle_v1.md`
  - v1 contract for the annual denominator bundle

## Contract ownership map

The v1 contract has two surfaces:

- human-facing contract:
  - `documentation/external_bundle/site_handoff_inputs_v1.md`
  - `documentation/external_bundle/canonical_inputs_v1.md`
  - `documentation/external_bundle/sir_wide_v1.md`
  - `documentation/external_bundle/sample_scope_reference_v1.md`
  - `documentation/external_bundle/denominator_bundle_v1.md`
- executable contract and validation rules:
  - `R/external_bundle_validation_helpers.R`
  - specifically `orchidee_external_contract_v1()`

When the v1 schema changes, update both surfaces in the same change.

The current internal producer, `R/build_sir_wide_artifact.R`, is a useful
reference implementation for the CHU artifact, but it is not the external
adapter contract. A future hospital adapter should produce artifacts that
match the external contract; it should not be required to reproduce the CHU
raw extraction path.

For a Rennes-style handoff, start one level upstream with
`site_handoff_inputs_v1.md`: the site provides elementary source blocks,
ORCHIDEE derives the runtime artifacts, and the resulting four files are
assembled into a validated canonical bundle.

## Validator

Use the standalone validator:

```powershell
& 'C:\Program Files\R\R-4.5.2\bin\Rscript.exe' scripts/validate_external_bundle.R data
```

Default behavior:
- validates `sir_wide.rds`
- validates `sir_wide_meta.rds`
- validates `sample_scope_reference.rds` if present
- otherwise accepts the current native `ratb_scope_cache` as a
  compatibility source for the sample-scope reference
- validates `denominator_bundle.rds` if present
- otherwise accepts the current native `ratb_scope_cache` as a
  compatibility source for the denominator bundle

The validator is additive only. It is not called by the main notebooks.

For a true external bundle, use strict preferred mode:

```powershell
& 'C:\Program Files\R\R-4.5.2\bin\Rscript.exe' scripts/validate_external_bundle.R outputs/external_bundle_v1 --strict-preferred
```

Strict preferred mode rejects CHU compatibility sources such as
`ratb_scope_cache`. It requires the four preferred files:
`sir_wide.rds`, `sir_wide_meta.rds`, `sample_scope_reference.rds`, and
`denominator_bundle.rds`.

## Materialize a preferred bundle

Current CHU artifacts still validate through compatibility sources such as
`ratb_scope_cache`. To write the preferred four-file bundle shape, run:

```powershell
& 'C:\Program Files\R\R-4.5.2\bin\Rscript.exe' scripts/materialize_external_bundle.R data outputs/external_bundle_v1 --force
```

This writes `sir_wide.rds`, `sir_wide_meta.rds`,
`sample_scope_reference.rds`, and `denominator_bundle.rds` to the output
directory, then validates that output directory in strict preferred mode.
This means the materialized output must contain the four preferred files
and must not rely on CHU compatibility sources such as `ratb_scope_cache`.

## Build a bundle from site handoff inputs

For a Rennes-style handoff, build the preferred bundle directly from the
elementary local blocks:

```powershell
& 'C:\Program Files\R\R-4.5.2\bin\Rscript.exe' `
  scripts/build_external_bundle_from_site_inputs.R `
  <microbiology_observations.rds|csv|tsv> `
  <bacteria_mapping.rds|csv|tsv> `
  <sample_type_mapping.rds|csv|tsv> `
  <antibiotic_mapping.rds|csv|tsv> `
  <unit_mapping.rds|csv|tsv> `
  <denominator_by_year.rds|csv|tsv> `
  <output_bundle_dir> `
  [de_reference.rds|csv|tsv] `
  [--force]
```

This writes the same four preferred files and validates them in strict
preferred mode. It is not a universal HDW connector: the hospital still owns
local extraction and mapping into these simple handoff blocks.

## Runtime smoke test

Use the runtime smoke test to check that a validated bundle can be converted
into the downstream ORCHIDEE inputs expected by the RATB method:

```powershell
& 'C:\Program Files\R\R-4.5.2\bin\Rscript.exe' scripts/smoke_external_runtime_inputs.R outputs/external_bundle_v1
```

This test validates the bundle, applies the sample-scope reference to
`sir_wide`, and checks that the scoped microbiology rows and annual
denominator table satisfy the core invariants. It does not render notebooks
or write pipeline caches.

For a true external handoff, run the same smoke test in strict preferred
mode:

```powershell
& 'C:\Program Files\R\R-4.5.2\bin\Rscript.exe' scripts/smoke_external_runtime_inputs.R outputs/external_bundle_v1 --strict-preferred
```

## Loader helper

The code boundary for future external execution is split in two:

- `load_validated_external_input_bundle()`
  - loads a bundle only after it passes the external contract;
  - coerces current compatibility sources, such as `ratb_scope_cache`, into
    the preferred canonical surfaces;
  - implemented in `R/external_bundle_validation_helpers.R`.
- `build_ratb_downstream_scope_from_canonical_inputs()`
  - applies the sample-scope reference to `sir_wide`;
  - returns the scoped microbiology rows and annual denominator table needed
    by the downstream RATB method;
  - implemented in `R/ratb_canonical_runtime_helpers.R`.

These helpers are also additive. They make the future runtime boundary
executable. The main notebooks still use the current native CHU path for
loading and QA, but the runtime scope and denominator objects are now built
in the notebook from the same canonical `sample_scope_reference` and
`denominator_bundle` boundary.
