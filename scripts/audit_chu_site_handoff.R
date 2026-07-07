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
fail_on_build_failure <- "--fail-on-build-failure" %in% args
args <- setdiff(args, c("--force", "--fail-on-build-failure"))

if (length(args) > 2L || any(args %in% c("-h", "--help"))) {
  cat("Usage: Rscript scripts/audit_chu_site_handoff.R [site_input_dir] [bundle_dir] [--force] [--fail-on-build-failure]\n")
  cat("Default site_input_dir: outputs/chu_site_inputs\n")
  cat("Default bundle_dir: outputs/chu_site_bundle\n")
  cat("\n")
  cat("This diagnostic script exports CHU-derived elementary handoff inputs,\n")
  cat("then tries the same site-input builder used for external hospitals.\n")
  quit(status = 0L)
}

site_input_dir <- if (length(args) >= 1L) args[[1L]] else file.path("outputs", "chu_site_inputs")
bundle_dir <- if (length(args) >= 2L) args[[2L]] else file.path("outputs", "chu_site_bundle")

source("R/bootstrap.R")
orchidee_source_required_script("helpers.R", "helpers script")
orchidee_source_required_script("phenotype_flag_helpers.R", "phenotype helpers")
orchidee_source_required_script(
  "external_bundle_validation_helpers.R",
  "external bundle validation helpers"
)
orchidee_source_required_script("ratb_hospital_days_helpers.R", "RATB hospital days helpers")
orchidee_source_required_script("external_handoff_helpers.R", "external handoff helpers")

required_paths <- c(
  sir_long = file.path("data", "sir_long"),
  sir_wide = file.path("data", "sir_wide.rds"),
  ratb_scope_cache = file.path("data", "ratb_scope_cache")
)
missing_paths <- required_paths[!file.exists(required_paths)]
if (length(missing_paths) > 0L) {
  stop(
    "Missing CHU artifacts required for self-handoff audit: ",
    paste(names(missing_paths), "=", missing_paths, collapse = ", "),
    call. = FALSE
  )
}

prepare_output_dir <- function(path) {
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

stop_if_existing_outputs <- function(paths, force) {
  existing <- paths[file.exists(paths)]
  if (length(existing) > 0L && !isTRUE(force)) {
    stop(
      "Output files already exist: ",
      paste(existing, collapse = ", "),
      "\nPass --force to overwrite diagnostic outputs.",
      call. = FALSE
    )
  }
}

require_columns <- function(df, cols, label) {
  missing_cols <- setdiff(cols, names(df))
  if (length(missing_cols) > 0L) {
    stop(
      label, " is missing required columns: ",
      paste(missing_cols, collapse = ", "),
      call. = FALSE
    )
  }
}

rename_column <- function(df, old, new) {
  names(df)[names(df) == old] <- new
  df
}

write_rds <- function(x, path) {
  saveRDS(x, path)
  invisible(path)
}

write_csv <- function(x, path) {
  utils::write.csv(x, path, row.names = FALSE, fileEncoding = "UTF-8")
  invisible(path)
}

build_chu_microbiology_observations <- function(sir_long, sir_wide) {
  core_cols <- c(
    "PATID", "EVTID", "ELTID", "DATEPRELEV", "SEJUF", "souche_id",
    "IDENTIFICATION", "NATUREPVT", "LBLANA", "STRRES",
    "bact_norm", "naturepvt_norm"
  )
  require_columns(sir_long, core_cols, "sir_long")

  optional_cols <- intersect("HEUREPRELEV", names(sir_long))
  obs <- sir_long[, c(core_cols, optional_cols), drop = FALSE]
  obs <- rename_column(obs, "IDENTIFICATION", "bacteria_local")
  obs <- rename_column(obs, "NATUREPVT", "sample_type_local")
  obs <- rename_column(obs, "LBLANA", "antibiotic_local")
  obs <- rename_column(obs, "STRRES", "sir_result")

  phenotype_key_cols <- c(
    "PATID", "EVTID", "ELTID", "DATEPRELEV", "souche_id",
    "bact_norm", "naturepvt_norm"
  )
  phenotype_cols <- c("blse_status_row", "carbapenemase_status_row")
  if (all(c(phenotype_key_cols, phenotype_cols) %in% names(sir_wide))) {
    phenotype_lookup <- unique(sir_wide[, c(phenotype_key_cols, phenotype_cols), drop = FALSE])
    obs <- merge(
      obs,
      phenotype_lookup,
      by = phenotype_key_cols,
      all.x = TRUE,
      sort = FALSE
    )
  }

  obs$ratb_diagnostic_scope <- TRUE
  output_cols <- c(
    "PATID", "EVTID", "ELTID", "DATEPRELEV", optional_cols,
    "SEJUF", "souche_id", "bacteria_local", "sample_type_local",
    "antibiotic_local", "sir_result", "ratb_diagnostic_scope",
    intersect(phenotype_cols, names(obs))
  )
  obs <- obs[, output_cols, drop = FALSE]
  row.names(obs) <- NULL
  obs
}

build_two_column_mapping <- function(df, local_col, canonical_col, output_local, output_canonical) {
  require_columns(df, c(local_col, canonical_col), "mapping source")
  out <- unique(data.frame(
    local = df[[local_col]],
    canonical = df[[canonical_col]],
    stringsAsFactors = FALSE
  ))
  names(out) <- c(output_local, output_canonical)
  row.names(out) <- NULL
  out
}

build_audit_summary <- function(
    microbiology_observations,
    bacteria_mapping,
    sample_type_mapping,
    antibiotic_mapping,
    unit_mapping,
    denominator_by_year,
    sir_wide
  ) {
  nonmissing_sample_local <- !is.na(sample_type_mapping$sample_type_local) &
    nzchar(as.character(sample_type_mapping$sample_type_local))
  sample_missing_canonical <- is.na(sample_type_mapping$naturepvt_norm) |
    !nzchar(as.character(sample_type_mapping$naturepvt_norm))

  data.frame(
    metric = c(
      "microbiology_observations_rows",
      "bacteria_mapping_rows",
      "sample_type_mapping_rows",
      "sample_type_mapping_missing_canonical_rows",
      "sample_type_mapping_missing_canonical_nonmissing_local_rows",
      "antibiotic_mapping_rows",
      "unit_mapping_rows",
      "denominator_by_year_rows",
      "current_sir_wide_rows",
      "current_sir_wide_missing_naturepvt_norm_rows"
    ),
    value = c(
      nrow(microbiology_observations),
      nrow(bacteria_mapping),
      nrow(sample_type_mapping),
      sum(sample_missing_canonical),
      sum(sample_missing_canonical & nonmissing_sample_local),
      nrow(antibiotic_mapping),
      nrow(unit_mapping),
      nrow(denominator_by_year),
      nrow(sir_wide),
      sum(is.na(sir_wide$naturepvt_norm))
    ),
    stringsAsFactors = FALSE
  )
}

build_status_report <- function(status, message, validation_report = NULL) {
  report <- list(
    status = status,
    message = message,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    validation_ok = NA,
    validation_errors = character(),
    validation_warnings = character()
  )
  if (!is.null(validation_report)) {
    report$validation_ok <- isTRUE(validation_report$ok)
    report$validation_errors <- validation_report$errors
    report$validation_warnings <- validation_report$warnings
  }
  report
}

sir_long <- readRDS(required_paths[["sir_long"]])
sir_wide <- readRDS(required_paths[["sir_wide"]])
ratb_scope_cache <- readRDS(required_paths[["ratb_scope_cache"]])

if (!is.data.frame(sir_long)) stop("data/sir_long is not a data frame.", call. = FALSE)
if (!is.data.frame(sir_wide)) stop("data/sir_wide.rds is not a data frame.", call. = FALSE)
if (!is.list(ratb_scope_cache)) stop("data/ratb_scope_cache is not a list.", call. = FALSE)

if (!is.data.frame(ratb_scope_cache$ratb_uf_ta_de_reference)) {
  stop("ratb_scope_cache$ratb_uf_ta_de_reference is required for unit_mapping.", call. = FALSE)
}
if (!is.data.frame(ratb_scope_cache$incidence_denominator_by_year)) {
  stop("ratb_scope_cache$incidence_denominator_by_year is required for denominator_by_year.", call. = FALSE)
}

microbiology_observations <- build_chu_microbiology_observations(sir_long, sir_wide)
bacteria_mapping <- build_two_column_mapping(
  sir_long,
  "IDENTIFICATION", "bact_norm",
  "bacteria_local", "bact_norm"
)
sample_type_mapping <- build_two_column_mapping(
  sir_long,
  "NATUREPVT", "naturepvt_norm",
  "sample_type_local", "naturepvt_norm"
)
antibiotic_mapping <- build_two_column_mapping(
  sir_long,
  "LBLANA", "atb_norm",
  "antibiotic_local", "atb_norm"
)

unit_mapping_cols <- c("SEJUF", "CODE_TA", "de_domain_ref")
require_columns(ratb_scope_cache$ratb_uf_ta_de_reference, unit_mapping_cols, "ratb_uf_ta_de_reference")
unit_mapping <- unique(ratb_scope_cache$ratb_uf_ta_de_reference[, unit_mapping_cols, drop = FALSE])
row.names(unit_mapping) <- NULL

denominator_by_year <- ratb_scope_cache$incidence_denominator_by_year[, c(
  "calendar_year", "hospital_nights"
), drop = FALSE]
row.names(denominator_by_year) <- NULL

site_input_dir <- prepare_output_dir(site_input_dir)
bundle_dir <- prepare_output_dir(bundle_dir)

site_input_files <- file.path(site_input_dir, c(
  "microbiology_observations.rds",
  "bacteria_mapping.rds",
  "sample_type_mapping.rds",
  "antibiotic_mapping.rds",
  "unit_mapping.rds",
  "denominator_by_year.rds",
  "audit_summary.csv",
  "build_attempt.rds"
))
bundle_files <- file.path(bundle_dir, c(
  "sir_wide.rds",
  "sir_wide_meta.rds",
  "sample_scope_reference.rds",
  "denominator_bundle.rds"
))
stop_if_existing_outputs(c(site_input_files, bundle_files), force = force)

audit_summary <- build_audit_summary(
  microbiology_observations = microbiology_observations,
  bacteria_mapping = bacteria_mapping,
  sample_type_mapping = sample_type_mapping,
  antibiotic_mapping = antibiotic_mapping,
  unit_mapping = unit_mapping,
  denominator_by_year = denominator_by_year,
  sir_wide = sir_wide
)

write_rds(microbiology_observations, file.path(site_input_dir, "microbiology_observations.rds"))
write_rds(bacteria_mapping, file.path(site_input_dir, "bacteria_mapping.rds"))
write_rds(sample_type_mapping, file.path(site_input_dir, "sample_type_mapping.rds"))
write_rds(antibiotic_mapping, file.path(site_input_dir, "antibiotic_mapping.rds"))
write_rds(unit_mapping, file.path(site_input_dir, "unit_mapping.rds"))
write_rds(denominator_by_year, file.path(site_input_dir, "denominator_by_year.rds"))
write_csv(audit_summary, file.path(site_input_dir, "audit_summary.csv"))

build_attempt <- tryCatch({
  bundle <- orchidee_handoff_build_external_bundle_from_site_inputs(
    microbiology_observations = microbiology_observations,
    bacteria_mapping = bacteria_mapping,
    sample_type_mapping = sample_type_mapping,
    antibiotic_mapping = antibiotic_mapping,
    unit_mapping = unit_mapping,
    denominator_by_year = denominator_by_year
  )

  write_rds(bundle$sir_wide, file.path(bundle_dir, "sir_wide.rds"))
  write_rds(bundle$sir_wide_meta, file.path(bundle_dir, "sir_wide_meta.rds"))
  write_rds(bundle$sample_scope_reference, file.path(bundle_dir, "sample_scope_reference.rds"))
  write_rds(bundle$denominator_bundle, file.path(bundle_dir, "denominator_bundle.rds"))

  validation_report <- validate_external_input_bundle(
    bundle_dir = bundle_dir,
    strict_preferred = TRUE
  )
  if (isTRUE(validation_report$ok)) {
    build_status_report("pass", "CHU-derived site handoff builds and validates.", validation_report)
  } else {
    build_status_report("validation_fail", "Built bundle did not validate.", validation_report)
  }
}, error = function(e) {
  build_status_report("build_fail", conditionMessage(e))
})

write_rds(build_attempt, file.path(site_input_dir, "build_attempt.rds"))

cat("CHU self-handoff audit\n")
cat("Site input dir: ", site_input_dir, "\n", sep = "")
cat("Bundle dir: ", bundle_dir, "\n", sep = "")
cat("Build status: ", build_attempt$status, "\n", sep = "")
cat("Message: ", build_attempt$message, "\n", sep = "")
cat("Audit summary: ", file.path(site_input_dir, "audit_summary.csv"), "\n", sep = "")

if (!identical(build_attempt$status, "pass") && isTRUE(fail_on_build_failure)) {
  quit(status = 1L)
}
quit(status = 0L)