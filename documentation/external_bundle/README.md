---
editor_options:
  markdown:
    wrap: 72
---

# External Bundle Documentation

This folder documents the ORCHIDEE bundle schemas and the two operator
procedures that produce them. It is an index and deliberately contains no
runnable onboarding recipe.

The repository [README](../../README.md) routes an operator to the right
procedure; current command parameters are available through each entry point's
`Get-Help` output.

## Which document answers which question?

- [site_handoff_inputs.md](site_handoff_inputs.md)
  - What should an external hospital provide?
  - This is the human-facing onboarding contract.
- [rouen_raw_handoff.md](rouen_raw_handoff.md)
  - How are Rouen raw exports transformed into the six handoff blocks?
- [sir_wide.md](sir_wide.md)
  - What is the exact schema and hospitalization-unit meaning of the internal
    microbiology file?
- [sample_scope_reference.md](sample_scope_reference.md)
  - What is the exact schema of the sample-level TA/DE scope file?
- [denominator_bundle_v2.md](denominator_bundle_v2.md)
  - What is the annual incidence denominator consumed by today's runtime?
- [denominator_bundle_v3.md](denominator_bundle_v3.md)
  - What is the exact profiled exposure and current TA/DE context schema?
- [operational_v2_adoption_2026-07-19.md](operational_v2_adoption_2026-07-19.md)
  - Why is strict v2 now the canonical operational notebook input?
- [../operational_flow.md](../operational_flow.md)
  - How do the adapters, retained bundle v3, operational projection v2 and RATB
    runtime fit together?

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
