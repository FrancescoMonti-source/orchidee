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
strict_preferred <- "--strict-preferred" %in% args
args <- setdiff(args, "--strict-preferred")

if (length(args) > 1L || any(args %in% c("-h", "--help"))) {
  cat("Usage: Rscript scripts/smoke_external_runtime_inputs.R [bundle_dir] [--strict-preferred]\n")
  cat("Default bundle_dir: data\n")
  cat("--strict-preferred requires sample_scope_reference.rds and denominator_bundle.rds\n")
  quit(status = 0L)
}

bundle_dir <- if (length(args) == 0L) file.path("data") else args[[1]]
path_report <- validate_external_input_bundle(bundle_dir)
if (isTRUE(strict_preferred)) {
  path_report <- external_bundle_enforce_preferred_sources(path_report)
}
if (!isTRUE(path_report$ok)) {
  print_external_input_bundle_validation(path_report)
  quit(status = 1L)
}

bundle <- load_validated_external_input_bundle(bundle_dir)

runtime_inputs <- build_ratb_downstream_scope_from_canonical_inputs(
  sir_wide = bundle$sir_wide,
  sample_scope_reference = bundle$sample_scope_reference,
  denominator_bundle = bundle$denominator_bundle
)

runtime_validation <- validate_ratb_canonical_runtime_inputs(
  runtime_inputs = runtime_inputs,
  sir_wide = bundle$sir_wide
)

if (!isTRUE(runtime_validation$ok)) {
  cat("FAIL: canonical bundle could not build valid downstream ORCHIDEE inputs.\n")
  cat("Failures:\n")
  for (failure in runtime_validation$errors) {
    cat(" - ", failure, "\n", sep = "")
  }
  quit(status = 1L)
}

denominator_years <- runtime_inputs$incidence_denominator_by_year$calendar_year
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
