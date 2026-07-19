---
editor_options:
  markdown:
    wrap: 72
---

# Rouen raw handoff v1

## Purpose

This adapter gives Rouen the same explicit handoff boundary already used for
an external site. It starts from the two local raw-domain objects and stops at
the portable ORCHIDEE v2 bundle:

```text
Rouen bacteriology export ──> four microbiology blocks ─┐
                                                        ├─> six site inputs
redsan PMSI output ─────────> two PMSI blocks ──────────┘
                                                                  |
                                                                  v
                                                     canonical bundle v2
```

The shared builder still owns `sir_wide`, its metadata, the sample-scope
reference and the denominator bundle. The Rouen adapter does not implement
completion, deduplication, indicators or reporting.

## Inputs

The command takes two local RDS files.

The versioned default window is the half-open interval
`[2022-01-01, 2025-01-01)`, covering sample years 2022 through 2024. Both
microbiology and the hospital-night denominator use this same window. Change
it only through `config/rouen_raw_handoff_v1.R` and record the resulting audit.

### Bacteriology

The bacteriology object is the long Rouen export. It must contain:

```text
PATID, EVTID, ELTID, DATEPRELEV, HEUREPRELEV,
SEJUM, SEJUF, DLVL, TYPEANA, LBLANA, LBLRES,
STRRES, IDENTIFICATION, NATUREPVT, TRI
```

`PATID + EVTID + ELTID` identifies one document occurrence when `EVTID` is
available. `PATID` and `ELTID` are always required. Missing `EVTID` rows are
filled only when the same `PATID + ELTID` has one unambiguous event value; the
audit counts those fills. If all rows lack `EVTID`, the occurrence uses the
conservative `PATID + ELTID` fallback already defined by the shared handoff
contract and cannot receive a PMSI unit. A missing row alongside several event
values is rejected rather than guessed.

### PMSI

The PMSI RDS is the list returned by `redsan` and must contain `pmsi$main`.
The denominator path additionally needs the current PMSI fields used by the
CHU audit, including `PMSISTATUT`, `SEJDUR` and `GHM`.

The adapter reapplies `redsan::prefer_pmsi_src_c_over_dw()` to `pmsi$main`.
This is idempotent for a current `redsan` 0.2.0 output and safely normalizes
an older processed local artifact. ORCHIDEE does not reimplement the source
policy.

## Microbiology decisions

### Screening

Screening is decided for the complete document occurrence. If any raw row in
`PATID + EVTID + ELTID` contains one configured screening `TYPEANA`, every
SIR row from that occurrence is marked non-diagnostic. The v1 configuration
contains:

```text
BGBLSE_R.BGBLSE_R2
BGCARBA_R.BGCARBA_R2
BGABMR_R.BGABMR_R2
BGSAMR_R.BGSAMR_R2
```

These codes are visible knobs in `config/rouen_raw_handoff_v1.R`; the shared
builder, not the adapter, performs the final whole-document exclusion.

### SIR values

The adapter preserves the source value for audit and normalizes:

- `S`, `SFP`, `---S` to `S`;
- `R`, `---R` to `R`;
- `I`, `ZIT` to `ZIT`;
- `NC`, `NA`, `N/A` and blank values to missing.

An unsupported retained value fails explicitly.

`DLVL` becomes the local isolate key `souche_id`. `TRI` preserves the source
ordering used to resolve repeated explicit results: after class expansion,
the last explicit value in this order is the value retained by the shared
builder.

### Sample types

All regex rules are evaluated. Their file order never resolves a semantic
conflict:

- one canonical target, even through several matching patterns: map it;
- several canonical targets: leave it unresolved unless an exact reviewed
  decision exists;
- no target or an exact `defer` decision: keep `naturepvt_norm` missing.

The rules and human decisions are separate:

- `dictionaries/rouen_naturepvt_regex_v1.csv`;
- `dictionaries/rouen_naturepvt_exact_decisions_v1.csv`.

For example, explicit urine collected through a catheter remains `urines`,
explicit catheter material can be `pvt_profond`, and the generic label
`SONDE` remains deliberately unresolved.

### Bacteria, antibiotics and phenotypes

The adapter reuses the existing species and antibiotic dictionaries. A
bacterial label containing alternatives such as `X ou Y` remains ambiguous
instead of being forced to the first species.

An observed Enterobacterales species absent from the explicit
species/antibiotic table receives the same RATB antibiotic panel as
`escherichia_coli`. The audit lists every species added by this local extension.

Class results are expanded before the shared builder:

- `c3g_class` to cefotaxime, ceftriaxone and ceftazidime;
- `fluoroquinolones_class` to ofloxacine, levofloxacine and
  ciprofloxacine;
- `fosfomycine_class` to IV and trometamol forms.

Expanded rows precede explicit rows, so a later explicit drug result wins.
BLSE and carbapenemase signals are read from the complete raw document, not
only SIR rows, and must resolve to an exact candidate isolate key.

## Hospitalization-unit attribution

For each document occurrence, the adapter looks for PMSI records with the
same `PATID + EVTID` and an active half-open interval:

```text
DATENT <= sample_datetime < DATSORT
```

One active UM/UF pair is assigned. If several pairs are active, the
microbiology UM/UF pair may break the tie only when it identifies exactly one
candidate. Otherwise attribution remains ambiguous.

In bundle v2, canonical `SEJUF` is the attributed hospitalization UF. An
unassigned or ambiguous document gets `SEJUF = NA`; the microbiology UF is
kept in the local audit and is never used as a hidden fallback.

## TA/DE and denominator

The same C-over-DW PMSI table feeds the unit-stay denominator. The adapter
joins the current institutional unit and CONSORES references, applies the
TA/DE perimeter, and produces both:

- `hospital_nights_by_year_unit` for audit and future stratification;
- `denominator_by_year` for the portable bundle.

Every run verifies that the annual total equals the sum of its unit-year
rows. Intervals are clipped to the configured half-open window. Night bounds
use the PMSI local calendar date, so a local midnight is not shifted into the
previous UTC date.

## Run

From the repository root:

```powershell
Rscript scripts/build_rouen_external_bundle_v2.R `
  <bacteriology_raw.rds> `
  <pmsi.rds> `
  outputs/rouen_bundle_v2
```

Add `--force` only to replace existing outputs.

The output contains:

```text
site_inputs/
  microbiology_observations.rds
  bacteria_mapping.rds
  sample_type_mapping.rds
  antibiotic_mapping.rds
  unit_mapping.rds
  denominator_by_year.rds

bundle/
  sir_wide.rds
  sir_wide_meta.rds
  sample_scope_reference.rds
  denominator_bundle.rds

adapter_audit.rds
```

The command performs strict v2 bundle validation and the canonical runtime
smoke before reporting success.

## Audit and privacy

`adapter_audit.rds` explains the screening, mapping, attribution and
denominator counts. In particular, audit summaries include a `meaning`
column so their intent remains readable later. The sample-type audit retains
one row per matched regex as well as the candidate-target summary, so a
mapping conflict can be traced back to the exact rules that produced it.
Detailed audit tables retain document keys and unresolved local labels.

The microbiology summary distinguishes all screening documents, screening
documents with SIR, all raw rows in those documents and their SIR rows. It
also reports rows received, invalid or missing dates, and rows outside the
configured window.

The raw files, six site inputs, bundle and audit are local clinical artifacts.
Write them under ignored `outputs/` or another protected location. Never add
them to Git or publish them with the source repository.

## Current adoption boundary

This command produces the strict preferred bundle accepted by the operational
`external_bundle_v2` notebook mode, which is now the canonical default.
Selection remains explicit and fail-closed; the CHU-native path is an opt-in
legacy comparison/rollback mode, and its caches are not overwritten. A full
render is required after selecting a new bundle so completion, deduplication
and indicators are all derived from the same signed runtime input.
