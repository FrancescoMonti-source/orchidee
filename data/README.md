# Local run data

This directory is the optional local landing area for run-specific inputs such
as Rouen bacteriology and PMSI exports.

Its contents are ignored by Git. ORCHIDEE accepts those inputs as explicit CLI
paths, so they may also remain in another protected location.

The Rouen quick start uses protected-path examples. `data/bact22_24` and
`data/pmsi` remain valid alternatives when those local inputs are kept here;
neither location nor filename is required.

An external site may likewise keep its six handoff files in a dedicated ignored
subdirectory such as `data/site_handoff/`, or pass protected paths elsewhere.

Generated bundles, audits, caches and report artifacts belong under `outputs/`
or the configured external workspace, not here.
