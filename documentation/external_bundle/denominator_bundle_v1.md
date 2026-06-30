---
editor_options:
  markdown:
    wrap: 72
---

# Denominator Bundle v1 Contract

This document defines the first external compatibility contract for the
annual denominator bundle.

The external contract is a bundle because the current incidence runtime
uses a named annual nights table. The current CHU workflow can carry
additional denominator audit tables, but those are not required from another
hospital.

Naming note: `provisional` is retained in v1 object and column names for
compatibility with the current runtime. It marks the current incidence
denominator object whose night-count convention remains reviewable; it is
not a second denominator running alongside the PMSI TA/DE denominator.

## Preferred file

The preferred external file is:
- `denominator_bundle.rds`

It must be an R list containing one required table:
- `hospital_days_year_summary_provisional`

## Compatibility source

For fidelity with the current repo, the validator also accepts the native
`ratb_scope_cache` artifact if it contains the required runtime table.

That compatibility path is for validation convenience only.
The preferred external contract remains `denominator_bundle.rds`.

## Required table: `hospital_days_year_summary_provisional`

Purpose:
- runtime-relevant annual denominator currently consumed by incidence
- based on current PMSI TA/DE eligible hospital nights

Required columns:
- `calendar_year`
- `n_episodes`
- `n_cross_year_episodes`
- `hospital_nights_provisional`

Type expectations:
- all columns: integer-like

Invariants:
- no duplicate `calendar_year`
- no negative counts
- no missing `calendar_year`

## Extra elements

The bundle may contain extra list elements or extra columns, but they are
not part of the v1 contract.
The validator ignores extra list elements and warns about extra columns.

## Optional CHU audit table

The current CHU cache also contains `hospital_days_year_summary`, a generic
annual hospital-days audit summary. It remains useful for local QA in the
notebook, but another hospital does not need to provide it to satisfy the
portable ORCHIDEE v1 input contract.
