---
editor_options:
  markdown:
    wrap: 72
---

# Canonical Input Boundary v1

This note defines the intended boundary between a local hospital adapter and
the shared ORCHIDEE downstream core.

The goal is not to build a universal HDW connector. Each hospital remains
responsible for extracting and mapping its own local data. ORCHIDEE starts
only once those local data have been converted into the canonical inputs
listed here.

For a Rennes-style handoff, the human-facing exchange can happen one level
upstream. `site_handoff_inputs_v1.md` describes elementary source blocks
that ORCHIDEE can convert into this canonical runtime bundle.

## Boundary

### Site adapter responsibility

The site adapter owns all raw-to-canonical work:

- retrieving data from the local HDW or source systems;
- mapping local microbiology labels to canonical bacteria, antibiotics,
  sample types and phenotypes;
- flagging diagnostic versus screening / non-diagnostic microbiology rows via
  `ratb_diagnostic_scope` (the site knows its own local screening test types);
  the sample-level exclusion itself is applied by the core, not the site;
- mapping local units to the TA/DE perimeter used for RATB surveillance;
- building the annual PMSI/activity denominator table expected by
  ORCHIDEE.

Adapter code can be hospital-specific. It should not be implemented inside
the ORCHIDEE core unless it is genuinely part of the shared RATB method.

### ORCHIDEE core responsibility

The shared core owns the downstream method:

- excluding screening / non-diagnostic samples in full, at the sample level: a
  whole `ELTID` is dropped when any of its rows is flagged non-diagnostic,
  matching the frozen RATB method;
- applying the RATB analysis scope to canonical microbiology rows;
- running completion strategies;
- applying SPARES-style deduplication;
- computing proportions, incidence densities and phenotype indicators;
- producing reproducible QA tables and report exports.

Core code should not depend on CHU raw extraction names, EDSaN access,
local biology software conventions, or site-specific screening codes.

## Current v1 canonical files

The current external contract uses four files:

- `sir_wide.rds`
  - canonical microbiology rows in wide S/I/R format;
  - exact schema in `sir_wide_v1.md`.
- `sir_wide_meta.rds`
  - metadata and freshness information for `sir_wide.rds`;
  - exact required fields in `sir_wide_v1.md`.
- `sample_scope_reference.rds`
  - sample-level TA/DE scope reference joined to `sir_wide` by `SEJUF`;
  - exact schema in `sample_scope_reference_v1.md`.
- `denominator_bundle.rds`
  - annual PMSI/activity denominator table
    (`incidence_denominator_by_year`);
  - exact schema in `denominator_bundle_v1.md`.

The executable validator is:

```powershell
Rscript scripts/validate_external_bundle.R <bundle_dir>
```

It validates the shape and basic invariants of these files. It does not
validate that a hospital's raw-to-canonical adapter made the scientifically
right local mapping choices.

After validation, `load_validated_external_input_bundle()` can load the
canonical files and `build_ratb_downstream_scope_from_canonical_inputs()`
from `R/ratb_canonical_runtime_helpers.R` can build the minimal downstream
scope and denominator objects used by the RATB method.

For a command-line check of that same boundary, run:

```powershell
Rscript scripts/smoke_external_runtime_inputs.R <bundle_dir>
```

To convert current compatible artifacts into the preferred four-file bundle
layout, run:

```powershell
Rscript scripts/materialize_external_bundle.R <source_bundle_dir> <output_bundle_dir>
```

The materializer accepts a compatible source bundle, but validates the
output directory in strict preferred mode. The produced bundle must therefore
contain the four preferred files and cannot depend on `ratb_scope_cache`.

To build the preferred four-file bundle from Rennes-style elementary handoff
inputs, run:

```powershell
Rscript scripts/build_external_bundle_from_site_inputs.R `
  <microbiology_observations> `
  <bacteria_mapping> `
  <sample_type_mapping> `
  <antibiotic_mapping> `
  <unit_mapping> `
  <denominator_by_year> `
  <output_bundle_dir>
```

That script derives `sir_wide.rds`, `sir_wide_meta.rds`,
`sample_scope_reference.rds`, and `denominator_bundle.rds`, then validates
the output in strict preferred mode.

## What is not canonical input

These objects are CHU/local implementation details, not portable ORCHIDEE
inputs:

- raw EDSaN extraction calls;
- raw `bact22_24` and `pmsi` files;
- CHU-specific `TYPEANA` screening codes;
- CHU-specific extraction windows;
- local microbiology label spelling before dictionary mapping;
- local unit-reference text files before TA/DE mapping.

`R/build_sir_wide_artifact.R` is therefore best read as the current CHU
adapter and reference producer for `sir_wide.rds`, not as the contract that
another hospital must reproduce line by line.

## Current open boundary

The current runtime still uses a native CHU recompute path to produce
`ratb_scope_cache` from `sir_wide`, PMSI data and TA/DE references. Within
that cache, the CHU path provides the canonical `sample_scope_reference`
and `denominator_bundle` objects plus local QA context. The notebook then
builds the scoped microbiology rows and incidence denominator table from
those canonical objects through `R/ratb_canonical_runtime_helpers.R`.

The main notebooks do not yet branch into a full external-runtime mode.
The external bundle validator accepts the current native `ratb_scope_cache`
as a compatibility source when the preferred four-file bundle has not been
materialized.

The intended portability direction is now:

- the site adapter maps local unit information into a canonical sample-scope
  reference;
- the ORCHIDEE core applies that reference to microbiology rows;
- the site adapter should not pre-filter `sir_wide` to hide rows outside the
  RATB TA/DE perimeter.

This keeps the surveillance counting rule in the shared core while keeping
local HDW extraction and unit mapping outside the core. The v1 validator
already knows this preferred file, while still accepting the current native
`ratb_scope_cache` as a compatibility source.

The v1 bundle is therefore a documented and validated compatibility target
with an executable core scope boundary, not a fully wired external notebook
execution mode.
