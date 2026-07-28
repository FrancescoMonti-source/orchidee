# Minimal synthetic site handoff

These six CSV files contain no patient-derived data. They are a versioned,
executable example of the
[external-site handoff contract](../../documentation/external_bundle/site_handoff_inputs.md).
The onboarding test consumes these same files so the public example cannot
drift from the known-good build fixture.

From the repository root, run:

```powershell
& .\scripts\build_site.ps1 -RunExample
```

A successful run writes paired validated bundles under
`outputs/site_example/`. Do not replace these files with local clinical data;
generate private working templates with `build_site.ps1 -EmitTemplates`.
