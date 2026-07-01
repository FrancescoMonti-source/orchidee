---
editor_options:
  markdown:
    wrap: 72
---

# Denominator Bundle v1 Contract

This document defines the first external compatibility contract for the
annual denominator bundle.

The external contract is a bundle because the incidence runtime uses a named
annual nights table. The current CHU workflow can carry additional
denominator audit tables, but those are not required from another hospital.

## Preferred file

The preferred external file is:
- `denominator_bundle.rds`

It must be an R list containing one required table:
- `incidence_denominator_by_year`

## Compatibility source

For fidelity with the current repo, the validator also accepts the native
`ratb_scope_cache` artifact if it contains the required runtime table.
It also accepts the older current-runtime table
`hospital_days_year_summary_provisional` and maps it to the canonical
external table.

That compatibility path is for validation convenience only.
The preferred external contract remains `denominator_bundle.rds`.

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

## Extra elements

The bundle may contain extra list elements or extra columns, but they are not
part of the v1 contract. For example, `n_episodes` and
`n_cross_year_episodes` can remain useful audit columns in local CHU outputs.

The validator ignores extra list elements and warns about extra columns.
Loader and materialization helpers retain only the required v1 columns at the
portable ORCHIDEE boundary.

## Compatibility aliases

Current CHU artifacts may still expose:

- table: `hospital_days_year_summary_provisional`
- night column: `hospital_nights_provisional`

The loader accepts that shape and converts it to
`incidence_denominator_by_year$hospital_nights` before data crosses the
portable ORCHIDEE boundary. The shared runtime helper expects the canonical
table after this conversion. Current CHU/internal QA code may still carry the
legacy table as an optional alias, but it is outside the shared runtime
validation surface.

## Optional CHU audit table

The current CHU cache also contains `hospital_days_year_summary`, a generic
annual hospital-days audit summary. It remains useful for local QA in the
notebook, but another hospital does not need to provide it to satisfy the
portable ORCHIDEE v1 input contract.
