# External bundle validation helpers for Orchidee.
#
# This layer is intentionally additive. It documents and validates a future
# external input contract without changing the current runtime path.

orchidee_external_contract_v1 <- function() {
  atb_cols <- c(
    "levofloxacine",
    "rifampicine",
    "tetracycline",
    "vancomycine",
    "acide_fusidique",
    "erythromycine",
    "fosfomycine_trometamol",
    "gentamicine",
    "kanamycine",
    "oxacilline",
    "trimethoprime_sulfamethoxazole",
    "amikacine",
    "amoxicilline_acide_clavulanique",
    "amoxicilline_ampicilline",
    "ceftazidime",
    "ceftriaxone",
    "mecillinam",
    "nitrofurantoine",
    "ofloxacine",
    "piperacilline_tazobactam",
    "ertapeneme",
    "fosfomycine_iv",
    "cefepime",
    "cefotaxime",
    "ciprofloxacine",
    "imipeneme",
    "meropeneme",
    "tobramycine",
    "pristinamycine",
    "ticarcilline",
    "daptomycine",
    "linezolide",
    "teicoplanine",
    "moxifloxacine",
    "cefoxitine"
  )

  list(
    version = "v1",
    bundle = list(
      required_files = c("sir_wide.rds", "sir_wide_meta.rds"),
      preferred_sample_scope_reference_file = "sample_scope_reference.rds",
      compatibility_sample_scope_reference_files = c("ratb_scope_cache", "ratb_scope_cache.rds"),
      preferred_denominator_file = "denominator_bundle.rds",
      compatibility_denominator_files = c("ratb_scope_cache", "ratb_scope_cache.rds")
    ),
    sir_wide = list(
      required_columns = c(
        "PATID",
        "EVTID",
        "ELTID",
        "DATEPRELEV",
        "HEUREPRELEV",
        "souche_id",
        "naturepvt_norm",
        "bact_norm",
        "SEJUF",
        atb_cols,
        "blse_status_row",
        "carbapenemase_status_row",
        "blse_flag",
        "carbapenemase_flag"
      ),
      atb_cols = atb_cols,
      derived_columns = c("nb_resultats"),
      allowed_atb_values = c("S", "R", "ZIT"),
      row_grain_key = c(
        "PATID",
        "EVTID",
        "ELTID",
        "DATEPRELEV",
        "souche_id",
        "naturepvt_norm",
        "bact_norm"
      ),
      required_meta_fields = c(
        "artifact_version",
        "created_at",
        "sir_wide_n_rows",
        "sir_wide_n_eltid",
        "atb_cols",
        "supported_atb_cols",
        "phenotype_status_cols",
        "phenotype_flag_cols",
        "filtre_atb"
      ),
      phenotype_status_allowed = list(
        blse_status_row = c("negative", "no_signal", "positive"),
        carbapenemase_status_row = c("negative", "no_signal", "positive", "unknown")
      ),
      phenotype_flag_cols = c("blse_flag", "carbapenemase_flag"),
      phenotype_status_cols = c("blse_status_row", "carbapenemase_status_row")
    ),
    sample_scope_reference = list(
      required_columns = c(
        "SEJUF",
        "sample_CODE_TA",
        "sample_CODE_DE",
        "sample_de_domain_ref",
        "sample_uf_is_eligible_by_ta_de",
        "sample_uf_ta_de_status",
        "sample_uf_ta_de_reason"
      ),
      character_columns = c(
        "SEJUF",
        "sample_CODE_TA",
        "sample_CODE_DE",
        "sample_de_domain_ref",
        "sample_uf_ta_de_status",
        "sample_uf_ta_de_reason"
      ),
      logical_columns = c("sample_uf_is_eligible_by_ta_de"),
      status_allowed = c(
        "eligible_ta_de",
        "excluded_ta",
        "excluded_de_domain",
        "review_unmapped_uf",
        "review_unmapped_de",
        "review_missing_sample_uf"
      ),
      reason_allowed = c(
        "eligible_ta_de",
        "ta_not_03_20",
        "ta_03_20_de_domain_not_included",
        "uf_absent_from_consores_structure",
        "ta_03_20_unmapped_de",
        "missing_sample_uf"
      )
    ),
    denominator_bundle = list(
      required_tables = c(
        "incidence_denominator_by_year"
      ),
      compatibility_tables = c("hospital_days_year_summary_provisional"),
      tables = list(
        incidence_denominator_by_year = list(
          required_columns = c(
            "calendar_year",
            "hospital_nights"
          ),
          integerish_columns = c(
            "calendar_year",
            "hospital_nights"
          ),
          non_negative_columns = c(
            "hospital_nights"
          )
        )
      )
    )
  )
}

external_bundle_is_integerish <- function(x) {
  is.numeric(x) && all(is.na(x) | abs(x - round(x)) < sqrt(.Machine$double.eps))
}

external_bundle_add_issue <- function(issues, text) {
  c(issues, text)
}

external_bundle_validate_paths <- function(bundle_dir, contract = orchidee_external_contract_v1()) {
  errors <- character(0)
  warnings <- character(0)

  if (!dir.exists(bundle_dir)) {
    errors <- external_bundle_add_issue(errors, paste0("Bundle directory does not exist: ", bundle_dir))
    return(list(ok = FALSE, errors = errors, warnings = warnings, paths = NULL))
  }

  sir_wide_path <- file.path(bundle_dir, "sir_wide.rds")
  sir_wide_meta_path <- file.path(bundle_dir, "sir_wide_meta.rds")

  if (!file.exists(sir_wide_path)) {
    errors <- external_bundle_add_issue(errors, paste0("Missing required file: ", sir_wide_path))
  }
  if (!file.exists(sir_wide_meta_path)) {
    errors <- external_bundle_add_issue(errors, paste0("Missing required file: ", sir_wide_meta_path))
  }

  sample_scope_path <- file.path(bundle_dir, contract$bundle$preferred_sample_scope_reference_file)
  sample_scope_source <- "preferred"
  if (!file.exists(sample_scope_path)) {
    compat_candidates <- file.path(bundle_dir, contract$bundle$compatibility_sample_scope_reference_files)
    existing <- compat_candidates[file.exists(compat_candidates)]
    if (length(existing) > 0L) {
      sample_scope_path <- existing[[1]]
      sample_scope_source <- "compatibility"
      warnings <- external_bundle_add_issue(
        warnings,
        paste0(
          "Preferred sample-scope reference file not found; using compatibility source ",
          basename(sample_scope_path),
          "."
        )
      )
    } else {
      errors <- external_bundle_add_issue(
        errors,
        paste0(
          "Missing sample-scope reference. Expected ",
          contract$bundle$preferred_sample_scope_reference_file,
          " or one of: ",
          paste(contract$bundle$compatibility_sample_scope_reference_files, collapse = ", ")
        )
      )
    }
  }

  denominator_path <- file.path(bundle_dir, contract$bundle$preferred_denominator_file)
  denominator_source <- "preferred"
  if (!file.exists(denominator_path)) {
    compat_candidates <- file.path(bundle_dir, contract$bundle$compatibility_denominator_files)
    existing <- compat_candidates[file.exists(compat_candidates)]
    if (length(existing) > 0L) {
      denominator_path <- existing[[1]]
      denominator_source <- "compatibility"
      warnings <- external_bundle_add_issue(
        warnings,
        paste0(
          "Preferred denominator file not found; using compatibility source ",
          basename(denominator_path),
          "."
        )
      )
    } else {
      errors <- external_bundle_add_issue(
        errors,
        paste0(
          "Missing denominator bundle. Expected ",
          contract$bundle$preferred_denominator_file,
          " or one of: ",
          paste(contract$bundle$compatibility_denominator_files, collapse = ", ")
        )
      )
    }
  }

  list(
    ok = length(errors) == 0L,
    errors = unique(errors),
    warnings = unique(warnings),
    paths = list(
      bundle_dir = normalizePath(bundle_dir, winslash = "/", mustWork = FALSE),
      sir_wide = sir_wide_path,
      sir_wide_meta = sir_wide_meta_path,
      sample_scope_reference = sample_scope_path,
      sample_scope_reference_source = sample_scope_source,
      denominator_bundle = denominator_path,
      denominator_source = denominator_source
    )
  )
}

external_bundle_load_bundle <- function(paths) {
  list(
    sir_wide = readRDS(paths$sir_wide),
    sir_wide_meta = readRDS(paths$sir_wide_meta),
    sample_scope_reference = readRDS(paths$sample_scope_reference),
    denominator_bundle = readRDS(paths$denominator_bundle)
  )
}

external_bundle_sir_wide_contract_columns <- function(contract = orchidee_external_contract_v1()) {
  unique(c(contract$sir_wide$required_columns, contract$sir_wide$derived_columns))
}

external_bundle_add_derived_sir_wide_columns <- function(
    sir_wide,
    contract = orchidee_external_contract_v1()
  ) {
  if (!is.data.frame(sir_wide)) {
    return(sir_wide)
  }

  atb_cols <- contract$sir_wide$atb_cols
  if (!"nb_resultats" %in% names(sir_wide) &&
      all(atb_cols %in% names(sir_wide))) {
    atb_mat <- as.matrix(sir_wide[, atb_cols, drop = FALSE])
    sr_mat <- atb_mat == "S" | atb_mat == "R"
    sr_mat[is.na(sr_mat)] <- FALSE
    sir_wide$nb_resultats <- rowSums(sr_mat)
  }

  sir_wide
}

external_bundle_subset_sir_wide <- function(
    sir_wide,
    contract = orchidee_external_contract_v1()
  ) {
  contract_columns <- external_bundle_sir_wide_contract_columns(contract)
  sir_wide <- external_bundle_add_derived_sir_wide_columns(
    sir_wide,
    contract = contract
  )
  if (!is.data.frame(sir_wide) || !all(contract_columns %in% names(sir_wide))) {
    return(sir_wide)
  }

  sir_wide[contract_columns]
}

external_bundle_validate_sir_wide <- function(sir_wide, sir_wide_meta, contract = orchidee_external_contract_v1()) {
  errors <- character(0)
  warnings <- character(0)
  spec <- contract$sir_wide
  sir_wide <- external_bundle_add_derived_sir_wide_columns(
    sir_wide,
    contract = contract
  )

  if (!is.data.frame(sir_wide)) {
    errors <- external_bundle_add_issue(errors, "sir_wide is not a data.frame.")
    return(list(ok = FALSE, errors = errors, warnings = warnings))
  }

  missing_cols <- setdiff(spec$required_columns, names(sir_wide))
  if (length(missing_cols) > 0L) {
    errors <- external_bundle_add_issue(
      errors,
      paste0("sir_wide is missing required columns: ", paste(missing_cols, collapse = ", "))
    )
  }

  contract_cols <- external_bundle_sir_wide_contract_columns(contract)
  extra_cols <- setdiff(names(sir_wide), contract_cols)
  if (length(extra_cols) > 0L) {
    warnings <- external_bundle_add_issue(
      warnings,
      paste0("sir_wide contains extra columns outside the v1 contract: ", paste(extra_cols, collapse = ", "))
    )
  }

  if (length(missing_cols) == 0L) {
    character_cols <- c(
      "PATID", "EVTID", "ELTID", "souche_id", "naturepvt_norm", "bact_norm",
      "SEJUF",
      spec$atb_cols,
      spec$phenotype_status_cols
    )

    bad_character_cols <- character_cols[!vapply(sir_wide[character_cols], is.character, logical(1))]
    if (length(bad_character_cols) > 0L) {
      errors <- external_bundle_add_issue(
        errors,
        paste0("sir_wide columns must be character: ", paste(bad_character_cols, collapse = ", "))
      )
    }

    if (!inherits(sir_wide$DATEPRELEV, "Date")) {
      errors <- external_bundle_add_issue(errors, "sir_wide$DATEPRELEV must inherit from Date.")
    }
    if (!inherits(sir_wide$HEUREPRELEV, "difftime")) {
      errors <- external_bundle_add_issue(errors, "sir_wide$HEUREPRELEV must inherit from difftime.")
    }
    if (!is.numeric(sir_wide$nb_resultats)) {
      errors <- external_bundle_add_issue(errors, "sir_wide$nb_resultats must be numeric.")
    }

    bad_flag_cols <- spec$phenotype_flag_cols[!vapply(sir_wide[spec$phenotype_flag_cols], is.logical, logical(1))]
    if (length(bad_flag_cols) > 0L) {
      errors <- external_bundle_add_issue(
        errors,
        paste0("sir_wide phenotype flag columns must be logical: ", paste(bad_flag_cols, collapse = ", "))
      )
    }

    order_cols <- intersect(c("evt_order", "elt_order"), names(sir_wide))
    bad_order_cols <- order_cols[!vapply(sir_wide[order_cols], external_bundle_is_integerish, logical(1))]
    if (length(bad_order_cols) > 0L) {
      errors <- external_bundle_add_issue(
        errors,
        paste0("sir_wide order columns must be integer-like: ", paste(bad_order_cols, collapse = ", "))
      )
    }

    atb_values <- unique(unlist(sir_wide[spec$atb_cols], use.names = FALSE))
    atb_values <- sort(unique(atb_values[!is.na(atb_values)]))
    unsupported_atb_values <- setdiff(atb_values, spec$allowed_atb_values)
    if (length(unsupported_atb_values) > 0L) {
      errors <- external_bundle_add_issue(
        errors,
        paste0("sir_wide ATB columns contain unsupported values: ", paste(unsupported_atb_values, collapse = ", "))
      )
    }

    for (status_col in names(spec$phenotype_status_allowed)) {
      vals <- unique(sir_wide[[status_col]])
      vals <- sort(unique(vals[!is.na(vals)]))
      bad_vals <- setdiff(vals, spec$phenotype_status_allowed[[status_col]])
      if (length(bad_vals) > 0L) {
        errors <- external_bundle_add_issue(
          errors,
          paste0(
            "sir_wide$", status_col,
            " contains unsupported values: ",
            paste(bad_vals, collapse = ", ")
          )
        )
      }
    }

    for (flag_col in spec$phenotype_flag_cols) {
      if (any(is.na(sir_wide[[flag_col]]))) {
        errors <- external_bundle_add_issue(errors, paste0("sir_wide$", flag_col, " contains NA values."))
      }
    }

    non_missing_key_cols <- c("PATID", "ELTID", "DATEPRELEV", "souche_id", "bact_norm")
    key_na <- vapply(non_missing_key_cols, function(col) any(is.na(sir_wide[[col]])), logical(1))
    if (any(key_na)) {
      errors <- external_bundle_add_issue(
        errors,
        paste0(
          "sir_wide required non-missing key columns contain NA values: ",
          paste(non_missing_key_cols[key_na], collapse = ", ")
        )
      )
    }

    if (nrow(unique(sir_wide[spec$row_grain_key])) != nrow(sir_wide)) {
      errors <- external_bundle_add_issue(
        errors,
        paste0(
          "sir_wide row-grain key is not unique: ",
          paste(spec$row_grain_key, collapse = ", ")
        )
      )
    }
  }

  if (!is.list(sir_wide_meta)) {
    errors <- external_bundle_add_issue(errors, "sir_wide_meta is not a list.")
    return(list(ok = FALSE, errors = unique(errors), warnings = unique(warnings)))
  }

  missing_meta_fields <- setdiff(spec$required_meta_fields, names(sir_wide_meta))
  if (length(missing_meta_fields) > 0L) {
    errors <- external_bundle_add_issue(
      errors,
      paste0("sir_wide_meta is missing required fields: ", paste(missing_meta_fields, collapse = ", "))
    )
  }

  if (length(missing_meta_fields) == 0L) {
    if (!external_bundle_is_integerish(sir_wide_meta$artifact_version) || length(sir_wide_meta$artifact_version) != 1L) {
      errors <- external_bundle_add_issue(errors, "sir_wide_meta$artifact_version must be a length-1 integer-like value.")
    }
    if (!is.character(sir_wide_meta$created_at) || length(sir_wide_meta$created_at) != 1L || !nzchar(sir_wide_meta$created_at)) {
      errors <- external_bundle_add_issue(errors, "sir_wide_meta$created_at must be a non-empty length-1 character value.")
    }
    if (!external_bundle_is_integerish(sir_wide_meta$sir_wide_n_rows) || length(sir_wide_meta$sir_wide_n_rows) != 1L) {
      errors <- external_bundle_add_issue(errors, "sir_wide_meta$sir_wide_n_rows must be a length-1 integer-like value.")
    } else if (as.integer(sir_wide_meta$sir_wide_n_rows) != nrow(sir_wide)) {
      errors <- external_bundle_add_issue(errors, "sir_wide_meta$sir_wide_n_rows does not match nrow(sir_wide).")
    }
    if (!external_bundle_is_integerish(sir_wide_meta$sir_wide_n_eltid) || length(sir_wide_meta$sir_wide_n_eltid) != 1L) {
      errors <- external_bundle_add_issue(errors, "sir_wide_meta$sir_wide_n_eltid must be a length-1 integer-like value.")
    } else if (as.integer(sir_wide_meta$sir_wide_n_eltid) != length(unique(sir_wide$ELTID))) {
      errors <- external_bundle_add_issue(errors, "sir_wide_meta$sir_wide_n_eltid does not match distinct ELTID count.")
    }

    required_supported <- spec$atb_cols
    if (!setequal(sir_wide_meta$supported_atb_cols, required_supported)) {
      errors <- external_bundle_add_issue(errors, "sir_wide_meta$supported_atb_cols does not match the v1 supported ATB set.")
    }
    if (!all(sir_wide_meta$atb_cols %in% required_supported)) {
      errors <- external_bundle_add_issue(errors, "sir_wide_meta$atb_cols contains values outside the v1 supported ATB set.")
    }
    if (!setequal(sir_wide_meta$filtre_atb, required_supported)) {
      errors <- external_bundle_add_issue(errors, "sir_wide_meta$filtre_atb does not match the v1 supported ATB set.")
    }
    if (!setequal(sir_wide_meta$phenotype_status_cols, spec$phenotype_status_cols)) {
      errors <- external_bundle_add_issue(errors, "sir_wide_meta$phenotype_status_cols does not match the v1 phenotype status columns.")
    }
    if (!setequal(sir_wide_meta$phenotype_flag_cols, spec$phenotype_flag_cols)) {
      errors <- external_bundle_add_issue(errors, "sir_wide_meta$phenotype_flag_cols does not match the v1 phenotype flag columns.")
    }
  }

  list(ok = length(errors) == 0L, errors = unique(errors), warnings = unique(warnings))
}

external_bundle_coerce_sample_scope_reference <- function(sample_scope_reference) {
  if (is.data.frame(sample_scope_reference)) {
    return(sample_scope_reference)
  }

  if (is.list(sample_scope_reference) && is.data.frame(sample_scope_reference$sample_scope_reference)) {
    return(sample_scope_reference$sample_scope_reference)
  }

  if (is.list(sample_scope_reference) && is.data.frame(sample_scope_reference$ratb_uf_ta_de_reference)) {
    ref <- sample_scope_reference$ratb_uf_ta_de_reference
    compat_cols <- c(
      "SEJUF",
      "CODE_TA",
      "CODE_DE",
      "de_domain_ref",
      "uf_is_eligible_by_ta_de",
      "uf_ta_de_status",
      "uf_ta_de_reason"
    )
    if (!all(compat_cols %in% names(ref))) {
      return(sample_scope_reference)
    }
    return(data.frame(
      SEJUF = as.character(ref$SEJUF),
      sample_CODE_TA = as.character(ref$CODE_TA),
      sample_CODE_DE = as.character(ref$CODE_DE),
      sample_de_domain_ref = as.character(ref$de_domain_ref),
      sample_uf_is_eligible_by_ta_de = as.logical(ref$uf_is_eligible_by_ta_de),
      sample_uf_ta_de_status = as.character(ref$uf_ta_de_status),
      sample_uf_ta_de_reason = as.character(ref$uf_ta_de_reason),
      stringsAsFactors = FALSE
    ))
  }

  sample_scope_reference
}

external_bundle_validate_sample_scope_reference <- function(
    sample_scope_reference,
    contract = orchidee_external_contract_v1()
  ) {
  errors <- character(0)
  warnings <- character(0)
  spec <- contract$sample_scope_reference
  sample_scope_reference <- external_bundle_coerce_sample_scope_reference(sample_scope_reference)

  if (!is.data.frame(sample_scope_reference)) {
    errors <- external_bundle_add_issue(errors, "sample_scope_reference is not a data.frame.")
    return(list(ok = FALSE, errors = errors, warnings = warnings))
  }

  missing_cols <- setdiff(spec$required_columns, names(sample_scope_reference))
  if (length(missing_cols) > 0L) {
    errors <- external_bundle_add_issue(
      errors,
      paste0("sample_scope_reference is missing required columns: ", paste(missing_cols, collapse = ", "))
    )
  }

  extra_cols <- setdiff(names(sample_scope_reference), spec$required_columns)
  if (length(extra_cols) > 0L) {
    warnings <- external_bundle_add_issue(
      warnings,
      paste0("sample_scope_reference contains extra columns outside the v1 contract: ", paste(extra_cols, collapse = ", "))
    )
  }

  if (length(missing_cols) == 0L) {
    bad_character_cols <- spec$character_columns[
      !vapply(sample_scope_reference[spec$character_columns], is.character, logical(1))
    ]
    if (length(bad_character_cols) > 0L) {
      errors <- external_bundle_add_issue(
        errors,
        paste0("sample_scope_reference columns must be character: ", paste(bad_character_cols, collapse = ", "))
      )
    }

    bad_logical_cols <- spec$logical_columns[
      !vapply(sample_scope_reference[spec$logical_columns], is.logical, logical(1))
    ]
    if (length(bad_logical_cols) > 0L) {
      errors <- external_bundle_add_issue(
        errors,
        paste0("sample_scope_reference columns must be logical: ", paste(bad_logical_cols, collapse = ", "))
      )
    }

    if (any(is.na(sample_scope_reference$SEJUF))) {
      errors <- external_bundle_add_issue(errors, "sample_scope_reference$SEJUF contains NA values.")
    }
    if (any(duplicated(sample_scope_reference$SEJUF[!is.na(sample_scope_reference$SEJUF)]))) {
      errors <- external_bundle_add_issue(errors, "sample_scope_reference contains duplicate SEJUF values.")
    }
    if (any(is.na(sample_scope_reference$sample_uf_is_eligible_by_ta_de))) {
      errors <- external_bundle_add_issue(errors, "sample_scope_reference$sample_uf_is_eligible_by_ta_de contains NA values.")
    }
    if (any(is.na(sample_scope_reference$sample_uf_ta_de_status))) {
      errors <- external_bundle_add_issue(errors, "sample_scope_reference$sample_uf_ta_de_status contains NA values.")
    }
    if (any(is.na(sample_scope_reference$sample_uf_ta_de_reason))) {
      errors <- external_bundle_add_issue(errors, "sample_scope_reference$sample_uf_ta_de_reason contains NA values.")
    }

    bad_status <- setdiff(
      unique(sample_scope_reference$sample_uf_ta_de_status[!is.na(sample_scope_reference$sample_uf_ta_de_status)]),
      spec$status_allowed
    )
    if (length(bad_status) > 0L) {
      errors <- external_bundle_add_issue(
        errors,
        paste0("sample_scope_reference$sample_uf_ta_de_status contains unsupported values: ", paste(bad_status, collapse = ", "))
      )
    }

    bad_reason <- setdiff(
      unique(sample_scope_reference$sample_uf_ta_de_reason[!is.na(sample_scope_reference$sample_uf_ta_de_reason)]),
      spec$reason_allowed
    )
    if (length(bad_reason) > 0L) {
      errors <- external_bundle_add_issue(
        errors,
        paste0("sample_scope_reference$sample_uf_ta_de_reason contains unsupported values: ", paste(bad_reason, collapse = ", "))
      )
    }
  }

  list(ok = length(errors) == 0L, errors = unique(errors), warnings = unique(warnings))
}

external_bundle_subset_sample_scope_reference <- function(
    sample_scope_reference,
    contract = orchidee_external_contract_v1()
  ) {
  sample_scope_reference <- external_bundle_coerce_sample_scope_reference(sample_scope_reference)
  required_columns <- contract$sample_scope_reference$required_columns

  if (!is.data.frame(sample_scope_reference) ||
      !all(required_columns %in% names(sample_scope_reference))) {
    return(sample_scope_reference)
  }

  sample_scope_reference[required_columns]
}

external_bundle_validate_denominator_table <- function(tbl, table_name, table_spec) {
  errors <- character(0)
  warnings <- character(0)

  if (!is.data.frame(tbl)) {
    errors <- external_bundle_add_issue(errors, paste0(table_name, " is not a data.frame."))
    return(list(ok = FALSE, errors = errors, warnings = warnings))
  }

  missing_cols <- setdiff(table_spec$required_columns, names(tbl))
  if (length(missing_cols) > 0L) {
    errors <- external_bundle_add_issue(
      errors,
      paste0(table_name, " is missing required columns: ", paste(missing_cols, collapse = ", "))
    )
  }

  extra_cols <- setdiff(names(tbl), table_spec$required_columns)
  if (length(extra_cols) > 0L) {
    warnings <- external_bundle_add_issue(
      warnings,
      paste0(table_name, " contains extra columns outside the v1 contract: ", paste(extra_cols, collapse = ", "))
    )
  }

  if (length(missing_cols) == 0L) {
    bad_integerish <- table_spec$integerish_columns[!vapply(tbl[table_spec$integerish_columns], external_bundle_is_integerish, logical(1))]
    if (length(bad_integerish) > 0L) {
      errors <- external_bundle_add_issue(
        errors,
        paste0(table_name, " columns must be integer-like: ", paste(bad_integerish, collapse = ", "))
      )
    }

    for (col in table_spec$non_negative_columns) {
      if (!is.numeric(tbl[[col]])) {
        errors <- external_bundle_add_issue(errors, paste0(table_name, "$", col, " must be numeric."))
      } else if (any(tbl[[col]] < 0, na.rm = TRUE)) {
        errors <- external_bundle_add_issue(errors, paste0(table_name, "$", col, " contains negative values."))
      }
    }

    if (any(is.na(tbl$calendar_year))) {
      errors <- external_bundle_add_issue(errors, paste0(table_name, "$calendar_year contains NA values."))
    }
    if (any(duplicated(tbl$calendar_year))) {
      errors <- external_bundle_add_issue(errors, paste0(table_name, " contains duplicate calendar_year values."))
    }
  }

  list(ok = length(errors) == 0L, errors = unique(errors), warnings = unique(warnings))
}

external_bundle_coerce_denominator_bundle <- function(
    denominator_bundle,
    contract = orchidee_external_contract_v1()
  ) {
  if (!is.list(denominator_bundle)) {
    return(denominator_bundle)
  }

  required_tables <- contract$denominator_bundle$required_tables
  if (all(required_tables %in% names(denominator_bundle))) {
    return(denominator_bundle)
  }

  legacy_tbl <- denominator_bundle$hospital_days_year_summary_provisional
  if (!is.data.frame(legacy_tbl) &&
      is.list(denominator_bundle$denominator_bundle)) {
    legacy_tbl <- denominator_bundle$denominator_bundle$hospital_days_year_summary_provisional
  }

  if (!is.data.frame(legacy_tbl) ||
      !all(c("calendar_year", "hospital_nights_provisional") %in% names(legacy_tbl))) {
    return(denominator_bundle)
  }

  list(
    incidence_denominator_by_year = data.frame(
      calendar_year = legacy_tbl$calendar_year,
      hospital_nights = legacy_tbl$hospital_nights_provisional,
      stringsAsFactors = FALSE
    )
  )
}

external_bundle_validate_denominator_bundle <- function(denominator_bundle, contract = orchidee_external_contract_v1()) {
  errors <- character(0)
  warnings <- character(0)
  spec <- contract$denominator_bundle
  denominator_bundle <- external_bundle_coerce_denominator_bundle(
    denominator_bundle,
    contract = contract
  )

  if (!is.list(denominator_bundle)) {
    errors <- external_bundle_add_issue(errors, "Denominator bundle is not a list.")
    return(list(ok = FALSE, errors = errors, warnings = warnings))
  }

  missing_tables <- setdiff(spec$required_tables, names(denominator_bundle))
  if (length(missing_tables) > 0L) {
    errors <- external_bundle_add_issue(
      errors,
      paste0("Denominator bundle is missing required tables: ", paste(missing_tables, collapse = ", "))
    )
  }

  if (length(missing_tables) == 0L) {
    for (table_name in spec$required_tables) {
      table_validation <- external_bundle_validate_denominator_table(
        tbl = denominator_bundle[[table_name]],
        table_name = table_name,
        table_spec = spec$tables[[table_name]]
      )
      errors <- c(errors, table_validation$errors)
      warnings <- c(warnings, table_validation$warnings)
    }
  }

  list(ok = length(errors) == 0L, errors = unique(errors), warnings = unique(warnings))
}

external_bundle_subset_denominator_bundle <- function(
    denominator_bundle,
    contract = orchidee_external_contract_v1()
  ) {
  denominator_bundle <- external_bundle_coerce_denominator_bundle(
    denominator_bundle,
    contract = contract
  )
  required_tables <- contract$denominator_bundle$required_tables
  if (!is.list(denominator_bundle) || !all(required_tables %in% names(denominator_bundle))) {
    return(denominator_bundle)
  }
  denominator_bundle <- denominator_bundle[required_tables]
  for (table_name in required_tables) {
    required_columns <- contract$denominator_bundle$tables[[table_name]]$required_columns
    if (is.data.frame(denominator_bundle[[table_name]]) &&
        all(required_columns %in% names(denominator_bundle[[table_name]]))) {
      denominator_bundle[[table_name]] <- denominator_bundle[[table_name]][required_columns]
    }
  }
  denominator_bundle
}

validate_external_input_bundle <- function(
    bundle_dir = file.path("data"),
    contract = orchidee_external_contract_v1(),
    strict_preferred = FALSE
  ) {
  path_validation <- external_bundle_validate_paths(bundle_dir, contract = contract)
  errors <- path_validation$errors
  warnings <- path_validation$warnings

  if (!isTRUE(path_validation$ok)) {
    report <- list(
      ok = FALSE,
      bundle_dir = normalizePath(bundle_dir, winslash = "/", mustWork = FALSE),
      errors = unique(errors),
      warnings = unique(warnings),
      paths = path_validation$paths,
      denominator_source = NA_character_,
      contract_version = contract$version
    )
    if (isTRUE(strict_preferred) && !is.null(report$paths)) {
      report <- external_bundle_enforce_preferred_sources(report)
    }
    return(report)
  }

  loaded <- external_bundle_load_bundle(path_validation$paths)
  sir_wide_validation <- external_bundle_validate_sir_wide(
    sir_wide = loaded$sir_wide,
    sir_wide_meta = loaded$sir_wide_meta,
    contract = contract
  )
  sample_scope_validation <- external_bundle_validate_sample_scope_reference(
    sample_scope_reference = loaded$sample_scope_reference,
    contract = contract
  )
  denominator_validation <- external_bundle_validate_denominator_bundle(
    denominator_bundle = loaded$denominator_bundle,
    contract = contract
  )

  errors <- c(errors, sir_wide_validation$errors, sample_scope_validation$errors, denominator_validation$errors)
  warnings <- c(warnings, sir_wide_validation$warnings, sample_scope_validation$warnings, denominator_validation$warnings)

  report <- list(
    ok = length(errors) == 0L,
    bundle_dir = normalizePath(bundle_dir, winslash = "/", mustWork = FALSE),
    errors = unique(errors),
    warnings = unique(warnings),
    paths = path_validation$paths,
    sample_scope_reference_source = basename(path_validation$paths$sample_scope_reference),
    denominator_source = basename(path_validation$paths$denominator_bundle),
    contract_version = contract$version
  )
  if (isTRUE(strict_preferred)) {
    report <- external_bundle_enforce_preferred_sources(report)
  }

  report
}

external_bundle_enforce_preferred_sources <- function(report) {
  errors <- character(0)
  paths <- report$paths

  if (is.null(paths)) {
    errors <- external_bundle_add_issue(
      errors,
      "Cannot enforce preferred sources because bundle paths were not resolved."
    )
  } else {
    if (!identical(paths$sample_scope_reference_source, "preferred")) {
      errors <- external_bundle_add_issue(
        errors,
        "Strict preferred mode requires sample_scope_reference.rds."
      )
    }
    if (!identical(paths$denominator_source, "preferred")) {
      errors <- external_bundle_add_issue(
        errors,
        "Strict preferred mode requires denominator_bundle.rds."
      )
    }
  }

  if (length(errors) > 0L) {
    report$ok <- FALSE
    report$errors <- unique(c(report$errors, errors))
  }

  report
}

load_validated_external_input_bundle <- function(
    bundle_dir = file.path("data"),
    contract = orchidee_external_contract_v1(),
    strict_preferred = FALSE,
    validation_report = NULL
  ) {
  report <- validation_report
  if (is.null(report)) {
    report <- validate_external_input_bundle(
      bundle_dir = bundle_dir,
      contract = contract,
      strict_preferred = strict_preferred
    )
  }
  if (!isTRUE(report$ok)) {
    stop(
      "External input bundle does not match the ORCHIDEE contract:\n",
      paste(report$errors, collapse = "\n"),
      call. = FALSE
    )
  }

  loaded <- external_bundle_load_bundle(report$paths)

  list(
    sir_wide = external_bundle_subset_sir_wide(
      loaded$sir_wide,
      contract = contract
    ),
    sir_wide_meta = loaded$sir_wide_meta,
    sample_scope_reference = external_bundle_subset_sample_scope_reference(
      loaded$sample_scope_reference,
      contract = contract
    ),
    denominator_bundle = external_bundle_subset_denominator_bundle(
      loaded$denominator_bundle,
      contract = contract
    ),
    validation_report = report
  )
}

print_external_input_bundle_validation <- function(report) {
  cat("Bundle directory: ", report$bundle_dir, "\n", sep = "")
  if (!is.null(report$paths)) {
    cat("sir_wide: ", report$paths$sir_wide, "\n", sep = "")
    cat("sir_wide_meta: ", report$paths$sir_wide_meta, "\n", sep = "")
    cat("sample-scope reference: ", report$paths$sample_scope_reference, "\n", sep = "")
    cat("denominator bundle: ", report$paths$denominator_bundle, "\n", sep = "")
  }
  cat("Contract version: ", report$contract_version %||% "v1", "\n", sep = "")

  if (length(report$warnings) > 0L) {
    cat("Warnings:\n")
    for (line in report$warnings) {
      cat(" - ", line, "\n", sep = "")
    }
  }

  if (isTRUE(report$ok)) {
    cat("PASS: bundle matches the Orchidee external input contract.\n")
    return(invisible(report))
  }

  cat("FAIL: bundle does not match the Orchidee external input contract.\n")
  if (length(report$errors) > 0L) {
    cat("Errors:\n")
    for (line in report$errors) {
      cat(" - ", line, "\n", sep = "")
    }
  }

  invisible(report)
}

