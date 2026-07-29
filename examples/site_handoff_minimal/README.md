# Installation smoke-test fixture

These six CSV files contain no patient-derived data. They are the versioned
fixture behind `build_site.ps1 -RunSmokeTest`, which answers one binary
question: can this clone, with this R and these packages, run the v3 builder,
the v2 projection, strict validation and the runtime smoke? If it can, every
later problem belongs to local extraction or mapping.

From the repository root, run:

```powershell
& .\scripts\build_site.ps1 -RunSmokeTest
```

A successful run writes paired validated bundles under
`outputs/site_smoke_test/`.

## This is not onboarding material

The fixture is deliberately one synthetic observation. It is a self-test, not a
worked example, and it teaches nothing about a real handoff: it exercises no
deduplication, no screening exclusion, no phenotype, no resistance and no
perimeter filtering, because a single in-perimeter row makes each of those a
no-op.

Do not enlarge it to imitate a real site. Extra rows would make the self-test
slower and no more conclusive, and a synthetic cohort is not what a site needs.
The commands that serve onboarding are:

- `build_site.ps1 -EmitTemplates` for the canonical headers and the
  ORCHIDEE mapping-reference kit;
- `build_site.ps1 -Diagnose` for an aggregated report of contract problems in
  the site's own six blocks.

The contract itself is documented in
[site_handoff_inputs.md](../../documentation/external_bundle/site_handoff_inputs.md).

`tests/test_site_onboarding.R` consumes these same files, so the fixture cannot
drift from the known-good build path. Do not replace them with local clinical
data; generate private working templates with `build_site.ps1 -EmitTemplates`.
