---
editor_options:
  markdown:
    wrap: 72
---

# Denominator Bundle v1 Contract

This document defines the first external compatibility contract for the
annual denominator bundle.

The external contract is a bundle because the current incidence runtime
uses a provisional annual nights table, while the repo also produces a
more generic annual audit table that is useful for traceability and later
evolution.

Naming note: `provisional` is retained in v1 object and column names for
compatibility with the current runtime. It marks the current incidence
denominator object whose night-count convention remains reviewable; it is
not a second denominator running alongside the PMSI TA/DE denominator.

## Preferred file

The preferred external file is:
- `denominator_bundle.rds`

It must be an R list containing two required tables:
- `hospital_days_year_summary`
- `hospital_days_year_summary_provisional`

## Compatibility source

For fidelity with the current repo, the validator also accepts the native
`ratb_scope_cache` artifact if it contains the two required tables.

That compatibility path is for validation convenience only.
The preferred external contract remains `denominator_bundle.rds`.

## Required table: `hospital_days_year_summary`

Purpose:
- generic annual hospital-days audit summary
- future-proof companion to the runtime denominator table

Required columns:
- `calendar_year`
- `n_stays`
- `n_cross_year_stays`
- `hospital_days_exact`
- `hospital_days_floor`
- `hospital_days_ceiling`
- `hospital_days_round`

Type expectations:
- `calendar_year`, `n_stays`, `n_cross_year_stays`: integer-like
- all `hospital_days_*` columns: numeric

Invariants:
- no duplicate `calendar_year`
- no negative counts
- no missing `calendar_year`

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

## Why both tables are kept in v1

- `hospital_days_year_summary_provisional` is what the current incidence
  layer actually consumes
- `hospital_days_year_summary` keeps an audit-friendly annual summary
  alongside it

This avoids redefining the contract later when the project evolves.
