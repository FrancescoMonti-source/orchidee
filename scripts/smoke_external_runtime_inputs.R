#!/usr/bin/env Rscript

resolve_project_root <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0L) {
    script_file <- sub("^--file=", "", file_arg[[1]])
    script_dir <- dirname(normalizePath(script_file, winslash = "/", mustWork = TRUE))
    return(normalizePath(file.path(script_dir, ".."), winslash = "/", mustWork = TRUE))
  }
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

project_root <- resolve_project_root()
setwd(project_root)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(lubridate)
  library(tibble)
})

source("R/bootstrap.R")
orchidee_source_required_script("helpers.R", "helpers script")
orchidee_source_required_script(
  "external_bundle_validation_helpers.R",
  "external bundle validation helpers"
)
orchidee_source_required_script(
  "ratb_canonical_runtime_helpers.R",
  "RATB canonical runtime helpers"
)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 1L || any(args %in% c("-h", "--help"))) {
  cat("Usage: Rscript scripts/smoke_external_runtime_inputs.R [bundle_dir]\n")
  cat("Default bundle_dir: data\n")
  quit(status = 0L)
}

bundle_dir <- if (length(args) == 0L) file.path("data") else args[[1]]
bundle <- load_validated_external_input_bundle(bundle_dir)

runtime_inputs <- build_ratb_downstream_scope_from_canonical_inputs(
  sir_wide = bundle$sir_wide,
  sample_scope_reference = bundle$sample_scope_reference,
  denominator_bundle = bundle$denominator_bundle
)

required_scope_cols <- c(
  "PATID",
  "EVTID",
  "ELTID",
  "SEJUF",
  "sample_uf_is_eligible_by_ta_de",
  "sample_uf_ta_de_status",
  "sample_uf_ta_de_reason"
)

failures <- character(0)
add_failure <- function(text) {
  failures <<- c(failures, text)
}

if (!is.data.frame(runtime_inputs$sir_wide_ratb_scope)) {
  add_failure("sir_wide_ratb_scope is not a data frame.")
} else {
  missing_scope_cols <- setdiff(required_scope_cols, names(runtime_inputs$sir_wide_ratb_scope))
  if (length(missing_scope_cols) > 0L) {
    add_failure(paste0(
      "sir_wide_ratb_scope is missing columns: ",
      paste(missing_scope_cols, collapse = ", ")
    ))
  }
  if (nrow(runtime_inputs$sir_wide_ratb_scope) != nrow(bundle$sir_wide)) {
    add_failure("sir_wide_ratb_scope row count differs from sir_wide.")
  }
}

if (!is.data.frame(runtime_inputs$sir_wide_ratb_analytic_scope)) {
  add_failure("sir_wide_ratb_analytic_scope is not a data frame.")
} else {
  if (nrow(runtime_inputs$sir_wide_ratb_analytic_scope) >
      nrow(runtime_inputs$sir_wide_ratb_scope)) {
    add_failure("sir_wide_ratb_analytic_scope has more rows than sir_wide_ratb_scope.")
  }
  if (!all(runtime_inputs$sir_wide_ratb_analytic_scope$sample_uf_is_eligible_by_ta_de)) {
    add_failure("sir_wide_ratb_analytic_scope contains non-eligible sample rows.")
  }
}

if (!is.data.frame(runtime_inputs$hospital_days_year_summary_provisional)) {
  add_failure("hospital_days_year_summary_provisional is not a data frame.")
} else {
  required_runtime_denominator_cols <- c("calendar_year", "hospital_nights_provisional")
  missing_runtime_denominator_cols <- setdiff(
    required_runtime_denominator_cols,
    names(runtime_inputs$hospital_days_year_summary_provisional)
  )
  if (length(missing_runtime_denominator_cols) > 0L) {
    add_failure(paste0(
      "hospital_days_year_summary_provisional is missing columns: ",
      paste(missing_runtime_denominator_cols, collapse = ", ")
    ))
  } else if (any(runtime_inputs$hospital_days_year_summary_provisional$hospital_nights_provisional < 0)) {
    add_failure("hospital_days_year_summary_provisional contains negative nights.")
  }
}

if (!is.data.frame(runtime_inputs$hospital_days_year_summary)) {
  add_failure("hospital_days_year_summary is not a data frame.")
}

if (length(failures) > 0L) {
  cat("FAIL: canonical bundle could not build valid downstream ORCHIDEE inputs.\n")
  cat("Failures:\n")
  for (failure in failures) {
    cat(" - ", failure, "\n", sep = "")
  }
  quit(status = 1L)
}

denominator_years <- runtime_inputs$hospital_days_year_summary_provisional$calendar_year
cat("PASS: canonical bundle builds downstream ORCHIDEE inputs.\n")
cat("Bundle directory: ", normalizePath(bundle_dir, winslash = "/", mustWork = FALSE), "\n", sep = "")
cat("Contract version: ", bundle$validation_report$contract_version %||% "v1", "\n", sep = "")
cat("Microbiology rows: ", nrow(bundle$sir_wide), "\n", sep = "")
cat("Scoped microbiology rows: ", nrow(runtime_inputs$sir_wide_ratb_scope), "\n", sep = "")
cat("Analytic microbiology rows: ", nrow(runtime_inputs$sir_wide_ratb_analytic_scope), "\n", sep = "")
cat(
  "Denominator years: ",
  paste(sort(unique(denominator_years)), collapse = ", "),
  "\n",
  sep = ""
)
