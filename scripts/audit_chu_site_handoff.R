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
  cat("This diagnostic script derives elementary handoff inputs from current\n")
  cat("data/sir_wide.rds, then tries the same site-input builder used for\n")
  cat("external hospitals. It is a roundtrip proof, not a raw CHU extraction test.\n")
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

write_rds <- function(x, path) {
  saveRDS(x, path)
  invisible(path)
}

write_csv <- function(x, path) {
  utils::write.csv(x, path, row.names = FALSE, fileEncoding = "UTF-8")
  invisible(path)
}

build_identity_mapping <- function(values, output_local, output_canonical) {
  out <- unique(data.frame(
    local = as.character(values),
    canonical = as.character(values),
    stringsAsFactors = FALSE
  ))
  names(out) <- c(output_local, output_canonical)
  row.names(out) <- NULL
  out
}

build_chu_microbiology_observations <- function(sir_wide, supported_atb) {
  row_cols <- c(
    "PATID", "EVTID", "ELTID", "DATEPRELEV", "HEUREPRELEV", "SEJUF",
    "souche_id", "bact_norm", "naturepvt_norm"
  )
  phenotype_cols <- c("blse_status_row", "carbapenemase_status_row")
  require_columns(sir_wide, row_cols, "sir_wide")
  require_columns(sir_wide, supported_atb, "sir_wide")

  atb_values <- sir_wide[supported_atb]
  has_result <- !is.na(atb_values) & atb_values != ""
  result_idx <- which(as.matrix(has_result), arr.ind = TRUE)
  if (nrow(result_idx) == 0L) {
    stop("sir_wide contains no supported non-missing S/I/R values.", call. = FALSE)
  }
  result_idx <- result_idx[order(result_idx[, "row"], result_idx[, "col"]), , drop = FALSE]

  base <- sir_wide[result_idx[, "row"], row_cols, drop = FALSE]
  obs <- data.frame(
    PATID = base$PATID,
    EVTID = base$EVTID,
    ELTID = base$ELTID,
    DATEPRELEV = base$DATEPRELEV,
    HEUREPRELEV = base$HEUREPRELEV,
    SEJUF = base$SEJUF,
    souche_id = base$souche_id,
    bacteria_local = base$bact_norm,
    sample_type_local = base$naturepvt_norm,
    antibiotic_local = supported_atb[result_idx[, "col"]],
    sir_result = as.character(as.matrix(atb_values)[result_idx]),
    ratb_diagnostic_scope = TRUE,
    stringsAsFactors = FALSE
  )

  for (col in intersect(phenotype_cols, names(sir_wide))) {
    obs[[col]] <- sir_wide[[col]][result_idx[, "row"]]
  }

  row.names(obs) <- NULL
  obs
}

make_row_key <- function(df, key_cols) {
  parts <- lapply(df[key_cols], function(x) {
    x <- as.character(x)
    x[is.na(x)] <- "<NA>"
    x
  })
  do.call(paste, c(parts, sep = "\r"))
}

normalize_compare_value <- function(x) {
  if (inherits(x, "difftime")) {
    x <- as.character(as.numeric(x, units = "secs"))
  } else if (inherits(x, "Date")) {
    x <- as.character(x)
  } else {
    x <- as.character(x)
  }
  x[is.na(x)] <- "<NA>"
  x
}

build_roundtrip_report <- function(current_sir_wide, rebuilt_sir_wide, contract) {
  key_cols <- contract$sir_wide$row_grain_key
  # Derive the comparison columns from the contract so a new portable
  # sir_wide column is covered automatically instead of silently skipped.
  compare_cols <- external_bundle_sir_wide_contract_columns(contract)
  compare_cols <- intersect(
    compare_cols,
    intersect(names(current_sir_wide), names(rebuilt_sir_wide))
  )

  current_key <- make_row_key(current_sir_wide, key_cols)
  rebuilt_key <- make_row_key(rebuilt_sir_wide, key_cols)
  shared_key <- intersect(current_key, rebuilt_key)

  current_only <- sum(!current_key %in% rebuilt_key)
  rebuilt_only <- sum(!rebuilt_key %in% current_key)

  value_mismatches <- 0L
  mismatch_columns <- character()
  if (length(shared_key) > 0L) {
    current_aligned <- current_sir_wide[match(shared_key, current_key), compare_cols, drop = FALSE]
    rebuilt_aligned <- rebuilt_sir_wide[match(shared_key, rebuilt_key), compare_cols, drop = FALSE]
    mismatch_by_col <- vapply(compare_cols, function(col) {
      sum(normalize_compare_value(current_aligned[[col]]) != normalize_compare_value(rebuilt_aligned[[col]]))
    }, integer(1))
    value_mismatches <- sum(mismatch_by_col)
    mismatch_columns <- names(mismatch_by_col)[mismatch_by_col > 0L]
  }

  status <- if (
    current_only == 0L && rebuilt_only == 0L && value_mismatches == 0L
  ) "exact" else "mismatch"

  list(
    status = status,
    current_rows = nrow(current_sir_wide),
    rebuilt_rows = nrow(rebuilt_sir_wide),
    shared_keys = length(shared_key),
    current_only_keys = current_only,
    rebuilt_only_keys = rebuilt_only,
    value_mismatches = value_mismatches,
    mismatch_columns = mismatch_columns
  )
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

build_status_report <- function(status, message, validation_report = NULL, roundtrip_report = NULL) {
  report <- list(
    status = status,
    message = message,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    roundtrip = roundtrip_report,
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

sir_wide <- readRDS(required_paths[["sir_wide"]])
ratb_scope_cache <- readRDS(required_paths[["ratb_scope_cache"]])
contract <- orchidee_external_contract_v1()
supported_atb <- contract$sir_wide$atb_cols

if (!is.data.frame(sir_wide)) stop("data/sir_wide.rds is not a data frame.", call. = FALSE)
if (!is.list(ratb_scope_cache)) stop("data/ratb_scope_cache is not a list.", call. = FALSE)

if (!is.data.frame(ratb_scope_cache$ratb_uf_ta_de_reference)) {
  stop("ratb_scope_cache$ratb_uf_ta_de_reference is required for unit_mapping.", call. = FALSE)
}
if (!is.data.frame(ratb_scope_cache$incidence_denominator_by_year)) {
  stop("ratb_scope_cache$incidence_denominator_by_year is required for denominator_by_year.", call. = FALSE)
}

microbiology_observations <- build_chu_microbiology_observations(sir_wide, supported_atb)
bacteria_mapping <- build_identity_mapping(
  sir_wide$bact_norm,
  "bacteria_local", "bact_norm"
)
sample_type_mapping <- build_identity_mapping(
  sir_wide$naturepvt_norm,
  "sample_type_local", "naturepvt_norm"
)
antibiotic_mapping <- build_identity_mapping(
  supported_atb,
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
  roundtrip_report <- build_roundtrip_report(sir_wide, bundle$sir_wide, contract)
  if (isTRUE(validation_report$ok) && identical(roundtrip_report$status, "exact")) {
    build_status_report(
      "pass",
      "Current sir_wide roundtrip builds, validates and reproduces the canonical artifact.",
      validation_report,
      roundtrip_report = roundtrip_report
    )
  } else if (isTRUE(validation_report$ok)) {
    build_status_report(
      "roundtrip_mismatch",
      "Built bundle validates, but rebuilt sir_wide differs from current sir_wide.",
      validation_report,
      roundtrip_report = roundtrip_report
    )
  } else {
    build_status_report(
      "validation_fail",
      "Built bundle did not validate.",
      validation_report,
      roundtrip_report = roundtrip_report
    )
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
if (!is.null(build_attempt$roundtrip)) {
  cat(
    "Roundtrip: ", build_attempt$roundtrip$status,
    " (current rows ", build_attempt$roundtrip$current_rows,
    ", rebuilt rows ", build_attempt$roundtrip$rebuilt_rows,
    ", value mismatches ", build_attempt$roundtrip$value_mismatches,
    ")\n",
    sep = ""
  )
}
cat("Audit summary: ", file.path(site_input_dir, "audit_summary.csv"), "\n", sep = "")

if (!identical(build_attempt$status, "pass") && isTRUE(fail_on_build_failure)) {
  quit(status = 1L)
}
quit(status = 0L)