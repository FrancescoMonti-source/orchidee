# Configuration

This folder contains operational knobs for running Orchidee.

Start with `pipeline.R` when you need to change cache recompute switches, date
windows, common paths, or report display defaults.

Do not put normalization dictionaries or imported institutional references here:

- use `dictionaries/` for curated microbiology and antibiotic mappings
- use `ref/` for imported UF/UM/CIM10/CCAM-style reference tables,
  including active CONSORES TA/DE perimeter references
- use `R/` for implementation logic
