# Configuration

This folder contains operational knobs for running Orchidee.

Use `pipeline.R` for runtime paths, cache controls, report display and the
publication settings. Use `rouen_raw_handoff.R` for the Rouen source window,
screening codes and versioned adapter references. Clinical input paths remain
CLI parameters.

Do not put normalization mappings or imported institutional references here:

- use `mappings/` for curated microbiology and antibiotic transformations
- use `ref/consores/` for the shared TA/DE code catalogues
- use `ref/rouen/` for the versioned unit and establishment references used
  only by the Rouen adapter
- use `R/` for implementation logic
