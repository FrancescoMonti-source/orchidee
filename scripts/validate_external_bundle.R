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
source("R/bootstrap.R")
orchidee_source_required_script("helpers.R", "helpers script")
orchidee_source_required_script("external_bundle_validation_helpers.R", "external bundle validation helpers")

args <- commandArgs(trailingOnly = TRUE)
strict_preferred <- "--strict-preferred" %in% args
contract_args <- grep("^--contract=", args, value = TRUE)
if (length(contract_args) > 1L) {
  stop("Pass at most one --contract option.", call. = FALSE)
}
contract_version <- if (length(contract_args) == 0L) {
  "v1"
} else {
  sub("^--contract=", "", contract_args[[1L]])
}
if (!contract_version %in% c("v1", "v2", "v3")) {
  stop("--contract must be v1, v2 or v3.", call. = FALSE)
}
args <- setdiff(args, c("--strict-preferred", contract_args))

if (length(args) > 1L || any(args %in% c("-h", "--help"))) {
  cat(
    "Usage: Rscript scripts/validate_external_bundle.R ",
    "[bundle_dir] [--contract=v1|v2|v3] [--strict-preferred]\n",
    sep = ""
  )
  cat("Default bundle_dir: data\n")
  cat("--strict-preferred requires sample_scope_reference.rds and denominator_bundle.rds\n")
  quit(status = 0L)
}

bundle_dir <- if (length(args) == 0L) file.path("data") else args[[1]]
contract <- switch(
  contract_version,
  v1 = orchidee_external_contract_v1(),
  v2 = orchidee_external_contract_v2(),
  v3 = orchidee_external_contract_v3()
)
report <- validate_external_input_bundle(
  bundle_dir = bundle_dir,
  contract = contract,
  strict_preferred = strict_preferred
)
print_external_input_bundle_validation(report)
quit(status = if (isTRUE(report$ok)) 0L else 1L)
