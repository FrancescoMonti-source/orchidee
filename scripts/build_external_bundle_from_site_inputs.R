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

args <- commandArgs(trailingOnly = TRUE)
force <- "--force" %in% args
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
args <- setdiff(args, c("--force", contract_args))

if (length(args) < 7L || length(args) > 8L || "--help" %in% args || "-h" %in% args) {
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
    "    [de_reference.{rds,csv,tsv,tab,txt}] \\\n",
    "    [--contract=v1|v2|v3] [--force]\n\n",
    "Inputs:\n",
    "  microbiology_observations: long local S/I/R observations with the\n",
    "    columns documented in site_handoff_inputs_v1.md.\n",
    "  bacteria_mapping: bacteria_local + bact_norm.\n",
    "  sample_type_mapping: sample_type_local + naturepvt_norm.\n",
    "  antibiotic_mapping: antibiotic_local + atb_norm.\n",
    "  unit_mapping: one row per SEJUF with CODE_TA and either de_domain_ref\n",
    "    or CODE_DE plus a de_reference table.\n",
    "  denominator: v1/v2 use calendar_year + hospital_nights; v3 uses\n",
    "    calendar_year + SEJUM + SEJUF + CODE_TA + CODE_DE + hospital_nights.\n",
    "  de_reference: optional CODE_DE + de_domain_ref/DOMAINE dictionary.\n",
    "  --contract=v2: declare SEJUF as the hospitalization unit at sampling.\n",
    "  --contract=v3: keep v2 SEJUF semantics and require the fine denominator.\n",
    sep = ""
  )
  quit(status = if (length(args) == 0L || "--help" %in% args || "-h" %in% args) 0L else 1L)
}

microbiology_path <- args[[1L]]
bacteria_mapping_path <- args[[2L]]
sample_type_mapping_path <- args[[3L]]
antibiotic_mapping_path <- args[[4L]]
unit_mapping_path <- args[[5L]]
denominator_path <- args[[6L]]
output_bundle_dir <- args[[7L]]
de_reference_path <- if (length(args) >= 8L) args[[8L]] else NA_character_

source("R/bootstrap.R")
orchidee_source_required_script("helpers.R")
orchidee_source_required_script("phenotype_flag_helpers.R")
orchidee_source_required_script("external_bundle_validation_helpers.R")
orchidee_source_required_script("ratb_hospital_days_helpers.R")
orchidee_source_required_script("external_handoff_helpers.R")

contract <- switch(
  contract_version,
  v1 = orchidee_external_contract_v1(),
  v2 = orchidee_external_contract_v2(),
  v3 = orchidee_external_contract_v3()
)

microbiology_observations <- orchidee_handoff_read_table(microbiology_path)
bacteria_mapping <- orchidee_handoff_read_table(bacteria_mapping_path)
sample_type_mapping <- orchidee_handoff_read_table(sample_type_mapping_path)
antibiotic_mapping <- orchidee_handoff_read_table(antibiotic_mapping_path)
unit_mapping <- orchidee_handoff_read_table(unit_mapping_path)
denominator_input <- orchidee_handoff_read_table(denominator_path)
de_reference <- NULL
if (!is.na(de_reference_path) && nzchar(de_reference_path)) {
  de_reference <- orchidee_handoff_read_table(de_reference_path)
}

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
  de_reference = de_reference,
  contract = contract,
  denominator_by_year_um_uf_ta_de = if (identical(contract_version, "v3")) {
    denominator_input
  } else {
    NULL
  }
)

dir.create(output_bundle_dir, recursive = TRUE, showWarnings = FALSE)
output_files <- file.path(
  output_bundle_dir,
  c(
    "sir_wide.rds",
    "sir_wide_meta.rds",
    "sample_scope_reference.rds",
    "denominator_bundle.rds"
  )
)
if (!isTRUE(force) && any(file.exists(output_files))) {
  stop(
    "Output bundle files already exist in ",
    output_bundle_dir,
    ". Pass --force to overwrite them.",
    call. = FALSE
  )
}
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

cat(
  "Built strict preferred ORCHIDEE ", contract$version,
  " external bundle: ", output_bundle_dir, "\n",
  sep = ""
)
