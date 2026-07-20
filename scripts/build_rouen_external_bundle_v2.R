#!/usr/bin/env Rscript

# Compatibility entry point. The unversioned builder defaults to contract v2.
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_dir <- if (length(file_arg) > 0L) {
  dirname(normalizePath(
    sub("^--file=", "", file_arg[[1L]]),
    winslash = "/",
    mustWork = TRUE
  ))
} else {
  file.path(getwd(), "scripts")
}
source(file.path(script_dir, "build_rouen_external_bundle.R"))
