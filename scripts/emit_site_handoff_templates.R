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

source("R/external_bundle_validation_helpers.R")
source("R/ratb_hospital_days_helpers.R")
source("R/external_handoff_helpers.R")
spec <- orchidee_handoff_site_input_spec()
template_paths <- file.path(output_dir, paste0(names(spec), ".csv"))
reference_tables <- orchidee_handoff_mapping_reference_tables(project_root)
reference_dir <- file.path(output_dir, "mapping_reference")
reference_paths <- file.path(
  reference_dir,
  paste0(names(reference_tables), ".csv")
)
reference_readme_path <- file.path(reference_dir, "README.txt")
generated_paths <- c(
  template_paths,
  reference_paths,
  reference_readme_path
)
existing_paths <- generated_paths[file.exists(generated_paths)]
if (length(existing_paths) > 0L) {
  stop(
    "Refusing to overwrite existing site-input templates or mapping ",
    "references: ",
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
if (!dir.exists(reference_dir) && !dir.create(
  reference_dir,
  recursive = TRUE,
  showWarnings = FALSE
)) {
  stop(
    "Cannot create mapping-reference directory: ",
    reference_dir,
    call. = FALSE
  )
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
for (reference_name in names(reference_tables)) {
  path <- file.path(reference_dir, paste0(reference_name, ".csv"))
  utils::write.csv(
    reference_tables[[reference_name]],
    path,
    row.names = FALSE,
    na = "",
    fileEncoding = "UTF-8"
  )
  cat("Created: ", path, "\n", sep = "")
}
writeLines(
  c(
    "ORCHIDEE site-handoff mapping references",
    "",
    "The hospital still owns every local-to-ORCHIDEE mapping decision.",
    "These files only expose the ORCHIDEE target and reference surface.",
    "",
    "Closed values:",
    "- supported_atb_norm.csv",
    "- allowed_denominator_profiles.csv",
    "",
    "Recognized bacterial taxonomy, not a bundle-wide allow-list:",
    "- recognized_bact_norm.csv",
    "",
    "Current indicator targets, not a bundle-wide allow-list:",
    "- current_indicator_naturepvt_norm.csv",
    "",
    "Complete national references with a current-perimeter flag:",
    "- reference_code_ta.csv",
    "- reference_code_de.csv",
    "",
    "Values outside the current TA/DE perimeter remain valid v3 activity."
  ),
  reference_readme_path,
  useBytes = TRUE
)
cat("Created: ", reference_readme_path, "\n", sep = "")
cat(
  "PASS: six empty site-handoff CSV templates and their mapping-reference ",
  "kit were created. ",
  "Populate copies with protected local data before building.\n",
  sep = ""
)
