---
editor_options:
  markdown:
    wrap: 72
---

# `sir_wide` v2: hospitalization-unit semantics

## Purpose

Contract v2 keeps the four-file bundle and the tabular shape of v1. Its only
intentional change is to make the meaning of `sir_wide$SEJUF` explicit:

`SEJUF` is the hospitalization unit active when the microbiology sample was
collected (`hospitalization_unit_at_sampling`).

The column is not renamed because it remains the UF code used to join the
TA/DE scope reference. A second UF column would duplicate the canonical key
and would be ignored by the current portable core.

## Adapter responsibility

The site adapter must assign the hospitalization unit before calling the
shared bundle builder. For the Rouen adapter, the ratified default is:

- use PMSI intervals after the `redsan` `c_over_dw` source policy;
- match the sample datetime inside the half-open interval
  `DATENT <= sample_datetime < DATSORT`;
- retain `PATID` as a provenance guard for the `EVTID` join;
- do not fall back to the microbiology unit when the hospitalization unit is
  unresolved.

Ambiguous and unassigned documents remain visible in the adapter audit. Their
canonical `SEJUF` is missing, so they are excluded from the
hospitalization-based analytical perimeter.

The bundle validator checks the declared semantics. It cannot reconstruct the
PMSI attribution from the four portable files; that remains an upstream
adapter gate.

## Required metadata

In addition to all v1 metadata, `sir_wide_meta.rds` must contain exactly:

```text
contract_version = "v2"
sejuf_semantics = "hospitalization_unit_at_sampling"
```

Build and validate this profile with:

```powershell
Rscript scripts/build_external_bundle_from_site_inputs.R `
  <microbiology_observations> `
  <bacteria_mapping> `
  <sample_type_mapping> `
  <antibiotic_mapping> `
  <unit_mapping> `
  <denominator_by_year> `
  <output_bundle_dir> `
  --contract=v2

Rscript scripts/validate_external_bundle.R `
  <output_bundle_dir> `
  --contract=v2 `
  --strict-preferred

Rscript scripts/smoke_external_runtime_inputs.R `
  <output_bundle_dir> `
  --contract=v2 `
  --strict-preferred
```

Contract v1 remains the default when `--contract` is omitted.

External bundle v3 inherits this same `SEJUF` meaning and changes only the
denominator contract; see `denominator_bundle_v3.md`.
