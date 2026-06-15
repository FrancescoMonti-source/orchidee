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

source_required_script <- function(script_name, what) {
  candidates <- c(file.path("R", script_name), script_name)
  existing <- candidates[file.exists(candidates)]
  if (length(existing) == 0L) {
    stop(
      "Missing ", what, ". Expected one of: ",
      paste(candidates, collapse = ", "),
      call. = FALSE
    )
  }
  source(existing[[1]])
  invisible(normalizePath(existing[[1]], winslash = "/", mustWork = TRUE))
}

project_root <- resolve_project_root()
setwd(project_root)
source_required_script("helpers.R", "helpers script")
source_required_script("external_bundle_validation_helpers.R", "external bundle validation helpers")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 1L || any(args %in% c("-h", "--help"))) {
  cat("Usage: Rscript scripts/validate_external_bundle.R [bundle_dir]\n")
  cat("Default bundle_dir: data\n")
  quit(status = 0L)
}

bundle_dir <- if (length(args) == 0L) file.path("data") else args[[1]]
report <- validate_external_input_bundle(bundle_dir)
print_external_input_bundle_validation(report)
quit(status = if (isTRUE(report$ok)) 0L else 1L)
