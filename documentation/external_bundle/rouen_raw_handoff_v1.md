---
editor_options:
  markdown:
    wrap: 72
---

# Rouen raw handoff v1

## Purpose

This adapter gives Rouen the same explicit handoff boundary used for an
external site. It starts from the two local raw-domain objects and stops at the
six handoff blocks plus the selected portable ORCHIDEE bundle:

```text
Rouen bacteriology export ──> four microbiology blocks ─┐
                                                        ├─> six handoff blocks
redsan PMSI output ─────────> two PMSI blocks ──────────┘
                                                                  |
                                                                  v
                                                  canonical bundle v2 or v3
```

The shared builder still owns `sir_wide`, its metadata, the sample-scope
reference and the denominator bundle. The Rouen adapter does not implement
completion, deduplication, indicators or reporting.

## Inputs

The command takes two local RDS files as positional inputs. Building the two
PMSI handoff blocks also requires the local unit references and the private
CONSORES structure workbook described below.

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

### Local unit and CONSORES references

The Rouen producer reads the versioned `ref_uf.txt`, `ref_um.txt`,
`ref_uf2um.txt` and TA/DE code lists. The institutional structure workbook is
not public and must not be added to `ref/`. It is read by default from:

```text
data/consores_structure_intranet_maj_2025.xlsx
```

Set `ORCHIDEE_CONSORES_STRUCTURE_PATH` when it is stored elsewhere. The
workbook is a prerequisite of the local Rouen producer and of the legacy
`chu_native` recompute only. It is not required by the operational
`external_bundle_v2` runtime, nor by another site's builder when that site
already supplies a complete `unit_mapping` block.

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
joins the current institutional unit and CONSORES references and produces:

- `denominator_by_year` for the portable v2 bundle;
- `incidence_exposure_by_year_um_uf_ta_de_profile` for the portable v3
  bundle;
- `hospital_nights_by_year_um_uf_ta_de` as the local audit source of the
  current-perimeter table;
- `hospital_nights_by_year_unit` unchanged for the existing v2 QA display.

Every run verifies that the annual total equals the sum of its unit-year
rows. Intervals are clipped to the configured half-open window. Night bounds
use the PMSI local calendar date, so a local midnight is not shifted into the
previous UTC date.

The v3 exposure table carries mapped valid activity even when TA/DE is outside
the current perimeter. It adds `de_domain_ref`, `denominator_profile_id`,
`exposure_value` and `exposure_unit` to the year + UM + UF + TA + DE
dimensions. The adapter verifies that selecting the current
`spares_current_v1` context reproduces the v2 annual denominator exactly.

## Run

From the repository root:

```powershell
$output = "outputs/rouen_current"
Rscript scripts/build_rouen_external_bundle.R `
  <bacteriology_raw.rds> `
  <pmsi.rds> `
  $output `
  --contract=v3 `
  --operational-v2-output="$output/bundle_v2_operational"
```

Add `--force` only to replace existing outputs.

This is the preferred Rouen path. It retains the complete v3 construction and
materializes the separate v2 input accepted by the current notebooks. A direct
`--contract=v2` build remains available as an explicit compatibility path; it
replaces the sixth block with `denominator_by_year.rds` and writes its bundle
under `bundle/`.

The output contains:

```text
site_inputs/
  microbiology_observations.rds
  bacteria_mapping.rds
  sample_type_mapping.rds
  antibiotic_mapping.rds
  unit_mapping.rds
  incidence_exposure_by_year_um_uf_ta_de_profile.rds

bundle_v3/
  sir_wide.rds
  sir_wide_meta.rds
  sample_scope_reference.rds
  denominator_bundle.rds

bundle_v2_operational/
  sir_wide.rds
  sir_wide_meta.rds
  sample_scope_reference.rds
  denominator_bundle.rds

adapter_audit.rds
build_manifest.txt
```

The command performs strict validation and the canonical runtime smoke for both
the retained v3 bundle and its closed `spares_current_v1` v2 projection before
reporting success. `build_manifest.txt` records input and output paths, hashes,
repository HEAD, projection profile and validation status without requiring R.

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

The raw files, six handoff blocks, bundle and audit are local clinical artifacts.
Write them under ignored `outputs/` or another protected location. Never add
them to Git or publish them with the source repository.

## Current adoption boundary

The preferred command retains v3 and explicitly projects the strict bundle
accepted by the operational `external_bundle_v2` notebook mode. The operational
selector does not adopt v3 implicitly. Selection remains explicit and
fail-closed; the CHU-native path is an opt-in legacy comparison/rollback mode,
and its caches are not overwritten. A full render is required after an explicit
future adoption so raw
deduplication and indicators are derived from the same signed runtime input.
Completion remains a separate opt-in diagnostic.
