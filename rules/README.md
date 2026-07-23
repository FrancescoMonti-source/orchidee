# Rules

This folder is reserved for Orchidee analytical rule tables.

Use it for project-authored analytical decisions that are neither runtime
config, normalization mappings nor imported reference facts.

`couples_species_atb.csv` is the active species-antibiotic universe consumed by
the packaged Rouen adapter.

There is currently no active RATB perimeter table in this folder. The packaged
Rouen adapter combines the establishment references under `ref/rouen/`, the
CONSORES TA/DE catalogues under `ref/consores/`, and project policy encoded in
`R/ratb_hospital_days_helpers.R`. Other sites provide the corresponding
handoff mappings; the shared runtime does not depend on the Rouen references.
