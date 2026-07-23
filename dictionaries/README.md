# Dictionaries

This directory contains versioned mappings curated by ORCHIDEE to translate
local microbiology values into canonical ORCHIDEE values.

A dictionary encodes a maintained transformation such as a regex mapping,
an exact reviewed decision or a source-to-target expansion. Imported facts
about hospital structures, units or external code systems belong in `ref/`.
Project-authored analytical inclusion rules belong in `rules/`.

`couples_species_atb.csv` is an active analytical universe consumed by the
Rouen adapter. Its current location predates this directory contract; moving it
to `rules/` is a separate, consumer-aware change. `family.csv` and
`naturepvt_regex_map.csv` currently have no active consumer; treat all three as
implementation details, never as onboarding inputs.
