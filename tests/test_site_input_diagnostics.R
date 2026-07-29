#!/usr/bin/env Rscript

# Why: -Diagnose exists because the builder is fail-fast and truncates its
# value lists. These tests protect the two properties that make it useful to a
# site: one pass reports every blocking class at once, and a problem that only
# makes rows audit-only never masquerades as a blocking error.

source("R/external_bundle_validation_helpers.R")
source("R/ratb_hospital_days_helpers.R")
source("R/external_handoff_helpers.R")

run_diagnostics <- function(input_dir, report_dir) {
  rscript <- file.path(
    R.home("bin"),
    if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
  )
  input_paths <- file.path(
    input_dir,
    paste0(names(orchidee_handoff_site_input_spec("v3")), ".csv")
  )
  output <- suppressWarnings(system2(
    rscript,
    c(
      "--no-save",
      "--no-restore",
      shQuote("scripts/diagnose_site_inputs.R"),
      shQuote(input_paths),
      shQuote(report_dir)
    ),
    stdout = TRUE,
    stderr = TRUE
  ))
  status <- attr(output, "status")
  if (is.null(status)) status <- 0L
  findings_path <- file.path(report_dir, "findings.csv")
  findings <- if (file.exists(findings_path)) {
    utils::read.csv(
      findings_path,
      stringsAsFactors = FALSE,
      fileEncoding = "UTF-8"
    )
  } else {
    NULL
  }
  list(
    status = status,
    output = output,
    findings = findings,
    report_dir = report_dir
  )
}

severity_of <- function(result, block, check) {
  if (is.null(result$findings)) return(NA_character_)
  matched <- result$findings$severity[
    result$findings$block == block & result$findings$check == check
  ]
  if (length(matched) == 0L) NA_character_ else matched[[1L]]
}

write_blocks <- function(dir, blocks) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  for (block_name in names(blocks)) {
    utils::write.csv(
      blocks[[block_name]],
      file.path(dir, paste0(block_name, ".csv")),
      row.names = FALSE,
      na = "",
      fileEncoding = "UTF-8"
    )
  }
  dir
}

test_root <- file.path(tempdir(), "orchidee_site_diagnostics")
unlink(test_root, recursive = TRUE, force = TRUE)
dir.create(test_root, recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(test_root, recursive = TRUE, force = TRUE), add = TRUE)

## Clean handoff -------------------------------------------------------------

clean_blocks <- list(
  microbiology_observations = data.frame(
    PATID = c("PDIAG001", "PDIAG002"),
    EVTID = c("SDIAG001", "SDIAG002"),
    ELTID = c("MDIAG001", "MDIAG002"),
    DATEPRELEV = c("2024-03-12", "2024-04-02"),
    HEUREPRELEV = c("09:15", "10:00"),
    SEJUF = c("UFDIAG1", "UFDIAG1"),
    souche_id = c("I1", "I1"),
    bacteria_local = c("E. coli", "E. coli"),
    sample_type_local = c("Urine", "Urine"),
    antibiotic_local = c("Cefotaxime", "Cefotaxime"),
    sir_result = c("S", "R"),
    ratb_diagnostic_scope = c(TRUE, TRUE),
    blse_status_row = c("no_signal", "no_signal"),
    carbapenemase_status_row = c("no_signal", "no_signal"),
    stringsAsFactors = FALSE
  ),
  bacteria_mapping = data.frame(
    bacteria_local = "E. coli",
    bact_norm = "escherichia_coli",
    stringsAsFactors = FALSE
  ),
  sample_type_mapping = data.frame(
    sample_type_local = "Urine",
    naturepvt_norm = "urines",
    stringsAsFactors = FALSE
  ),
  antibiotic_mapping = data.frame(
    antibiotic_local = "Cefotaxime",
    atb_norm = "cefotaxime",
    stringsAsFactors = FALSE
  ),
  unit_mapping = data.frame(
    SEJUF = "UFDIAG1",
    CODE_TA = "03",
    CODE_DE = "102",
    de_domain_ref = "MÉDECINE",
    stringsAsFactors = FALSE
  ),
  incidence_exposure_by_year_um_uf_ta_de_profile = data.frame(
    calendar_year = 2024L,
    SEJUM = "UMDIAG1",
    SEJUF = "UFDIAG1",
    CODE_TA = "03",
    CODE_DE = "102",
    de_domain_ref = "MÉDECINE",
    denominator_profile_id = "midnight_presence",
    exposure_value = 1000L,
    exposure_unit = "patient_days",
    stringsAsFactors = FALSE
  )
)

clean_result <- run_diagnostics(
  write_blocks(file.path(test_root, "clean inputs"), clean_blocks),
  file.path(test_root, "clean report")
)

## Broken handoff ------------------------------------------------------------
##
## One fixture carries every blocking class plus the audit-only distinctions,
## because the point of the command is that a single pass reports them all.

broken_blocks <- clean_blocks
broken_blocks$microbiology_observations <- data.frame(
  PATID = c(
    "PDIAG001", "PDIAG001", "PDIAG002", "PDIAG003", "PDIAG004", "PDIAG005"
  ),
  EVTID = c(
    "SDIAG001", "SDIAG001", "SDIAG002", "SDIAG003", "SDIAG004", NA_character_
  ),
  ELTID = c(
    "MDIAG001", "MDIAG001", "MDIAG002", "MDIAG003", "MDIAG004", "MDIAG005"
  ),
  DATEPRELEV = c(
    "2024-03-12", "2024-03-12", "2024-04-02", "2024-05-20", "2023-06-11",
    "2024-07-01"
  ),
  HEUREPRELEV = c("09:15", "09:15", "10:00", "11:30", "08:00", "08:00"),
  SEJUF = c(
    "UFDIAG1", "UFDIAG1", "UFDIAG1", "UFAUDIT", "UFDIAG1", "UFDIAG2"
  ),
  souche_id = rep("I1", 6L),
  bacteria_local = c(
    "E. coli", "E. coli", "E. coli", "Staphylococcus aureus", "E. coli",
    "E. coli"
  ),
  sample_type_local = c(
    "Urine", "Urine", "Urine", "Pus", "Urine", "Urine"
  ),
  antibiotic_local = c(
    "Cefotaxime", "Amoxicilline", "Cefotaxime", "Oxacilline", "Cefotaxime",
    "Cefotaxime"
  ),
  sir_result = c("R", "S", "S", "R", "S", "ZZZ"),
  ratb_diagnostic_scope = c(TRUE, FALSE, TRUE, TRUE, TRUE, TRUE),
  blse_status_row = rep("no_signal", 6L),
  carbapenemase_status_row = rep("no_signal", 6L),
  stringsAsFactors = FALSE
)
broken_blocks$sample_type_mapping <- data.frame(
  sample_type_local = c("Urine", "Pus"),
  naturepvt_norm = c("urines", NA_character_),
  stringsAsFactors = FALSE
)
broken_blocks$antibiotic_mapping <- data.frame(
  antibiotic_local = c("Cefotaxime", "Amoxicilline", "Oxacilline"),
  atb_norm = c("cefotaxime", "amoxicilline", "not_a_real_atb"),
  stringsAsFactors = FALSE
)
broken_blocks$unit_mapping <- data.frame(
  SEJUF = c("UFDIAG1", "UFDIAG1", "UFDIAG2"),
  CODE_TA = c("03", "03", "10"),
  CODE_DE = c("102", "102", "211"),
  de_domain_ref = c("MÉDECINE", "MÉDECINE", "URGENCES"),
  stringsAsFactors = FALSE
)
broken_blocks$incidence_exposure_by_year_um_uf_ta_de_profile <- data.frame(
  calendar_year = c(2024L, 2024L, 2024L, 2024L),
  SEJUM = c("UMDIAG1", "UMDIAG1", "UMDIAG2", "UMDIAG3"),
  SEJUF = c("UFDIAG1", "UFDIAG1", "UFDIAG2", "UFORPHAN"),
  CODE_TA = c("03", "03", "20", "03"),
  CODE_DE = c("102", "102", "211", "102"),
  de_domain_ref = c(
    "MÉDECINE", "MÉDECINE", "URGENCES", "MÉDECINE"
  ),
  denominator_profile_id = rep("midnight_presence", 4L),
  exposure_value = c(1000L, 500L, 300L, 200L),
  exposure_unit = rep("patient_days", 4L),
  stringsAsFactors = FALSE
)

broken_result <- run_diagnostics(
  write_blocks(file.path(test_root, "broken inputs"), broken_blocks),
  file.path(test_root, "broken report")
)

## Missing required column ---------------------------------------------------

missing_column_blocks <- clean_blocks
missing_column_blocks$unit_mapping <-
  missing_column_blocks$unit_mapping[, c("SEJUF", "CODE_TA"), drop = FALSE]
missing_column_result <- run_diagnostics(
  write_blocks(file.path(test_root, "missing column inputs"), missing_column_blocks),
  file.path(test_root, "missing column report")
)

## Assertions ----------------------------------------------------------------

expected_blocking <- list(
  c("bacteria_mapping", "unmapped_local_labels"),
  c("antibiotic_mapping", "unsupported_atb_norm"),
  c("unit_mapping", "duplicate_sejuf"),
  c("unit_mapping", "exposure_uf_not_covered"),
  c("incidence_exposure_by_year_um_uf_ta_de_profile", "duplicate_grain_rows"),
  c(
    "incidence_exposure_by_year_um_uf_ta_de_profile",
    "ta_de_disagrees_with_unit_mapping"
  ),
  c("microbiology_observations", "unsupported_sir_values")
)
broken_blocking_severities <- vapply(
  expected_blocking,
  function(entry) severity_of(broken_result, entry[[1L]], entry[[2L]]),
  character(1)
)

patient_identifiers <- unique(broken_blocks$microbiology_observations$PATID)
report_text <- paste(
  readLines(
    file.path(broken_result$report_dir, "site_input_diagnostics.txt"),
    warn = FALSE,
    encoding = "UTF-8"
  ),
  collapse = "\n"
)
label_coverage <- utils::read.csv(
  file.path(broken_result$report_dir, "label_coverage.csv"),
  stringsAsFactors = FALSE,
  fileEncoding = "UTF-8"
)
unit_coverage <- utils::read.csv(
  file.path(broken_result$report_dir, "unit_coverage.csv"),
  stringsAsFactors = FALSE,
  fileEncoding = "UTF-8"
)
year_coverage <- utils::read.csv(
  file.path(broken_result$report_dir, "year_coverage.csv"),
  stringsAsFactors = FALSE,
  fileEncoding = "UTF-8"
)

unmapped_bacteria <- label_coverage[
  label_coverage$dimension == "bacteria" &
    label_coverage$status == "unmapped", ,
  drop = FALSE
]

stopifnot(
  # A contract-satisfying handoff passes with no blocking finding.
  identical(clean_result$status, 0L),
  any(grepl("PASS:", clean_result$output, fixed = TRUE)),
  !any(clean_result$findings$severity == "BLOCKING"),

  # A broken handoff fails, and one pass reports every blocking class.
  identical(broken_result$status, 1L),
  all(broken_blocking_severities == "BLOCKING"),
  sum(broken_result$findings$severity == "BLOCKING") ==
    length(expected_blocking),

  # Audit-only problems stay warnings and never block the build.
  identical(
    severity_of(broken_result, "unit_mapping", "microbiology_uf_not_covered"),
    "WARNING"
  ),
  identical(
    severity_of(broken_result, "sample_type_mapping", "blank_canonical_value"),
    "WARNING"
  ),
  identical(
    severity_of(
      broken_result,
      "microbiology_observations",
      "screening_propagation"
    ),
    "WARNING"
  ),
  identical(
    severity_of(
      broken_result,
      "incidence_exposure_by_year_um_uf_ta_de_profile",
      "year_not_covered"
    ),
    "WARNING"
  ),

  # Severities are restricted to the three documented levels.
  all(
    broken_result$findings$severity %in% c("BLOCKING", "WARNING", "INFO")
  ),

  # Coverage counts are reported per label in rows and document occurrences.
  identical(unmapped_bacteria$local_label, "Staphylococcus aureus"),
  identical(unmapped_bacteria$n_rows, 1L),
  identical(unmapped_bacteria$n_document_occurrences, 1L),

  # Screening exclusion is counted on whole document occurrences: the pair of
  # rows sharing MDIAG001 leaves the build although only one is flagged.
  any(grepl(
    "removes 2 rows (1 occurrences)",
    broken_result$output,
    fixed = TRUE
  )),

  # The perimeter distinction is visible per unit rather than only in totals.
  identical(sort(unit_coverage$SEJUF), c("UFDIAG1", "UFDIAG2")),
  identical(
    unit_coverage$included_in_spares_current[
      unit_coverage$SEJUF == "UFDIAG2"
    ],
    FALSE
  ),

  # The projection total is reported next to the profiled total, so a site can
  # see how much of its declared activity the current perimeter retains. Here
  # UFDIAG2 is mapped outside the perimeter and UFORPHAN has no unit row, so
  # only the 1500 patient-days of UFDIAG1 survive the spares_current context.
  identical(as.numeric(year_coverage$exposure_total), 2000),
  identical(as.numeric(year_coverage$exposure_in_spares_current), 1500),

  # A missing required column blocks without crashing the run.
  identical(missing_column_result$status, 1L),
  identical(
    severity_of(
      missing_column_result,
      "unit_mapping",
      "missing_required_columns"
    ),
    "BLOCKING"
  ),

  # The report carries aggregate counts and local vocabulary, never patients.
  !any(vapply(
    patient_identifiers,
    function(identifier) grepl(identifier, report_text, fixed = TRUE),
    logical(1)
  ))
)

cat("PASS: site input diagnostics\n")
