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
source("R/bootstrap.R")
orchidee_source_required_script(
  "operational_v2_gate_helpers.R",
  "operational v2 regression gate helpers"
)

args <- commandArgs(trailingOnly = TRUE)
if (any(args %in% c("-h", "--help"))) {
  cat(
    "Usage: Rscript scripts/compare_operational_v2_gate.R ",
    "<baseline_bundle_dir> <baseline_runtime_dir> ",
    "<candidate_bundle_dir> <candidate_runtime_dir>\n",
    sep = ""
  )
  quit(status = 0L)
}
if (length(args) != 4L) {
  stop("Pass exactly four gate directories; use --help for usage.", call. = FALSE)
}

report <- compare_operational_v2_gate(
  baseline_bundle_dir = args[[1L]],
  baseline_runtime_dir = args[[2L]],
  candidate_bundle_dir = args[[3L]],
  candidate_runtime_dir = args[[4L]]
)
print_operational_v2_gate_report(report)
quit(status = if (isTRUE(report$ok)) 0L else 1L)
