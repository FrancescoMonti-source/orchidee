#!/usr/bin/env Rscript

source("R/operational_v2_gate_helpers.R")

run_operational_v2_gate_test <- function() {
  test_root <- tempfile("orchidee-operational-v2-gate-")
  on.exit(unlink(test_root, recursive = TRUE), add = TRUE)

  baseline_bundle <- file.path(test_root, "baseline", "bundle")
  baseline_runtime <- file.path(test_root, "baseline", "runtime")
  candidate_bundle <- file.path(test_root, "candidate", "bundle")
  candidate_runtime <- file.path(test_root, "candidate", "runtime")
  for (path in c(
    baseline_bundle,
    candidate_bundle,
    file.path(baseline_runtime, "cache"),
    file.path(baseline_runtime, "downloads"),
    file.path(candidate_runtime, "cache"),
    file.path(candidate_runtime, "downloads")
  )) {
    dir.create(path, recursive = TRUE)
  }

  bundle_objects <- list(
    sir_wide = data.frame(PATID = "P1", result = "R"),
    sample_scope_reference = data.frame(SEJUF = "UF1", eligible = TRUE),
    denominator_bundle = list(
      incidence_denominator_by_year = data.frame(
        calendar_year = 2024L,
        hospital_nights = 100L
      )
    )
  )
  for (name in names(bundle_objects)) {
    saveRDS(bundle_objects[[name]], file.path(baseline_bundle, paste0(name, ".rds")))
    saveRDS(bundle_objects[[name]], file.path(candidate_bundle, paste0(name, ".rds")))
  }
  saveRDS(
    list(created_at = "baseline-time", contract_version = "v2"),
    file.path(baseline_bundle, "sir_wide_meta.rds")
  )
  saveRDS(
    list(created_at = "candidate-time", contract_version = "v2"),
    file.path(candidate_bundle, "sir_wide_meta.rds")
  )
  for (name in c("dedup_results", "ratb_raw_runtime_audit")) {
    value <- list(name = name, n = 1L)
    saveRDS(value, file.path(baseline_runtime, "cache", name))
    saveRDS(value, file.path(candidate_runtime, "cache", name))
  }

  workbook <- list(panel = data.frame(year = 2024L, n = 10L))
  openxlsx::write.xlsx(
    workbook,
    file.path(baseline_runtime, "downloads", "ratb_panel.xlsx")
  )
  openxlsx::write.xlsx(
    workbook,
    file.path(candidate_runtime, "downloads", "ratb_panel.xlsx")
  )

  matching_report <- compare_operational_v2_gate(
    baseline_bundle,
    baseline_runtime,
    candidate_bundle,
    candidate_runtime
  )

  saveRDS(
    list(created_at = "candidate-time", contract_version = "v3"),
    file.path(candidate_bundle, "sir_wide_meta.rds")
  )
  metadata_report <- compare_operational_v2_gate(
    baseline_bundle,
    baseline_runtime,
    candidate_bundle,
    candidate_runtime
  )
  saveRDS(
    list(created_at = "candidate-time", contract_version = "v2"),
    file.path(candidate_bundle, "sir_wide_meta.rds")
  )

  changed_denominator <- bundle_objects$denominator_bundle
  changed_denominator$incidence_denominator_by_year$hospital_nights <- 101L
  saveRDS(
    changed_denominator,
    file.path(candidate_bundle, "denominator_bundle.rds")
  )
  denominator_report <- compare_operational_v2_gate(
    baseline_bundle,
    baseline_runtime,
    candidate_bundle,
    candidate_runtime
  )
  saveRDS(
    bundle_objects$denominator_bundle,
    file.path(candidate_bundle, "denominator_bundle.rds")
  )

  changed_workbook <- list(panel = data.frame(year = 2024L, n = 11L))
  openxlsx::write.xlsx(
    changed_workbook,
    file.path(candidate_runtime, "downloads", "ratb_panel.xlsx"),
    overwrite = TRUE
  )
  workbook_report <- compare_operational_v2_gate(
    baseline_bundle,
    baseline_runtime,
    candidate_bundle,
    candidate_runtime
  )

  # Why: protects the operational v2 regression-gate invariant: volatile build
  # time is ignored, while a canonical denominator or published cell change
  # must fail closed without relying on private clinical fixtures.
  stopifnot(
    isTRUE(matching_report$ok),
    !isTRUE(metadata_report$ok),
    !metadata_report$checks$ok[
      metadata_report$checks$name == "bundle/sir_wide_meta.rds"
    ],
    !isTRUE(denominator_report$ok),
    !denominator_report$checks$ok[
      denominator_report$checks$name == "bundle/denominator_bundle.rds"
    ],
    !isTRUE(workbook_report$ok),
    !workbook_report$checks$ok[
      workbook_report$checks$name == "report_workbook_cells"
    ]
  )
}

run_operational_v2_gate_test()
cat("PASS: operational v2 regression gate\n")
