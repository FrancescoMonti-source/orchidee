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
  "ratb_operational_input_helpers.R",
  "ratb_raw_runtime_helpers.R"
)
invisible(lapply(required_scripts, orchidee_source_required_script))

args <- commandArgs(trailingOnly = TRUE)
if (any(args %in% c("-h", "--help"))) {
  cat(
    "Usage: python scripts/orchidee.py run-r ",
    "scripts/build_ratb_raw_runtime.R [--force]\n",
    "Rebuilds the canonical raw dedup cache when its bundle or the code that ",
    "produces it changed; --force rebuilds a cache that is already current.\n",
    sep = ""
  )
  quit(status = 0L)
}
unknown_args <- setdiff(args, "--force")
if (length(unknown_args) > 0L) {
  stop(
    "Unsupported arguments: ",
    paste(unknown_args, collapse = ", "),
    "; use --help for usage.",
    call. = FALSE
  )
}
force <- "--force" %in% args

operational_runtime <- load_ratb_operational_runtime(config = orchidee_config)
cache_dir <- operational_runtime$context$cache_dir
species_regex_map_path <- ratb_raw_cache_species_regex_map_path(
  orchidee_config$paths$mappings_dir
)

# Reading the cached verdict costs one small RDS; rebuilding costs the whole
# dedup pass. Ask before working.
staleness_reasons <- local({
  cache_paths <- file.path(cache_dir, c("dedup_results", "dedup_cache_meta"))
  if (!all(file.exists(cache_paths) & !dir.exists(cache_paths))) {
    return("it does not exist yet")
  }
  cache_meta <- tryCatch(
    readRDS(file.path(cache_dir, "dedup_cache_meta")),
    error = function(e) NULL
  )
  ratb_raw_cache_staleness_reasons(
    cache_meta,
    operational_runtime$runtime_input_signature,
    species_regex_map_path
  )
})

if (length(staleness_reasons) == 0L && !force) {
  cat("SKIP: canonical raw RATB runtime cache is already current.\n")
  cat(
    "Cache: ",
    normalizePath(cache_dir, winslash = "/", mustWork = TRUE),
    "\n",
    sep = ""
  )
  quit(status = 0L)
}

cat(
  "Rebuilding the canonical raw RATB runtime cache because ",
  if (force) {
    "--force was passed"
  } else {
    paste(staleness_reasons, collapse = " and ")
  },
  ".\n",
  sep = ""
)

result <- build_ratb_raw_operational_cache(
  operational_runtime = operational_runtime,
  sir_wide_meta = operational_runtime$sir_wide_meta,
  species_regex_map_path = species_regex_map_path,
  cache_dir = cache_dir
)

print(result$audit$population_summary)
cat("PASS: built canonical raw RATB runtime cache.\n")
cat("Input source: ", operational_runtime$input_source, "\n", sep = "")
cat(
  "Cache: ",
  normalizePath(cache_dir, winslash = "/", mustWork = TRUE),
  "\n",
  sep = ""
)
