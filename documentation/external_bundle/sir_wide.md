---
editor_options:
  markdown:
    wrap: 72
---

# `sir_wide` contract

## Purpose and semantics

`sir_wide.rds` is the canonical wide microbiology artifact shared by bundle
v2 and v3. `sir_wide$SEJUF` is the hospitalization unit active when the sample
was collected (`hospitalization_unit_at_sampling`).

The site adapter must establish this attribution before calling the shared
builder. For Rouen, it uses PMSI intervals after the `redsan` `C > DW` source
policy and the half-open match
`DATENT <= sample_datetime < DATSORT`, guarded by `PATID + EVTID`. It never
falls back silently to the microbiology unit.

## Required files and row grain

A bundle contains:

- `sir_wide.rds`;
- `sir_wide_meta.rds`.

The unique row grain is:

```text
PATID + EVTID + ELTID + DATEPRELEV + souche_id + naturepvt_norm + bact_norm
```

`EVTID` and `naturepvt_norm` may be missing. The other row-grain fields must
be non-missing.

## Required columns

Identifiers and scope:

```text
PATID EVTID ELTID DATEPRELEV HEUREPRELEV souche_id
naturepvt_norm bact_norm SEJUF
```

Supported antibiotic columns:

```text
levofloxacine rifampicine tetracycline vancomycine acide_fusidique
erythromycine fosfomycine_trometamol gentamicine kanamycine oxacilline
trimethoprime_sulfamethoxazole amikacine
amoxicilline_acide_clavulanique amoxicilline_ampicilline ceftazidime
ceftriaxone mecillinam nitrofurantoine ofloxacine
piperacilline_tazobactam ertapeneme fosfomycine_iv cefepime cefotaxime
ciprofloxacine imipeneme meropeneme tobramycine pristinamycine
ticarcilline daptomycine linezolide teicoplanine moxifloxacine cefoxitine
```

Phenotype columns:

```text
blse_status_row carbapenemase_status_row blse_flag carbapenemase_flag
```

`nb_resultats` is derived by the loader when absent. `SEJUM`, `TYPEANA`,
`evt_order` and `elt_order` may remain as local audit columns but are not part
of the portable contract.

## Types and allowed values

- identifiers, taxonomy, `SEJUF`, antibiotic and status columns: character;
- `DATEPRELEV`: `Date`;
- `HEUREPRELEV`: `difftime`-based time serialized by R;
- phenotype flags: non-missing logical;
- optional ordering columns: integer-like.

Antibiotic values are `S`, `R`, `ZIT` or missing. `blse_status_row` accepts
`negative`, `no_signal` and `positive`; `carbapenemase_status_row` also accepts
`unknown`.

## Required metadata

`sir_wide_meta.rds` is a list containing:

```text
artifact_version created_at sir_wide_n_rows sir_wide_n_eltid
atb_cols supported_atb_cols phenotype_status_cols phenotype_flag_cols
filtre_atb contract_version sejuf_semantics
```

The counts and column vectors must agree with `sir_wide`. For bundle v2:

```text
contract_version = "v2"
sejuf_semantics  = "hospitalization_unit_at_sampling"
```

Bundle v3 uses `contract_version = "v3"` and the same `sejuf_semantics`.

## Adapter and validation boundary

Ambiguous or unassigned documents remain visible in the site audit. Their
canonical `SEJUF` is missing, so they are excluded from the
hospitalization-based analytical perimeter. The bundle validator checks the
declared shape and semantics; it cannot reconstruct the local PMSI attribution.

Build and validate an explicit direct v2 bundle with:

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

The preferred onboarding path constructs bundle v3 and its separate v2
operational projection as described in `site_handoff_inputs.md`.
