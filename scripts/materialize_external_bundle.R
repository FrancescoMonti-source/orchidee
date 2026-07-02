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
orchidee_source_required_script(
  "external_bundle_validation_helpers.R",
  "external bundle validation helpers"
)

args <- commandArgs(trailingOnly = TRUE)
force <- "--force" %in% args
args <- setdiff(args, "--force")

if (length(args) > 2L || any(args %in% c("-h", "--help"))) {
  cat("Usage: Rscript scripts/materialize_external_bundle.R [source_bundle_dir] [output_bundle_dir] [--force]\n")
  cat("Default source_bundle_dir: data\n")
  cat("Default output_bundle_dir: outputs/external_bundle_v1\n")
  quit(status = 0L)
}

source_bundle_dir <- if (length(args) >= 1L) args[[1]] else file.path("data")
output_bundle_dir <- if (length(args) >= 2L) {
  args[[2]]
} else {
  file.path("outputs", "external_bundle_v1")
}

bundle <- load_validated_external_input_bundle(source_bundle_dir)
contract <- orchidee_external_contract_v1()

output_files <- file.path(
  output_bundle_dir,
  c(
    "sir_wide.rds",
    "sir_wide_meta.rds",
    contract$bundle$preferred_sample_scope_reference_file,
    contract$bundle$preferred_denominator_file
  )
)

if (!dir.exists(output_bundle_dir)) {
  dir.create(output_bundle_dir, recursive = TRUE, showWarnings = FALSE)
}

existing_output <- output_files[file.exists(output_files)]
if (length(existing_output) > 0L && !isTRUE(force)) {
  stop(
    "Output bundle files already exist: ",
    paste(existing_output, collapse = ", "),
    "\nUse --force to overwrite them.",
    call. = FALSE
  )
}

saveRDS(bundle$sir_wide, file.path(output_bundle_dir, "sir_wide.rds"))
saveRDS(bundle$sir_wide_meta, file.path(output_bundle_dir, "sir_wide_meta.rds"))
saveRDS(
  bundle$sample_scope_reference,
  file.path(output_bundle_dir, contract$bundle$preferred_sample_scope_reference_file)
)
saveRDS(
  bundle$denominator_bundle,
  file.path(output_bundle_dir, contract$bundle$preferred_denominator_file)
)

report <- validate_external_input_bundle(
  output_bundle_dir,
  contract = contract,
  strict_preferred = TRUE
)
if (!isTRUE(report$ok)) {
  cat("FAIL: materialized bundle does not validate.\n")
  if (length(report$errors) > 0L) {
    cat("Errors:\n")
    for (line in report$errors) {
      cat(" - ", line, "\n", sep = "")
    }
  }
  quit(status = 1L)
}

cat("PASS: materialized preferred external bundle.\n")
cat("Source bundle: ", normalizePath(source_bundle_dir, winslash = "/", mustWork = FALSE), "\n", sep = "")
cat("Output bundle: ", normalizePath(output_bundle_dir, winslash = "/", mustWork = FALSE), "\n", sep = "")
cat("Files:\n")
for (path in output_files) {
  cat(" - ", normalizePath(path, winslash = "/", mustWork = FALSE), "\n", sep = "")
}
