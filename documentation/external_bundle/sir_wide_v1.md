---
editor_options:
  markdown:
    wrap: 72
---

# `sir_wide` v1 Contract

This document defines the first external compatibility contract for the
microbiology artifact.

v1 deliberately prioritizes compatibility and safety, while keeping the
portable surface smaller than the current CHU internal artifact.

## Required files

A valid external bundle must include:
- `sir_wide.rds`
- `sir_wide_meta.rds`

## Required row grain

`ELTID` alone is not the row key.

The compatibility row grain is:
- `(PATID, EVTID, ELTID, DATEPRELEV, souche_id, naturepvt_norm, bact_norm)`

That key must be unique across rows.

For v1, `EVTID` and `naturepvt_norm` may be missing because the current
internal artifact already allows that pattern.
The validator still requires the other row-grain fields to be non-missing.

## Required columns

### Identifier and ordering columns

- `PATID`
- `EVTID`
- `ELTID`
- `DATEPRELEV`
- `HEUREPRELEV`
- `souche_id`

### Scope and taxonomy columns

- `naturepvt_norm`
- `bact_norm`
- `SEJUF`

`SEJUF` is required because the current RATB microbiology perimeter is
derived at sample level from the sample UF and the CONSORES TA/DE
reference.

`SEJUM` and `TYPEANA` may be present in CHU/internal artifacts as local
audit context, but they are not required by the portable ORCHIDEE core.

`evt_order` and `elt_order` may be present as local deterministic ordering
helpers. They are optional because the shared SPARES code derives ordering
from the canonical date, time, document identifier and row order when these
columns are absent.

`nb_resultats` may be present as a local completeness helper. It is optional
because the ORCHIDEE loader derives it from the supported antibiotic columns
when absent.

### Supported antibiotic columns

- `levofloxacine`
- `rifampicine`
- `tetracycline`
- `vancomycine`
- `acide_fusidique`
- `erythromycine`
- `fosfomycine_trometamol`
- `gentamicine`
- `kanamycine`
- `oxacilline`
- `trimethoprime_sulfamethoxazole`
- `amikacine`
- `amoxicilline_acide_clavulanique`
- `amoxicilline_ampicilline`
- `ceftazidime`
- `ceftriaxone`
- `mecillinam`
- `nitrofurantoine`
- `ofloxacine`
- `piperacilline_tazobactam`
- `ertapeneme`
- `fosfomycine_iv`
- `cefepime`
- `cefotaxime`
- `ciprofloxacine`
- `imipeneme`
- `meropeneme`
- `tobramycine`
- `pristinamycine`
- `ticarcilline`
- `daptomycine`
- `linezolide`
- `teicoplanine`
- `moxifloxacine`
- `cefoxitine`

### Phenotype columns

- `blse_status_row`
- `carbapenemase_status_row`
- `blse_flag`
- `carbapenemase_flag`

Extra columns may exist, but they are not part of the v1 contract.
The validator ignores them after warning.

## Expected types

- `PATID`, `EVTID`, `ELTID`, `souche_id`, `naturepvt_norm`, `bact_norm`,
  `SEJUF`: character
- all supported antibiotic columns: character
- `blse_status_row`, `carbapenemase_status_row`: character
- `DATEPRELEV`: `Date`
- `HEUREPRELEV`: `difftime`-based time column serialized by R
- `blse_flag`, `carbapenemase_flag`: logical
- optional `nb_resultats`: numeric when present; derived by the loader when
  absent
- optional `evt_order`, `elt_order`: integer-like when present

## Allowed values

### Antibiotic columns

Allowed non-missing values:
- `S`
- `R`
- `ZIT`

Missing values are allowed.

### Phenotype status columns

`blse_status_row` allowed values:
- `negative`
- `no_signal`
- `positive`

`carbapenemase_status_row` allowed values:
- `negative`
- `no_signal`
- `positive`
- `unknown`

### Phenotype flags

- logical `TRUE`
- logical `FALSE`
- no `NA`

## Required metadata fields

`sir_wide_meta.rds` must be a list containing at least:
- `artifact_version`
- `created_at`
- `sir_wide_n_rows`
- `sir_wide_n_eltid`
- `atb_cols`
- `supported_atb_cols`
- `phenotype_status_cols`
- `phenotype_flag_cols`
- `filtre_atb`

Validation-relevant expectations:
- `sir_wide_n_rows` matches `nrow(sir_wide)`
- `sir_wide_n_eltid` matches `n_distinct(ELTID)`
- `supported_atb_cols` matches the full v1 supported ATB set
- `atb_cols` is a subset of the supported ATB set
- `filtre_atb` matches the full v1 supported ATB set
- phenotype column vectors match the v1 contract

Additional metadata fields are allowed but not required by the v1
validator.

