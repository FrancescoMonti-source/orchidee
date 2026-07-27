---
editor_options:
  markdown:
    wrap: 72
---

# External Bundle Documentation

This folder documents how another hospital can connect local data to the
ORCHIDEE RATB core.

This file is only an index and deliberately contains no runnable onboarding
recipe. Follow the linked operator contract; current command parameters are
also available through the entry point's `Get-Help` output.

ORCHIDEE can have different local entry adapters. Rouen uses its site-specific
adapter. Rennes or another hospital should use the site-handoff inputs
described here. Both paths must converge to the same internal ORCHIDEE files
before shared RATB scope, deduplication and indicator logic run.

## Start here

For Rennes or another hospital HDW team, start with:

[site_handoff_inputs.md](site_handoff_inputs.md)

That document answers the practical first question: which files should the
site prepare, with which columns? Its template command also emits the
ORCHIDEE mapping targets and TA/DE references needed to populate them without
guessing canonical values.

For a Rouen operator starting from the automatic BACT export and the PMSI object
already produced by `redsan`, start with:

[rouen_raw_handoff.md](rouen_raw_handoff.md)

That path asks for two clinical input paths and generates the six handoff blocks.

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
