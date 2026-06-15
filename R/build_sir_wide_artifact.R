#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(stringr)
  library(lubridate)
  library(corpustools)
})

# -----------------------------------------------------------------------------
# Path and sourcing helpers
# -----------------------------------------------------------------------------
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

source_required_script <- function(script_name, what) {
  candidates <- c(file.path("R", script_name), script_name)
  existing <- candidates[file.exists(candidates)]
  if (length(existing) == 0L) {
    stop(
      "Missing ", what, ". Expected one of: ",
      paste(candidates, collapse = ", "),
      call. = FALSE
    )
  }
  source(existing[[1]])
  invisible(normalizePath(existing[[1]], winslash = "/", mustWork = TRUE))
}

source_required_config <- function(config_name, what) {
  candidates <- c(file.path("config", config_name), config_name)
  existing <- candidates[file.exists(candidates)]
  if (length(existing) == 0L) {
    stop(
      "Missing ", what, ". Expected one of: ",
      paste(candidates, collapse = ", "),
      call. = FALSE
    )
  }
  source(existing[[1]])
  invisible(normalizePath(existing[[1]], winslash = "/", mustWork = TRUE))
}

project_root <- resolve_project_root()
setwd(project_root)
source_required_config("pipeline.R", "pipeline config")

# -----------------------------------------------------------------------------
# Build configuration
# Edit config/pipeline.R to adapt the artifact builder to a new extraction window.
# -----------------------------------------------------------------------------
build_cfg <- orchidee_config$build$sir_wide
data_dir <- orchidee_config$paths$data_dir
dictionaries_dir <- orchidee_config$paths$dictionaries_dir

if (is.na(build_cfg$expected_bact_date_start) ||
    is.na(build_cfg$expected_bact_date_end) ||
    build_cfg$expected_bact_date_start > build_cfg$expected_bact_date_end) {
  stop(
    "Invalid build_cfg DATEPRELEV window: expected_bact_date_start must be <= expected_bact_date_end.",
    call. = FALSE
  )
}

# -----------------------------------------------------------------------------
# Lightweight text normalization helper used across mapping steps
# -----------------------------------------------------------------------------
strip_accents <- function(x) {
  if (is.factor(x)) x <- as.character(x)
  if (!is.character(x)) return(x)
  if (exists("rm_accent", mode = "function")) {
    return(rm_accent(x))
  }
  iconv(x, from = "", to = "ASCII//TRANSLIT")
}

source_required_script("helpers.R", "helpers script")
source_required_script("normalisation_bact.R", "normalisation_bact script")
source_required_script("normalisation_atb.R", "normalisation_atb script")
source_required_script("spares_shared_primitives.R", "spares_shared_primitives script")
source_required_script("phenotype_flag_helpers.R", "phenotype_flag_helpers script")

# -----------------------------------------------------------------------------
# Resolve all required inputs (raw extracts + dictionaries)
# -----------------------------------------------------------------------------
resolve_dictionary_path <- function(filename, what) {
  resolve_existing_path(
    c(
      file.path(dictionaries_dir, filename),
      filename,
      file.path(data_dir, filename)
    ),
    what = what
  )
}

pmsi_path <- resolve_existing_path(
  c("pmsi", file.path(data_dir, "pmsi")),
  what = "pmsi raw input"
)
bact_path <- resolve_existing_path(
  c("bact22_24", file.path(data_dir, "bact22_24")),
  what = "bact22_24 raw input"
)
atb_regex_map_path <- resolve_dictionary_path(
  "atb_regex_map.csv",
  what = "ATB regex mapping"
)
species_regex_map_path <- resolve_dictionary_path(
  "species_regex_map.csv",
  what = "species regex mapping"
)
naturepvt_regex_map_path <- resolve_dictionary_path(
  "naturepvt_regex_map.csv",
  what = "sample-site regex mapping"
)
couples_species_atb_path <- resolve_dictionary_path(
  "couples_species_atb.csv",
  what = "species-ATB couples mapping"
)
atb_expand_map_path <- resolve_dictionary_path(
  "atb_expand_map.csv",
  what = "ATB expansion mapping"
)
dictionary_root <- basename(dirname(couples_species_atb_path))

# -----------------------------------------------------------------------------
# Load raw extracts and enforce DATEPRELEV guardrails
# -----------------------------------------------------------------------------
# pmsi is loaded for upstream parity and metadata traceability.
pmsi <- readRDS(pmsi_path)
bact <- readRDS(bact_path)

coerce_to_date <- function(x) {
  if (inherits(x, "Date")) return(x)
  if (inherits(x, "POSIXt")) return(as.Date(x))
  suppressWarnings(as.Date(as.character(x)))
}

expected_bact_date_start <- build_cfg$expected_bact_date_start
expected_bact_date_end <- build_cfg$expected_bact_date_end

dateprelev_rows_before <- nrow(bact)
date_prelev_coerced <- coerce_to_date(bact$DATEPRELEV)
dateprelev_invalid_mask <- is.na(date_prelev_coerced)
dateprelev_out_of_window_mask <- !dateprelev_invalid_mask &
  (date_prelev_coerced < expected_bact_date_start | date_prelev_coerced > expected_bact_date_end)
dateprelev_drop_mask <- dateprelev_invalid_mask | dateprelev_out_of_window_mask
dateprelev_dropped_total <- sum(dateprelev_drop_mask)
dateprelev_dropped_invalid <- sum(dateprelev_invalid_mask)
dateprelev_dropped_out_of_window <- sum(dateprelev_out_of_window_mask)
dateprelev_dropped_year_counts <- table(
  lubridate::year(date_prelev_coerced[dateprelev_drop_mask]),
  useNA = "ifany"
)

bact <- bact %>%
  mutate(DATEPRELEV = date_prelev_coerced) %>%
  filter(!dateprelev_drop_mask)
dateprelev_rows_after <- nrow(bact)

if (dateprelev_rows_after == 0L) {
  stop(
    "No rows left in bact after DATEPRELEV filtering to [",
    expected_bact_date_start, ", ", expected_bact_date_end, "].",
    call. = FALSE
  )
}

if (isTRUE(build_cfg$fail_on_dropped_dateprelev_rows) && dateprelev_dropped_total > 0L) {
  stop(
    "DATEPRELEV guard dropped ", dateprelev_dropped_total, " rows. ",
    "Set build_cfg$fail_on_dropped_dateprelev_rows = FALSE to allow drop-and-continue mode.",
    call. = FALSE
  )
}

locked_screening_typeana <- c(
  "BGBLSE_R.BGBLSE_R2",
  "BGCARBA_R.BGCARBA_R2",
  "BGABMR_R.BGABMR_R2"
)

screening_required_cols <- c("ELTID", "TYPEANA", "LBLRES")
missing_screening_cols <- setdiff(screening_required_cols, names(bact))
if (length(missing_screening_cols) > 0L) {
  stop(
    "Cannot apply depistage exclusion. Missing columns: ",
    paste(missing_screening_cols, collapse = ", "),
    call. = FALSE
  )
}

screening_rows <- bact %>%
  filter(TYPEANA %in% locked_screening_typeana)

screening_eltid <- screening_rows %>%
  filter(!is.na(ELTID), ELTID != "") %>%
  distinct(ELTID) %>%
  pull(ELTID)

screening_drop_mask <- !is.na(bact$ELTID) & bact$ELTID %in% screening_eltid
screening_rows_before <- nrow(bact)
screening_rows_dropped <- sum(screening_drop_mask)
screening_sir_rows_dropped <- sum(screening_drop_mask & bact$LBLRES == "SIR", na.rm = TRUE)
screening_typeana_counts <- table(screening_rows$TYPEANA, useNA = "ifany")

bact <- bact %>%
  filter(!screening_drop_mask)
screening_rows_after <- nrow(bact)

if (screening_rows_after == 0L) {
  stop(
    "No rows left in bact after locked depistage ELTID exclusion.",
    call. = FALSE
  )
}

# -----------------------------------------------------------------------------
# Load and sanitize dictionaries
# -----------------------------------------------------------------------------
atb_regex_map <- read.csv(atb_regex_map_path, stringsAsFactors = FALSE)
species_regex_map <- read.csv(species_regex_map_path, stringsAsFactors = FALSE)
naturepvt_regex_map <- read.csv(naturepvt_regex_map_path, stringsAsFactors = FALSE) %>%
  transmute(
    pattern = as.character(pattern),
    naturepvt_norm = as.character(naturepvt_norm)
  ) %>%
  mutate(
    pattern = str_squish(pattern),
    naturepvt_norm = str_squish(naturepvt_norm)
  ) %>%
  filter(
    !is.na(pattern), pattern != "",
    !is.na(naturepvt_norm), naturepvt_norm != ""
  ) %>%
  distinct()
if (nrow(naturepvt_regex_map) == 0L) {
  stop("naturepvt_regex_map.csv is empty after cleaning.", call. = FALSE)
}
naturepvt_patterns <- stringr::regex(naturepvt_regex_map$pattern)
couples_species_atb <- read.csv(couples_species_atb_path, stringsAsFactors = FALSE) %>%
  transmute(
    bact_norm = as.character(bact_norm),
    atb_norm = as.character(atb_norm)
  ) %>%
  filter(
    !is.na(bact_norm), bact_norm != "",
    !is.na(atb_norm), atb_norm != ""
  ) %>%
  distinct()
if (nrow(couples_species_atb) == 0L) {
  stop("couples_species_atb.csv is empty after cleaning.", call. = FALSE)
}

atb_expand_map <- read.csv(atb_expand_map_path, stringsAsFactors = FALSE) %>%
  transmute(
    atb_norm_source = as.character(atb_norm_source),
    atb_norm_target = as.character(atb_norm_target)
  ) %>%
  filter(
    !is.na(atb_norm_source), atb_norm_source != "",
    !is.na(atb_norm_target), atb_norm_target != ""
  ) %>%
  distinct()

filtre_species <- sort(unique(couples_species_atb$bact_norm))
filtre_atb <- sort(unique(couples_species_atb$atb_norm))
expand_sources <- sort(unique(atb_expand_map$atb_norm_source))
atb_filter_base <- sort(unique(c(filtre_atb, expand_sources)))

missing_expand_targets <- setdiff(unique(atb_expand_map$atb_norm_target), filtre_atb)
if (length(missing_expand_targets) > 0L) {
  stop(
    "Expansion targets missing from couples dictionary: ",
    paste(missing_expand_targets, collapse = ", "),
    call. = FALSE
  )
}

# -----------------------------------------------------------------------------
# Core normalization pipeline: species -> ATB -> sample site
# -----------------------------------------------------------------------------
species_mapping_to_join_back <- normalize_bact(
  bact %>% distinct(IDENTIFICATION),
  species_regex_map
) %>%
  filter(!is.na(IDENTIFICATION))

bact_species_norm <- left_join(bact, species_mapping_to_join_back)

# Extend couples to all observed Enterobacterales species using E. coli ATB panel.
# This keeps dictionary-driven scope while avoiding silent exclusion of mapped
# Enterobacterales species not explicitly listed in couples_species_atb.csv.
ecoli_atb_panel <- couples_species_atb %>%
  filter(bact_norm == "escherichia_coli") %>%
  pull(atb_norm) %>%
  unique()
if (length(ecoli_atb_panel) == 0L) {
  stop(
    "Cannot extend Enterobacterales scope: no escherichia_coli ATB panel found in couples_species_atb.csv.",
    call. = FALSE
  )
}

observed_enterobacterales_species <- bact_species_norm %>%
  filter(
    !is.na(bact_order), bact_order == "Enterobacterales",
    !is.na(bact_norm), bact_norm != ""
  ) %>%
  distinct(bact_norm) %>%
  pull(bact_norm)

enterobacterales_missing_in_couples <- setdiff(
  observed_enterobacterales_species,
  unique(couples_species_atb$bact_norm)
)

if (length(enterobacterales_missing_in_couples) > 0L) {
  enterobacterales_added_pairs <- tidyr::crossing(
    bact_norm = sort(enterobacterales_missing_in_couples),
    atb_norm = sort(ecoli_atb_panel)
  )
  couples_species_atb <- bind_rows(couples_species_atb, enterobacterales_added_pairs) %>%
    distinct()
}

filtre_species <- sort(unique(couples_species_atb$bact_norm))
filtre_atb <- sort(unique(couples_species_atb$atb_norm))
expand_sources <- sort(unique(atb_expand_map$atb_norm_source))
atb_filter_base <- sort(unique(c(filtre_atb, expand_sources)))

atb_mapping_to_join_back <- normalise_atb(
  bact_species_norm %>%
    filter(LBLRES == "SIR") %>%
    distinct(LBLANA, LBLRES),
  atb_regex_map
)

bact_species_atb_norm <- left_join(bact_species_norm, distinct(atb_mapping_to_join_back))

bact_species_atb_norm <- bact_species_atb_norm %>%
  mutate(NATUREPVT = strip_accents(NATUREPVT))

naturepvt_lookup <- bact_species_atb_norm %>%
  distinct(NATUREPVT) %>%
  mutate(
    naturepvt_norm = dplyr::if_else(
      !is.na(NATUREPVT),
      naturepvt_regex_map$naturepvt_norm[purrr::map_int(
        NATUREPVT,
        ~ stringr::str_which(.x, naturepvt_patterns)[1]
      )],
      NA_character_
    )
  )

bact_species_atb_pvt_norm <- left_join(
  distinct(bact_species_atb_norm),
  distinct(naturepvt_lookup)
)

phenotype_key_cols <- c(
  "PATID", "EVTID", "ELTID", "DATEPRELEV", "souche_id", "bact_norm", "naturepvt_norm"
)
phenotype_status_lookup <- bact_species_atb_pvt_norm %>%
  rename(souche_id = DLVL) %>%
  mutate(naturepvt_norm = tolower(strip_accents(naturepvt_norm))) %>%
  build_phenotype_status_lookup(key_cols = phenotype_key_cols)

# -----------------------------------------------------------------------------
# Keep analysis-relevant rows and harmonize core fields
# -----------------------------------------------------------------------------
bact_norm <- bact_species_atb_pvt_norm %>%
  filter(LBLRES %in% c("Isolat et commentaire germe", "SIR")) %>%
  rename(souche_id = DLVL) %>%
  mutate(
    across(everything(), strip_accents),
    STRRES = case_when(
      STRRES == "SFP" ~ "S",
      STRRES == "I" ~ "ZIT",
      STRRES == "---R" ~ "R",
      STRRES == "NC" ~ NA_character_,
      TRUE ~ STRRES
    )
  ) %>%
  filter(!is.na(STRRES)) %>%
  arrange(PATID, EVTID, ELTID, TRI) %>%
  select(
    PATID, EVTID, ELTID, DATEPRELEV, HEUREPRELEV, NATUREPVT, naturepvt_norm,
    souche_id, IDENTIFICATION, bact_norm, TRI, atb_norm, LBLRES, STRRES,
    atb_match_origin, atb_family, atb_subfamily, bact_order, bact_family,
    bact_genus, taxon_type, PATAGE, PATSEX, CASFM, SEJUM, SEJUF, TYPEANA, bact_matched,
    atb_matched, NUMRES, CMI, ST, LBLANA
  )

# -----------------------------------------------------------------------------
# Build SIR long table and apply explicit + expanded ATB dictionary logic
# -----------------------------------------------------------------------------
sir_long_base <- bact_norm %>%
  ungroup() %>%
  filter(
    LBLRES == "SIR",
    !is.na(STRRES),
    STRRES != "",
    bact_norm %in% filtre_species,
    atb_norm %in% atb_filter_base
  ) %>%
  mutate(
    atb_match_origin = if_else(is.na(atb_match_origin), "explicit", atb_match_origin)
  ) %>%
  distinct()

sir_long_expanded <- sir_long_base %>%
  inner_join(atb_expand_map, by = c("atb_norm" = "atb_norm_source")) %>%
  mutate(
    atb_norm = atb_norm_target,
    atb_match_origin = "expanded"
  ) %>%
  select(-atb_norm_target)

sir_long <- bind_rows(sir_long_base, sir_long_expanded) %>%
  semi_join(couples_species_atb, by = c("bact_norm", "atb_norm")) %>%
  mutate(.origin_rank = if_else(atb_match_origin == "explicit", 1L, 0L)) %>%
  arrange(
    PATID, EVTID, ELTID, DATEPRELEV, HEUREPRELEV, souche_id,
    bact_norm, atb_norm, .origin_rank, TRI
  ) %>%
  select(-.origin_rank) %>%
  distinct()

# -----------------------------------------------------------------------------
# Pivot to wide format and compute deterministic ordering keys
# -----------------------------------------------------------------------------
stopifnot(exists(".spares_time_sort_key", mode = "function"))
normalize_time_key <- function(x) .spares_time_sort_key(x)
ensure_supported_atb_cols <- function(df, supported_cols) {
  missing_cols <- setdiff(supported_cols, names(df))
  if (length(missing_cols) > 0L) {
    df[missing_cols] <- NA_character_
  }
  df
}

collapse_unique_or_na <- function(x) {
  vals <- sort(unique(x[!is.na(x) & nzchar(x)]))
  if (length(vals) == 0L) {
    return(NA_character_)
  }
  paste(vals, collapse = "|")
}

sample_attribute_lookup <- sir_long %>%
  mutate(naturepvt_norm = tolower(strip_accents(naturepvt_norm))) %>%
  group_by(across(all_of(phenotype_key_cols))) %>%
  summarise(
    SEJUF = collapse_unique_or_na(SEJUF),
    SEJUM = collapse_unique_or_na(SEJUM),
    TYPEANA = collapse_unique_or_na(TYPEANA),
    .groups = "drop"
  )

sir_wide <- sir_long %>%
  ungroup() %>%
  mutate(naturepvt_norm = tolower(strip_accents(naturepvt_norm))) %>%
  select(any_of(c(
    "PATID", "EVTID", "ELTID", "DATEPRELEV", "HEUREPRELEV", "souche_id",
    "naturepvt_norm", "bact_norm", "atb_norm", "STRRES"
  ))) %>%
  pivot_wider(
    names_from = atb_norm,
    values_from = STRRES,
    values_fn = ~ dplyr::last(na.omit(.x)),
    values_fill = NA_character_
  ) %>%
  ensure_supported_atb_cols(filtre_atb) %>%
  left_join(sample_attribute_lookup, by = phenotype_key_cols) %>%
  left_join(phenotype_status_lookup, by = phenotype_key_cols) %>%
  mutate(
    blse_status_row = dplyr::coalesce(blse_status_row, "no_signal"),
    carbapenemase_status_row = dplyr::coalesce(carbapenemase_status_row, "no_signal"),
    blse_flag = dplyr::coalesce(blse_flag, FALSE),
    carbapenemase_flag = dplyr::coalesce(carbapenemase_flag, FALSE),
    nb_resultats = rowSums(across(any_of(filtre_atb), ~ .x %in% c("S", "R")), na.rm = TRUE)
  ) %>%
  relocate(nb_resultats, .after = souche_id)

required_order_cols <- c("PATID", "EVTID", "ELTID", "DATEPRELEV")
missing_required <- setdiff(required_order_cols, names(sir_wide))
if (length(missing_required) > 0L) {
  stop(
    "Missing required columns for evt/elt ordering: ",
    paste(missing_required, collapse = ", "),
    call. = FALSE
  )
}

if (!"HEUREPRELEV" %in% names(sir_wide)) {
  sir_wide$HEUREPRELEV <- NA_character_
}

sir_wide <- sir_wide %>%
  mutate(
    .row_id_tmp = row_number(),
    .date_sort = as.Date(DATEPRELEV),
    .time_sort = normalize_time_key(HEUREPRELEV)
  )

evt_order_tbl <- sir_wide %>%
  group_by(PATID, EVTID) %>%
  arrange(
    is.na(.date_sort), .date_sort, is.na(.time_sort), .time_sort,
    ELTID, .row_id_tmp, .by_group = TRUE
  ) %>%
  slice_head(n = 1) %>%
  ungroup() %>%
  group_by(PATID) %>%
  arrange(
    is.na(.date_sort), .date_sort, is.na(.time_sort), .time_sort,
    EVTID, .by_group = TRUE
  ) %>%
  mutate(evt_order = row_number()) %>%
  ungroup() %>%
  select(PATID, EVTID, evt_order)

elt_order_tbl <- sir_wide %>%
  group_by(PATID, EVTID, ELTID) %>%
  arrange(is.na(.date_sort), .date_sort, is.na(.time_sort), .time_sort, .row_id_tmp, .by_group = TRUE) %>%
  slice_head(n = 1) %>%
  ungroup() %>%
  group_by(PATID, EVTID) %>%
  arrange(is.na(.date_sort), .date_sort, is.na(.time_sort), .time_sort, ELTID, .by_group = TRUE) %>%
  mutate(elt_order = row_number()) %>%
  ungroup() %>%
  select(PATID, EVTID, ELTID, elt_order)

sir_wide <- sir_wide %>%
  left_join(evt_order_tbl, by = c("PATID", "EVTID")) %>%
  left_join(elt_order_tbl, by = c("PATID", "EVTID", "ELTID")) %>%
  arrange(
    PATID, evt_order, elt_order,
    is.na(.date_sort), .date_sort,
    is.na(.time_sort), .time_sort,
    naturepvt_norm, bact_norm, souche_id,
    desc(nb_resultats),
    ELTID, .row_id_tmp
  ) %>%
  select(-.row_id_tmp, -.date_sort, -.time_sort)

# -----------------------------------------------------------------------------
# Detect final ATB columns and compute artifact freshness signature
# -----------------------------------------------------------------------------
candidate_atb <- intersect(filtre_atb, names(sir_wide))
supported_atb_cols <- candidate_atb
is_atb_col <- function(x) {
  ux <- unique(na.omit(as.character(x)))
  length(ux) > 0L && all(ux %in% c("S", "R", "ZIT"))
}
atb_cols <- supported_atb_cols[vapply(sir_wide[supported_atb_cols], is_atb_col, logical(1))]
if (length(atb_cols) == 0L) {
  stop("No ATB columns detected in built sir_wide artifact.", call. = FALSE)
}
if (!setequal(supported_atb_cols, filtre_atb)) {
  stop("Supported ATB columns in sir_wide do not match filtre_atb.", call. = FALSE)
}

script_paths <- vapply(
  c("helpers.R", "normalisation_bact.R", "normalisation_atb.R", "spares_shared_primitives.R", "phenotype_flag_helpers.R"),
  function(x) resolve_existing_path(c(file.path("R", x), x), what = paste0("script ", x)),
  character(1)
)

upstream_signature <- compute_upstream_signature(
  raw_input_paths = c(pmsi_path, bact_path),
  hashed_paths = c(
    script_paths,
    atb_regex_map_path,
    species_regex_map_path,
    naturepvt_regex_map_path,
    couples_species_atb_path,
    atb_expand_map_path
  )
)

pkg_version_safe <- function(pkg) {
  if (requireNamespace(pkg, quietly = TRUE)) as.character(utils::packageVersion(pkg)) else NA_character_
}

named_int_list <- function(x) {
  if (length(x) == 0L) return(list())
  vals <- as.integer(x)
  nms <- names(x)
  if (is.null(nms)) nms <- as.character(seq_along(vals))
  nms[is.na(nms)] <- "NA"
  stats::setNames(as.list(vals), nms)
}

# -----------------------------------------------------------------------------
# Assemble metadata (including guard audit and builder configuration)
# -----------------------------------------------------------------------------
sir_wide_meta <- list(
  artifact_version = 4L,
  created_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
  sir_wide_n_rows = nrow(sir_wide),
  sir_wide_n_eltid = dplyr::n_distinct(sir_wide$ELTID),
  atb_cols = atb_cols,
  supported_atb_cols = supported_atb_cols,
  phenotype_status_cols = c("blse_status_row", "carbapenemase_status_row"),
  phenotype_flag_cols = c("blse_flag", "carbapenemase_flag"),
  filtre_atb = filtre_atb,
  couples_n_pairs = nrow(couples_species_atb),
  couples_species = filtre_species,
  dictionary_root = dictionary_root,
  dateprelev_guard = list(
    expected_start = as.character(expected_bact_date_start),
    expected_end = as.character(expected_bact_date_end),
    rows_before = dateprelev_rows_before,
    rows_after = dateprelev_rows_after,
    dropped_total = dateprelev_dropped_total,
    dropped_invalid = dateprelev_dropped_invalid,
    dropped_out_of_window = dateprelev_dropped_out_of_window,
    dropped_year_counts = named_int_list(dateprelev_dropped_year_counts)
  ),
  depistage_guard = list(
    rule = "exclude_whole_eltid_when_typeana_in_locked_screening_codes",
    locked_typeana = locked_screening_typeana,
    rows_before = screening_rows_before,
    rows_after = screening_rows_after,
    dropped_rows = screening_rows_dropped,
    dropped_eltid = length(screening_eltid),
    dropped_sir_rows = screening_sir_rows_dropped,
    screening_typeana_counts = named_int_list(screening_typeana_counts)
  ),
  builder_config = list(
    expected_bact_date_start = as.character(expected_bact_date_start),
    expected_bact_date_end = as.character(expected_bact_date_end),
    fail_on_dropped_dateprelev_rows = isTRUE(build_cfg$fail_on_dropped_dateprelev_rows)
  ),
  upstream_signature = upstream_signature,
  builder_session = list(
    r_version = R.version.string,
    platform = R.version$platform,
    package_versions = c(
      dplyr = pkg_version_safe("dplyr"),
      tidyr = pkg_version_safe("tidyr"),
      stringr = pkg_version_safe("stringr"),
      purrr = pkg_version_safe("purrr"),
      lubridate = pkg_version_safe("lubridate")
    )
  )
)

if (!dir.exists(data_dir)) {
  dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
}

# -----------------------------------------------------------------------------
# Persist artifact + metadata, then print a compact build summary
# -----------------------------------------------------------------------------
sir_wide_path <- file.path(data_dir, "sir_wide.rds")
sir_wide_meta_path <- file.path(data_dir, "sir_wide_meta.rds")
saveRDS(sir_wide, sir_wide_path)
saveRDS(sir_wide_meta, sir_wide_meta_path)

date_range <- suppressWarnings(range(as.Date(sir_wide$DATEPRELEV), na.rm = TRUE))
if (!all(is.finite(as.numeric(date_range)))) {
  date_range <- c(NA, NA)
}

cat("Built sir_wide artifact successfully.\n")
cat(" - rows: ", nrow(sir_wide), "\n", sep = "")
cat(" - distinct ELTID: ", dplyr::n_distinct(sir_wide$ELTID), "\n", sep = "")
cat(" - supported ATB columns: ", length(supported_atb_cols), "\n", sep = "")
cat(" - observed ATB columns: ", length(atb_cols), "\n", sep = "")
cat(" - date range: ", as.character(date_range[[1]]), " to ", as.character(date_range[[2]]), "\n", sep = "")
cat(
  " - DATEPRELEV guard: kept ", dateprelev_rows_after, "/", dateprelev_rows_before,
  " rows in [", as.character(expected_bact_date_start), ", ", as.character(expected_bact_date_end), "]",
  " (dropped=", dateprelev_dropped_total,
  ", invalid=", dateprelev_dropped_invalid,
  ", out_of_window=", dateprelev_dropped_out_of_window, ")\n",
  sep = ""
)
if (length(dateprelev_dropped_year_counts) > 0L) {
  dropped_years_report <- paste0(
    names(dateprelev_dropped_year_counts), "=",
    as.integer(dateprelev_dropped_year_counts),
    collapse = ", "
  )
  cat(" - dropped DATEPRELEV years: ", dropped_years_report, "\n", sep = "")
}
cat(
  " - depistage guard: dropped ", screening_rows_dropped, " rows across ",
  length(screening_eltid), " ELTID",
  " (SIR rows dropped=", screening_sir_rows_dropped, ")\n",
  sep = ""
)
cat(" - output: ", normalizePath(sir_wide_path, winslash = "/", mustWork = TRUE), "\n", sep = "")
cat(" - metadata: ", normalizePath(sir_wide_meta_path, winslash = "/", mustWork = TRUE), "\n", sep = "")
cat(" - loaded pmsi rows: ", nrow(pmsi), "\n", sep = "")


