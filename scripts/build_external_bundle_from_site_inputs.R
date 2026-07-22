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

normalize_output_path_for_comparison <- function(path) {
  normalized <- normalizePath(path, winslash = "/", mustWork = FALSE)
  if (identical(.Platform$OS.type, "windows")) tolower(normalized) else normalized
}

project_root <- resolve_project_root()
setwd(project_root)

args <- commandArgs(trailingOnly = TRUE)
force <- "--force" %in% args
contract_args <- grep("^--contract=", args, value = TRUE)
if (length(contract_args) > 1L) {
  stop("Pass at most one --contract option.", call. = FALSE)
}
contract_version <- if (length(contract_args) == 0L) {
  NA_character_
} else {
  sub("^--contract=", "", contract_args[[1L]])
}
if (!is.na(contract_version) && !contract_version %in% c("v2", "v3")) {
  stop("--contract must be v2 or v3.", call. = FALSE)
}
operational_v2_args <- grep(
  "^--operational-v2-output=",
  args,
  value = TRUE
)
if (length(operational_v2_args) > 1L) {
  stop("Pass at most one --operational-v2-output option.", call. = FALSE)
}
operational_v2_output <- if (length(operational_v2_args) == 0L) {
  NA_character_
} else {
  sub("^--operational-v2-output=", "", operational_v2_args[[1L]])
}
if (!is.na(operational_v2_output) && !nzchar(operational_v2_output)) {
  stop("--operational-v2-output requires a directory.", call. = FALSE)
}
if (!is.na(operational_v2_output) && !identical(contract_version, "v3")) {
  stop("--operational-v2-output is only available with --contract=v3.", call. = FALSE)
}
args <- setdiff(args, c("--force", contract_args, operational_v2_args))

if (length(args) == 8L) {
  stop(
    "The handoff contains exactly six site-owned blocks; do not pass a ",
    "seventh de_reference block.",
    call. = FALSE
  )
}
if (length(args) != 7L || "--help" %in% args || "-h" %in% args) {
  cat(
    "Usage:\n",
    "  Rscript scripts/build_external_bundle_from_site_inputs.R \\\n",
    "    <microbiology_observations.{rds,csv,tsv,tab,txt}> \\\n",
    "    <bacteria_mapping.{rds,csv,tsv,tab,txt}> \\\n",
    "    <sample_type_mapping.{rds,csv,tsv,tab,txt}> \\\n",
    "    <antibiotic_mapping.{rds,csv,tsv,tab,txt}> \\\n",
    "    <unit_mapping.{rds,csv,tsv,tab,txt}> \\\n",
    "    <denominator.{rds,csv,tsv,tab,txt}> \\\n",
    "    <output_bundle_dir> \\\n",
    "    --contract=v2|v3 [--operational-v2-output=<dir>] [--force]\n\n",
    "Inputs:\n",
    "  microbiology_observations: long local S/I/R observations with the\n",
    "    columns documented in site_handoff_inputs.md.\n",
    "  bacteria_mapping: bacteria_local + bact_norm.\n",
    "  sample_type_mapping: sample_type_local + naturepvt_norm.\n",
    "  antibiotic_mapping: antibiotic_local + atb_norm.\n",
    "  unit_mapping: one row per SEJUF with CODE_TA, CODE_DE and\n",
    "    de_domain_ref directly in this block.\n",
    "  denominator: v2 uses calendar_year + hospital_nights; v3 uses\n",
    "    year + UM + UF + TA + DE + domain + profile + exposure + unit.\n",
    "  --contract=v2: declare SEJUF as the hospitalization unit at sampling.\n",
    "  --contract=v3: keep v2 SEJUF semantics and require profiled exposure;\n",
    "    unit_mapping must contain CODE_TA, CODE_DE and de_domain_ref.\n",
    "  --operational-v2-output: validate v3, then materialize its closed\n",
    "    spares_current projection as a separate operational v2 bundle.\n",
    sep = ""
  )
  quit(status = if (length(args) == 0L || "--help" %in% args || "-h" %in% args) 0L else 1L)
}
if (is.na(contract_version)) {
  stop("Pass --contract=v2 or --contract=v3.", call. = FALSE)
}

microbiology_path <- args[[1L]]
bacteria_mapping_path <- args[[2L]]
sample_type_mapping_path <- args[[3L]]
antibiotic_mapping_path <- args[[4L]]
unit_mapping_path <- args[[5L]]
denominator_path <- args[[6L]]
output_bundle_dir <- args[[7L]]

suppressPackageStartupMessages(library(dplyr))
source("R/bootstrap.R")
orchidee_source_required_script("helpers.R")
orchidee_source_required_script("phenotype_flag_helpers.R")
orchidee_source_required_script("external_bundle_validation_helpers.R")
orchidee_source_required_script("ratb_hospital_days_helpers.R")
orchidee_source_required_script("external_handoff_helpers.R")
orchidee_source_required_script("ratb_canonical_runtime_helpers.R")

contract <- switch(
  contract_version,
  v2 = orchidee_external_contract_v2(),
  v3 = orchidee_external_contract_v3()
)

microbiology_observations <- orchidee_handoff_read_table(microbiology_path)
bacteria_mapping <- orchidee_handoff_read_table(bacteria_mapping_path)
sample_type_mapping <- orchidee_handoff_read_table(sample_type_mapping_path)
antibiotic_mapping <- orchidee_handoff_read_table(antibiotic_mapping_path)
unit_mapping <- orchidee_handoff_read_table(unit_mapping_path)
denominator_input <- orchidee_handoff_read_table(denominator_path)

bundle <- orchidee_handoff_build_external_bundle_from_site_inputs(
  microbiology_observations = microbiology_observations,
  bacteria_mapping = bacteria_mapping,
  sample_type_mapping = sample_type_mapping,
  antibiotic_mapping = antibiotic_mapping,
  unit_mapping = unit_mapping,
  denominator_by_year = if (identical(contract_version, "v3")) {
    NULL
  } else {
    denominator_input
  },
  contract = contract,
  incidence_exposure_by_year_um_uf_ta_de_profile = if (
    identical(contract_version, "v3")
  ) {
    denominator_input
  } else {
    NULL
  }
)

bundle_file_names <- c(
  "sir_wide.rds",
  "sir_wide_meta.rds",
  "sample_scope_reference.rds",
  "denominator_bundle.rds"
)
output_files <- file.path(output_bundle_dir, bundle_file_names)
operational_v2_files <- if (is.na(operational_v2_output)) {
  character()
} else {
  file.path(operational_v2_output, bundle_file_names)
}
if (!is.na(operational_v2_output) && identical(
  normalize_output_path_for_comparison(output_bundle_dir),
  normalize_output_path_for_comparison(operational_v2_output)
)) {
  stop(
    "--operational-v2-output must differ from output_bundle_dir.",
    call. = FALSE
  )
}
if (!isTRUE(force) && any(file.exists(c(output_files, operational_v2_files)))) {
  stop(
    "Output bundle files already exist in a requested output directory",
    ". Pass --force to overwrite them.",
    call. = FALSE
  )
}

dir.create(output_bundle_dir, recursive = TRUE, showWarnings = FALSE)
saveRDS(bundle$sir_wide, file.path(output_bundle_dir, "sir_wide.rds"))
saveRDS(bundle$sir_wide_meta, file.path(output_bundle_dir, "sir_wide_meta.rds"))
saveRDS(
  bundle$sample_scope_reference,
  file.path(output_bundle_dir, "sample_scope_reference.rds")
)
saveRDS(
  bundle$denominator_bundle,
  file.path(output_bundle_dir, "denominator_bundle.rds")
)

report <- validate_external_input_bundle(
  bundle_dir = output_bundle_dir,
  contract = contract,
  strict_preferred = TRUE
)
print_external_input_bundle_validation(report)
if (!isTRUE(report$ok)) {
  quit(status = 1L)
}

if (!is.na(operational_v2_output)) {
  operational_v2_bundle <- project_external_bundle_v3_to_operational_v2(bundle)
  dir.create(operational_v2_output, recursive = TRUE, showWarnings = FALSE)
  saveRDS(
    operational_v2_bundle$sir_wide,
    file.path(operational_v2_output, "sir_wide.rds")
  )
  saveRDS(
    operational_v2_bundle$sir_wide_meta,
    file.path(operational_v2_output, "sir_wide_meta.rds")
  )
  saveRDS(
    operational_v2_bundle$sample_scope_reference,
    file.path(operational_v2_output, "sample_scope_reference.rds")
  )
  saveRDS(
    operational_v2_bundle$denominator_bundle,
    file.path(operational_v2_output, "denominator_bundle.rds")
  )

  operational_v2_report <- validate_external_input_bundle(
    bundle_dir = operational_v2_output,
    contract = orchidee_external_contract_v2(),
    strict_preferred = TRUE
  )
  print_external_input_bundle_validation(operational_v2_report)
  if (!isTRUE(operational_v2_report$ok)) {
    quit(status = 1L)
  }
}

if (!is.na(operational_v2_output)) {
  v2_runtime_path <- normalizePath(
    operational_v2_output,
    winslash = "/",
    mustWork = TRUE
  )
  rscript_path <- normalizePath(
    file.path(
      R.home("bin"),
      if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
    ),
    winslash = "/",
    mustWork = TRUE
  )
  cat(
    "\nBuild complete.\n",
    "Keep this complete v3 bundle: ",
    normalizePath(output_bundle_dir, winslash = "/", mustWork = TRUE),
    "\n",
    "Use this v2 bundle with the current ORCHIDEE runtime: ",
    v2_runtime_path,
    "\n",
    "Next steps (PowerShell):\n",
    "  $env:ORCHIDEE_EXTERNAL_BUNDLE_V2_DIR = \"",
    v2_runtime_path,
    "\"\n",
    "  $env:ORCHIDEE_EXTERNAL_WORKSPACE_DIR = ",
    "\"outputs/site_runtime\"\n",
    "  & \"", rscript_path, "\" --vanilla ",
    "scripts/smoke_external_runtime_inputs.R ",
    "$env:ORCHIDEE_EXTERNAL_BUNDLE_V2_DIR ",
    "--contract=v2 --strict-preferred\n",
    "  & .\\scripts\\render_orchidee.ps1 -Target full\n",
    sep = ""
  )
} else {
  cat(
    "Built validated ORCHIDEE ", contract$version,
    " external bundle: ",
    normalizePath(output_bundle_dir, winslash = "/", mustWork = TRUE),
    "\n",
    sep = ""
  )
  if (identical(contract$version, "v3")) {
    cat(
      "The current notebooks do not read v3 directly. Re-run with ",
      "--operational-v2-output=<directory> to create their v2 input.\n",
      sep = ""
    )
  }
}
