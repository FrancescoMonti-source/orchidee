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
if (length(args) != 1L || any(args %in% c("-h", "--help"))) {
  cat(
    "Usage (PowerShell): & .\\scripts\\run_r.ps1 ",
    "scripts/emit_site_handoff_templates.R <output_directory>\n",
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

output_dir <- normalizePath(args[[1L]], winslash = "/", mustWork = FALSE)
if (file.exists(output_dir) && !dir.exists(output_dir)) {
  stop("Template output must be a directory: ", output_dir, call. = FALSE)
}

source("R/external_handoff_helpers.R")
spec <- orchidee_handoff_site_input_spec("v3")
template_paths <- file.path(output_dir, paste0(names(spec), ".csv"))
existing_paths <- template_paths[file.exists(template_paths)]
if (length(existing_paths) > 0L) {
  stop(
    "Refusing to overwrite existing site-input templates: ",
    paste(existing_paths, collapse = ", "),
    call. = FALSE
  )
}
if (!dir.exists(output_dir) && !dir.create(
  output_dir,
  recursive = TRUE,
  showWarnings = FALSE
)) {
  stop("Cannot create template output directory: ", output_dir, call. = FALSE)
}

for (block_name in names(spec)) {
  path <- file.path(output_dir, paste0(block_name, ".csv"))
  writeLines(
    paste(spec[[block_name]]$template_columns, collapse = ","),
    path,
    useBytes = TRUE
  )
  cat("Created: ", path, "\n", sep = "")
}
cat(
  "PASS: six empty site-handoff CSV templates were created. ",
  "Populate copies with protected local data before building.\n",
  sep = ""
)
