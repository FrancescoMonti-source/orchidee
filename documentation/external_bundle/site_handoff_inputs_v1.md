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

In this v1, the microbiology block is still `sir_wide.rds`. ORCHIDEE derives
the other runtime artifacts around it.

## Input 1: microbiology source block

Preferred file:

- `sir_wide.rds`

For the current executable handoff builder, the microbiology source block is
already the canonical wide microbiology table, provided as RDS so that dates
and times keep their R classes.

This file contains the canonical wide microbiology rows. Its schema remains
defined in `sir_wide_v1.md`.

Rennes may build it from local microbiology observations and local mapping
dictionaries. That local raw-to-canonical mapping is site-owned.

This is the main remaining upstream step: ORCHIDEE now derives the other
runtime artifacts from simpler handoff blocks, but the generic
raw-microbiology-to-`sir_wide` adapter is not part of this v1 builder.

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

Build a strict preferred bundle:

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
