## Rennes/external-site handoff helpers.
##
## These helpers build ORCHIDEE's canonical runtime bundle from simpler,
## site-owned input blocks. They deliberately sit upstream of the canonical
## runtime contract validated in `R/external_bundle_validation_helpers.R`.

orchidee_handoff_trim_or_na <- function(x) {
  x <- trimws(as.character(x))
  x[!nzchar(x)] <- NA_character_
  x
}

orchidee_handoff_detect_delimiter <- function(path) {
  header <- readLines(path, n = 1L, warn = FALSE, encoding = "UTF-8")
  if (length(header) == 0L) {
    stop("Empty delimited file: ", path, call. = FALSE)
  }
  header <- sub("^\ufeff", "", header[[1]], useBytes = TRUE)
  n_semicolon <- lengths(regmatches(header, gregexpr(";", header, fixed = TRUE)))
  n_comma <- lengths(regmatches(header, gregexpr(",", header, fixed = TRUE)))
  if (n_semicolon > n_comma) ";" else ","
}

orchidee_handoff_read_table <- function(path) {
  if (!file.exists(path)) {
    stop("Missing handoff input file: ", path, call. = FALSE)
  }

  ext <- tolower(tools::file_ext(path))
  if (identical(ext, "rds")) {
    return(readRDS(path))
  }

  if (ext %in% c("csv", "txt")) {
    delimiter <- orchidee_handoff_detect_delimiter(path)
    return(utils::read.table(
      file = path,
      header = TRUE,
      sep = delimiter,
      quote = "\"",
      comment.char = "",
      stringsAsFactors = FALSE,
      check.names = FALSE,
      fill = TRUE,
      colClasses = "character",
      fileEncoding = "UTF-8"
    ))
  }

  if (ext %in% c("tsv", "tab")) {
    return(utils::read.delim(
      file = path,
      stringsAsFactors = FALSE,
      check.names = FALSE,
      colClasses = "character",
      fileEncoding = "UTF-8"
    ))
  }

  stop(
    "Unsupported handoff input extension for ",
    path,
    ". Use .rds, .csv, .tsv, .tab, or .txt.",
    call. = FALSE
  )
}

orchidee_handoff_require_functions <- function(required_funs) {
  missing <- required_funs[!vapply(required_funs, exists, logical(1), mode = "function")]
  if (length(missing) > 0L) {
    stop(
      "Missing required helper functions: ",
      paste(missing, collapse = ", "),
      ". Source the relevant ORCHIDEE helper scripts first.",
      call. = FALSE
    )
  }
}

orchidee_handoff_integerish_vector <- function(x, col_name) {
  if (is.factor(x)) x <- as.character(x)

  if (is.numeric(x)) {
    bad <- is.na(x) | !is.finite(x) |
      abs(x - round(x)) >= sqrt(.Machine$double.eps)
    if (any(bad)) {
      stop(col_name, " must contain non-missing integer-like values.", call. = FALSE)
    }
    return(as.integer(x))
  }

  if (is.character(x)) {
    x <- orchidee_handoff_trim_or_na(x)
    bad <- is.na(x) | !grepl("^-?[0-9]+$", x)
    if (any(bad)) {
      stop(col_name, " must contain non-missing integer-like values.", call. = FALSE)
    }
    return(as.integer(x))
  }

  stop(col_name, " must be numeric/integer-like or character integer values.", call. = FALSE)
}

orchidee_handoff_logical_vector <- function(x, col_name) {
  if (is.logical(x)) {
    if (any(is.na(x))) {
      stop(col_name, " must not contain missing values.", call. = FALSE)
    }
    return(x)
  }

  if (is.numeric(x)) {
    bad <- is.na(x) | !x %in% c(0, 1)
    if (any(bad)) {
      stop(col_name, " must contain TRUE/FALSE or 1/0 values.", call. = FALSE)
    }
    return(x == 1)
  }

  x_chr <- orchidee_handoff_ascii_lower(x)
  out <- dplyr::case_when(
    x_chr %in% c("true", "t", "1", "yes", "y", "oui", "o") ~ TRUE,
    x_chr %in% c("false", "f", "0", "no", "n", "non") ~ FALSE,
    TRUE ~ NA
  )
  if (any(is.na(out))) {
    stop(col_name, " must contain TRUE/FALSE or 1/0 values.", call. = FALSE)
  }
  out
}

orchidee_handoff_domain_key <- function(x) {
  x <- orchidee_handoff_trim_or_na(x)
  x <- iconv(x, from = "", to = "ASCII//TRANSLIT")
  toupper(x)
}

orchidee_handoff_normalize_included_de_domain <- function(x) {
  orchidee_handoff_require_functions("ratb_included_ta_de_domains")
  included_domains <- ratb_included_ta_de_domains()
  domain_key <- orchidee_handoff_domain_key(x)
  included_key <- orchidee_handoff_domain_key(included_domains)
  matched <- included_domains[match(domain_key, included_key)]
  ifelse(is.na(matched), orchidee_handoff_trim_or_na(x), matched)
}

orchidee_handoff_ascii_lower <- function(x) {
  x <- orchidee_handoff_trim_or_na(x)
  x <- iconv(x, from = "", to = "ASCII//TRANSLIT")
  tolower(x)
}

orchidee_handoff_parse_date <- function(x, col_name = "DATEPRELEV") {
  if (inherits(x, "Date")) {
    return(x)
  }
  if (is.factor(x)) x <- as.character(x)
  if (is.numeric(x)) {
    out <- as.Date(x, origin = "1970-01-01")
  } else {
    x_chr <- orchidee_handoff_trim_or_na(x)
    out <- as.Date(x_chr)
    bad <- is.na(out) & !is.na(x_chr)
    if (any(bad)) {
      out[bad] <- as.Date(x_chr[bad], format = "%d/%m/%Y")
    }
  }
  bad <- is.na(out)
  if (any(bad)) {
    stop(col_name, " must contain non-missing dates.", call. = FALSE)
  }
  out
}

orchidee_handoff_parse_time <- function(x, col_name = "HEUREPRELEV") {
  if (inherits(x, "difftime")) {
    return(x)
  }
  if (missing(x) || is.null(x)) {
    return(as.difftime(rep(NA_real_, 0L), units = "secs"))
  }
  if (is.factor(x)) x <- as.character(x)
  if (is.numeric(x)) {
    return(as.difftime(x, units = "secs"))
  }

  x_chr <- orchidee_handoff_trim_or_na(x)
  out <- as.difftime(rep(NA_real_, length(x_chr)), units = "secs")
  has_value <- !is.na(x_chr)
  hh_mm <- has_value & grepl("^[0-9]{1,2}:[0-9]{2}$", x_chr)
  x_chr[hh_mm] <- paste0(x_chr[hh_mm], ":00")
  has_value <- !is.na(x_chr)
  parsed <- suppressWarnings(as.difftime(x_chr[has_value], format = "%H:%M:%S"))
  out[has_value] <- parsed
  bad <- has_value & is.na(out)
  if (any(bad)) {
    stop(col_name, " must use HH:MM or HH:MM:SS when provided.", call. = FALSE)
  }
  out
}

orchidee_handoff_normalize_sir <- function(x) {
  x <- toupper(orchidee_handoff_trim_or_na(x))
  dplyr::case_when(
    x %in% c("S", "SFP", "---S") ~ "S",
    x %in% c("R", "---R") ~ "R",
    x %in% c("I", "ZIT") ~ "ZIT",
    x %in% c("NC", "NA", "N/A") | is.na(x) ~ NA_character_,
    TRUE ~ x
  )
}

orchidee_handoff_prepare_mapping <- function(
    mapping,
    local_col,
    canonical_col,
    label,
    allow_missing_canonical = FALSE
  ) {
  if (!is.data.frame(mapping)) {
    stop(label, " must be a data frame.", call. = FALSE)
  }
  required_cols <- c(local_col, canonical_col)
  missing_cols <- setdiff(required_cols, names(mapping))
  if (length(missing_cols) > 0L) {
    stop(
      label, " is missing required columns: ",
      paste(missing_cols, collapse = ", "),
      call. = FALSE
    )
  }

  out <- data.frame(
    local_key = orchidee_handoff_trim_or_na(mapping[[local_col]]),
    canonical_value = orchidee_handoff_trim_or_na(mapping[[canonical_col]]),
    stringsAsFactors = FALSE
  )
  out <- out[!is.na(out$local_key), , drop = FALSE]
  if (!isTRUE(allow_missing_canonical) && any(is.na(out$canonical_value))) {
    stop(label, " contains missing canonical values.", call. = FALSE)
  }
  duplicated_keys <- unique(out$local_key[duplicated(out$local_key)])
  if (length(duplicated_keys) > 0L) {
    conflicting_keys <- duplicated_keys[vapply(duplicated_keys, function(key) {
      values <- out$canonical_value[out$local_key == key]
      values_for_compare <- ifelse(is.na(values), "<missing>", values)
      length(unique(values_for_compare)) > 1L
    }, logical(1))]
    if (length(conflicting_keys) > 0L) {
      stop(
        label, " contains duplicate local keys with conflicting canonical values: ",
        paste(utils::head(conflicting_keys, 10L), collapse = ", "),
        if (length(conflicting_keys) > 10L) ", ..." else "",
        call. = FALSE
      )
    }
    out <- out[!duplicated(out$local_key), , drop = FALSE]
  }
  out
}

orchidee_handoff_map_values <- function(
    x,
    mapping,
    label,
    allow_missing_canonical = FALSE
  ) {
  x_key <- orchidee_handoff_trim_or_na(x)
  match_idx <- match(x_key, mapping$local_key)
  missing_map <- is.na(match_idx) & !is.na(x_key)
  if (any(missing_map)) {
    missing_values <- sort(unique(x_key[missing_map]))
    stop(
      label, " has unmapped values: ",
      paste(utils::head(missing_values, 10L), collapse = ", "),
      if (length(missing_values) > 10L) ", ..." else "",
      call. = FALSE
    )
  }

  mapped <- mapping$canonical_value[match_idx]
  if (!isTRUE(allow_missing_canonical)) {
    missing_canonical <- is.na(mapped) & !is.na(x_key)
    if (any(missing_canonical)) {
      missing_values <- sort(unique(x_key[missing_canonical]))
      stop(
        label, " maps to missing canonical values: ",
        paste(utils::head(missing_values, 10L), collapse = ", "),
        if (length(missing_values) > 10L) ", ..." else "",
        call. = FALSE
      )
    }
  }

  mapped
}

orchidee_handoff_collapse_phenotype <- function(x, allowed, col_name) {
  orchidee_handoff_require_functions(c(
    "normalize_phenotype_status",
    "collapse_phenotype_status"
  ))
  status <- normalize_phenotype_status(x)
  bad <- is.na(status) & !is.na(orchidee_handoff_trim_or_na(x))
  if (any(bad)) {
    bad_vals <- sort(unique(as.character(x)[bad]))
    stop(
      col_name, " contains unsupported phenotype statuses: ",
      paste(utils::head(bad_vals, 10L), collapse = ", "),
      if (length(bad_vals) > 10L) ", ..." else "",
      call. = FALSE
    )
  }
  out <- collapse_phenotype_status(status)
  if (!out %in% allowed) {
    stop(col_name, " collapsed to unsupported value: ", out, call. = FALSE)
  }
  out
}

orchidee_handoff_build_sir_wide_from_microbiology <- function(
    microbiology_observations,
    bacteria_mapping,
    sample_type_mapping,
    antibiotic_mapping,
    contract = orchidee_external_contract_v2()
  ) {
  orchidee_handoff_require_functions("phenotype_status_to_flag")
  if (!is.data.frame(microbiology_observations)) {
    stop("microbiology_observations must be a data frame.", call. = FALSE)
  }
  if (!is.list(contract)) {
    stop("contract must be a list.", call. = FALSE)
  }

  required_obs_cols <- c(
    "PATID", "ELTID", "DATEPRELEV", "SEJUF",
    "bacteria_local", "sample_type_local", "antibiotic_local", "sir_result"
  )
  missing_obs_cols <- setdiff(required_obs_cols, names(microbiology_observations))
  if (length(missing_obs_cols) > 0L) {
    stop(
      "microbiology_observations is missing required columns: ",
      paste(missing_obs_cols, collapse = ", "),
      call. = FALSE
    )
  }
  diagnostic_cols <- c("ratb_diagnostic_scope", "diagnostic_scope", "is_diagnostic")
  diagnostic_col <- diagnostic_cols[diagnostic_cols %in% names(microbiology_observations)][1]
  if (is.na(diagnostic_col)) {
    stop(
      "microbiology_observations must contain ratb_diagnostic_scope ",
      "(or diagnostic_scope/is_diagnostic) so screening rows are explicit.",
      call. = FALSE
    )
  }

  bacteria_map <- orchidee_handoff_prepare_mapping(
    bacteria_mapping,
    "bacteria_local",
    "bact_norm",
    "bacteria_mapping"
  )
  sample_type_map <- orchidee_handoff_prepare_mapping(
    sample_type_mapping,
    "sample_type_local",
    "naturepvt_norm",
    "sample_type_mapping",
    allow_missing_canonical = TRUE
  )
  antibiotic_map <- orchidee_handoff_prepare_mapping(
    antibiotic_mapping,
    "antibiotic_local",
    "atb_norm",
    "antibiotic_mapping"
  )

  obs <- microbiology_observations
  diagnostic_scope <- orchidee_handoff_logical_vector(
    obs[[diagnostic_col]],
    paste0("microbiology_observations$", diagnostic_col)
  )
  obs$PATID <- orchidee_handoff_trim_or_na(obs$PATID)
  obs$EVTID <- if ("EVTID" %in% names(obs)) {
    orchidee_handoff_trim_or_na(obs$EVTID)
  } else {
    rep(NA_character_, nrow(obs))
  }
  obs$ELTID <- orchidee_handoff_trim_or_na(obs$ELTID)

  # Screening exclusion follows the most specific usable document identity.
  # Complete PATID + ELTID groups use PATID + EVTID + ELTID. If any row in a
  # PATID + ELTID group lacks EVTID, that group conservatively falls back to
  # PATID + ELTID. ELTID alone is never propagated across patients.
  has_patient_sample <- !is.na(obs$PATID) & !is.na(obs$ELTID)
  propagate_screening <- rep(FALSE, nrow(obs))
  valid_scope_rows <- which(has_patient_sample)
  if (length(valid_scope_rows) > 0L) {
    patient_sample_key <- paste(
      obs$PATID[valid_scope_rows],
      obs$ELTID[valid_scope_rows],
      sep = "\r"
    )
    fallback_to_patient_sample <- ave(
      is.na(obs$EVTID[valid_scope_rows]),
      patient_sample_key,
      FUN = any
    )
    document_key <- ifelse(
      fallback_to_patient_sample,
      paste(
        "patient_sample",
        obs$PATID[valid_scope_rows],
        obs$ELTID[valid_scope_rows],
        sep = "\r"
      ),
      paste(
        "event_sample",
        obs$PATID[valid_scope_rows],
        obs$EVTID[valid_scope_rows],
        obs$ELTID[valid_scope_rows],
        sep = "\r"
      )
    )
    screening_document_keys <- unique(
      document_key[!diagnostic_scope[valid_scope_rows]]
    )
    propagate_screening[valid_scope_rows] <-
      document_key %in% screening_document_keys
  }

  drop_mask <- (!diagnostic_scope) | propagate_screening
  obs <- obs[!drop_mask, , drop = FALSE]
  if (nrow(obs) == 0L) {
    stop(
      "No rows remain after excluding screening document occurrences from ",
      "microbiology_observations (", diagnostic_col, " exclusion).",
      call. = FALSE
    )
  }

  obs$DATEPRELEV <- orchidee_handoff_parse_date(obs$DATEPRELEV)
  obs$HEUREPRELEV <- if ("HEUREPRELEV" %in% names(obs)) {
    orchidee_handoff_parse_time(obs$HEUREPRELEV)
  } else {
    as.difftime(rep(NA_real_, nrow(obs)), units = "secs")
  }
  obs$souche_id <- if ("souche_id" %in% names(obs)) {
    orchidee_handoff_trim_or_na(obs$souche_id)
  } else if ("isolate_local_id" %in% names(obs)) {
    orchidee_handoff_trim_or_na(obs$isolate_local_id)
  } else {
    rep(NA_character_, nrow(obs))
  }
  obs$SEJUF <- orchidee_handoff_trim_or_na(obs$SEJUF)
  obs$bact_norm <- orchidee_handoff_map_values(
    obs$bacteria_local,
    bacteria_map,
    "microbiology_observations$bacteria_local"
  )
  obs$naturepvt_norm <- orchidee_handoff_ascii_lower(orchidee_handoff_map_values(
    obs$sample_type_local,
    sample_type_map,
    "microbiology_observations$sample_type_local",
    allow_missing_canonical = TRUE
  ))
  obs$atb_norm <- orchidee_handoff_map_values(
    obs$antibiotic_local,
    antibiotic_map,
    "microbiology_observations$antibiotic_local"
  )
  obs$sir_result <- orchidee_handoff_normalize_sir(obs$sir_result)

  missing_souche <- is.na(obs$souche_id)
  if (any(missing_souche)) {
    sample_type_for_souche <- dplyr::coalesce(
      obs$naturepvt_norm[missing_souche],
      "missing_sample_type"
    )
    obs$souche_id[missing_souche] <- paste(
      "derived",
      sample_type_for_souche,
      obs$bact_norm[missing_souche],
      sep = "__"
    )
  }

  non_missing_key_cols <- c("PATID", "ELTID", "DATEPRELEV", "souche_id", "bact_norm")
  key_na <- vapply(non_missing_key_cols, function(col) any(is.na(obs[[col]])), logical(1))
  if (any(key_na)) {
    stop(
      "microbiology_observations required non-missing fields contain NA: ",
      paste(non_missing_key_cols[key_na], collapse = ", "),
      call. = FALSE
    )
  }

  supported_atb <- contract$sir_wide$atb_cols
  unsupported_atb <- setdiff(unique(obs$atb_norm[!is.na(obs$atb_norm)]), supported_atb)
  if (length(unsupported_atb) > 0L) {
    stop(
      "antibiotic_mapping maps to unsupported ORCHIDEE ATB columns: ",
      paste(unsupported_atb, collapse = ", "),
      call. = FALSE
    )
  }
  unsupported_sir <- setdiff(unique(obs$sir_result[!is.na(obs$sir_result)]), contract$sir_wide$allowed_atb_values)
  if (length(unsupported_sir) > 0L) {
    stop(
      "microbiology_observations$sir_result contains unsupported values: ",
      paste(unsupported_sir, collapse = ", "),
      call. = FALSE
    )
  }

  row_key_cols <- contract$sir_wide$row_grain_key
  row_key <- do.call(paste, c(obs[row_key_cols], sep = "\r"))
  row_key_levels <- unique(row_key)
  row_id <- match(row_key, row_key_levels)
  row_groups <- unname(split(
    seq_len(nrow(obs)),
    factor(row_id, levels = seq_along(row_key_levels))
  ))

  for (attr_col in c("SEJUF", "HEUREPRELEV")) {
    attr_conflict <- vapply(row_groups, function(idx) {
      vals <- obs[[attr_col]][idx]
      vals <- vals[!is.na(vals)]
      length(unique(vals)) > 1L
    }, logical(1))
    if (any(attr_conflict)) {
      stop(
        "microbiology_observations has conflicting ", attr_col,
        " values within the same ORCHIDEE row key.",
        call. = FALSE
      )
    }
  }

  row_base_idx <- match(row_key_levels, row_key)
  sir_wide <- obs[row_base_idx, c(
    "PATID", "EVTID", "ELTID", "DATEPRELEV", "HEUREPRELEV", "souche_id",
    "naturepvt_norm", "bact_norm", "SEJUF"
  ), drop = FALSE]
  sir_wide$SEJUF <- vapply(row_groups, function(idx) {
    vals <- obs$SEJUF[idx]
    vals <- vals[!is.na(vals)]
    if (length(vals) == 0L) NA_character_ else vals[[1L]]
  }, character(1))
  sir_wide$HEUREPRELEV <- as.difftime(vapply(row_groups, function(idx) {
    vals <- obs$HEUREPRELEV[idx]
    vals <- vals[!is.na(vals)]
    if (length(vals) == 0L) NA_real_ else as.numeric(vals[[1L]], units = "secs")
  }, numeric(1)), units = "secs")

  sir_matrix <- matrix(
    NA_character_,
    nrow = nrow(sir_wide),
    ncol = length(supported_atb),
    dimnames = list(NULL, supported_atb)
  )
  result_rows <- which(!is.na(obs$atb_norm) & !is.na(obs$sir_result))
  if (length(result_rows) > 0L) {
    result_key <- paste(row_id[result_rows], obs$atb_norm[result_rows], sep = "\r")
    split_rows <- split(result_rows, result_key)
    for (idx in split_rows) {
      # Mirror the current CHU pivot rule: keep the last non-missing value.
      vals <- obs$sir_result[idx]
      vals <- vals[!is.na(vals)]
      if (length(vals) > 0L) {
        sir_matrix[row_id[idx[[1L]]], obs$atb_norm[idx[[1L]]]] <- vals[[length(vals)]]
      }
    }
  }
  sir_wide <- cbind(sir_wide, as.data.frame(sir_matrix, stringsAsFactors = FALSE))

  blse_col <- c("blse_status_row", "blse_status")
  blse_col <- blse_col[blse_col %in% names(obs)][1]
  carba_col <- c("carbapenemase_status_row", "carbapenemase_status")
  carba_col <- carba_col[carba_col %in% names(obs)][1]
  phenotype_allowed <- contract$sir_wide$phenotype_status_allowed

  blse_status <- rep("no_signal", nrow(sir_wide))
  carba_status <- rep("no_signal", nrow(sir_wide))
  for (i in seq_along(row_groups)) {
    idx <- row_groups[[i]]
    if (!is.na(blse_col)) {
      blse_status[[i]] <- orchidee_handoff_collapse_phenotype(
        obs[[blse_col]][idx],
        phenotype_allowed$blse_status_row,
        blse_col
      )
    }
    if (!is.na(carba_col)) {
      carba_status[[i]] <- orchidee_handoff_collapse_phenotype(
        obs[[carba_col]][idx],
        phenotype_allowed$carbapenemase_status_row,
        carba_col
      )
    }
  }

  sir_wide$blse_status_row <- blse_status
  sir_wide$carbapenemase_status_row <- carba_status
  sir_wide$blse_flag <- phenotype_status_to_flag(sir_wide$blse_status_row)
  sir_wide$carbapenemase_flag <- phenotype_status_to_flag(sir_wide$carbapenemase_status_row)
  tested_matrix <- as.data.frame(
    lapply(sir_wide[supported_atb], function(x) x %in% c("S", "R")),
    stringsAsFactors = FALSE
  )
  sir_wide$nb_resultats <- rowSums(tested_matrix, na.rm = TRUE)

  preferred_order <- c(
    "PATID", "EVTID", "ELTID", "DATEPRELEV", "HEUREPRELEV", "souche_id",
    "nb_resultats", "naturepvt_norm", "bact_norm", "SEJUF",
    supported_atb,
    "blse_status_row", "carbapenemase_status_row", "blse_flag", "carbapenemase_flag"
  )
  sir_wide <- sir_wide[, preferred_order, drop = FALSE]
  row.names(sir_wide) <- NULL
  sir_wide
}

orchidee_handoff_build_sir_wide_meta <- function(
    sir_wide,
    contract = orchidee_external_contract_v2(),
    artifact_version = 4L,
    created_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    source_label = "external_handoff"
  ) {
  stopifnot(is.data.frame(sir_wide), is.list(contract))
  if (!"ELTID" %in% names(sir_wide)) {
    stop("sir_wide must contain ELTID to derive metadata.", call. = FALSE)
  }

  sir_spec <- contract$sir_wide
  supported_atb_cols <- sir_spec$atb_cols
  observed_atb_cols <- supported_atb_cols[vapply(
    supported_atb_cols,
    function(col) any(sir_wide[[col]] %in% sir_spec$allowed_atb_values, na.rm = TRUE),
    logical(1)
  )]

  metadata <- list(
    artifact_version = as.integer(artifact_version),
    created_at = as.character(created_at),
    sir_wide_n_rows = nrow(sir_wide),
    sir_wide_n_eltid = length(unique(sir_wide$ELTID)),
    atb_cols = observed_atb_cols,
    supported_atb_cols = supported_atb_cols,
    phenotype_status_cols = sir_spec$phenotype_status_cols,
    phenotype_flag_cols = sir_spec$phenotype_flag_cols,
    filtre_atb = supported_atb_cols,
    handoff_source = source_label,
    handoff_generated_by = "R/external_handoff_helpers.R"
  )

  if (!is.null(sir_spec$required_meta_values)) {
    metadata[names(sir_spec$required_meta_values)] <-
      sir_spec$required_meta_values
  }

  metadata
}

orchidee_handoff_build_sample_scope_reference <- function(
    unit_mapping,
    contract = orchidee_external_contract_v2()
  ) {
  orchidee_handoff_require_functions(c(
    "ratb_normalize_code_ta",
    "ratb_normalize_code_de",
    "ratb_included_ta_de_domains"
  ))
  if (!is.data.frame(unit_mapping)) {
    stop("unit_mapping must be a data frame.", call. = FALSE)
  }

  required_unit_cols <- c("SEJUF", "CODE_TA", "CODE_DE", "de_domain_ref")
  missing_unit_cols <- setdiff(required_unit_cols, names(unit_mapping))
  if (length(missing_unit_cols) > 0L) {
    stop(
      "unit_mapping is missing required columns: ",
      paste(missing_unit_cols, collapse = ", "),
      call. = FALSE
    )
  }

  unit <- data.frame(
    SEJUF = orchidee_handoff_trim_or_na(unit_mapping$SEJUF),
    CODE_TA = ratb_normalize_code_ta(unit_mapping$CODE_TA),
    stringsAsFactors = FALSE
  )

  if (any(is.na(unit$SEJUF))) {
    stop("unit_mapping$SEJUF contains missing values.", call. = FALSE)
  }
  if (any(duplicated(unit$SEJUF))) {
    duplicate_sejuf <- unique(unit$SEJUF[duplicated(unit$SEJUF)])
    stop(
      "unit_mapping contains duplicate SEJUF values: ",
      paste(utils::head(duplicate_sejuf, 10L), collapse = ", "),
      if (length(duplicate_sejuf) > 10L) ", ..." else "",
      call. = FALSE
    )
  }

  unit$CODE_DE_norm <- ratb_normalize_code_de(unit_mapping$CODE_DE)
  unit$de_domain_ref <- orchidee_handoff_trim_or_na(
    unit_mapping$de_domain_ref
  )
  unit$de_domain_ref <- orchidee_handoff_normalize_included_de_domain(
    unit$de_domain_ref
  )

  if (all(is.na(unit$de_domain_ref))) {
    stop(
      "No de_domain_ref information available in unit_mapping.",
      call. = FALSE
    )
  }

  included_domains <- ratb_included_ta_de_domains()
  uf_ta_eligible <- unit$CODE_TA %in% c("03", "20")
  uf_de_mapped <- !is.na(unit$de_domain_ref)
  uf_de_eligible <- unit$de_domain_ref %in% included_domains
  uf_is_eligible <- uf_ta_eligible & uf_de_eligible

  status <- ifelse(
    uf_is_eligible,
    "eligible_ta_de",
    ifelse(
      is.na(unit$CODE_TA),
      "review_unmapped_uf",
      ifelse(
        uf_ta_eligible & !uf_de_mapped,
        "review_unmapped_de",
        ifelse(uf_ta_eligible & !uf_de_eligible, "excluded_de_domain", "excluded_ta")
      )
    )
  )

  reason <- ifelse(
    uf_is_eligible,
    "eligible_ta_de",
    ifelse(
      is.na(unit$CODE_TA),
      "uf_absent_from_consores_structure",
      ifelse(
        uf_ta_eligible & !uf_de_mapped,
        "ta_03_20_unmapped_de",
        ifelse(
          uf_ta_eligible & !uf_de_eligible,
          "ta_03_20_de_domain_not_included",
          "ta_not_03_20"
        )
      )
    )
  )

  sample_scope_reference <- data.frame(
    SEJUF = unit$SEJUF,
    sample_CODE_TA = unit$CODE_TA,
    sample_CODE_DE = unit$CODE_DE_norm,
    sample_de_domain_ref = unit$de_domain_ref,
    sample_uf_is_eligible_by_ta_de = uf_is_eligible,
    sample_uf_ta_de_status = status,
    sample_uf_ta_de_reason = reason,
    stringsAsFactors = FALSE
  )
  required_columns <- contract$sample_scope_reference$required_columns
  sample_scope_reference[required_columns]
}

orchidee_handoff_build_denominator_bundle <- function(
    denominator_by_year = NULL,
    incidence_exposure_by_year_um_uf_ta_de_profile = NULL,
    contract = orchidee_external_contract_v2()
  ) {
  if (identical(contract$version, "v3")) {
    orchidee_handoff_require_functions(c(
      "ratb_normalize_code_ta",
      "ratb_normalize_code_de"
    ))
    exposure <- incidence_exposure_by_year_um_uf_ta_de_profile
    if (!is.data.frame(exposure)) {
      stop(
        "incidence_exposure_by_year_um_uf_ta_de_profile must be a data frame ",
        "for contract v3.",
        call. = FALSE
      )
    }
    required_cols <- c(
      "calendar_year", "SEJUM", "SEJUF", "CODE_TA", "CODE_DE",
      "de_domain_ref", "denominator_profile_id", "exposure_value",
      "exposure_unit"
    )
    missing_cols <- setdiff(required_cols, names(exposure))
    if (length(missing_cols) > 0L) {
      stop(
        "incidence_exposure_by_year_um_uf_ta_de_profile is missing required ",
        "columns: ",
        paste(missing_cols, collapse = ", "),
        call. = FALSE
      )
    }

    canonical_exposure <- data.frame(
      calendar_year = orchidee_handoff_integerish_vector(
        exposure$calendar_year,
        "incidence_exposure_by_year_um_uf_ta_de_profile$calendar_year"
      ),
      SEJUM = orchidee_handoff_trim_or_na(exposure$SEJUM),
      SEJUF = orchidee_handoff_trim_or_na(exposure$SEJUF),
      CODE_TA = ratb_normalize_code_ta(exposure$CODE_TA),
      CODE_DE = ratb_normalize_code_de(exposure$CODE_DE),
      de_domain_ref = orchidee_handoff_normalize_included_de_domain(
        exposure$de_domain_ref
      ),
      denominator_profile_id = orchidee_handoff_trim_or_na(
        exposure$denominator_profile_id
      ),
      exposure_value = orchidee_handoff_integerish_vector(
        exposure$exposure_value,
        "incidence_exposure_by_year_um_uf_ta_de_profile$exposure_value"
      ),
      exposure_unit = orchidee_handoff_trim_or_na(exposure$exposure_unit),
      stringsAsFactors = FALSE
    )
    missing_dimension <- vapply(
      canonical_exposure[required_cols],
      function(x) any(is.na(x)),
      logical(1)
    )
    if (any(missing_dimension)) {
      stop(
        "incidence_exposure_by_year_um_uf_ta_de_profile must not contain ",
        "missing values in: ",
        paste(names(missing_dimension)[missing_dimension], collapse = ", "),
        call. = FALSE
      )
    }
    if (any(canonical_exposure$exposure_value < 0L)) {
      stop(
        "incidence_exposure_by_year_um_uf_ta_de_profile$exposure_value must ",
        "be non-negative.",
        call. = FALSE
      )
    }
    profiles <- ratb_denominator_profile_registry()
    profile_match <- match(
      canonical_exposure$denominator_profile_id,
      profiles$denominator_profile_id
    )
    invalid_profile <- is.na(profile_match)
    invalid_unit <- !invalid_profile &
      canonical_exposure$exposure_unit != profiles$exposure_unit[profile_match]
    if (any(invalid_profile | invalid_unit)) {
      stop(
        "incidence_exposure_by_year_um_uf_ta_de_profile contains an ",
        "unsupported denominator profile/exposure unit pair.",
        call. = FALSE
      )
    }
    grain_cols <- c(
      "calendar_year", "SEJUM", "SEJUF", "CODE_TA", "CODE_DE",
      "de_domain_ref", "denominator_profile_id"
    )
    if (any(duplicated(canonical_exposure[grain_cols]))) {
      stop(
        "incidence_exposure_by_year_um_uf_ta_de_profile contains duplicate ",
        "rows at grain ",
        paste(grain_cols, collapse = " + "),
        ".",
        call. = FALSE
      )
    }
    canonical_exposure <- canonical_exposure[
      do.call(order, canonical_exposure[grain_cols]),
      ,
      drop = FALSE
    ]
    row.names(canonical_exposure) <- NULL

    return(list(
      incidence_exposure_by_year_um_uf_ta_de_profile = canonical_exposure
    ))
  }

  if (!is.data.frame(denominator_by_year)) {
    stop("denominator_by_year must be a data frame.", call. = FALSE)
  }
  required_cols <- c("calendar_year", "hospital_nights")
  missing_cols <- setdiff(required_cols, names(denominator_by_year))
  if (length(missing_cols) > 0L) {
    stop(
      "denominator_by_year is missing required columns: ",
      paste(missing_cols, collapse = ", "),
      call. = FALSE
    )
  }

  incidence_denominator_by_year <- data.frame(
    calendar_year = orchidee_handoff_integerish_vector(
      denominator_by_year$calendar_year,
      "denominator_by_year$calendar_year"
    ),
    hospital_nights = orchidee_handoff_integerish_vector(
      denominator_by_year$hospital_nights,
      "denominator_by_year$hospital_nights"
    ),
    stringsAsFactors = FALSE
  )
  if (any(incidence_denominator_by_year$hospital_nights < 0L)) {
    stop("denominator_by_year$hospital_nights must be non-negative.", call. = FALSE)
  }

  incidence_denominator_by_year <- incidence_denominator_by_year[
    order(incidence_denominator_by_year$calendar_year),
    ,
    drop = FALSE
  ]
  row.names(incidence_denominator_by_year) <- NULL

  list(incidence_denominator_by_year = incidence_denominator_by_year)
}

orchidee_handoff_build_external_bundle <- function(
    sir_wide,
    unit_mapping,
    denominator_by_year = NULL,
    contract = orchidee_external_contract_v2(),
    incidence_exposure_by_year_um_uf_ta_de_profile = NULL
  ) {
  list(
    sir_wide = sir_wide,
    sir_wide_meta = orchidee_handoff_build_sir_wide_meta(
      sir_wide = sir_wide,
      contract = contract
    ),
    sample_scope_reference = orchidee_handoff_build_sample_scope_reference(
      unit_mapping = unit_mapping,
      contract = contract
    ),
    denominator_bundle = orchidee_handoff_build_denominator_bundle(
      denominator_by_year = denominator_by_year,
      incidence_exposure_by_year_um_uf_ta_de_profile =
        incidence_exposure_by_year_um_uf_ta_de_profile,
      contract = contract
    )
  )
}

orchidee_handoff_build_external_bundle_from_site_inputs <- function(
    microbiology_observations,
    bacteria_mapping,
    sample_type_mapping,
    antibiotic_mapping,
    unit_mapping,
    denominator_by_year = NULL,
    contract = orchidee_external_contract_v2(),
    incidence_exposure_by_year_um_uf_ta_de_profile = NULL
  ) {
  sir_wide <- orchidee_handoff_build_sir_wide_from_microbiology(
    microbiology_observations = microbiology_observations,
    bacteria_mapping = bacteria_mapping,
    sample_type_mapping = sample_type_mapping,
    antibiotic_mapping = antibiotic_mapping,
    contract = contract
  )

  orchidee_handoff_build_external_bundle(
    sir_wide = sir_wide,
    unit_mapping = unit_mapping,
    denominator_by_year = denominator_by_year,
    contract = contract,
    incidence_exposure_by_year_um_uf_ta_de_profile =
      incidence_exposure_by_year_um_uf_ta_de_profile
  )
}
