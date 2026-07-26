#!/usr/bin/env Rscript

required_packages <- c(
  "dplyr",
  "lubridate",
  "purrr",
  "readr",
  "readxl",
  "redsan",
  "stringi",
  "stringr",
  "tibble",
  "tidyr"
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
    "Missing Rouen R packages: ",
    paste(missing_packages, collapse = ", "),
    call. = FALSE
  )
}

if (utils::packageVersion("redsan") < numeric_version("0.2.0")) {
  stop(
    "redsan 0.2.0 or newer is required; found ",
    as.character(utils::packageVersion("redsan")),
    ".",
    call. = FALSE
  )
}

config_path <- file.path("config", "rouen_raw_handoff.R")
if (!file.exists(config_path)) {
  stop("Missing Rouen adapter configuration: ", config_path, call. = FALSE)
}

config_environment <- new.env(parent = baseenv())
sys.source(config_path, envir = config_environment)
config <- config_environment$rouen_raw_handoff_config

is_nonempty_scalar_character <- function(value) {
  is.character(value) &&
    length(value) == 1L &&
    !is.na(value) &&
    nzchar(trimws(value))
}

if (!is.list(config)) {
  stop("Rouen adapter configuration must be a list.", call. = FALSE)
}
if (!is_nonempty_scalar_character(config$adapter_id)) {
  stop("Rouen adapter_id must be a non-empty string.", call. = FALSE)
}
if (
  !is.character(config$screening_typeana_codes) ||
    length(config$screening_typeana_codes) == 0L ||
    anyNA(config$screening_typeana_codes) ||
    any(!nzchar(trimws(config$screening_typeana_codes)))
) {
  stop(
    "Rouen screening_typeana_codes must contain non-empty strings.",
    call. = FALSE
  )
}
for (section in c("references", "mappings", "rules")) {
  if (!is.list(config[[section]])) {
    stop("Rouen config section must be a list: ", section, call. = FALSE)
  }
}

if (
  !inherits(config$target_start, "Date") ||
    length(config$target_start) != 1L ||
    is.na(config$target_start) ||
    !inherits(config$target_end_exclusive, "Date") ||
    length(config$target_end_exclusive) != 1L ||
    is.na(config$target_end_exclusive) ||
    config$target_start >= config$target_end_exclusive
) {
  stop(
    "Rouen target_start and target_end_exclusive must define a valid ",
    "half-open Date interval.",
    call. = FALSE
  )
}

configured_path_values <- list(
  establishment_structure =
    config$references$establishment_structure,
  codes_ta = config$references$codes_ta,
  codes_de = config$references$codes_de,
  unit_uf = file.path(config$references$unit_ref_dir, "ref_uf.txt"),
  unit_um = file.path(config$references$unit_ref_dir, "ref_um.txt"),
  unit_uf_to_um = file.path(
    config$references$unit_ref_dir,
    "ref_uf2um.txt"
  ),
  mapping_species = config$mappings$species,
  mapping_sample_type_rules = config$mappings$sample_type_rules,
  mapping_sample_type_decisions =
    config$mappings$sample_type_decisions,
  mapping_antibiotic = config$mappings$antibiotic,
  mapping_antibiotic_expansion =
    config$mappings$antibiotic_expansion,
  rule_supported_species_antibiotics =
    config$rules$supported_species_antibiotics
)
invalid_path_keys <- names(configured_path_values)[
  !vapply(
    configured_path_values,
    is_nonempty_scalar_character,
    logical(1)
  )
]
if (length(invalid_path_keys) > 0L) {
  stop(
    "Missing or invalid Rouen configuration path: ",
    paste(invalid_path_keys, collapse = ", "),
    call. = FALSE
  )
}
configured_paths <- unlist(configured_path_values, use.names = TRUE)
missing_paths <- configured_paths[
  !file.exists(configured_paths) |
    dir.exists(configured_paths)
]
if (length(missing_paths) > 0L) {
  stop(
    "Missing versioned Rouen configuration input: ",
    paste(missing_paths, collapse = ", "),
    call. = FALSE
  )
}

structure_path <- normalizePath(
  config$references$establishment_structure,
  winslash = "/",
  mustWork = TRUE
)

cat(
  "Window:    [",
  format(config$target_start),
  ", ",
  format(config$target_end_exclusive),
  ")\n",
  sep = ""
)
cat("Structure: ", structure_path, "\n", sep = "")
cat(
  "Screening: ",
  length(unique(config$screening_typeana_codes)),
  " versioned TYPEANA codes\n",
  sep = ""
)
cat(
  "Workflow:  retain bundle v3; project spares_current / ",
  "midnight_presence to operational bundle v2\n",
  sep = ""
)
