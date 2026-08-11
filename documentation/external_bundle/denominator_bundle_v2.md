---
editor_options:
  markdown:
    wrap: 72
---

# Denominator Bundle v2 Contract

This document defines the annual denominator consumed by the operational v2
runtime.

The external contract is a bundle because the incidence runtime uses a named
annual nights table. A local adapter can carry additional denominator audit
tables, but those are not required from another hospital.

## Canonical file

The external file is:

- `denominator_bundle.rds`

It must be an R list containing one required table:
- `incidence_denominator_by_year`

## Required table: `incidence_denominator_by_year`

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

## Extra elements

The bundle may contain extra list elements or extra columns, but they are not
part of the v2 contract. For example, `n_episodes`, `n_unit_stays`, and
`n_cross_year_episodes` can remain useful audit columns in local Rouen outputs.

The Rouen adapter also keeps `hospital_nights_by_year_unit`, grouped by
`calendar_year + SEJUM + SEJUF`, in its PMSI audit saved as
`adapter_audit.rds`. That table is the source of the annual global aggregate but
is not required by the portable v2 bundle. External bundle v3 instead
transports profiled exposure at year + UM + UF + TA + DE grain, including
mapped activity outside today's scope; see `denominator_bundle_v3.md`. The
detail must never be recovered from the annual total.

The validator ignores extra list elements and warns about extra columns.
The canonical loader retains only the required v2 columns at the
portable ORCHIDEE boundary.

## Local audit data

The Rouen adapter audit may contain `hospital_days_year_summary`, a generic
annual hospital-days summary. It remains useful for local QA, but it is not
part of the portable ORCHIDEE v2 input contract.
