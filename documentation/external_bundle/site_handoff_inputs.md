---
editor_options:
  markdown:
    wrap: 72
---

# Site Handoff Inputs

This is the sole maintained human-facing operator procedure for Rennes or
another hospital that does not already have a packaged ORCHIDEE site adapter.
The repository README and external-bundle index only orient readers here;
`Get-Help .\scripts\build_site.ps1 -Full` lists the current command parameters.

Rouen operators should not prepare the six blocks below. Start with
[rouen_raw_handoff.md](rouen_raw_handoff.md) and provide only the BACT and PMSI
input paths; the versioned Rouen adapter generates the blocks.

You do not need to reproduce the Rouen adapter. You prepare the simple input
blocks below; ORCHIDEE turns them into its internal validated bundles.

## What you need to provide

The preferred handoff always contains exactly these six blocks:

1. `microbiology_observations`
2. `bacteria_mapping`
3. `sample_type_mapping`
4. `antibiotic_mapping`
5. `unit_mapping`
6. `incidence_exposure_by_year_um_uf_ta_de_profile`

These are called **handoff blocks**: their names do not carry a bundle version.
They contain all information needed to build bundle v3, even while the current
notebook runtime still consumes bundle v2. In particular, `unit_mapping`
contains TA, DE and DE-domain information directly, and the sixth block keeps
profiled exposure instead of an already filtered annual total. There is no
seventh block in the preferred handoff.

In plain language, the complete path is:

```text
six site-owned blocks
    -> bundle v3: the complete validated copy to retain
    -> bundle v2: the reduced operational view used by ORCHIDEE today
    -> runtime: deduplication, indicators and report
```

Producing v2 from v3 does not overwrite or roll back v3. It creates a separate
operational view that intentionally carries less denominator detail. Preserve
the more detailed v3 bundle for future stratified analyses.

Accepted formats are `.rds`, `.csv`, `.tsv`, `.tab`, or `.txt`. CSV files can
use commas or semicolons. Text files must be UTF-8.

Before running ORCHIDEE commands on a fresh clone, restore the R environment
from `renv.lock`:

```powershell
& .\scripts\setup.ps1
```

Before working on protected local data, check this installation:

```powershell
& .\scripts\build_site.ps1 -RunSmokeTest
```

This uses only files under `examples/site_handoff_minimal/`, runs the same v3
build, v2 projection, strict validation and runtime smoke as a real handoff,
and writes under `outputs/site_smoke_test/` by default. A failure points at the
installation. A `PASS` rules the installation out as the sole explanation, but on
one synthetic observation it exercises no deduplication, screening exclusion,
phenotype, resistance or perimeter filtering, so it cannot by itself place a
later problem in local extraction or mapping. On a deliberate repeat, follow the
collision message and use
`-Force`, or select another `-Output`.

The fixture is a single synthetic observation. It exists to prove the
installation, not to teach the contract: it shows you nothing about your own
data, and `-Diagnose` below is the command that does. Read the block
descriptions in this document rather than the fixture.

If the six files do not exist yet, generate empty CSV templates with the
canonical headers and the ORCHIDEE mapping-reference kit:

```powershell
$handoff = "data/site_handoff"
& .\scripts\build_site.ps1 -EmitTemplates $handoff
```

The command refuses to overwrite any existing generated file. Populate the six
top-level templates with the protected local data; do not commit them.
`$handoff` may instead point to a protected directory outside the checkout.

## Mapping targets supplied by ORCHIDEE

ORCHIDEE cannot decide what a local Rennes or hospital label means. The site
owns that interpretation and fills the mapping blocks. ORCHIDEE owns the target
surface: it must show the exact canonical values and national references the
site can map to.

`-EmitTemplates` therefore creates:

```text
mapping_reference/
  README.txt
  supported_atb_norm.csv
  recognized_bact_norm.csv
  current_indicator_naturepvt_norm.csv
  reference_code_ta.csv
  reference_code_de.csv
  allowed_denominator_profiles.csv
```

These files have four deliberately different roles:

| Files | Meaning |
| --- | --- |
| `supported_atb_norm.csv`, `allowed_denominator_profiles.csv` | Closed values accepted by the current builder. |
| `recognized_bact_norm.csv` | Canonical bacterium targets recognized by the bundled taxonomy, with their order, family and genus when known. It is not a bundle-wide allow-list. |
| `current_indicator_naturepvt_norm.csv` | Sample-type targets selected by the current report. It is not a bundle-wide allow-list. |
| `reference_code_ta.csv`, `reference_code_de.csv` | Complete national references. `included_in_spares_current` marks whether that TA or DE-domain component is selected today; actual unit eligibility requires both. `FALSE` means outside today's analysis, not invalid v3 activity. |

The reference kit is not a seventh handoff block and is not returned to
ORCHIDEE. For example, ORCHIDEE supplies `cefotaxime` as a supported target;
the site decides whether local labels such as `CTX` or `CEFOTAX` mean
`cefotaxime`.

ORCHIDEE writes four internal files per materialized bundle after validation:

- `sir_wide.rds`
- `sir_wide_meta.rds`
- `sample_scope_reference.rds`
- `denominator_bundle.rds`

Do not build those four files by hand for a first handoff. Bundle version names
describe these materialized outputs, not the six site-owned blocks.

## Current operational boundary

The preferred command validates and retains a complete bundle v3, then derives
a separate strict bundle v2 for today's operational notebooks. It selects the
closed `spares_current` context: the current RATB perimeter (TA 03/20 and the
ratified DE domains) with the `midnight_presence` patient-day count. A site does
not configure this selection during onboarding. The operation leaves the
retained v3 bundle unchanged; the separate v2 bundle contains only the annual
denominator needed by today's runtime.

Both outputs declare the same semantic rule: `SEJUF` in microbiology is the
hospitalization UF active at sampling. The site adapter must establish that
attribution before handoff; v2 or v3 is a semantic claim, not only a metadata
switch. See `sir_wide.md`.

The builder also accepts an explicit direct v2 input with
`denominator_by_year`, but no contract is inferred when `--contract` is
omitted. Nothing here changes the runtime contract: v3 is retained for future
use and does not by itself publish stratified indicators. Its exact schema is
in `denominator_bundle_v3.md`.

## Block 1: microbiology_observations

This block contains one row per local S/I/R result for one sample, one bacterium
and one antibiotic.

Required columns:

| Column | Meaning |
| --- | --- |
| `PATID` | Patient identifier. |
| `ELTID` | Sample / microbiology event identifier. |
| `DATEPRELEV` | Sample date. Use `YYYY-MM-DD` or `DD/MM/YYYY` in text files; `YYYY/MM/DD` also works, and a trailing time of day is ignored provided it is a real time — the time of day belongs in `HEUREPRELEV`. Each value is read on its own, so the column may mix these forms, but anything else after the date is refused rather than guessed at. In a typed `.rds` the column may be a `Date` or a day number, and it must fall on a whole day: R hides a fractional day behind an ordinary-looking date while keeping it a distinct value in the row grain. |
| `SEJUF` | Hospitalization UF active at sampling. ORCHIDEE uses it to apply the RATB TA/DE perimeter. |
| `bacteria_local` | Local bacterium label. |
| `sample_type_local` | Local sample-type label. |
| `antibiotic_local` | Local antibiotic label. |
| `sir_result` | Local S/I/R result. |
| `ratb_diagnostic_scope` | TRUE if the row belongs to diagnostic RATB microbiology, FALSE for screening / non-diagnostic rows. Exclusion is applied per document occurrence — see the note under Block 1. |

Exactly one diagnostic-scope column is required. Its accepted names are
`ratb_diagnostic_scope`, `diagnostic_scope` and `is_diagnostic`; do not provide
more than one of them in the same file. Use `ratb_diagnostic_scope` for new
handoffs.

Optional columns:

| Column | Meaning |
| --- | --- |
| `EVTID` | Hospital stay / encounter identifier, if available. When present on every row of a `PATID + ELTID` group, it keeps reused sample identifiers separate during screening exclusion. |
| `HEUREPRELEV` | Sample time, `HH:MM` or `HH:MM:SS`. |
| `souche_id` or `isolate_local_id` | Local isolate identifier when the lab distinguishes several isolates for the same sample. |
| `blse_status_row` or `blse_status` | Optional BLSE status: `positive`, `negative`, `unknown`, `no_signal`. |
| `carbapenemase_status_row` or `carbapenemase_status` | Optional carbapenemase status: `positive`, `negative`, `unknown`, `no_signal`. |

Accepted `sir_result` values:

- `S`, `SFP` and `---S` become `S`;
- `R` and `---R` become `R`;
- `I` and `ZIT` become `ZIT`;
- `NC`, `NA`, `N/A` or blank values become missing.

Minimal example:

```csv
PATID,EVTID,ELTID,DATEPRELEV,HEUREPRELEV,SEJUF,bacteria_local,sample_type_local,antibiotic_local,sir_result,ratb_diagnostic_scope
P001,S001,MIC001,2024-03-12,09:15,UF1234,Escherichia coli,Urine,Amoxicilline acide clavulanique,R,TRUE
```

Important: `ratb_diagnostic_scope` is not the TA/DE hospital perimeter. It is
the local microbiology decision that keeps screening and other non-diagnostic
material out before ORCHIDEE applies the hospital-unit perimeter.

Exclusion is applied at the document occurrence level: if any row of a given
`PATID + EVTID + ELTID` occurrence is marked `FALSE` (screening /
non-diagnostic), ORCHIDEE drops that whole occurrence across all bacteria,
antibiotics and phenotypes. If any row within the same `PATID + ELTID` group
lacks `EVTID`, ORCHIDEE conservatively uses `PATID + ELTID` for that group.
It never propagates screening through `ELTID` alone across patients. This
matches the RATB rule that a screening sample is excluded in full while
preserving distinct occurrences when a source identifier is reused. You
therefore do not need to remove screening rows yourself: flag them and keep the
flag consistent within the document occurrence.

If several rows map to the same ORCHIDEE row key and antibiotic, ORCHIDEE keeps
the last non-missing S/I/R value in input order. If the laboratory reports
several isolates of the same species in one sample, provide `souche_id` or
`isolate_local_id` so those isolates remain separate.

## Block 2: bacteria_mapping

This block maps local bacterium labels to ORCHIDEE bacterium names.

Required columns:

| Column | Meaning |
| --- | --- |
| `bacteria_local` | Local bacterium label as it appears in `microbiology_observations`. |
| `bact_norm` | Canonical ORCHIDEE bacterium token. |

Example:

```csv
bacteria_local,bact_norm
Escherichia coli,escherichia_coli
Klebsiella pneumoniae,klebsiella_pneumoniae
```

Use `mapping_reference/recognized_bact_norm.csv` for the exact tokens
recognized by the bundled taxonomy. The taxonomy columns explain which tokens
also contribute to pooled indicators such as Enterobacterales. A different
`bact_norm` may remain valid portable microbiology, but it does not
automatically create a published indicator.

## Block 3: sample_type_mapping

This block maps local sample-type labels to ORCHIDEE sample types.

Required columns:

| Column | Meaning |
| --- | --- |
| `sample_type_local` | Local sample-type label as it appears in `microbiology_observations`. |
| `naturepvt_norm` | ORCHIDEE sample type. |

Example:

```csv
sample_type_local,naturepvt_norm
Urine,urines
Hemoculture,hemoculture
```

`naturepvt_norm` may be left blank when a local sample type cannot be
classified reliably. Those rows remain available for global indicators, but
cannot contribute to analyses that require a known sample type. The number of
blank mappings should be reviewed during onboarding.
`mapping_reference/current_indicator_naturepvt_norm.csv` lists the sample types
selected by the current report; it is not a bundle-wide allow-list.

## Block 4: antibiotic_mapping

This block maps local antibiotic labels to ORCHIDEE antibiotic columns.

Required columns:

| Column | Meaning |
| --- | --- |
| `antibiotic_local` | Local antibiotic label as it appears in `microbiology_observations`. |
| `atb_norm` | ORCHIDEE antibiotic column. |

Example:

```csv
antibiotic_local,atb_norm
Amoxicilline acide clavulanique,amoxicilline_acide_clavulanique
Cefotaxime,cefotaxime
```

Only include antibiotic result rows that map to supported ORCHIDEE antibiotic
columns. The builder fails if `atb_norm` is not one of those columns.
The exact closed list is generated in
`mapping_reference/supported_atb_norm.csv`.

## Block 5: unit_mapping

This block maps hospitalization UF codes to the national TA/DE structure. It
must cover every `SEJUF` present in profiled exposure. Observed microbiology UF
codes should also be listed when a mapping exists; an unresolved UF remains
visible as audit-only rather than receiving an inferred mapping.

Required columns:

| Column | Meaning |
| --- | --- |
| `SEJUF` | Hospitalization UF. Must match the other handoff blocks. |
| `CODE_TA` | TA code for the unit. |
| `CODE_DE` | National DE code for the unit. |
| `de_domain_ref` | National DE domain corresponding to `CODE_DE`. |

Expected grain: one row per `SEJUF`.

```csv
SEJUF,CODE_TA,CODE_DE,de_domain_ref
UF1234,03,102,MÉDECINE
UF5678,10,211,URGENCES
```

Use `mapping_reference/reference_code_ta.csv` and
`mapping_reference/reference_code_de.csv` to translate the site's local
structure. They contain the complete national references and identify the
current `spares_current` perimeter without treating other mapped activity as
invalid.

## Block 6: incidence_exposure_by_year_um_uf_ta_de_profile

This block contains hospital exposure independently of microbiology rows. It
preserves the fine structure needed by v3; ORCHIDEE derives the annual v2
denominator from it for the current runtime.

Required columns:

| Column | Meaning |
| --- | --- |
| `calendar_year` | Calendar year. |
| `SEJUM` | Hospitalization UM for the unit stay. |
| `SEJUF` | Hospitalization UF for the unit stay. |
| `CODE_TA` | TA code joined to `SEJUF`. |
| `CODE_DE` | DE code joined to `SEJUF`. |
| `de_domain_ref` | National DE domain joined to `CODE_DE`. |
| `denominator_profile_id` | Closed counting profile; currently `midnight_presence`. |
| `exposure_value` | Exposure at this exact grain. |
| `exposure_unit` | Unit fixed by the profile; currently `patient_days`. |

Expected grain: one row per
`calendar_year + SEJUM + SEJUF + CODE_TA + CODE_DE + de_domain_ref +
denominator_profile_id`.

All nine columns are required and non-missing. Include positive exposure from
valid mapped activity even when its TA/DE is outside the current RATB
perimeter. The projection selects `spares_current` and derives the current
annual total; do not provide a second independently computed annual table.

`unit_mapping` must cover every `SEJUF` in this block. Its TA, DE and DE-domain
values must agree exactly; strict validation rejects missing or contradictory
cross-block mappings.
The accepted profile/unit pair is generated in
`mapping_reference/allowed_denominator_profiles.csv`.

## Build and validate the ORCHIDEE bundles

From the repository root, first run the safe preflight:

```powershell
$handoff = "data/site_handoff"
& .\scripts\build_site.ps1 `
  -MicrobiologyObservations `
    (Join-Path $handoff "microbiology_observations.csv") `
  -BacteriaMapping (Join-Path $handoff "bacteria_mapping.csv") `
  -SampleTypeMapping (Join-Path $handoff "sample_type_mapping.csv") `
  -AntibioticMapping (Join-Path $handoff "antibiotic_mapping.csv") `
  -UnitMapping (Join-Path $handoff "unit_mapping.csv") `
  -IncidenceExposure `
    (Join-Path $handoff `
      "incidence_exposure_by_year_um_uf_ta_de_profile.csv") `
  -DryRun
```

This reads only delimited-file headers; RDS inputs must be deserialized to
inspect their columns. It checks that the six files exist and carry the
expected columns. It does not look at their content and does not create an
output directory.

Once `-DryRun` passes, replace `-DryRun` with `-Diagnose` in the same command:

```powershell
$handoff = "data/site_handoff"
& .\scripts\build_site.ps1 `
  -MicrobiologyObservations `
    (Join-Path $handoff "microbiology_observations.csv") `
  -BacteriaMapping (Join-Path $handoff "bacteria_mapping.csv") `
  -SampleTypeMapping (Join-Path $handoff "sample_type_mapping.csv") `
  -AntibioticMapping (Join-Path $handoff "antibiotic_mapping.csv") `
  -UnitMapping (Join-Path $handoff "unit_mapping.csv") `
  -IncidenceExposure `
    (Join-Path $handoff `
      "incidence_exposure_by_year_um_uf_ta_de_profile.csv") `
  -Diagnose
```

`-Diagnose` reads the six blocks once and reports **every** contract problem in
a single pass, classified as:

| Level | Meaning |
| --- | --- |
| `BLOCKING` | The build cannot complete until this is corrected. |
| `WARNING` | The build completes, but rows lose analytic value; review it. |
| `INFO` | Counts that describe the handoff, including perimeter coverage. |

This matters because the builder itself stops at the first problem and lists at
most ten offending values. Correcting a real handoff through build failures
alone takes one rebuild per problem class; `-Diagnose` collapses that into one
report you can work through.

Each mapping dimension is reported per local label with both `n_rows` and
`n_document_occurrences`, so you can tell a label worth mapping from a
negligible one. Values beyond the tenth are truncated in the summary but kept
in full in `finding_values.csv`, so one pass is enough however many labels are
involved. Both tables carry a `finding_id`, and the summary prints it as `[#n]`
beside each finding: some checks are reported once per field, so the id is what
ties a list of values to the finding it belongs to.

The report is written to a `diagnostics` subdirectory of `-Output` when you
pass one, otherwise to `outputs\site_diagnostics`; `-Report` overrides both.
Beyond the six input paths it records for provenance, it contains aggregate
counts and your own local vocabulary only; it never writes patient identifiers.

Exit status 2 means the diagnostics could not produce a verdict — a technical
problem, not a statement about your blocks. It covers failures before R starts
too, such as an unusable `-Report` directory, so status 1 always means blocking
findings and nothing else.

The new report is composed in full before the previous one is replaced, so a run
that fails while composing it leaves the earlier report in place. Replacing the
files is not a single atomic step, so a complete report is marked by
`report_manifest.txt`, which lists the files it is made of. A report directory
without it was interrupted, whatever the files beside it look like, and the run
exits 2 naming what it could not write.

The order matters and is enforced: the previous manifest is deleted first and its
removal is verified, because a manifest that survived would certify the files
replaced after it. If it cannot be removed, nothing else is touched and the
previous report stays whole. The new manifest is renamed into place only after
every other artifact is published.

One run publishes into a report directory at a time. A run takes
`.orchidee_diagnostics.lock` there and releases it when it is done; a second run
started against the same directory meanwhile is refused with exit status 2
rather than interleaving its files with the first one's. If a run is killed the
lock stays behind: the refusal message names it, and it can be deleted once you
have established that no diagnostics run is still running.

Establishing that is your part of the contract, not a formality. Deleting the
lock while its run is alive is not supported: the run that owns it may then
remove the lock a later run has taken, and two runs would publish into the
directory at once. The lock is a directory, and no portable operation removes
one only while it is still ours, so this is a boundary rather than something the
command defends against.

`-Diagnose` answers one question: do the six blocks satisfy the handoff
contract? It does not predict which indicators the report will publish.

Exit status is 1 while any `BLOCKING` finding remains, so the command can gate a
local script. A `PASS` is a promise: it means the build this procedure runs
next completes on these blocks — bundle v3, its `spares_current` projection to
operational v2, and strict validation of both. Every check mirrors a rule the
builder, the v3 contract or that projection actually enforces, and the test
suite asserts the invariant by running that same build on each passing fixture.

When it reports `PASS`, rerun exactly the same command with neither `-DryRun`
nor `-Diagnose` for a first build. If the preflight reports a
completed existing output, choose another `-Output` or, after review, add
`-Force` as instructed by its warning.

Add `-Output "D:\ORCHIDEE\site_current"` when generated bundles must live in a
protected external workspace. Use
`Get-Help .\scripts\build_site.ps1 -Full` to see all supported knobs.

The wrapper validates bundle v3 first. It then applies the closed
`spares_current` context, materializes a separate strict bundle v2 and
validates and smoke-tests that output. It does not adopt v3 as a notebook
runtime input. `-Force` is only for an intentional repeat build over a complete
output created by this same workflow; it is not part of the first-build command.

## Use the resulting bundle

The default output layout is:

```text
outputs/site_current/
  bundle_v3/
    build_manifest.txt
  bundle_v2_operational/
    build_manifest.txt
  runtime/                    # created only by a later render
```

Each bundle directory also contains the four RDS files. The manifest is written
last, after strict validation, canonical runtime smoke and publication; without
it, treat that directory as incomplete. The two manifests must carry the same
`build_id`; a mismatch means the pair did not come from one completed run. The
manifest is builder metadata, not a fifth file required by the v2 or v3 runtime
contract.

The build already runs the v2 runtime smoke. Preserve `bundle_v3` as the
complete validated bundle. To calculate indicators from the v2 bundle produced
by this same build:

```powershell
$bundle = (Resolve-Path `
  "outputs/site_current/bundle_v2_operational").Path
$workspace = Join-Path (Get-Location) "outputs/site_current/runtime"

& .\scripts\render_orchidee.ps1 -Target full `
  -Bundle $bundle `
  -Workspace $workspace
```

The wrapper prints this command with the exact resolved paths at the end of the
build. The `full` render calculates the operational indicators and writes its
caches and report exports under the selected private workspace.

### Explicit direct v2 path

For maintenance and comparison, the builder accepts `denominator_by_year` as
block 6 under v2. `unit_mapping` still provides `CODE_TA`, `CODE_DE` and
`de_domain_ref` directly; there is no seventh reference block. The explicit
command is:

```powershell
& .\scripts\run_r.ps1 scripts/build_external_bundle_from_site_inputs.R `
  inputs/microbiology_observations.csv `
  inputs/bacteria_mapping.csv `
  inputs/sample_type_mapping.csv `
  inputs/antibiotic_mapping.csv `
  inputs/unit_mapping.csv `
  inputs/denominator_by_year.csv `
  outputs/site_bundle_v2 `
  --contract=v2
```

This path does not infer hospitalization-unit attribution and cannot recover
v3 detail from an annual denominator. It is a maintainer-only comparison path,
not the preferred onboarding path.

## If validation fails

Run `-Diagnose` first: it lists every problem at once, while the messages below
appear one at a time. The most common failures are:

- a required column is missing;
- a local bacterium, sample type or antibiotic has no mapping;
- an antibiotic maps to a value absent from
  `mapping_reference/supported_atb_norm.csv`;
- all microbiology rows are marked outside `ratb_diagnostic_scope`;
- `SEJUF` is duplicated in `unit_mapping`;
- `DATEPRELEV` or `HEUREPRELEV` has an unsupported format;
- two rows give conflicting S/I/R results for the same sample, bacterium,
  isolate and antibiotic.

If a lab reports multiple isolates of the same species in one sample, provide
`souche_id` or `isolate_local_id` so ORCHIDEE can keep them distinct.

## Who owns what?

The hospital owns:

- extracting data from the local HDW or source systems;
- deciding which microbiology rows are diagnostic RATB rows;
- mapping local bacteria, sample types and antibiotics to ORCHIDEE values;
- mapping local units to TA/DE information;
- computing the profiled hospital exposure independently from microbiology.

ORCHIDEE owns:

- validating the handoff blocks;
- deriving the four internal bundle files;
- excluding screening / non-diagnostic material at the document-occurrence
  level, with the composite identity and missing-`EVTID` fallback described
  under Block 1;
- applying the RATB perimeter;
- running raw deduplication and indicator calculation.
