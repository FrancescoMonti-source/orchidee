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

## Boundary

### Site adapter responsibility

The site adapter owns all raw-to-canonical work:

- retrieving data from the local HDW or source systems;
- mapping local microbiology labels to canonical bacteria, antibiotics,
  sample types and phenotypes;
- identifying diagnostic microbiology rows and excluding local screening
  material that should not enter RATB indicators;
- mapping local units to the TA/DE perimeter used for RATB surveillance;
- building the annual PMSI/activity denominator tables expected by
  ORCHIDEE.

Adapter code can be hospital-specific. It should not be implemented inside
the ORCHIDEE core unless it is genuinely part of the shared RATB method.

### ORCHIDEE core responsibility

The shared core owns the downstream method:

- applying the RATB analysis scope to canonical microbiology rows;
- running completion strategies;
- applying SPARES-style deduplication;
- computing proportions, incidence densities and phenotype indicators;
- producing reproducible QA tables and report exports.

Core code should not depend on CHU raw extraction names, EDSaN access,
local biology software conventions, or site-specific screening codes.

## Current v1 canonical files

The current dormant external contract uses three files:

- `sir_wide.rds`
  - canonical microbiology rows in wide S/I/R format;
  - exact schema in `sir_wide_v1.md`.
- `sir_wide_meta.rds`
  - metadata and freshness information for `sir_wide.rds`;
  - exact required fields in `sir_wide_v1.md`.
- `denominator_bundle.rds`
  - annual PMSI/activity denominator tables;
  - exact schema in `denominator_bundle_v1.md`.

The executable validator is:

```powershell
Rscript scripts/validate_external_bundle.R <bundle_dir>
```

It validates the shape and basic invariants of these files. It does not
validate that a hospital's raw-to-canonical adapter made the scientifically
right local mapping choices.

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

The current runtime still builds `ratb_scope_cache` inside the native CHU
workflow from `sir_wide`, PMSI data and TA/DE references. The external
bundle validator accepts the resulting denominator bundle for compatibility,
but the main notebooks do not yet branch into an external-runtime mode.

The intended portability direction is now:

- the site adapter maps local unit information into a canonical sample-scope
  reference;
- the ORCHIDEE core applies that reference to microbiology rows;
- the site adapter should not pre-filter `sir_wide` to hide rows outside the
  RATB TA/DE perimeter.

This keeps the surveillance counting rule in the shared core while keeping
local HDW extraction and unit mapping outside the core.

The current v1 validator does not yet require that separate sample-scope
reference file. Until that schema increment is implemented, the v1 bundle is
a documented and validated compatibility target, not a fully wired external
execution mode.
