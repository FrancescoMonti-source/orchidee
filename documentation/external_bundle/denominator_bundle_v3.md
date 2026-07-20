---
editor_options:
  markdown:
    wrap: 72
---

# Denominator Bundle v3 Contract

## Purpose

External bundle v3 promotes the incidence denominator to the finest grain
currently required for later stratification by hospitalization UM, UF, TA or
DE. It retains the v2 meaning of `sir_wide$SEJUF`: the hospitalization UF
active at sampling.

This is an explicit successor contract. It does not change the accepted v1 or
v2 bundle shapes, and it is not yet the default operational notebook input.

## Preferred file

The preferred file remains `denominator_bundle.rds`. Under contract v3 it must
be an R list containing exactly the required canonical table after loading:

```text
incidence_denominator_by_year_um_uf_ta_de
```

The long name states the grain deliberately; `unit` alone would not say
whether the table refers to UM, UF or both.

## Required table

Required columns, in order:

```text
calendar_year
SEJUM
SEJUF
CODE_TA
CODE_DE
hospital_nights
```

The row grain is:

```text
calendar_year + SEJUM + SEJUF + CODE_TA + CODE_DE
```

Type and integrity requirements:

- `calendar_year` and `hospital_nights` are integer-like;
- `SEJUM`, `SEJUF`, `CODE_TA` and `CODE_DE` are character columns;
- none of the six required columns may be missing;
- `hospital_nights` is non-negative;
- the declared row grain is unique.

Only hospital nights inside the RATB TA/DE perimeter belong in this table. The
table must be computed independently from microbiology rows.

## One source table, derived annual total

Contract v3 does not transport a second annual denominator table. The runtime
derives the unchanged global annual input with:

```text
group by calendar_year
hospital_nights = sum(hospital_nights)
```

This avoids two canonical tables that could diverge. The current indicator
engine continues to consume the derived
`incidence_denominator_by_year`; the fine table is also retained in runtime
inputs for a future, separate implementation of stratified incidence.

No stratified panel is added merely by adopting this contract. Indicator
specification, numerator dimensions and publication decisions remain separate
work.

## Site handoff input

For `--contract=v3`, the sixth site-owned input is
`denominator_by_year_um_uf_ta_de` with the same six columns and grain. The
shared builder validates and stores it as the canonical table above.

For `--contract=v1` or `--contract=v2`, the sixth input remains
`denominator_by_year` with `calendar_year + hospital_nights`.

## Rouen producer

The Rouen PMSI adapter derives `hospital_nights_by_year_um_uf_ta_de` from
eligible PMSI unit stays
after the `redsan` `C > DW` source policy and joins the maintained TA/DE
reference before aggregation. Build a v3 candidate with:

```powershell
Rscript scripts/build_rouen_external_bundle.R `
  <bacteriology_raw.rds> `
  <pmsi.rds> `
  <output_dir> `
  --contract=v3
```

The previous `scripts/build_rouen_external_bundle_v2.R` entry point remains a
compatibility wrapper and still defaults to v2.
