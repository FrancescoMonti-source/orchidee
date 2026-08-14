#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L || !args[[1L]] %in% c(
  "indicators",
  "full"
)) {
  stop(
    "Usage: check_render_environment.R indicators|full",
    call. = FALSE
  )
}
target <- args[[1L]]

required_packages <- c(
  "conflicted",
  "stringr",
  "tidyverse",
  "magrittr",
  "openxlsx",
  "lubridate",
  "DT",
  "purrr",
  "ggplot2",
  "knitr",
  "rmarkdown",
  "dplyr",
  "tibble"
)
available <- vapply(
  required_packages,
  requireNamespace,
  logical(1),
  quietly = TRUE
)
missing_packages <- required_packages[!available]
if (length(missing_packages) > 0L) {
  stop(
    "Missing render R packages: ",
    paste(missing_packages, collapse = ", "),
    call. = FALSE
  )
}

if (target %in% c("indicators", "full")) {
  config_environment <- new.env(parent = baseenv())
  sys.source("config/pipeline.R", envir = config_environment)
  helper_environment <- new.env(parent = baseenv())
  sys.source(
    "R/ratb_operational_input_helpers.R",
    envir = helper_environment
  )
  context <- helper_environment$resolve_ratb_operational_context(
    config_environment$orchidee_config
  )

  if (!dir.exists(context$bundle_dir)) {
    stop(
      "Operational bundle directory not found: ",
      context$bundle_dir,
      call. = FALSE
    )
  }
  required_bundle_files <- file.path(
    context$bundle_dir,
    c(
      "sir_wide.rds",
      "sir_wide_meta.rds",
      "sample_scope_reference.rds",
      "denominator_bundle.rds"
    )
  )
  missing_bundle_files <- required_bundle_files[
    !file.exists(required_bundle_files) |
      dir.exists(required_bundle_files)
  ]
  if (length(missing_bundle_files) > 0L) {
    stop(
      "Operational bundle is incomplete: ",
      paste(missing_bundle_files, collapse = ", "),
      call. = FALSE
    )
  }
  validation_environment <- new.env(parent = baseenv())
  sys.source(
    "R/external_bundle_validation_helpers.R",
    envir = validation_environment
  )
  bundle_validation <- validation_environment$validate_external_input_bundle(
    bundle_dir = context$bundle_dir,
    contract = validation_environment$orchidee_external_contract_v2()
  )
  if (!isTRUE(bundle_validation$ok)) {
    stop(
      "Operational bundle failed strict validation:\n - ",
      paste(bundle_validation$errors, collapse = "\n - "),
      call. = FALSE
    )
  }

  workspace_dir <- dirname(context$cache_dir)
  if (file.exists(workspace_dir) && !dir.exists(workspace_dir)) {
    stop(
      "Runtime workspace must be a directory: ",
      workspace_dir,
      call. = FALSE
    )
  }

  if (target == "indicators") {
    required_cache_files <- file.path(
      context$cache_dir,
      c("dedup_results", "dedup_cache_meta")
    )
    missing_cache_files <- required_cache_files[
      !file.exists(required_cache_files) |
        dir.exists(required_cache_files)
    ]
    if (length(missing_cache_files) > 0L) {
      quote_powershell_string <- function(value) {
        paste0("'", gsub("'", "''", value, fixed = TRUE), "'")
      }
      stop(
        "Canonical raw dedup cache is incomplete: ",
        paste(missing_cache_files, collapse = ", "),
        ". Run:\n& .\\scripts\\render_orchidee.ps1 -Target full ",
        "-Bundle ",
        quote_powershell_string(normalizePath(
          context$bundle_dir,
          winslash = "/",
          mustWork = TRUE
        )),
        " -Workspace ",
        quote_powershell_string(normalizePath(
          workspace_dir,
          winslash = "/",
          mustWork = FALSE
        )),
        call. = FALSE
      )
    }
  }

  cat(
    "Bundle:   ",
    normalizePath(context$bundle_dir, winslash = "/", mustWork = TRUE),
    "\n",
    sep = ""
  )
  cat(
    "Workspace: ",
    normalizePath(workspace_dir, winslash = "/", mustWork = FALSE),
    "\n",
    sep = ""
  )
}

cat(
  "PASS: required R packages and ",
  if (target %in% c("indicators", "full")) {
    "operational paths"
  } else {
    "document target"
  },
  " are available.\n",
  sep = ""
)
