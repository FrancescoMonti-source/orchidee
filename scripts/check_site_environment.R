#!/usr/bin/env Rscript

resolve_project_root <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0L) {
    script_file <- sub("^--file=", "", file_arg[[1L]])
    script_dir <- dirname(normalizePath(
      script_file,
      winslash = "/",
      mustWork = TRUE
    ))
    return(normalizePath(
      file.path(script_dir, ".."),
      winslash = "/",
      mustWork = TRUE
    ))
  }
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

project_root <- resolve_project_root()
setwd(project_root)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 6L || any(args %in% c("-h", "--help"))) {
  cat(
    "Usage:\n",
    "  python scripts/orchidee.py run-r scripts/check_site_environment.R ",
    "<microbiology_observations> <bacteria_mapping> ",
    "<sample_type_mapping> <antibiotic_mapping> ",
    "<unit_mapping> ",
    "<incidence_exposure_by_year_um_uf_ta_de_profile>\n",
    sep = ""
  )
  quit(
    status = if (length(args) == 0L || any(args %in% c("-h", "--help"))) {
      0L
    } else {
      1L
    }
  )
}

required_packages <- c(
  "dplyr",
  "stringr"
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
    "Missing site-builder R packages: ",
    paste(missing_packages, collapse = ", "),
    call. = FALSE
  )
}

source("R/external_handoff_helpers.R")

block_names <- names(orchidee_handoff_site_input_spec())
names(args) <- block_names
input_schemas <- lapply(args, orchidee_handoff_read_table_schema)
orchidee_handoff_validate_site_input_columns(input_schemas)

if (any(tolower(tools::file_ext(args)) == "rds")) {
  cat(
    "Note: RDS inputs were deserialized to inspect their columns; ",
    "delimited inputs were read as headers only.\n",
    sep = ""
  )
}
cat(
  "PASS: required R packages and the six site-input column contracts ",
  "are available.\n",
  sep = ""
)
