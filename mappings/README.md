# Mappings

This directory contains versioned mappings curated by ORCHIDEE to translate
local microbiology values into canonical ORCHIDEE values.

A mapping encodes a maintained transformation such as a regex rule,
an exact reviewed decision or a source-to-target expansion. Imported facts
about hospital structures, units or external code systems belong in `ref/`.
Project-authored analytical inclusion rules belong in `rules/`.

Only actively consumed mappings belong here. Superseded snapshots without a
consumer are removed from the active tree and remain recoverable from Git
history. These mappings are adapter resources, never onboarding inputs.
