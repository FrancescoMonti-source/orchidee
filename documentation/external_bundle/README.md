---
editor_options:
  markdown:
    wrap: 72
---

# External Bundle Documentation

This folder documents how another hospital can connect local data to the
ORCHIDEE RATB core.

This file is only an index. It should not duplicate the detailed contract.
When details differ, the contract files below are authoritative.

ORCHIDEE can have different local entry adapters. Rouen uses its site-specific
adapter. Rennes or another hospital should use the site-handoff inputs
described here. Both paths must converge to the same internal ORCHIDEE files
before shared RATB scope, deduplication and indicator logic run.

## Start here

For a Rouen operator starting from the automatic BACT export and the PMSI object
already produced by `redsan`, start with:

[rouen_raw_handoff.md](rouen_raw_handoff.md)

That path asks for two clinical input paths and generates the six handoff blocks.

For Rennes or another hospital HDW team, start with:

[site_handoff_inputs.md](site_handoff_inputs.md)

That document answers the practical first question: which files should the
site prepare, with which columns?

## Which document answers which question?

- `site_handoff_inputs.md`
  - What should an external hospital provide?
  - This is the human-facing onboarding contract.
- `sir_wide.md`
  - What is the exact schema and hospitalization-unit meaning of the internal
    microbiology file?
- `sample_scope_reference.md`
  - What is the exact schema of the sample-level TA/DE scope file?
- `denominator_bundle_v2.md`
  - What is the annual incidence denominator consumed by today's runtime?
- `denominator_bundle_v3.md`
  - What is the exact profiled exposure and current TA/DE context schema?
- `rouen_raw_handoff.md`
  - How are Rouen raw exports transformed into the six handoff blocks?
- `operational_v2_adoption_2026-07-19.md`
  - Why is strict v2 now the canonical operational notebook input?
- `../operational_flow.md`
  - How do the Rouen adapter, bundle v2, raw RATB runtime and future unit-grain
    denominator fit together?

## Main external-site command

```powershell
$handoff = "data/site_handoff"
& .\scripts\build_site.ps1 `
  -MicrobiologyObservations `
    (Join-Path $handoff "microbiology_observations.csv") `
  -BacteriaMapping (Join-Path $handoff "bacteria_mapping.csv") `
  -SampleTypeMapping (Join-Path $handoff "sample_type_mapping.csv") `
  -AntibioticMapping (Join-Path $handoff "antibiotic_mapping.csv") `
  -UnitMapping (Join-Path $handoff "unit_mapping.csv") `
  -IncidenceExposure `
    (Join-Path $handoff `
      "incidence_exposure_by_year_um_uf_ta_de_profile.csv") `
  -DryRun
```

For a first build, after `PASS`, run the same command without `-DryRun`. If the
preflight reports a completed existing output, follow its collision message:
choose another `-Output` or, after review, add `-Force`. The command examples
and required columns are in `site_handoff_inputs.md`.
The preferred handoff is always six complete, unversioned blocks. Contract v3
retains the v2 hospitalization-unit semantics and interprets the sixth block as
profiled exposure at year + UM + UF + TA + DE grain. The command validates and
retains that complete bundle, then materializes the closed
`spares_current` projection as a separate strict v2 bundle for the current
runtime. It does not switch the notebooks to v3 or publish stratified panels.

CLIs that support both bundle contracts require an explicit
`--contract=v2|v3`; there is no implicit third contract.

## Maintainer-only helpers

These scripts are useful for ORCHIDEE maintainers, but they are not the first
path for a new hospital team:

- `scripts/validate_external_bundle.R`
  - validates an already built ORCHIDEE input bundle.
- `scripts/smoke_external_runtime_inputs.R`
  - checks that a validated bundle can build the downstream RATB inputs.
- `scripts/build_external_bundle_from_site_inputs.R`
  - underlying positional CLI for explicit contract and output comparisons.

## Ownership rule

- Local hospital teams own extraction from their HDW and mapping from local
  labels to ORCHIDEE handoff inputs.
- ORCHIDEE owns validation, downstream scope, deduplication and indicator
  calculation.
- Local QA tables and extraction details are not part of the portable handoff.
