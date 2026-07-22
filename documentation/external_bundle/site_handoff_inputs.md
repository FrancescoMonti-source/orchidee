---
editor_options:
  markdown:
    wrap: 72
---

# Site Handoff Inputs

This is the first document a hospital data-warehouse team should read when it
wants to connect local data to ORCHIDEE.

You do not need to reproduce the CHU extraction path. You prepare the simple
input blocks below; ORCHIDEE turns them into its internal validated bundles.

## What you need to provide

The preferred handoff always contains exactly these six blocks:

1. `microbiology_observations`
2. `bacteria_mapping`
3. `sample_type_mapping`
4. `antibiotic_mapping`
5. `unit_mapping`
6. `incidence_exposure_by_year_um_uf_ta_de_profile`

These are called **handoff blocks**: their names do not carry a bundle version.
They contain all information needed to build bundle v3, even while the current
notebook runtime still consumes bundle v2. In particular, `unit_mapping`
contains TA, DE and DE-domain information directly, and the sixth block keeps
profiled exposure instead of an already filtered annual total. There is no
seventh block in the preferred handoff.

In plain language, the complete path is:

```text
six site-owned blocks
    -> bundle v3: the complete validated copy to retain
    -> bundle v2: the reduced operational view used by ORCHIDEE today
    -> runtime: deduplication, indicators and report
```

Producing v2 from v3 does not overwrite or roll back v3. It creates a separate
operational view that intentionally carries less denominator detail. Preserve
the more detailed v3 bundle for future stratified analyses.

Accepted formats are `.rds`, `.csv`, `.tsv`, `.tab`, or `.txt`. CSV files can
use commas or semicolons. Text files must be UTF-8.

Before running ORCHIDEE commands on a fresh clone, restore the R environment
from `renv.lock` as described in the main `README.md`.

ORCHIDEE writes four internal files per materialized bundle after validation:

- `sir_wide.rds`
- `sir_wide_meta.rds`
- `sample_scope_reference.rds`
- `denominator_bundle.rds`

Do not build those four files by hand for a first handoff. Bundle version names
describe these materialized outputs, not the six site-owned blocks.

## Current operational boundary

The preferred command validates and retains a complete bundle v3, then derives
a separate strict bundle v2 for today's operational notebooks. It selects the
closed `spares_current` context: the current RATB perimeter (TA 03/20 and the
ratified DE domains) with the `midnight_presence` patient-day count. A site does
not configure this selection during onboarding. The operation leaves the
retained v3 bundle unchanged; the separate v2 bundle contains only the annual
denominator needed by today's runtime.

Both outputs declare the same semantic rule: `SEJUF` in microbiology is the
hospitalization UF active at sampling. The site adapter must establish that
attribution before handoff; v2 or v3 is a semantic claim, not only a metadata
switch. See `sir_wide.md`.

The builder also accepts an explicit direct v2 input with
`denominator_by_year`, but no contract is inferred when `--contract` is
omitted. Nothing here changes the runtime selector: v3 is retained for future
use and does not by itself publish stratified indicators. Its exact schema is
in `denominator_bundle_v3.md`.

## Block 1: microbiology_observations

This block contains one row per local S/I/R result for one sample, one bacterium
and one antibiotic.

Required columns:

| Column | Meaning |
| --- | --- |
| `PATID` | Patient identifier. |
| `ELTID` | Sample / microbiology event identifier. |
| `DATEPRELEV` | Sample date. Use `YYYY-MM-DD` or `DD/MM/YYYY` in text files. |
| `SEJUF` | Hospitalization UF active at sampling. ORCHIDEE uses it to apply the RATB TA/DE perimeter. |
| `bacteria_local` | Local bacterium label. |
| `sample_type_local` | Local sample-type label. |
| `antibiotic_local` | Local antibiotic label. |
| `sir_result` | Local S/I/R result. |
| `ratb_diagnostic_scope` | TRUE if the row belongs to diagnostic RATB microbiology, FALSE for screening / non-diagnostic rows. Exclusion is applied per document occurrence — see the note under Block 1. |

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

- `S`, `SFP` and `---S` become `S`;
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

## Block 2: bacteria_mapping

This block maps local bacterium labels to ORCHIDEE bacterium names.

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

## Block 3: sample_type_mapping

This block maps local sample-type labels to ORCHIDEE sample types.

Required columns:

| Column | Meaning |
| --- | --- |
| `sample_type_local` | Local sample-type label as it appears in `microbiology_observations`. |
| `naturepvt_norm` | ORCHIDEE sample type. |

Example:

```csv
sample_type_local,naturepvt_norm
Urine,urines
Hemoculture,hemoculture
```

`naturepvt_norm` may be left blank when a local sample type cannot be
classified reliably. Those rows remain available for global indicators, but
cannot contribute to analyses that require a known sample type. The number of
blank mappings should be reviewed during onboarding.

## Block 4: antibiotic_mapping

This block maps local antibiotic labels to ORCHIDEE antibiotic columns.

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

## Block 5: unit_mapping

This block maps hospitalization UF codes to the national TA/DE structure. It
must cover every `SEJUF` present in profiled exposure. Observed microbiology UF
codes should also be listed when a mapping exists; an unresolved UF remains
visible as audit-only rather than receiving an inferred mapping.

Required columns:

| Column | Meaning |
| --- | --- |
| `SEJUF` | Hospitalization UF. Must match the other handoff blocks. |
| `CODE_TA` | TA code for the unit. |
| `CODE_DE` | Local DE code for the unit. |
| `de_domain_ref` | National DE domain corresponding to `CODE_DE`. |

Expected grain: one row per `SEJUF`.

```csv
SEJUF,CODE_TA,CODE_DE,de_domain_ref
UF1234,03,D03,MÉDECINE
UF5678,10,D07,URGENCES
```

## Block 6: incidence_exposure_by_year_um_uf_ta_de_profile

This block contains hospital exposure independently of microbiology rows. It
preserves the fine structure needed by v3; ORCHIDEE derives the annual v2
denominator from it for the current runtime.

Required columns:

| Column | Meaning |
| --- | --- |
| `calendar_year` | Calendar year. |
| `SEJUM` | Hospitalization UM for the unit stay. |
| `SEJUF` | Hospitalization UF for the unit stay. |
| `CODE_TA` | TA code joined to `SEJUF`. |
| `CODE_DE` | DE code joined to `SEJUF`. |
| `de_domain_ref` | National DE domain joined to `CODE_DE`. |
| `denominator_profile_id` | Closed counting profile; currently `midnight_presence`. |
| `exposure_value` | Exposure at this exact grain. |
| `exposure_unit` | Unit fixed by the profile; currently `patient_days`. |

Expected grain: one row per
`calendar_year + SEJUM + SEJUF + CODE_TA + CODE_DE + de_domain_ref +
denominator_profile_id`.

All nine columns are required and non-missing. Include positive exposure from
valid mapped activity even when its TA/DE is outside the current RATB
perimeter. The projection selects `spares_current` and derives the current
annual total; do not provide a second independently computed annual table.

`unit_mapping` must cover every `SEJUF` in this block. Its TA, DE and DE-domain
values must agree exactly; strict validation rejects missing or contradictory
cross-block mappings.

## Build and validate the ORCHIDEE bundles

From the repository root, build the durable v3 bundle and its current
operational v2 projection in one command:

```powershell
Rscript `
  scripts/build_external_bundle_from_site_inputs.R `
  inputs/microbiology_observations.csv `
  inputs/bacteria_mapping.csv `
  inputs/sample_type_mapping.csv `
  inputs/antibiotic_mapping.csv `
  inputs/unit_mapping.csv `
  inputs/incidence_exposure_by_year_um_uf_ta_de_profile.csv `
  outputs/site_bundle_v3 `
  --contract=v3 `
  --operational-v2-output=outputs/site_bundle_v2 `
  --force
```

The builder validates bundle v3 first. It then applies the closed
`spares_current` context, materializes a separate strict bundle v2 and
validates that output. It never changes the notebook runtime selector.

## Use the resulting bundle

The command above creates two directories. Preserve `outputs/site_bundle_v3`
as the complete validated bundle. Point the current ORCHIDEE runtime to
`outputs/site_bundle_v2`:

```powershell
$env:ORCHIDEE_OPERATIONAL_INPUT_SOURCE = "external_bundle_v2"
$env:ORCHIDEE_EXTERNAL_BUNDLE_V2_DIR = `
  (Resolve-Path "outputs/site_bundle_v2").Path
$env:ORCHIDEE_EXTERNAL_WORKSPACE_DIR = `
  (Join-Path (Get-Location) "outputs/site_runtime")

Rscript scripts/smoke_external_runtime_inputs.R `
  $env:ORCHIDEE_EXTERNAL_BUNDLE_V2_DIR `
  --contract=v2 `
  --strict-preferred

& .\scripts\render_orchidee.ps1 -Target full
```

The smoke command checks that the four v2 files can build the shared RATB
inputs. The `full` render then calculates the operational indicators and writes
its caches and report exports under the selected private workspace.

### Explicit direct v2 path

For maintenance and comparison, the builder accepts `denominator_by_year` as
block 6 under v2. `unit_mapping` still provides `CODE_TA`, `CODE_DE` and
`de_domain_ref` directly; there is no seventh reference block. The explicit
command is:

```powershell
Rscript `
  scripts/build_external_bundle_from_site_inputs.R `
  inputs/microbiology_observations.csv `
  inputs/bacteria_mapping.csv `
  inputs/sample_type_mapping.csv `
  inputs/antibiotic_mapping.csv `
  inputs/unit_mapping.csv `
  inputs/denominator_by_year.csv `
  outputs/site_bundle_v2 `
  --contract=v2 `
  --force
```

This path does not infer hospitalization-unit attribution and cannot recover
v3 detail from an annual denominator. It is not the preferred onboarding path.

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
- computing the profiled hospital exposure independently from microbiology.

ORCHIDEE owns:

- validating the handoff blocks;
- deriving the four internal bundle files;
- excluding screening / non-diagnostic material at the document-occurrence
  level, with the composite identity and missing-`EVTID` fallback described
  under Block 1;
- applying the RATB perimeter;
- running raw deduplication and indicator calculation;
- exposing completion only as a separate opt-in diagnostic.
