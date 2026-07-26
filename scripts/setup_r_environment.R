#!/usr/bin/env Rscript

resolve_project_root <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) == 0L) {
    return(normalizePath(getwd(), winslash = "/", mustWork = TRUE))
  }

  script_file <- sub("^--file=", "", file_arg[[1L]])
  script_dir <- dirname(normalizePath(
    script_file,
    winslash = "/",
    mustWork = TRUE
  ))
  normalizePath(
    file.path(script_dir, ".."),
    winslash = "/",
    mustWork = TRUE
  )
}

project_root <- resolve_project_root()
lockfile <- file.path(project_root, "renv.lock")
if (!file.exists(lockfile)) {
  stop("Missing R dependency lockfile: ", lockfile, call. = FALSE)
}

if (!requireNamespace("renv", quietly = TRUE)) {
  stop(
    "renv did not activate. Check .Rprofile and renv/activate.R.",
    call. = FALSE
  )
}
lock <- renv::lockfile_read(lockfile)
project_library <- renv::paths$library(project = project_root)
renv::restore(
  project = project_root,
  library = project_library,
  lockfile = lockfile,
  prompt = FALSE
)

required <- names(lock$Packages)
installed <- utils::installed.packages(
  lib.loc = project_library,
  noCache = TRUE
)
missing <- setdiff(required, rownames(installed))
if (length(missing) > 0L) {
  stop(
    "Packages still missing after restore: ",
    paste(missing, collapse = ", "),
    call. = FALSE
  )
}

expected <- vapply(lock$Packages, `[[`, character(1), "Version")
actual <- installed[required, "Version"]
matches <- mapply(
  function(actual_version, expected_version) {
    utils::compareVersion(actual_version, expected_version) == 0L
  },
  actual,
  expected,
  USE.NAMES = FALSE
)
mismatched <- required[!matches]
if (length(mismatched) > 0L) {
  stop(
    "Package versions still differ from renv.lock: ",
    paste(mismatched, collapse = ", "),
    call. = FALSE
  )
}

status <- renv::status(
  project = project_root,
  library = project_library,
  lockfile = lockfile,
  sources = TRUE
)
if (!isTRUE(status$synchronized)) {
  stop(
    "The restored project library is not synchronized with renv.lock.",
    call. = FALSE
  )
}

cat("PASS: all locked R packages are installed at their locked versions.\n")
