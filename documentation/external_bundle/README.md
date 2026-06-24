---
editor_options:
  markdown:
    wrap: 72
---

# External Input Bundle for Orchidee

This folder documents a dormant external input contract for Orchidee.

The goal is to make the shared downstream core reusable by another
hospital without changing the current runtime path.

For now, this layer is strictly additive:
- it does not change the current notebooks
- it does not change the current build path
- it does not make the notebooks branch between internal and external
  modes

## Future operating model

Another hospital should not be asked to reproduce the full Orchidee raw
extraction pipeline.

Instead, the site should provide a canonical bundle made of:
- `sir_wide.rds`
- `sir_wide_meta.rds`
- `denominator_bundle.rds`

Once those artifacts match the contract, the shared Orchidee downstream
core can be plugged later without changing the artifact contract again.

## Normalization philosophy

Orchidee owns the canonical target schema.

Each hospital owns its own raw-to-canonical mapping layer upstream.
That means:
- local raw values do not need to match Orchidee raw inputs
- local raw values do need to be mapped into Orchidee's canonical
  normalized schema
- hospitals should not edit Orchidee core dictionaries just to fit local
  raw exports

The intended split is:
- local adapter layer at each hospital
- shared Orchidee core downstream of canonical artifacts

## Documents in this folder

- `sir_wide_v1.md`
  - exact v1 compatibility contract for the microbiology artifact
- `denominator_bundle_v1.md`
  - v1 contract for the annual denominator bundle

## Contract ownership map

The v1 contract has two surfaces:

- human-facing contract:
  - `documentation/external_bundle/sir_wide_v1.md`
  - `documentation/external_bundle/denominator_bundle_v1.md`
- executable contract and validation rules:
  - `R/external_bundle_validation_helpers.R`
  - specifically `orchidee_external_contract_v1()`

When the v1 schema changes, update both surfaces in the same change.

The current internal producer, `R/build_sir_wide_artifact.R`, is a useful
reference implementation for the CHU artifact, but it is not the external
adapter contract. A future hospital adapter should produce artifacts that
match the external contract; it should not be required to reproduce the CHU
raw extraction path.

## Validator

Use the standalone validator:

```powershell
& 'C:\Program Files\R\R-4.5.2\bin\Rscript.exe' scripts/validate_external_bundle.R data
```

Default behavior:
- validates `sir_wide.rds`
- validates `sir_wide_meta.rds`
- validates `denominator_bundle.rds` if present
- otherwise accepts the current native `ratb_scope_cache` as a
  compatibility source for the denominator bundle

The validator is additive only. It is not called by the main notebooks.
