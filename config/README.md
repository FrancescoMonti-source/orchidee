# Configuration

This folder contains operational knobs for running Orchidee.

Start with `pipeline.R` when you need to change cache recompute switches, date
windows, common paths, or report display defaults.

Do not put normalization dictionaries or imported institutional references here:

- use `dictionaries/` for curated microbiology and antibiotic mappings
- use `ref/consores/` for the shared TA/DE code catalogues
- use `ref/rouen/` for the versioned unit and establishment references used
  only by the Rouen adapter
- use `R/` for implementation logic
