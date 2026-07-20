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

args <- commandArgs(trailingOnly = TRUE)
force <- "--force" %in% args
help <- any(args %in% c("-h", "--help"))
contract_args <- grep("^--contract=", args, value = TRUE)
if (length(contract_args) > 1L) {
  stop("Pass at most one --contract option.", call. = FALSE)
}
contract_version <- if (length(contract_args) == 0L) {
  "v2"
} else {
  sub("^--contract=", "", contract_args[[1L]])
}
if (!contract_version %in% c("v2", "v3")) {
  stop("--contract must be v2 or v3 for the Rouen adapter.", call. = FALSE)
}
args <- setdiff(args, c("--force", "-h", "--help", contract_args))
if (help || length(args) != 3L) {
  cat(
    "Usage:\n",
    "  Rscript scripts/build_rouen_external_bundle.R \\\n",
    "    <bacteriology_raw.rds> <pmsi.rds> <output_dir> \\\n",
    "    [--contract=v2|v3] [--force]\n\n",
    "Inputs:\n",
    "  bacteriology_raw.rds: long Rouen bacteriology export.\n",
    "  pmsi.rds: redsan PMSI output containing pmsi$main.\n",
    "Output:\n",
    "  site_inputs/: the six explicit handoff tables for the selected contract.\n",
    "  bundle/: the four validated canonical bundle files.\n",
    "  adapter_audit.rds: local audit; it may contain patient identifiers.\n",
    "References:\n",
    "  Set ORCHIDEE_CONSORES_STRUCTURE_PATH to override the private local workbook.\n",
    "Default contract: v2. Contract v3 transports profiled UM/UF/TA/DE exposure.\n",
    sep = ""
  )
  quit(status = if (help) 0L else 1L)
}

bacteriology_path <- args[[1L]]
pmsi_path <- args[[2L]]
output_dir <- args[[3L]]
missing_inputs <- c(bacteriology_path, pmsi_path)[
  !file.exists(c(bacteriology_path, pmsi_path))
]
if (length(missing_inputs) > 0L) {
  stop("Missing Rouen raw input: ", paste(missing_inputs, collapse = ", "), call. = FALSE)
}

suppressPackageStartupMessages({
  library(dplyr)
  library(lubridate)
  library(purrr)
  library(stringr)
  library(tibble)
  library(tidyr)
})

source("R/bootstrap.R")
orchidee_source_required_script("helpers.R")
orchidee_source_required_script("normalisation_bact.R")
orchidee_source_required_script("normalisation_atb.R")
orchidee_source_required_script("phenotype_flag_helpers.R")
orchidee_source_required_script("external_bundle_validation_helpers.R")
orchidee_source_required_script("external_handoff_helpers.R")
orchidee_source_required_script("ratb_hospital_days_helpers.R")
orchidee_source_required_script("chu_sample_hospitalization_unit_attribution.R")
orchidee_source_required_script("ratb_canonical_runtime_helpers.R")
orchidee_source_required_script("rouen_microbiology_handoff_adapter.R")
orchidee_source_required_script("rouen_pmsi_handoff_adapter.R")
orchidee_source_required_config("rouen_raw_handoff_v1.R")

read_csv_quietly <- function(path) {
  suppressMessages(readr::read_csv(path, show_col_types = FALSE))
}

bacteriology_raw <- readRDS(bacteriology_path)
pmsi <- readRDS(pmsi_path)
if (!is.list(pmsi) || !is.data.frame(pmsi$main)) {
  stop("pmsi.rds must contain the redsan list element pmsi$main.", call. = FALSE)
}

config <- rouen_raw_handoff_v1_config
species_rules <- readr::read_delim(
  config$dictionaries$species,
  delim = ";",
  show_col_types = FALSE
)
sample_type_rules <- read_csv_quietly(config$dictionaries$sample_type_rules)
sample_type_decisions <- read_csv_quietly(
  config$dictionaries$sample_type_decisions
)
antibiotic_rules <- read_csv_quietly(config$dictionaries$antibiotic)
antibiotic_expansion <- read_csv_quietly(
  config$dictionaries$antibiotic_expansion
)
supported_pairs <- read_csv_quietly(
  config$dictionaries$supported_species_antibiotics
)

microbiology_handoff <- build_rouen_microbiology_handoff_v1(
  bacteriology_raw = bacteriology_raw,
  screening_typeana_codes = config$screening_typeana_codes,
  target_start = config$target_start,
  target_end_exclusive = config$target_end_exclusive,
  species_rules = species_rules,
  sample_type_rules = sample_type_rules,
  sample_type_exact_decisions = sample_type_decisions,
  antibiotic_rules = antibiotic_rules,
  antibiotic_expansion = antibiotic_expansion,
  supported_species_antibiotics = supported_pairs
)
unit_refs <- load_ratb_unit_references(ref_dir = config$references$unit_ref_dir)
ta_de_ref <- load_ratb_consores_ta_de_reference(
  structure_path = config$references$consores_structure,
  codes_ta_path = config$references$codes_ta,
  codes_de_path = config$references$codes_de
)
pmsi_handoff <- build_rouen_pmsi_handoff_v1(
  sample_context = microbiology_handoff$sample_context,
  pmsi_main = pmsi$main,
  unit_refs = unit_refs,
  ta_de_ref = ta_de_ref,
  target_start = config$target_start,
  target_end_exclusive = config$target_end_exclusive
)
contract <- switch(
  contract_version,
  v2 = orchidee_external_contract_v2(),
  v3 = orchidee_external_contract_v3()
)
result <- compose_rouen_external_bundle(
  microbiology_handoff = microbiology_handoff,
  pmsi_handoff = pmsi_handoff,
  contract = contract
)

runtime_inputs <- build_ratb_downstream_scope_from_canonical_inputs(
  sir_wide = result$bundle$sir_wide,
  sample_scope_reference = result$bundle$sample_scope_reference,
  denominator_bundle = result$bundle$denominator_bundle
)
runtime_validation <- validate_ratb_canonical_runtime_inputs(
  runtime_inputs = runtime_inputs,
  sir_wide = result$bundle$sir_wide
)
if (!isTRUE(runtime_validation$ok)) {
  stop(
    "Rouen ", contract_version,
    " bundle failed the canonical runtime smoke: ",
    paste(runtime_validation$errors, collapse = " | "),
    call. = FALSE
  )
}

site_input_dir <- file.path(output_dir, "site_inputs")
bundle_dir <- file.path(output_dir, "bundle")
site_input_paths <- file.path(
  site_input_dir,
  paste0(names(result$site_inputs), ".rds")
)
bundle_paths <- file.path(
  bundle_dir,
  paste0(names(result$bundle), ".rds")
)
audit_path <- file.path(output_dir, "adapter_audit.rds")
output_paths <- c(site_input_paths, bundle_paths, audit_path)
if (!isTRUE(force) && any(file.exists(output_paths))) {
  stop(
    "Rouen adapter outputs already exist under ", output_dir,
    ". Pass --force to overwrite them.",
    call. = FALSE
  )
}
dir.create(site_input_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(bundle_dir, recursive = TRUE, showWarnings = FALSE)

invisible(Map(saveRDS, result$site_inputs, site_input_paths))
invisible(Map(saveRDS, result$bundle, bundle_paths))
audit <- result$audit
git_head <- tryCatch(
  system2("git", c("rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE),
  error = function(condition) NA_character_
)
git_status <- tryCatch(
  system2("git", c("status", "--porcelain"), stdout = TRUE, stderr = FALSE),
  error = function(condition) NA_character_
)
input_paths <- c(
  bacteriology_raw = bacteriology_path,
  pmsi = pmsi_path
)
dictionary_paths <- unlist(config$dictionaries, use.names = TRUE)
reference_paths <- c(
  consores_structure = config$references$consores_structure,
  codes_ta = config$references$codes_ta,
  codes_de = config$references$codes_de,
  unit_uf = file.path(config$references$unit_ref_dir, "ref_uf.txt"),
  unit_um = file.path(config$references$unit_ref_dir, "ref_um.txt"),
  unit_uf_to_um = file.path(config$references$unit_ref_dir, "ref_uf2um.txt")
)
audit$metadata <- list(
  adapter_version = config$adapter_version,
  contract_version = contract_version,
  redsan_version = as.character(utils::packageVersion("redsan")),
  repository_head = if (length(git_head) == 1L) git_head else NA_character_,
  repository_working_tree_dirty = any(nzchar(git_status)),
  pmsi_source_policy = "c_over_dw",
  target_start = config$target_start,
  target_end_exclusive = config$target_end_exclusive,
  config = config,
  input_signatures = tibble::tibble(
    input = names(input_paths),
    bytes = unname(file.info(input_paths)$size),
    md5 = unname(tools::md5sum(input_paths))
  ),
  dictionary_signatures = tibble::tibble(
    dictionary = names(dictionary_paths),
    md5 = unname(tools::md5sum(dictionary_paths))
  ),
  reference_signatures = tibble::tibble(
    reference = names(reference_paths),
    bytes = unname(file.info(reference_paths)$size),
    md5 = unname(tools::md5sum(reference_paths))
  )
)
audit$runtime_validation <- runtime_validation
saveRDS(audit, audit_path)

report <- validate_external_input_bundle(
  bundle_dir = bundle_dir,
  contract = contract,
  strict_preferred = TRUE
)
print_external_input_bundle_validation(report)
if (!isTRUE(report$ok)) {
  quit(status = 1L)
}

cat(
  "PASS: built Rouen six-input handoff and canonical ",
  contract_version,
  " bundle.\n",
  sep = ""
)
cat("Output: ", normalizePath(output_dir, winslash = "/", mustWork = TRUE), "\n", sep = "")
