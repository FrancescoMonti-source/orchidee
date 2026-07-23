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

normalize_output_path_for_comparison <- function(path) {
  normalized <- normalizePath(path, winslash = "/", mustWork = FALSE)
  if (identical(.Platform$OS.type, "windows")) tolower(normalized) else normalized
}

path_is_same_or_descendant <- function(path, directory) {
  path <- normalize_output_path_for_comparison(path)
  directory <- normalize_output_path_for_comparison(directory)
  identical(path, directory) || startsWith(
    path,
    paste0(sub("/+$", "", directory), "/")
  )
}

build_lock_path <- function(output_path) {
  paste0(
    sub("/+$", "", normalize_output_path_for_comparison(output_path)),
    ".rouen-build.lock"
  )
}

capture_repository_state <- function() {
  run_git <- function(args) {
    tryCatch(
      system2("git", args, stdout = TRUE, stderr = FALSE),
      error = function(condition) NA_character_
    )
  }
  list(
    head = run_git(c("rev-parse", "HEAD")),
    status = run_git(c("status", "--porcelain")),
    tracked_diff = run_git(c("diff", "--no-ext-diff", "--binary", "HEAD", "--"))
  )
}

capture_file_signatures <- function(paths) {
  list(
    bytes = unname(file.info(paths)$size),
    md5 = unname(tools::md5sum(paths))
  )
}

claim_build_locks <- function(paths) {
  normalized <- vapply(
    paths,
    normalize_output_path_for_comparison,
    character(1)
  )
  paths <- paths[!duplicated(normalized)]
  claimed <- character()
  tryCatch(
    {
      for (path in paths) {
        dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
        if (!dir.create(path, showWarnings = FALSE)) {
          owner_path <- file.path(path, "owner.txt")
          owner <- if (file.exists(owner_path)) {
            paste(readLines(owner_path, warn = FALSE), collapse = "; ")
          } else {
            "owner metadata unavailable"
          }
          stop(
            "Another Rouen build holds the output lock ", path, " (", owner,
            "). Remove this lock only after confirming that no build is running.",
            call. = FALSE
          )
        }
        claimed <- c(claimed, path)
        writeLines(
          c(
            paste0("pid: ", Sys.getpid()),
            paste0(
              "claimed_at_utc: ",
              format(Sys.time(), tz = "UTC", format = "%Y-%m-%dT%H:%M:%SZ")
            )
          ),
          file.path(path, "owner.txt"),
          useBytes = TRUE
        )
      }
      claimed
    },
    error = function(condition) {
      unlink(claimed, recursive = TRUE, force = TRUE)
      stop(condition)
    }
  )
}

release_build_locks <- function(paths) {
  unlink(paths, recursive = TRUE, force = TRUE)
  remaining <- paths[file.exists(paths) | dir.exists(paths)]
  if (length(remaining) > 0L) {
    warning(
      "Could not remove Rouen build lock: ",
      paste(remaining, collapse = ", "),
      call. = FALSE
    )
  }
}

main <- function() {
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
  NA_character_
} else {
  sub("^--contract=", "", contract_args[[1L]])
}
if (!is.na(contract_version) && !contract_version %in% c("v2", "v3")) {
  stop("--contract must be v2 or v3 for the Rouen adapter.", call. = FALSE)
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
args <- setdiff(
  args,
  c("--force", "-h", "--help", contract_args, operational_v2_args)
)
if (help || length(args) != 3L) {
  cat(
    "Usage:\n",
    "  Rscript scripts/build_rouen_external_bundle.R \\\n",
    "    <bact_path> <pmsi_path> <output_dir> \\\n",
    "    --contract=v2|v3 [--operational-v2-output=<dir>] [--force]\n\n",
    "Inputs:\n",
    "  bact_path: long Rouen bacteriology RDS export.\n",
    "  pmsi_path: redsan RDS output containing pmsi$main.\n",
    "Output:\n",
    "  site_inputs/: the six explicit handoff tables for the selected contract.\n",
    "  bundle/: a direct compatibility build without projection.\n",
    "  bundle_v3/: the durable v3 bundle when projection is requested.\n",
    "  --operational-v2-output: with v3, materialize the closed\n",
    "    spares_current projection for today's runtime.\n",
    "  adapter_audit.rds: local audit; it may contain patient identifiers.\n",
    "  build_manifest.txt: human-readable paths, hashes and validation status.\n",
    "References:\n",
    "  Versioned Rouen and TA/DE references are loaded automatically.\n",
    "  Set ORCHIDEE_ROUEN_STRUCTURE_PATH only to override the structure workbook.\n",
    "--contract is required. Preferred Rouen onboarding uses v3 with\n",
    "  --operational-v2-output.\n",
    sep = ""
  )
  quit(status = if (help) 0L else 1L)
}
if (is.na(contract_version)) {
  stop("Pass --contract=v2 or --contract=v3.", call. = FALSE)
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

site_input_names <- c(
  "microbiology_observations",
  "bacteria_mapping",
  "sample_type_mapping",
  "antibiotic_mapping",
  "unit_mapping",
  if (identical(contract_version, "v3")) {
    "incidence_exposure_by_year_um_uf_ta_de_profile"
  } else {
    "denominator_by_year"
  }
)
bundle_object_names <- c(
  "sir_wide",
  "sir_wide_meta",
  "sample_scope_reference",
  "denominator_bundle"
)
site_input_dir <- file.path(output_dir, "site_inputs")
bundle_dir <- file.path(
  output_dir,
  if (!is.na(operational_v2_output)) "bundle_v3" else "bundle"
)
site_input_paths <- stats::setNames(
  file.path(site_input_dir, paste0(site_input_names, ".rds")),
  site_input_names
)
bundle_paths <- stats::setNames(
  file.path(bundle_dir, paste0(bundle_object_names, ".rds")),
  bundle_object_names
)
operational_v2_paths <- if (is.na(operational_v2_output)) {
  character()
} else {
  stats::setNames(
    file.path(operational_v2_output, paste0(bundle_object_names, ".rds")),
    bundle_object_names
  )
}
audit_path <- file.path(output_dir, "adapter_audit.rds")
manifest_path <- file.path(output_dir, "build_manifest.txt")
manifest_tmp_path <- paste0(manifest_path, ".tmp")

reserved_output_dirs <- c(
  output_dir,
  site_input_dir,
  bundle_dir,
  file.path(output_dir, "bundle")
)
operational_v2_collides <- !is.na(operational_v2_output) && any(vapply(
  c(
    reserved_output_dirs[-1L],
    site_input_paths,
    bundle_paths,
    audit_path,
    manifest_path,
    manifest_tmp_path
  ),
  function(path) path_is_same_or_descendant(operational_v2_output, path),
  logical(1)
)) || (!is.na(operational_v2_output) && path_is_same_or_descendant(
  output_dir,
  operational_v2_output
))
if (operational_v2_collides) {
  stop(
    "--operational-v2-output overlaps the source output layout. ",
    "Use a distinct directory below output_dir or a separate directory.",
    call. = FALSE
  )
}

incompatible_paths <- if (!is.na(operational_v2_output)) {
  c(
    file.path(output_dir, "bundle"),
    file.path(site_input_dir, "denominator_by_year.rds")
  )
} else if (identical(contract_version, "v2")) {
  c(
    file.path(output_dir, "bundle_v3"),
    file.path(
      site_input_dir,
      "incidence_exposure_by_year_um_uf_ta_de_profile.rds"
    )
  )
} else {
  c(
    file.path(output_dir, "bundle_v3"),
    file.path(site_input_dir, "denominator_by_year.rds")
  )
}
incompatible_paths <- incompatible_paths[
  file.exists(incompatible_paths) | dir.exists(incompatible_paths)
]
if (length(incompatible_paths) > 0L) {
  stop(
    "Output root contains artifacts from another Rouen build layout: ",
    paste(incompatible_paths, collapse = ", "),
    ". Use a distinct output root.",
    call. = FALSE
  )
}

output_paths <- c(
  site_input_paths,
  bundle_paths,
  operational_v2_paths,
  audit_path,
  manifest_path,
  manifest_tmp_path
)
input_paths <- c(
  bacteriology_raw = bacteriology_path,
  pmsi = pmsi_path
)
normalized_inputs <- vapply(
  input_paths,
  normalize_output_path_for_comparison,
  character(1)
)
requested_outputs <- c(output_dir, operational_v2_output, output_paths)
requested_outputs <- requested_outputs[!is.na(requested_outputs)]
normalized_outputs <- vapply(
  requested_outputs,
  normalize_output_path_for_comparison,
  character(1)
)
if (any(normalized_inputs %in% normalized_outputs)) {
  stop("A Rouen output path must not overwrite a raw input.", call. = FALSE)
}
output_directories <- c(output_dir, operational_v2_output)
output_directories <- output_directories[!is.na(output_directories)]
input_inside_output <- any(vapply(
  input_paths,
  function(input_path) any(vapply(
    output_directories,
    function(output_path) path_is_same_or_descendant(input_path, output_path),
    logical(1)
  )),
  logical(1)
))
if (input_inside_output) {
  stop("Rouen raw inputs must be outside the output directories.", call. = FALSE)
}
if (!isTRUE(force) && any(file.exists(output_paths))) {
  stop(
    "Rouen adapter outputs already exist under ", output_dir,
    ". Pass --force to overwrite them.",
    call. = FALSE
  )
}

build_lock_paths <- c(
  build_lock_path(output_dir),
  if (!is.na(operational_v2_output)) {
    build_lock_path(operational_v2_output)
  }
)
claimed_build_locks <- claim_build_locks(build_lock_paths)
on.exit(release_build_locks(claimed_build_locks), add = TRUE)
repository_state <- capture_repository_state()
if (!isTRUE(force) && any(file.exists(output_paths))) {
  stop(
    "Rouen adapter outputs appeared while claiming the build lock. ",
    "Rerun only after reviewing the existing output.",
    call. = FALSE
  )
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
orchidee_source_required_config("rouen_raw_handoff.R")

config <- rouen_raw_handoff_config
dictionary_paths <- unlist(config$dictionaries, use.names = TRUE)
rule_paths <- unlist(config$rules, use.names = TRUE)
reference_paths <- c(
  establishment_structure = config$references$establishment_structure,
  codes_ta = config$references$codes_ta,
  codes_de = config$references$codes_de,
  unit_uf = file.path(config$references$unit_ref_dir, "ref_uf.txt"),
  unit_um = file.path(config$references$unit_ref_dir, "ref_um.txt"),
  unit_uf_to_um = file.path(config$references$unit_ref_dir, "ref_uf2um.txt")
)
provenance_paths <- c(input_paths, dictionary_paths, rule_paths, reference_paths)
missing_provenance <- provenance_paths[!file.exists(provenance_paths)]
if (length(missing_provenance) > 0L) {
  stop(
    "Missing Rouen provenance input: ",
    paste(missing_provenance, collapse = ", "),
    call. = FALSE
  )
}
input_signatures <- capture_file_signatures(input_paths)
dictionary_signatures <- capture_file_signatures(dictionary_paths)
rule_signatures <- capture_file_signatures(rule_paths)
reference_signatures <- capture_file_signatures(reference_paths)

read_csv_quietly <- function(path) {
  suppressMessages(readr::read_csv(path, show_col_types = FALSE))
}

bacteriology_raw <- readRDS(bacteriology_path)
pmsi <- readRDS(pmsi_path)
if (!is.list(pmsi) || !is.data.frame(pmsi$main)) {
  stop("PMSI input must contain the redsan list element pmsi$main.", call. = FALSE)
}

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
  config$rules$supported_species_antibiotics
)

microbiology_handoff <- build_rouen_microbiology_handoff(
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
  structure_path = config$references$establishment_structure,
  codes_ta_path = config$references$codes_ta,
  codes_de_path = config$references$codes_de
)
pmsi_handoff <- build_rouen_pmsi_handoff(
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

analysis_context_id <- "spares_current"
analysis_context <- ratb_analysis_context_profile(analysis_context_id)
operational_v2_bundle <- if (is.na(operational_v2_output)) {
  NULL
} else {
  project_external_bundle_v3_to_operational_v2(
    result$bundle,
    analysis_context_id = analysis_context_id
  )
}

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

operational_v2_runtime_validation <- NULL
if (!is.null(operational_v2_bundle)) {
  operational_v2_runtime_inputs <- build_ratb_downstream_scope_from_canonical_inputs(
    sir_wide = operational_v2_bundle$sir_wide,
    sample_scope_reference = operational_v2_bundle$sample_scope_reference,
    denominator_bundle = operational_v2_bundle$denominator_bundle
  )
  operational_v2_runtime_validation <- validate_ratb_canonical_runtime_inputs(
    runtime_inputs = operational_v2_runtime_inputs,
    sir_wide = operational_v2_bundle$sir_wide
  )
  if (!isTRUE(operational_v2_runtime_validation$ok)) {
    stop(
      "Rouen projected v2 bundle failed the canonical runtime smoke: ",
      paste(operational_v2_runtime_validation$errors, collapse = " | "),
      call. = FALSE
    )
  }
}

if (!identical(names(result$site_inputs), site_input_names) ||
    !identical(names(result$bundle), bundle_object_names) ||
    (!is.null(operational_v2_bundle) &&
      !identical(names(operational_v2_bundle), bundle_object_names))) {
  stop(
    "Rouen builder object names disagree with the declared output layout.",
    call. = FALSE
  )
}
repository_state_after <- capture_repository_state()
provenance_unchanged <- identical(
  input_signatures,
  capture_file_signatures(input_paths)
) && identical(
  dictionary_signatures,
  capture_file_signatures(dictionary_paths)
) && identical(
  rule_signatures,
  capture_file_signatures(rule_paths)
) && identical(
  reference_signatures,
  capture_file_signatures(reference_paths)
)
if (!identical(repository_state, repository_state_after) ||
    !isTRUE(provenance_unchanged)) {
  stop(
    "Repository state or provenance inputs changed during the Rouen build. ",
    "No canonical output was published; rerun from a stable checkout.",
    call. = FALSE
  )
}
if (isTRUE(force)) {
  unlink(c(manifest_path, manifest_tmp_path), force = TRUE)
  remaining_manifests <- c(manifest_path, manifest_tmp_path)[
    file.exists(c(manifest_path, manifest_tmp_path))
  ]
  if (length(remaining_manifests) > 0L) {
    stop(
      "Could not invalidate the previous Rouen manifest: ",
      paste(remaining_manifests, collapse = ", "),
      call. = FALSE
    )
  }
}
dir.create(site_input_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(bundle_dir, recursive = TRUE, showWarnings = FALSE)
if (!is.null(operational_v2_bundle)) {
  dir.create(operational_v2_output, recursive = TRUE, showWarnings = FALSE)
}

invisible(Map(saveRDS, result$site_inputs, site_input_paths))
invisible(Map(saveRDS, result$bundle, bundle_paths))
if (!is.null(operational_v2_bundle)) {
  invisible(Map(saveRDS, operational_v2_bundle, operational_v2_paths))
}
audit <- result$audit
audit$metadata <- list(
  adapter_id = config$adapter_id,
  contract_version = contract_version,
  redsan_version = as.character(utils::packageVersion("redsan")),
  repository_head = if (length(repository_state$head) == 1L) {
    repository_state$head
  } else {
    NA_character_
  },
  repository_working_tree_dirty = any(nzchar(repository_state$status)),
  pmsi_source_policy = "c_over_dw",
  target_start = config$target_start,
  target_end_exclusive = config$target_end_exclusive,
  config = config,
  input_signatures = tibble::tibble(
    input = names(input_paths),
    bytes = input_signatures$bytes,
    md5 = input_signatures$md5
  ),
  dictionary_signatures = tibble::tibble(
    dictionary = names(dictionary_paths),
    md5 = dictionary_signatures$md5
  ),
  rule_signatures = tibble::tibble(
    rule = names(rule_paths),
    md5 = rule_signatures$md5
  ),
  reference_signatures = tibble::tibble(
    reference = names(reference_paths),
    bytes = reference_signatures$bytes,
    md5 = reference_signatures$md5
  )
)
audit$runtime_validation <- runtime_validation
audit$operational_v2_runtime_validation <- operational_v2_runtime_validation
saveRDS(audit, audit_path)

report <- validate_external_input_bundle(
  bundle_dir = bundle_dir,
  contract = contract,
  strict_preferred = TRUE
)
print_external_input_bundle_validation(report)
if (!isTRUE(report$ok)) {
  stop("Rouen source bundle failed strict validation.", call. = FALSE)
}

operational_v2_report <- NULL
if (!is.null(operational_v2_bundle)) {
  operational_v2_report <- validate_external_input_bundle(
    bundle_dir = operational_v2_output,
    contract = orchidee_external_contract_v2(),
    strict_preferred = TRUE
  )
  print_external_input_bundle_validation(operational_v2_report)
  if (!isTRUE(operational_v2_report$ok)) {
    stop("Rouen projected v2 bundle failed strict validation.", call. = FALSE)
  }
}

created_at_utc <- format(
  Sys.time(),
  tz = "UTC",
  format = "%Y-%m-%dT%H:%M:%SZ"
)
manifest_status <- function(validation) {
  if (is.null(validation)) return("not requested")
  if (isTRUE(validation$ok)) "PASS" else "FAIL"
}
manifest_file_section <- function(title, paths, md5 = NULL) {
  if (length(paths) == 0L) return(character())
  if (is.null(md5)) md5 <- unname(tools::md5sum(paths))
  c(
    "",
    title,
    paste0(
      names(paths), ": ",
      normalizePath(paths, winslash = "/", mustWork = TRUE),
      " | md5=", md5
    )
  )
}
operational_requested <- !is.null(operational_v2_bundle)
manifest_metadata <- c(
  created_at_utc = created_at_utc,
  repository_head = audit$metadata$repository_head,
  repository_working_tree_dirty = audit$metadata$repository_working_tree_dirty,
  adapter_id = audit$metadata$adapter_id,
  redsan_version = audit$metadata$redsan_version,
  source_contract = contract_version,
  target_start = as.character(audit$metadata$target_start),
  target_end_exclusive = as.character(audit$metadata$target_end_exclusive),
  pmsi_source_policy = audit$metadata$pmsi_source_policy,
  denominator_profile_id = if (operational_requested) {
    analysis_context$denominator_profile_id
  } else {
    "not requested"
  },
  site_inputs_directory = normalizePath(
    site_input_dir,
    winslash = "/",
    mustWork = TRUE
  ),
  canonical_bundle_directory = normalizePath(
    bundle_dir,
    winslash = "/",
    mustWork = TRUE
  ),
  operational_v2_directory = if (operational_requested) {
    normalizePath(operational_v2_output, winslash = "/", mustWork = TRUE)
  } else {
    "not requested"
  },
  operational_v2_analysis_context = if (operational_requested) {
    analysis_context$analysis_context_id
  } else {
    "not requested"
  },
  source_bundle_validation = manifest_status(report),
  source_runtime_smoke = manifest_status(runtime_validation),
  operational_v2_validation = manifest_status(operational_v2_report),
  operational_v2_runtime_smoke = manifest_status(
    operational_v2_runtime_validation
  )
)
manifest_lines <- c(
  "ORCHIDEE Rouen canonical build",
  paste0(names(manifest_metadata), ": ", unname(manifest_metadata)),
  manifest_file_section("Inputs", input_paths, input_signatures$md5),
  manifest_file_section(
    "Dictionaries",
    dictionary_paths,
    dictionary_signatures$md5
  ),
  manifest_file_section("Rules", rule_paths, rule_signatures$md5),
  manifest_file_section("References", reference_paths, reference_signatures$md5),
  manifest_file_section("Site inputs", site_input_paths),
  manifest_file_section("Source bundle", bundle_paths),
  manifest_file_section("Audit", c(adapter_audit = audit_path)),
  manifest_file_section("Operational v2", operational_v2_paths)
)
writeLines(manifest_lines, manifest_tmp_path, useBytes = TRUE)
if (!file.rename(manifest_tmp_path, manifest_path)) {
  stop("Could not finalize build_manifest.txt atomically.", call. = FALSE)
}

cat(
  "PASS: built Rouen six-input handoff and canonical ",
  contract_version,
  " bundle.\n",
  sep = ""
)
if (!is.null(operational_v2_bundle)) {
  cat(
    "PASS: projected strict operational v2 bundle with spares_current.\n",
    "Operational v2: ",
    normalizePath(operational_v2_output, winslash = "/", mustWork = TRUE),
    "\n",
    sep = ""
  )
}
cat("Output: ", normalizePath(output_dir, winslash = "/", mustWork = TRUE), "\n", sep = "")
}

main()
