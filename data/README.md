# Local run data

This directory is the optional local landing area for run-specific inputs such
as Rouen bacteriology and PMSI exports.

Its contents are ignored by Git. ORCHIDEE accepts those inputs as explicit CLI
paths, so they may also remain in another protected location.

The Rouen quick start currently points to `data/bact22_24` and `data/pmsi`.
Those names are examples, not a required directory layout.

Generated bundles, audits, caches and report artifacts belong under `outputs/`
or the configured external workspace, not here.
