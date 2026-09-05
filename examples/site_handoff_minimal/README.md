# Installation smoke-test fixture

These six CSV files contain no patient-derived data. They are the versioned
fixture behind `python scripts/orchidee.py site --run-smoke-test`, which answers one binary
question: can this clone, with this R and these packages, run the v3 builder,
the v2 projection, strict validation and the runtime smoke? A failure points at
the installation. A success rules the installation out as the sole explanation,
but it proves nothing about the data shapes the fixture never exercises, so it
cannot place a later problem in local extraction or mapping on its own. Use
`--diagnose` for that.

From the repository root, run:

```console
python scripts/orchidee.py site --run-smoke-test
```

A successful run writes paired validated bundles under
`outputs/site_smoke_test/`.

## This is not onboarding material

The fixture is deliberately one synthetic observation and one hospitalization
interval. It is a self-test, not a worked example, and it teaches nothing about
a real handoff: it exercises no deduplication, no screening exclusion, no
phenotype, no resistance, no transfer and no perimeter filtering, because a
single in-perimeter row makes each of those a no-op.

Do not enlarge it to imitate a real site. Extra rows would make the self-test
slower and no more conclusive. A worked example already exists for that purpose
and is kept separate on purpose: `examples/site_handoff_worked/`, four invented
stays with a transfer, a return to a unit, an out-of-perimeter unit and the
expected numbers spelled out.

The commands that serve onboarding are:

- `python scripts/orchidee.py site --emit-templates` for the canonical headers and the
  ORCHIDEE mapping-reference kit;
- `python scripts/orchidee.py site --diagnose` for an aggregated report of contract problems in
  the site's own six blocks.

The contract itself is documented in
[site_contract.md](../../documentation/site_contract.md).

`tests/test_site_onboarding.R` consumes these same files, so the fixture cannot
drift from the known-good build path. Do not replace them with local clinical
data; generate private working templates with
`python scripts/orchidee.py site --emit-templates`.
