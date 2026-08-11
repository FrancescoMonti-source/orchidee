---
editor_options:
  markdown:
    wrap: 72
---

# Bundle Contracts

A bundle is a directory of four canonical files. `v2` and `v3` are not two
successive versions of a protocol, and `v2` is not an older state left in
place: they are two forms of the same bundle, produced together by the same
build. `v3` is the complete construction contract, retained. `v2` is its closed
`spares_current` projection and the only operational runtime input.

| Canonical file | v2 | v3 |
|---|---|---|
| `sir_wide.rds` | identical contract | identical contract |
| `sir_wide_meta.rds` | `contract_version = "v2"` | `contract_version = "v3"` |
| `sample_scope_reference.rds` | four portable columns | plus retained TA/DE columns |
| `denominator_bundle.rds` | `incidence_denominator_by_year` | `incidence_exposure_by_year_um_uf_ta_de_profile` |

How these files are produced is described in
[site_handoff_inputs.md](site_handoff_inputs.md) for a site handoff and in
[rouen_raw_handoff.md](rouen_raw_handoff.md) for Rouen.

# `sir_wide`

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

# `sample_scope_reference`

The reference is the bridge between local hospital unit mapping and the
shared ORCHIDEE core. A site adapter maps local unit information into this
table; ORCHIDEE applies the table to `sir_wide` rows through `SEJUF`.

## Canonical file and row grain

The external file is `sample_scope_reference.rds`. It must be an R data frame
or tibble. The row grain is one row per sample unit:

- `SEJUF`

`SEJUF` must be unique when non-missing. Missing `SEJUF` is not useful for a
scope reference and is therefore rejected.

## Required columns

- `SEJUF`
- `sample_uf_is_eligible_by_ta_de`
- `sample_uf_ta_de_status`
- `sample_uf_ta_de_reason`

Contract v2 retains exactly this four-column portable shape. Contract v3
additionally requires and retains:

```text
sample_CODE_TA
sample_CODE_DE
sample_de_domain_ref
```

These character columns may be `NA` for an unmapped UF that remains visible for
audit.

Optional audit columns, such as `sample_consores_uf_label`, may be present. The
validator warns about extra columns but does not reject them. The v2 loader
retains only the required columns at the portable ORCHIDEE boundary.
`sample_consores_uf_label` is a legacy identifier retained for compatibility;
its value is the UF label from the Rouen establishment structure.

## Expected types

- `SEJUF`: character
- `sample_uf_is_eligible_by_ta_de`: logical
- `sample_uf_ta_de_status`: character
- `sample_uf_ta_de_reason`: character
- `sample_CODE_TA`, `sample_CODE_DE`, `sample_de_domain_ref`: character

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

`uf_absent_from_consores_structure` is a legacy identifier retained for
contract compatibility. For Rouen it means that the UF is absent from the
versioned establishment structure, not from a separate CONSORES workbook.

## Interpretation

The reference does not remove rows from `sir_wide` by itself. It provides
the mapped eligibility information that ORCHIDEE uses to decide which
microbiology rows contribute to RATB numerators and proportions.

The v2 portable core consumes the final eligibility flag plus status/reason
fields. In v3, the shared runtime also uses the retained TA, DE and DE-domain
values to verify that numerator scope and denominator exposure describe the
same mapped UF before applying the closed analysis context.

For the portable workflow, a site adapter should provide the broad canonical
`sir_wide` artifact plus this scope reference. The adapter should not
pre-filter `sir_wide` to make out-of-scope rows disappear before ORCHIDEE
applies the surveillance rule.

# `denominator_bundle`

The canonical file is `denominator_bundle.rds` in both contracts. It is a list
because the incidence runtime uses a named table. v3 separates two decisions
that v2 had already combined:

1. which TA/DE care context is analysed;
2. how the corresponding hospital exposure is counted.

A local adapter can carry additional denominator audit tables, but those are
not required from another hospital. The validator ignores extra list elements
and warns about extra columns; canonical loading retains only the required
table.

## v2 required table: `incidence_denominator_by_year`

Purpose:

- runtime-relevant annual denominator consumed by incidence
- based on current PMSI TA/DE eligible hospital nights

Required columns:

- `calendar_year`
- `hospital_nights`

Type expectations:

- all columns: integer-like

Invariants:

- no duplicate `calendar_year`
- no negative `hospital_nights`
- no missing `calendar_year`
- no missing `hospital_nights`

## v3 required table: `incidence_exposure_by_year_um_uf_ta_de_profile`

Required columns, in order:

```text
calendar_year
SEJUM
SEJUF
CODE_TA
CODE_DE
de_domain_ref
denominator_profile_id
exposure_value
exposure_unit
```

The row grain is:

```text
calendar_year + SEJUM + SEJUF + CODE_TA + CODE_DE +
de_domain_ref + denominator_profile_id
```

All required columns are non-missing. Codes and labels are character values;
`calendar_year` and `exposure_value` are integer-like in the currently accepted
profile. Exposure is non-negative and the declared grain is unique.

The Rouen producer transports every positive exposure contribution from valid
unit intervals for which UM, UF, TA, DE and DE domain are mapped, including
mapped activity outside the current RATB perimeter. Zero-exposure and unmapped
intervals remain visible in its site audit. The generic contract permits an
explicit zero row because exposure is non-negative; such a row is semantically
inert.

## Closed denominator profile

Contract v3 currently accepts one profile/unit pair:

```text
denominator_profile_id = midnight_presence
exposure_unit           = patient_days
```

Its executable definition is the existing Rouen calculation, after clipping
to the requested window:

```r
as.Date(exit, tz = source_tz) - as.Date(entry, tz = source_tz)
```

A same-date stay contributes zero; crossing one local calendar boundary
contributes one. The explicit formula is authoritative where informal wording
such as "presence at midnight" could leave an endpoint ambiguous.

Possible later profiles include counting local-noon instants, exact clipped
duration or local dates with positive overlap. They do not yet have reserved
identifiers and v3 validation does not accept them.

A second profile must arrive with its exact formula, unit, adapter gate and
publication rule. Arbitrary formulas or executable configuration are outside
the contract. The aggregate v3 table does not preserve timestamps, so a future
profile must be calculated upstream from precise stay intervals; it cannot be
reconstructed from `midnight_presence`.

## Current analysis context

The only executable context is `spares_current`. It combines:

- TA codes `03` and `20`;
- the currently ratified SPARES DE-domain list;
- denominator profile `midnight_presence`;
- publication per 1,000 patient-days.

The runtime joins the exposure table to `sample_scope_reference` by `SEJUF`,
requires TA, DE and DE domain to agree, then applies this context before annual
aggregation. Every exposure `SEJUF` must therefore exist in
`sample_scope_reference` with the same TA, DE and DE domain; strict bundle
validation rejects an absent or contradictory mapping before runtime.

It derives the unchanged engine input:

```text
calendar_year + hospital_nights
```

For the current context, that derived annual table must equal the v2
denominator exactly. The broader v3 table is retained in runtime inputs for
future work; the detail must never be recovered from the annual total.

This version assumes one stable TA/DE mapping per `SEJUF` over the target
window. A site with historical structure changes needs a later dated mapping
contract; it must not encode conflicting mappings as duplicate `SEJUF` rows.

A future emergency context may select TA `10` and an elapsed-time profile, but
it cannot be enabled by changing one string: numerator scope, context-specific
deduplication and publication units must be implemented together. No stratified
indicator panel is added merely by adopting this contract.

## Local audit tables

The Rouen adapter keeps `hospital_nights_by_year_unit`, grouped by
`calendar_year + SEJUM + SEJUF`, in its PMSI audit saved as `adapter_audit.rds`.
That table is the source of the annual global aggregate but is not required by
the portable v2 bundle. The audit may also contain `hospital_days_year_summary`,
a generic annual hospital-days summary, and columns such as `n_episodes`,
`n_unit_stays` and `n_cross_year_episodes`. All of these remain useful for local
QA and are outside the portable contract.
