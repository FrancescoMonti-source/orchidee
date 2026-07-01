---
editor_options:
  markdown:
    wrap: 72
---

# Sample Scope Reference v1 Contract

This document defines the external compatibility contract for the
sample-level RATB TA/DE scope reference.

The reference is the bridge between local hospital unit mapping and the
shared ORCHIDEE core. A site adapter maps local unit information into this
table; ORCHIDEE applies the table to `sir_wide` rows through `SEJUF`.

## Preferred file

The preferred external file is:

- `sample_scope_reference.rds`

It must be an R data frame or tibble.

## Compatibility source

For fidelity with the current CHU runtime, the validator also accepts the
native `ratb_scope_cache` artifact if it contains `ratb_uf_ta_de_reference`.

That compatibility path is for validation convenience only. The preferred
external contract remains `sample_scope_reference.rds`.

## Required row grain

The row grain is one row per sample unit:

- `SEJUF`

`SEJUF` must be unique when non-missing. Missing `SEJUF` is not useful for a
scope reference and is therefore rejected.

## Required columns

- `SEJUF`
- `sample_CODE_TA`
- `sample_CODE_DE`
- `sample_de_domain_ref`
- `sample_uf_is_eligible_by_ta_de`
- `sample_uf_ta_de_status`
- `sample_uf_ta_de_reason`

Optional audit columns, such as `sample_consores_uf_label`, may be present.
The validator warns about extra columns but does not reject them. Loader and
materialization helpers retain only the required v1 columns at the portable
ORCHIDEE boundary.

## Expected types

- `SEJUF`: character
- `sample_CODE_TA`: character
- `sample_CODE_DE`: character
- `sample_de_domain_ref`: character
- `sample_uf_is_eligible_by_ta_de`: logical
- `sample_uf_ta_de_status`: character
- `sample_uf_ta_de_reason`: character

## Allowed values

`sample_uf_is_eligible_by_ta_de` must be `TRUE` or `FALSE`, with no `NA`.

`sample_uf_ta_de_status` allowed values:

- `eligible_ta_de`
- `excluded_ta`
- `excluded_de_domain`
- `review_unmapped_uf`
- `review_unmapped_de`
- `review_missing_sample_uf`

`sample_uf_ta_de_reason` allowed values:

- `eligible_ta_de`
- `ta_not_03_20`
- `ta_03_20_de_domain_not_included`
- `uf_absent_from_consores_structure`
- `ta_03_20_unmapped_de`
- `missing_sample_uf`

## Interpretation

The reference does not remove rows from `sir_wide` by itself. It provides
the mapped eligibility information that ORCHIDEE uses to decide which
microbiology rows contribute to RATB numerators and proportions.

For the portable workflow, a site adapter should provide the broad canonical
`sir_wide` artifact plus this scope reference. The adapter should not
pre-filter `sir_wide` to make out-of-scope rows disappear before ORCHIDEE
applies the surveillance rule.
