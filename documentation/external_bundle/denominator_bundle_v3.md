---
editor_options:
  markdown:
    wrap: 72
---

# Denominator Bundle v3 Contract

## Purpose

External bundle v3 separates two decisions that v2 had already combined:

1. which TA/DE care context is analysed;
2. how the corresponding hospital exposure is counted.

It retains the v2 meaning of `sir_wide$SEJUF`: the hospitalization UF active
at sampling. It does not change the accepted v2 bundle shape, and it is not
yet the default operational notebook input.

## Preferred file and required table

The preferred file remains `denominator_bundle.rds`. After canonical
subsetting, its required portable table is:

```text
incidence_exposure_by_year_um_uf_ta_de_profile
```

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
inert. Extra local tables may be tolerated on input, but canonical loading
retains only the required portable table above.

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
aggregation. It derives the unchanged engine input:

Every exposure `SEJUF` must therefore exist in `sample_scope_reference` with
the same TA, DE and DE domain. Strict bundle validation rejects an absent or
contradictory mapping before runtime.

```text
calendar_year + hospital_nights
```

For the current context, that derived annual table must equal the v2
denominator exactly. The broader v3 table is retained in runtime inputs for
future work.

This version assumes one stable TA/DE mapping per `SEJUF` over the target
window. A site with historical structure changes needs a later dated mapping
contract; it must not encode conflicting mappings as duplicate `SEJUF` rows.

A future emergency context may select TA `10` and an elapsed-time profile, but
it cannot be enabled by changing one string: numerator scope, context-specific
deduplication and publication units must be implemented together.

## Sample scope v3

Under v3, `sample_scope_reference` also carries:

```text
sample_CODE_TA
sample_CODE_DE
sample_de_domain_ref
```

The columns must exist and be character; they may be missing for an unmapped UF
that remains audit-only. v2 keeps its four-column portable shape.

## Site handoff input

For `--contract=v3`, the sixth site-owned input is
`incidence_exposure_by_year_um_uf_ta_de_profile`, with the nine columns above.
The shared builder validates and stores it under the same canonical name.
Together with the other five blocks, this is the preferred unversioned handoff;
`unit_mapping` carries `CODE_TA`, `CODE_DE` and `de_domain_ref` directly.

Pass `--operational-v2-output=<directory>` to retain the validated v3 bundle
and materialize its closed `spares_current` projection as a separate strict
v2 bundle. This construction bridge does not adopt v3 in the notebook runtime.

For the explicit direct `--contract=v2` path, the sixth input is
`denominator_by_year` with `calendar_year + hospital_nights`.

## Rouen producer

The Rouen PMSI adapter builds the v3 exposure after the `redsan` `C > DW`
source policy and the maintained TA/DE joins. Its existing v2 path remains
unchanged. Every build verifies that selecting `spares_current` from the v3
table reproduces the v2 annual denominator.

Build and retain v3, then materialize the operational v2 view with:

```powershell
$bact = "data/bact22_24"
$pmsi = "data/pmsi"
$output = "outputs/rouen_current"
Rscript scripts/build_rouen_external_bundle.R `
  $bact `
  $pmsi `
  $output `
  --contract=v3 `
  --operational-v2-output="$output/bundle_v2_operational"
```

No stratified indicator panel is added merely by adopting this contract.
