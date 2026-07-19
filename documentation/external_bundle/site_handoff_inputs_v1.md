---
editor_options:
  markdown:
    wrap: 72
---

# Site Handoff Inputs v1

This is the first document a hospital data-warehouse team should read when it
wants to connect local data to ORCHIDEE.

You do not need to reproduce the CHU extraction path. You prepare the simple
input files below; ORCHIDEE turns them into its internal validated files.

## What you need to provide

Prepare these six required files:

1. `microbiology_observations`
2. `bacteria_mapping`
3. `sample_type_mapping`
4. `antibiotic_mapping`
5. `unit_mapping`
6. `denominator_by_year`

You may also provide a seventh optional file:

7. `de_reference`

Accepted formats are `.rds`, `.csv`, `.tsv`, `.tab`, or `.txt`. CSV files can
use commas or semicolons. Text files must be UTF-8.

Before running ORCHIDEE commands on a fresh clone, restore the R environment
from `renv.lock` as described in the main `README.md`.

ORCHIDEE writes these internal files after validation:

- `sir_wide.rds`
- `sir_wide_meta.rds`
- `sample_scope_reference.rds`
- `denominator_bundle.rds`

Do not build those four files by hand for a first handoff.

## File 1: microbiology_observations

This file contains one row per local S/I/R result for one sample, one bacterium
and one antibiotic.

Required columns:

| Column | Meaning |
| --- | --- |
| `PATID` | Patient identifier. |
| `ELTID` | Sample / microbiology event identifier. |
| `DATEPRELEV` | Sample date. Use `YYYY-MM-DD` or `DD/MM/YYYY` in text files. |
| `SEJUF` | Sample unit. ORCHIDEE uses this to apply the RATB TA/DE perimeter. |
| `bacteria_local` | Local bacterium label. |
| `sample_type_local` | Local sample-type label. |
| `antibiotic_local` | Local antibiotic label. |
| `sir_result` | Local S/I/R result. |
| `ratb_diagnostic_scope` | TRUE if the row belongs to diagnostic RATB microbiology, FALSE for screening / non-diagnostic rows. Exclusion is applied per document occurrence — see the note under File 1. |

Accepted aliases for `ratb_diagnostic_scope` are `diagnostic_scope` and
`is_diagnostic`, but `ratb_diagnostic_scope` is preferred.

Optional columns:

| Column | Meaning |
| --- | --- |
| `EVTID` | Hospital stay / encounter identifier, if available. When present on every row of a `PATID + ELTID` group, it keeps reused sample identifiers separate during screening exclusion. |
| `HEUREPRELEV` | Sample time, `HH:MM` or `HH:MM:SS`. |
| `souche_id` or `isolate_local_id` | Local isolate identifier when the lab distinguishes several isolates for the same sample. |
| `blse_status_row` or `blse_status` | Optional BLSE status: `positive`, `negative`, `unknown`, `no_signal`. |
| `carbapenemase_status_row` or `carbapenemase_status` | Optional carbapenemase status: `positive`, `negative`, `unknown`, `no_signal`. |

Accepted `sir_result` values:

- `S` and `SFP` become `S`;
- `R` and `---R` become `R`;
- `I` and `ZIT` become `ZIT`;
- `NC`, `NA`, `N/A` or blank values become missing.

Minimal example:

```csv
PATID,EVTID,ELTID,DATEPRELEV,HEUREPRELEV,SEJUF,bacteria_local,sample_type_local,antibiotic_local,sir_result,ratb_diagnostic_scope
P001,S001,MIC001,2024-03-12,09:15,UF1234,Escherichia coli,Urine,Amoxicilline acide clavulanique,R,TRUE
```

Important: `ratb_diagnostic_scope` is not the TA/DE hospital perimeter. It is
the local microbiology decision that keeps screening and other non-diagnostic
material out before ORCHIDEE applies the hospital-unit perimeter.

Exclusion is applied at the document occurrence level: if any row of a given
`PATID + EVTID + ELTID` occurrence is marked `FALSE` (screening /
non-diagnostic), ORCHIDEE drops that whole occurrence across all bacteria,
antibiotics and phenotypes. If any row within the same `PATID + ELTID` group
lacks `EVTID`, ORCHIDEE conservatively uses `PATID + ELTID` for that group.
It never propagates screening through `ELTID` alone across patients. This
matches the RATB rule that a screening sample is excluded in full while
preserving distinct occurrences when a source identifier is reused. You
therefore do not need to remove screening rows yourself: flag them and keep the
flag consistent within the document occurrence.

If several rows map to the same ORCHIDEE row key and antibiotic, ORCHIDEE keeps
the last non-missing S/I/R value in input order. If the laboratory reports
several isolates of the same species in one sample, provide `souche_id` or
`isolate_local_id` so those isolates remain separate.

## File 2: bacteria_mapping

This file maps local bacterium labels to ORCHIDEE bacterium names.

Required columns:

| Column | Meaning |
| --- | --- |
| `bacteria_local` | Local bacterium label as it appears in `microbiology_observations`. |
| `bact_norm` | ORCHIDEE bacterium name. |

Example:

```csv
bacteria_local,bact_norm
Escherichia coli,Escherichia coli
Klebsiella pneumoniae,Klebsiella pneumoniae
```

## File 3: sample_type_mapping

This file maps local sample-type labels to ORCHIDEE sample types.

Required columns:

| Column | Meaning |
| --- | --- |
| `sample_type_local` | Local sample-type label as it appears in `microbiology_observations`. |
| `naturepvt_norm` | ORCHIDEE sample type. |

Example:

```csv
sample_type_local,naturepvt_norm
Urine,urine
Hemoculture,hemoculture
```

`naturepvt_norm` may be left blank when a local sample type cannot be
classified reliably. Those rows remain available for global indicators, but
cannot contribute to analyses that require a known sample type. The number of
blank mappings should be reviewed during onboarding.

## File 4: antibiotic_mapping

This file maps local antibiotic labels to ORCHIDEE antibiotic columns.

Required columns:

| Column | Meaning |
| --- | --- |
| `antibiotic_local` | Local antibiotic label as it appears in `microbiology_observations`. |
| `atb_norm` | ORCHIDEE antibiotic column. |

Example:

```csv
antibiotic_local,atb_norm
Amoxicilline acide clavulanique,amoxicilline_acide_clavulanique
Cefotaxime,cefotaxime
```

Only include antibiotic result rows that map to supported ORCHIDEE antibiotic
columns. The builder fails if `atb_norm` is not one of those columns.

## File 5: unit_mapping

This file tells ORCHIDEE which local sample units belong to the RATB TA/DE
perimeter.

Required columns:

| Column | Meaning |
| --- | --- |
| `SEJUF` | Sample unit. Must match `SEJUF` in `microbiology_observations`. |
| `CODE_TA` | TA code for the unit. |

The file must also provide either:

- `de_domain_ref`, directly in `unit_mapping`;
- or `CODE_DE`, together with a separate `de_reference` file.

Expected grain: one row per `SEJUF`.

Example with `de_domain_ref` directly included:

```csv
SEJUF,CODE_TA,de_domain_ref
UF1234,03,MÉDECINE
UF5678,20,URGENCES
```

Example with `CODE_DE` instead:

```csv
SEJUF,CODE_TA,CODE_DE
UF1234,03,001
UF5678,20,002
```

In the second case, also provide `de_reference`.

## Optional file 7: de_reference

This file is only needed when `unit_mapping` provides `CODE_DE` but not
`de_domain_ref`.

Required columns:

| Column | Meaning |
| --- | --- |
| `CODE_DE` | DE code. |
| `de_domain_ref` or `DOMAINE` | Domain label for the DE code. |

Example:

```csv
CODE_DE,de_domain_ref
001,MÉDECINE
002,URGENCES
```

## File 6: denominator_by_year

This file contains the annual denominator for incidence indicators.

Required columns:

| Column | Meaning |
| --- | --- |
| `calendar_year` | Calendar year. |
| `hospital_nights` | Hospital nights in the RATB TA/DE perimeter. |

Expected grain: one row per calendar year.

Example:

```csv
calendar_year,hospital_nights
2024,363728
```

This denominator must be computed independently from microbiology rows.

## Build and validate the ORCHIDEE input files

From the repository root:

```powershell
Rscript `
  scripts/build_external_bundle_from_site_inputs.R `
  inputs/microbiology_observations.csv `
  inputs/bacteria_mapping.csv `
  inputs/sample_type_mapping.csv `
  inputs/antibiotic_mapping.csv `
  inputs/unit_mapping.csv `
  inputs/denominator_by_year.csv `
  outputs/site_bundle `
  inputs/de_reference.csv `
  --force
```

If `unit_mapping` already contains `de_domain_ref`, omit the `de_reference`
argument:

```powershell
Rscript `
  scripts/build_external_bundle_from_site_inputs.R `
  inputs/microbiology_observations.csv `
  inputs/bacteria_mapping.csv `
  inputs/sample_type_mapping.csv `
  inputs/antibiotic_mapping.csv `
  inputs/unit_mapping.csv `
  inputs/denominator_by_year.csv `
  outputs/site_bundle `
  --force
```

A successful run validates the inputs and writes the four ORCHIDEE internal
files to `outputs/site_bundle`.

## If validation fails

Read the first error message. The most common failures are:

- a required column is missing;
- a local bacterium, sample type or antibiotic has no mapping;
- an antibiotic maps to an unsupported ORCHIDEE antibiotic column;
- all microbiology rows are marked outside `ratb_diagnostic_scope`;
- `SEJUF` is duplicated in `unit_mapping`;
- `DATEPRELEV` or `HEUREPRELEV` has an unsupported format;
- two rows give conflicting S/I/R results for the same sample, bacterium,
  isolate and antibiotic.

If a lab reports multiple isolates of the same species in one sample, provide
`souche_id` or `isolate_local_id` so ORCHIDEE can keep them distinct.

## Who owns what?

The hospital owns:

- extracting data from the local HDW or source systems;
- deciding which microbiology rows are diagnostic RATB rows;
- mapping local bacteria, sample types and antibiotics to ORCHIDEE values;
- mapping local units to TA/DE information;
- computing the annual hospital-night denominator.

ORCHIDEE owns:

- validating the input files;
- deriving the four internal files;
- excluding screening / non-diagnostic material at the document-occurrence
  level, with the composite identity and missing-`EVTID` fallback described
  under File 1;
- applying the RATB perimeter;
- running completion, deduplication and indicator calculation.

## Advanced note

Use the primary path above, `build_external_bundle_from_site_inputs.R`, for a
first handoff: it takes the six elementary blocks and builds `sir_wide.rds`
and the rest of the bundle for you. You do not need to produce `sir_wide.rds`
yourself.

A different script, `scripts/build_external_bundle_from_handoff_inputs.R`, is
only for the narrower case where a site has already built a valid
`sir_wide.rds` and wants ORCHIDEE to derive the other three files from it. It
is a maintainer path, not the preferred first handoff for a new hospital team.
