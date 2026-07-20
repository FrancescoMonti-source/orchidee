#!/usr/bin/env Rscript

resolve_project_root <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0L) {
    script_file <- sub("^--file=", "", file_arg[[1L]])
    script_dir <- dirname(normalizePath(script_file, winslash = "/", mustWork = TRUE))
    return(normalizePath(file.path(script_dir, ".."), winslash = "/", mustWork = TRUE))
  }
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

project_root <- resolve_project_root()
setwd(project_root)

suppressPackageStartupMessages({
  library(dplyr)
  library(lubridate)
  library(purrr)
  library(tibble)
})

source(file.path("R", "setup.R"))
required_scripts <- c(
  "helpers.R",
  "normalisation_bact.R",
  "normalisation_atb.R",
  "spares_shared_primitives.R",
  "phenotype_flag_helpers.R",
  "spares_dedup.R",
  "ratb_indicator_helpers.R",
  "ratb_plausibility_qc_helpers.R",
  "ratb_canonical_runtime_helpers.R",
  "external_bundle_validation_helpers.R",
  "ratb_hospital_days_helpers.R",
  "chu_ratb_scope_adapter.R",
  "chu_ratb_scope_cache_helpers.R",
  "ratb_operational_input_helpers.R",
  "ratb_raw_runtime_helpers.R"
)
invisible(lapply(required_scripts, orchidee_source_required_script))

operational_runtime <- load_ratb_operational_runtime(
  config = orchidee_config,
  chu_cache_policy = "load_or_build"
)
result <- build_ratb_raw_operational_cache(
  operational_runtime = operational_runtime,
  sir_wide_meta = operational_runtime$sir_wide_meta,
  species_regex_map_path = file.path(
    orchidee_config$paths$dictionaries_dir,
    "species_regex_map.csv"
  ),
  cache_dir = operational_runtime$context$cache_dir
)

print(result$audit$population_summary)
cat("PASS: built canonical raw RATB runtime cache.\n")
cat("Input source: ", operational_runtime$input_source, "\n", sep = "")
cat(
  "Cache: ",
  normalizePath(operational_runtime$context$cache_dir, winslash = "/", mustWork = TRUE),
  "\n",
  sep = ""
)
