---
editor_options:
  markdown:
    wrap: 72
---

# Site Handoff Inputs v1

This document describes the human-facing input blocks expected from another
hospital, such as Rennes.

These inputs are deliberately one level upstream from the canonical
ORCHIDEE runtime bundle. Rennes should not be asked to author
`sir_wide_meta.rds`, `sample_scope_reference.rds`, or
`denominator_bundle.rds` by hand. The site provides elementary local inputs;
ORCHIDEE derives those runtime files internally.

## Relationship to the canonical bundle

The canonical runtime bundle remains:

- `sir_wide.rds`
- `sir_wide_meta.rds`
- `sample_scope_reference.rds`
- `denominator_bundle.rds`

That bundle is the machine/runtime contract. It is not the best onboarding
format for a new hospital.

The Rennes-facing handoff is:

```text
local site inputs
        |
        v
site handoff builder
        |
        v
canonical ORCHIDEE runtime bundle
        |
        v
existing validator and runtime smoke test
```

The preferred handoff now starts from elementary microbiology observations
plus local mapping dictionaries. ORCHIDEE derives `sir_wide.rds` and the
other runtime artifacts from those inputs.

For sites that have already built the canonical wide microbiology artifact,
the older prebuilt-`sir_wide.rds` builder remains available as a compatibility
path.

## Input 1: microbiology source block

Preferred files:

- `microbiology_observations.rds`, `microbiology_observations.csv`, or
  `microbiology_observations.tsv`
- `bacteria_mapping.rds`, `bacteria_mapping.csv`, or
  `bacteria_mapping.tsv`
- `sample_type_mapping.rds`, `sample_type_mapping.csv`, or
  `sample_type_mapping.tsv`
- `antibiotic_mapping.rds`, `antibiotic_mapping.csv`, or
  `antibiotic_mapping.tsv`

`microbiology_observations` is a long table. It should contain one row per
local microbiology S/I/R result for a sample, an identified bacterium and an
antibiotic.

Required columns:

- `PATID`
- `ELTID`
- `DATEPRELEV`
- `souche_id`
- `SEJUF`
- `bacteria_local`
- `sample_type_local`
- `antibiotic_local`
- `sir_result`

Optional columns:

- `EVTID`
- `HEUREPRELEV`
- `blse_status_row` or `blse_status`
- `carbapenemase_status_row` or `carbapenemase_status`

Interpretation:

- `DATEPRELEV` must be an R `Date` in RDS files, or an ISO date
  (`YYYY-MM-DD`) in delimited files; French dates (`DD/MM/YYYY`) are also
  accepted.
- `HEUREPRELEV`, when present in delimited files, must use `HH:MM` or
  `HH:MM:SS`.
- `sir_result` is normalized by ORCHIDEE:
  - `S` and `SFP` become `S`;
  - `R` and `---R` become `R`;
  - `I` and `ZIT` become `ZIT`;
  - `NC` or blank values become missing.

Mapping dictionaries:

- `bacteria_mapping` requires `bacteria_local` and `bact_norm`.
- `sample_type_mapping` requires `sample_type_local` and `naturepvt_norm`.
- `antibiotic_mapping` requires `antibiotic_local` and `atb_norm`.

The local values are hospital-owned. The mapped values must be ORCHIDEE
canonical values. The builder fails if a local value is not mapped or if an
antibiotic maps outside the v1 supported antibiotic set.

Phenotype statuses are optional in this handoff. If absent, ORCHIDEE records
`no_signal` for BLSE and carbapenemase at row level. If present, allowed
statuses are the values documented in `sir_wide_v1.md`.

Compatibility path:

- `sir_wide.rds`
  - prebuilt canonical wide microbiology artifact;
  - schema defined in `sir_wide_v1.md`;
  - still accepted by `build_external_bundle_from_handoff_inputs.R`.

## Input 2: unit mapping

Preferred file:

- `unit_mapping.rds`, `unit_mapping.csv`, or `unit_mapping.tsv`

Required columns:

- `SEJUF`
- `CODE_TA`

The file must also provide either:

- `de_domain_ref`

or:

- `CODE_DE`, together with a separate DE reference dictionary.

Expected grain:

- one row per `SEJUF`

Interpretation:

- the site owns the mapping from local units to TA/DE information;
- ORCHIDEE owns the RATB rule that turns that mapping into eligibility.

Included `de_domain_ref` values are the CONSORES/SPARES domains used by the
current RATB perimeter:

- `MÉDECINE`
- `URGENCES`
- `CHIRURGIE`
- `RÉANIMATION`
- `PÉDIATRIE`
- `GYNÉCOLOGIE-OBSTÉTRIQUE`
- `SOINS MÉDICAUX ET DE RÉADAPTATION`
- `SOINS DE LONGUE DURÉE`
- `PSYCHIATRIE`
- `ÉTABLISSEMENT D'HÉBERGEMENT POUR PERSONNES ÂGÉES DÉPENDANTES`

The builder normalizes case and accents for these included labels. Other
local domain labels are not guessed; they remain excluded unless the site maps
them to the expected vocabulary.

## Input 3: optional DE reference dictionary

Preferred file:

- `de_reference.rds`, `de_reference.csv`, or `de_reference.tsv`

Required columns:

- `CODE_DE`
- `de_domain_ref` or `DOMAINE`

This file is optional when `unit_mapping` already contains
`de_domain_ref`.

## Input 4: incidence denominator by year

Preferred file:

- `denominator_by_year.rds`, `denominator_by_year.csv`, or
  `denominator_by_year.tsv`

Required columns:

- `calendar_year`
- `hospital_nights`

Expected grain:

- one row per calendar year

Interpretation:

- `hospital_nights` is the PMSI/activity denominator for the RATB TA/DE
  perimeter;
- it must be computed independently from microbiology rows.

## Derived canonical files

From those inputs, ORCHIDEE derives:

- `sir_wide.rds`
  - generated by pivoting microbiology observations through the local
    mapping dictionaries.
- `sir_wide_meta.rds`
  - generated from `sir_wide`;
  - not requested from the site.
- `sample_scope_reference.rds`
  - generated from the unit mapping and DE reference;
  - contains the final RATB sample-UF eligibility fields.
- `denominator_bundle.rds`
  - generated from the annual denominator table.

The original `sir_wide.rds` is copied into the output bundle.

## Command-line builder

Build a strict preferred bundle from elementary site inputs:

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

Build a strict preferred bundle from an already built `sir_wide.rds`:

```powershell
& 'C:\Program Files\R\R-4.5.2\bin\Rscript.exe' `
  scripts/build_external_bundle_from_handoff_inputs.R `
  <sir_wide.rds> `
  <unit_mapping.rds|csv|tsv> `
  <denominator_by_year.rds|csv|tsv> `
  <output_bundle_dir> `
  [de_reference.rds|csv|tsv] `
  [--force]
```

The script writes:

- `sir_wide.rds`
- `sir_wide_meta.rds`
- `sample_scope_reference.rds`
- `denominator_bundle.rds`

It then runs the existing external-bundle validator in strict preferred
mode. A produced bundle is accepted only if it satisfies the canonical
runtime contract.

## Boundary

This handoff layer is not a universal HDW connector.

It does not make Rennes reproduce the CHU extraction path.

It asks Rennes for elementary hospital-owned inputs and leaves ORCHIDEE to
derive ORCHIDEE-owned runtime artifacts.
