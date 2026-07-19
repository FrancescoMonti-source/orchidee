# Rouen raw bacteriology to the four microbiology site-handoff blocks.
#
# This adapter owns local screening and mapping decisions. The shared handoff
# builder remains responsible for document exclusion and the canonical wide
# artifact.

rouen_handoff_require_columns <- function(data, required, label) {
  if (!is.data.frame(data)) {
    stop(label, " must be a data frame.", call. = FALSE)
  }
  missing <- setdiff(required, names(data))
  if (length(missing) > 0L) {
    stop(
      label, " is missing required columns: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  invisible(data)
}

rouen_handoff_clean_label <- function(x) {
  x <- stringr::str_squish(as.character(x))
  x[x == ""] <- NA_character_
  x
}

rouen_handoff_sample_type_key <- function(x) {
  x <- rouen_handoff_clean_label(x)
  x <- stringi::stri_trans_general(x, "Latin-ASCII")
  x <- stringr::str_to_upper(stringr::str_squish(x))
  x[x == ""] <- NA_character_
  x
}

rouen_handoff_prepare_sample_type_mapping <- function(
    local_labels,
    sample_type_rules,
    exact_decisions
  ) {
  rouen_handoff_require_columns(
    sample_type_rules,
    c("pattern", "naturepvt_norm"),
    "sample_type_rules"
  )
  rouen_handoff_require_columns(
    exact_decisions,
    c(
      "naturepvt_audit_key", "decision_action", "naturepvt_norm",
      "decision_reason"
    ),
    "exact_decisions"
  )

  rules <- sample_type_rules |>
    dplyr::transmute(
      rule_id = dplyr::row_number(),
      pattern = rouen_handoff_clean_label(.data$pattern),
      target = rouen_handoff_clean_label(.data$naturepvt_norm),
      rule_reason = if ("decision_reason" %in% names(sample_type_rules)) {
        rouen_handoff_clean_label(.data$decision_reason)
      } else {
        NA_character_
      }
    ) |>
    dplyr::filter(!is.na(.data$pattern), !is.na(.data$target))

  decisions <- exact_decisions |>
    dplyr::transmute(
      naturepvt_audit_key = rouen_handoff_sample_type_key(
        .data$naturepvt_audit_key
      ),
      decision_action = stringr::str_to_lower(
        rouen_handoff_clean_label(.data$decision_action)
      ),
      decision_target = rouen_handoff_clean_label(.data$naturepvt_norm),
      decision_reason = rouen_handoff_clean_label(.data$decision_reason)
    )

  if (anyDuplicated(decisions$naturepvt_audit_key)) {
    stop("exact_decisions contains duplicate audit keys.", call. = FALSE)
  }
  if (any(!decisions$decision_action %in% c("map", "defer"))) {
    stop("exact_decisions action must be map or defer.", call. = FALSE)
  }
  if (any(
    decisions$decision_action == "map" & is.na(decisions$decision_target)
  )) {
    stop("Mapped exact decisions require naturepvt_norm.", call. = FALSE)
  }

  labels <- tibble::tibble(
    sample_type_local = sort(unique(rouen_handoff_clean_label(local_labels)))
  ) |>
    dplyr::filter(!is.na(.data$sample_type_local)) |>
    dplyr::mutate(
      naturepvt_audit_key = rouen_handoff_sample_type_key(
        .data$sample_type_local
      )
    )

  rule_hits <- tidyr::crossing(labels, rules) |>
    dplyr::filter(stringr::str_detect(
      .data$naturepvt_audit_key,
      stringr::regex(.data$pattern)
    ))

  candidates <- rule_hits |>
    dplyr::group_by(.data$sample_type_local, .data$naturepvt_audit_key) |>
    dplyr::summarise(
      n_patterns = dplyr::n(),
      n_targets = dplyr::n_distinct(.data$target),
      candidate_targets = paste(sort(unique(.data$target)), collapse = " | "),
      candidate_target = if (dplyr::n_distinct(.data$target) == 1L) {
        sort(unique(.data$target))[[1L]]
      } else {
        NA_character_
      },
      .groups = "drop"
    )

  review <- labels |>
    dplyr::left_join(
      candidates,
      by = c("sample_type_local", "naturepvt_audit_key"),
      relationship = "one-to-one"
    ) |>
    dplyr::left_join(
      decisions,
      by = "naturepvt_audit_key",
      relationship = "many-to-one"
    ) |>
    dplyr::mutate(
      candidate_state = dplyr::case_when(
        is.na(.data$n_patterns) ~ "unmatched",
        .data$n_targets == 1L & .data$n_patterns == 1L ~
          "one_pattern_one_target",
        .data$n_targets == 1L ~ "multiple_patterns_same_target",
        TRUE ~ "multiple_canonical_targets"
      ),
      mapping_state = dplyr::case_when(
        .data$decision_action == "map" ~ "reviewed_override",
        .data$decision_action == "defer" ~ "review_deferred",
        TRUE ~ .data$candidate_state
      ),
      naturepvt_norm = dplyr::case_when(
        .data$decision_action == "map" ~ .data$decision_target,
        .data$decision_action == "defer" ~ NA_character_,
        .data$n_targets == 1L ~ .data$candidate_target,
        TRUE ~ NA_character_
      )
    ) |>
    dplyr::arrange(.data$sample_type_local)

  list(
    mapping = review |>
      dplyr::select(dplyr::all_of(c("sample_type_local", "naturepvt_norm"))),
    review = review,
    rule_hits = rule_hits
  )
}

rouen_handoff_build_species_lookup <- function(local_labels, species_rules) {
  labels <- tibble::tibble(
    IDENTIFICATION = sort(unique(rouen_handoff_clean_label(local_labels)))
  ) |>
    dplyr::filter(!is.na(.data$IDENTIFICATION))

  lookup <- normalize_bact(labels, species_rules) |>
    dplyr::rename(bacteria_local = "IDENTIFICATION")

  ambiguous_label <- stringr::str_detect(
    lookup$bacteria_local,
    stringr::regex("\\b(?:et\\s*/\\s*ou|ou)\\b", ignore_case = TRUE)
  )
  ambiguous_label[is.na(ambiguous_label)] <- FALSE
  lookup$taxon_type[ambiguous_label] <- "ambiguous"
  lookup$bact_norm[ambiguous_label] <- NA_character_
  lookup$bact_genus[ambiguous_label] <- NA_character_
  lookup$bact_family[ambiguous_label] <- NA_character_
  lookup$bact_order[ambiguous_label] <- NA_character_
  lookup$bact_matched[ambiguous_label] <- FALSE
  lookup$rouen_ambiguity_guard <- ambiguous_label
  lookup
}

rouen_handoff_prepare_mapping_tables <- function(
    observations,
    diagnostic_raw,
    species_rules,
    antibiotic_rules,
    antibiotic_expansion,
    supported_species_antibiotics
  ) {
  rouen_handoff_require_columns(
    antibiotic_expansion,
    c("atb_norm_source", "atb_norm_target"),
    "antibiotic_expansion"
  )
  rouen_handoff_require_columns(
    supported_species_antibiotics,
    c("bact_norm", "atb_norm"),
    "supported_species_antibiotics"
  )

  expansion <- antibiotic_expansion |>
    dplyr::transmute(
      atb_norm_source = rouen_handoff_clean_label(.data$atb_norm_source),
      atb_norm_target = rouen_handoff_clean_label(.data$atb_norm_target)
    )
  if (any(is.na(expansion$atb_norm_source)) ||
      any(is.na(expansion$atb_norm_target))) {
    stop("antibiotic_expansion cannot contain missing values.", call. = FALSE)
  }
  if (anyDuplicated(expansion)) {
    stop("antibiotic_expansion contains duplicate source/target pairs.", call. = FALSE)
  }

  species_lookup <- rouen_handoff_build_species_lookup(
    diagnostic_raw$IDENTIFICATION,
    species_rules
  )
  bacteria_counts <- observations |>
    dplyr::filter(.data$ratb_diagnostic_scope) |>
    dplyr::count(.data$bacteria_local, name = "n_sir_rows")
  bacteria_review <- bacteria_counts |>
    dplyr::left_join(
      species_lookup,
      by = "bacteria_local",
      relationship = "one-to-one"
    )

  base_pairs <- supported_species_antibiotics |>
    dplyr::transmute(
      bact_norm = as.character(.data$bact_norm),
      atb_norm = as.character(.data$atb_norm)
    ) |>
    dplyr::filter(!is.na(.data$bact_norm), !is.na(.data$atb_norm)) |>
    dplyr::distinct()
  ecoli_panel <- base_pairs |>
    dplyr::filter(.data$bact_norm == "escherichia_coli") |>
    dplyr::distinct(.data$atb_norm) |>
    dplyr::pull(.data$atb_norm)
  if (length(ecoli_panel) == 0L) {
    stop("The supported pair table has no escherichia_coli panel.", call. = FALSE)
  }
  unsupported_expansion_targets <- setdiff(
    unique(expansion$atb_norm_target),
    unique(base_pairs$atb_norm)
  )
  if (length(unsupported_expansion_targets) > 0L) {
    stop(
      "antibiotic_expansion contains targets outside the RATB panel: ",
      paste(unsupported_expansion_targets, collapse = ", "),
      call. = FALSE
    )
  }

  enterobacterales_extension <- bacteria_review |>
    dplyr::filter(
      !is.na(.data$bact_norm),
      .data$bact_order == "Enterobacterales",
      !.data$bact_norm %in% base_pairs$bact_norm
    ) |>
    dplyr::distinct(.data$bact_norm)
  effective_pairs <- dplyr::bind_rows(
    base_pairs,
    tidyr::crossing(
      bact_norm = enterobacterales_extension$bact_norm,
      atb_norm = sort(ecoli_panel)
    )
  ) |>
    dplyr::distinct()

  bacteria_review <- bacteria_review |>
    dplyr::mutate(
      mapping_state = dplyr::case_when(
        is.na(.data$bact_norm) ~ "unresolved_or_excluded",
        .data$bact_norm %in% base_pairs$bact_norm ~ "supported_explicit_panel",
        .data$bact_norm %in% enterobacterales_extension$bact_norm ~
          "supported_enterobacterales_extension",
        TRUE ~ "outside_supported_panel"
      )
    )

  antibiotic_counts <- observations |>
    dplyr::filter(.data$ratb_diagnostic_scope) |>
    dplyr::count(.data$antibiotic_local, name = "n_sir_rows")
  antibiotic_lookup <- normalise_atb(
    antibiotic_counts |>
      dplyr::transmute(
        LBLANA = .data$antibiotic_local,
        LBLRES = "SIR"
      ),
    antibiotic_rules
  ) |>
    dplyr::rename(
      antibiotic_local = "LBLANA",
      atb_norm_source = "atb_norm"
    )

  expandable_sources <- unique(as.character(
    expansion$atb_norm_source
  ))
  supported_targets <- unique(effective_pairs$atb_norm)
  antibiotic_review <- antibiotic_counts |>
    dplyr::left_join(
      antibiotic_lookup,
      by = "antibiotic_local",
      relationship = "one-to-one"
    ) |>
    dplyr::mutate(
      mapping_state = dplyr::case_when(
        is.na(.data$atb_norm_source) ~ "unmapped_or_excluded",
        .data$atb_norm_source %in% expandable_sources ~ "expandable_class",
        .data$atb_norm_source %in% supported_targets ~ "direct_supported_atb",
        TRUE ~ "mapped_outside_ratb_panel"
      )
    )

  list(
    species_lookup = species_lookup,
    bacteria_review = bacteria_review,
    antibiotic_review = antibiotic_review,
    antibiotic_expansion = expansion,
    effective_pairs = effective_pairs,
    enterobacterales_extension = enterobacterales_extension
  )
}

build_rouen_microbiology_handoff_v1 <- function(
    bacteriology_raw,
    screening_typeana_codes,
    target_start,
    target_end_exclusive,
    species_rules,
    sample_type_rules,
    sample_type_exact_decisions,
    antibiotic_rules,
    antibiotic_expansion,
    supported_species_antibiotics
  ) {
  required <- c(
    "PATID", "EVTID", "ELTID", "DATEPRELEV", "HEUREPRELEV",
    "SEJUM", "SEJUF", "DLVL", "TYPEANA", "LBLANA", "LBLRES",
    "STRRES", "IDENTIFICATION", "NATUREPVT", "TRI"
  )
  rouen_handoff_require_columns(bacteriology_raw, required, "bacteriology_raw")
  if (!inherits(target_start, "Date") ||
      !inherits(target_end_exclusive, "Date") ||
      target_start >= target_end_exclusive) {
    stop("The Rouen target interval must be a valid half-open Date range.", call. = FALSE)
  }

  document_key <- c("PATID", "EVTID", "ELTID")
  raw_rows_received <- nrow(bacteriology_raw)
  date_source <- bacteriology_raw$DATEPRELEV
  date_source_text <- rouen_handoff_clean_label(date_source)
  parsed_date <- if (inherits(date_source, "Date")) {
    date_source
  } else if (inherits(date_source, "POSIXt")) {
    as.Date(date_source)
  } else if (is.numeric(date_source)) {
    as.Date(date_source, origin = "1970-01-01")
  } else {
    parsed_ymd <- suppressWarnings(as.Date(date_source_text, format = "%Y-%m-%d"))
    parsed_dmy <- suppressWarnings(as.Date(date_source_text, format = "%d/%m/%Y"))
    dplyr::coalesce(parsed_ymd, parsed_dmy)
  }
  n_missing_date <- sum(is.na(date_source_text))
  n_invalid_date <- sum(!is.na(date_source_text) & is.na(parsed_date))
  if (n_missing_date > 0L || n_invalid_date > 0L) {
    stop(
      "Rouen bacteriology DATEPRELEV is missing on ", n_missing_date,
      " rows and invalid on ", n_invalid_date, " rows.",
      call. = FALSE
    )
  }
  raw_rows_before_target <- sum(parsed_date < target_start)
  raw_rows_after_target <- sum(parsed_date >= target_end_exclusive)

  target_raw <- bacteriology_raw |>
    dplyr::mutate(
      DATEPRELEV = parsed_date,
      PATID = rouen_handoff_clean_label(.data$PATID),
      EVTID = rouen_handoff_clean_label(.data$EVTID),
      ELTID = rouen_handoff_clean_label(.data$ELTID)
    ) |>
    dplyr::filter(
      .data$DATEPRELEV >= target_start,
      .data$DATEPRELEV < target_end_exclusive
    )
  if (nrow(target_raw) == 0L) {
    stop("No Rouen bacteriology rows fall inside the target interval.", call. = FALSE)
  }
  required_document_key <- c("PATID", "ELTID")
  missing_document_key <- vapply(
    required_document_key,
    function(col) any(is.na(target_raw[[col]])),
    logical(1)
  )
  if (any(missing_document_key)) {
    stop(
      "Rouen bacteriology document keys cannot be missing: ",
      paste(required_document_key[missing_document_key], collapse = ", "),
      call. = FALSE
    )
  }

  document_evtid_resolution <- target_raw |>
    dplyr::group_by(.data$PATID, .data$ELTID) |>
    dplyr::summarise(
      n_nonmissing_evtid = dplyr::n_distinct(.data$EVTID, na.rm = TRUE),
      has_missing_evtid = any(is.na(.data$EVTID)),
      resolved_evtid = if (.data$n_nonmissing_evtid == 1L) {
        unique(stats::na.omit(.data$EVTID))[[1L]]
      } else {
        NA_character_
      },
      .groups = "drop"
    )
  ambiguous_missing_evtid <- document_evtid_resolution |>
    dplyr::filter(.data$has_missing_evtid, .data$n_nonmissing_evtid > 1L)
  if (nrow(ambiguous_missing_evtid) > 0L) {
    stop(
      "Rouen bacteriology has missing EVTID rows that cannot be assigned ",
      "unambiguously within PATID + ELTID.",
      call. = FALSE
    )
  }
  target_raw <- target_raw |>
    dplyr::left_join(
      document_evtid_resolution |>
        dplyr::select(dplyr::all_of(c("PATID", "ELTID", "resolved_evtid"))),
      by = c("PATID", "ELTID"),
      relationship = "many-to-one"
    )
  evtid_rows_filled_from_document <- sum(
    is.na(target_raw$EVTID) & !is.na(target_raw$resolved_evtid)
  )
  target_raw <- target_raw |>
    dplyr::mutate(EVTID = dplyr::coalesce(.data$EVTID, .data$resolved_evtid)) |>
    dplyr::select(-dplyr::all_of("resolved_evtid"))

  document_scope <- target_raw |>
    dplyr::group_by(dplyr::across(dplyr::all_of(document_key))) |>
    dplyr::summarise(
      is_screening = any(.data$TYPEANA %in% screening_typeana_codes),
      has_sir = any(
        stringr::str_to_upper(rouen_handoff_clean_label(.data$LBLRES)) == "SIR",
        na.rm = TRUE
      ),
      .groups = "drop"
    )
  screening_documents <- document_scope |>
    dplyr::filter(.data$is_screening) |>
    dplyr::select(dplyr::all_of(document_key))
  screening_documents_with_sir <- document_scope |>
    dplyr::filter(.data$is_screening, .data$has_sir) |>
    dplyr::select(dplyr::all_of(document_key))
  screening_rows_all_raw <- target_raw |>
    dplyr::semi_join(screening_documents, by = document_key)

  sir_rows <- target_raw |>
    dplyr::filter(
      stringr::str_to_upper(rouen_handoff_clean_label(.data$LBLRES)) == "SIR"
    ) |>
    dplyr::mutate(source_row_order = dplyr::row_number())
  if (nrow(sir_rows) == 0L) {
    stop("No Rouen SIR rows fall inside the target interval.", call. = FALSE)
  }
  screening_sir_rows <- sir_rows |>
    dplyr::semi_join(screening_documents, by = document_key)

  sample_context <- sir_rows |>
    dplyr::transmute(
      PATID = .data$PATID,
      EVTID = .data$EVTID,
      ELTID = .data$ELTID,
      DATEPRELEV = .data$DATEPRELEV,
      HEUREPRELEV = orchidee_handoff_parse_time(.data$HEUREPRELEV),
      SEJUM = rouen_handoff_clean_label(.data$SEJUM),
      SEJUF = rouen_handoff_clean_label(.data$SEJUF)
    ) |>
    dplyr::distinct()
  context_conflicts <- sample_context |>
    dplyr::count(
      dplyr::across(dplyr::all_of(document_key)),
      name = "n_context_variants"
    ) |>
    dplyr::filter(.data$n_context_variants > 1L)
  if (nrow(context_conflicts) > 0L) {
    stop(
      "Rouen sample attribution requires one datetime and microbiology ",
      "UM/UF pair per PATID + EVTID + ELTID.",
      call. = FALSE
    )
  }

  observations <- sir_rows |>
    dplyr::left_join(
      document_scope |>
        dplyr::select(dplyr::all_of(c(document_key, "is_screening"))),
      by = document_key,
      relationship = "many-to-one"
    ) |>
    dplyr::transmute(
      PATID = .data$PATID,
      EVTID = .data$EVTID,
      ELTID = .data$ELTID,
      DATEPRELEV = .data$DATEPRELEV,
      HEUREPRELEV = orchidee_handoff_parse_time(.data$HEUREPRELEV),
      microbiology_SEJUM = rouen_handoff_clean_label(.data$SEJUM),
      microbiology_SEJUF = rouen_handoff_clean_label(.data$SEJUF),
      SEJUF = rouen_handoff_clean_label(.data$SEJUF),
      souche_id = rouen_handoff_clean_label(.data$DLVL),
      bacteria_local = rouen_handoff_clean_label(.data$IDENTIFICATION),
      sample_type_local = rouen_handoff_clean_label(.data$NATUREPVT),
      antibiotic_local = rouen_handoff_clean_label(.data$LBLANA),
      sir_result_source = as.character(.data$STRRES),
      sir_result = orchidee_handoff_normalize_sir(.data$STRRES),
      ratb_diagnostic_scope = !.data$is_screening,
      source_tri = .data$TRI,
      source_row_order = .data$source_row_order
    )

  unsupported_sir <- sort(unique(observations$sir_result[
    !is.na(observations$sir_result) &
      !observations$sir_result %in% c("S", "R", "ZIT")
  ]))
  if (length(unsupported_sir) > 0L) {
    stop(
      "Rouen SIR normalization produced unsupported values: ",
      paste(utils::head(unsupported_sir, 10L), collapse = ", "),
      call. = FALSE
    )
  }

  diagnostic_raw <- target_raw |>
    dplyr::anti_join(screening_documents, by = document_key)
  sample_type <- rouen_handoff_prepare_sample_type_mapping(
    observations$sample_type_local[observations$ratb_diagnostic_scope],
    sample_type_rules,
    sample_type_exact_decisions
  )
  mappings <- rouen_handoff_prepare_mapping_tables(
    observations = observations,
    diagnostic_raw = diagnostic_raw,
    species_rules = species_rules,
    antibiotic_rules = antibiotic_rules,
    antibiotic_expansion = antibiotic_expansion,
    supported_species_antibiotics = supported_species_antibiotics
  )

  diagnostic_mapped_base <- observations |>
    dplyr::filter(.data$ratb_diagnostic_scope, !is.na(.data$sir_result)) |>
    dplyr::left_join(
      mappings$bacteria_review |>
        dplyr::select(dplyr::all_of(c(
          "bacteria_local", "bact_norm", "mapping_state"
        ))) |>
        dplyr::rename(bacteria_mapping_state = "mapping_state"),
      by = "bacteria_local",
      relationship = "many-to-one"
    ) |>
    dplyr::left_join(
      mappings$antibiotic_review |>
        dplyr::select(dplyr::all_of(c(
          "antibiotic_local", "atb_norm_source", "mapping_state"
        ))) |>
        dplyr::rename(antibiotic_mapping_state = "mapping_state"),
      by = "antibiotic_local",
      relationship = "many-to-one"
    ) |>
    dplyr::filter(
      .data$bacteria_mapping_state %in% c(
        "supported_explicit_panel",
        "supported_enterobacterales_extension"
      ),
      .data$antibiotic_mapping_state %in% c(
        "direct_supported_atb",
        "expandable_class"
      )
    )

  explicit_rows <- diagnostic_mapped_base |>
    dplyr::filter(.data$antibiotic_mapping_state == "direct_supported_atb") |>
    dplyr::mutate(
      atb_norm = .data$atb_norm_source,
      atb_match_origin = "explicit",
      .origin_rank = 1L
    )
  expanded_rows <- diagnostic_mapped_base |>
    dplyr::filter(.data$antibiotic_mapping_state == "expandable_class") |>
    dplyr::inner_join(
      mappings$antibiotic_expansion,
      by = "atb_norm_source",
      relationship = "many-to-many"
    ) |>
    dplyr::mutate(
      atb_norm = .data$atb_norm_target,
      atb_match_origin = "expanded",
      .origin_rank = 0L
    ) |>
    dplyr::select(-dplyr::all_of("atb_norm_target"))

  supported_rows <- dplyr::bind_rows(explicit_rows, expanded_rows) |>
    dplyr::semi_join(
      mappings$effective_pairs,
      by = c("bact_norm", "atb_norm")
    ) |>
    dplyr::arrange(
      .data$PATID, .data$EVTID, .data$ELTID, .data$DATEPRELEV,
      .data$HEUREPRELEV, .data$souche_id, .data$bact_norm, .data$atb_norm,
      .data$.origin_rank, .data$source_tri, .data$source_row_order
    ) |>
    dplyr::mutate(handoff_row_order = dplyr::row_number()) |>
    dplyr::select(-dplyr::all_of(".origin_rank"))
  if (nrow(supported_rows) == 0L) {
    stop("No supported Rouen species/antibiotic observations remain.", call. = FALSE)
  }

  candidate_keys <- supported_rows |>
    dplyr::left_join(
      sample_type$mapping,
      by = "sample_type_local",
      relationship = "many-to-one"
    ) |>
    dplyr::transmute(
      PATID = .data$PATID,
      EVTID = .data$EVTID,
      ELTID = .data$ELTID,
      DATEPRELEV = .data$DATEPRELEV,
      souche_id = .data$souche_id,
      naturepvt_norm = orchidee_handoff_ascii_lower(.data$naturepvt_norm),
      bact_norm = .data$bact_norm
    ) |>
    dplyr::distinct()
  phenotype_key <- c(
    "PATID", "EVTID", "ELTID", "DATEPRELEV", "souche_id",
    "naturepvt_norm", "bact_norm"
  )
  coarse_key <- c("PATID", "EVTID", "ELTID", "DATEPRELEV", "souche_id")

  raw_for_phenotypes <- diagnostic_raw |>
    dplyr::transmute(
      PATID = .data$PATID,
      EVTID = .data$EVTID,
      ELTID = .data$ELTID,
      DATEPRELEV = .data$DATEPRELEV,
      souche_id = rouen_handoff_clean_label(.data$DLVL),
      bacteria_local = rouen_handoff_clean_label(.data$IDENTIFICATION),
      sample_type_local = rouen_handoff_clean_label(.data$NATUREPVT),
      LBLANA = .data$LBLANA,
      LBLRES = .data$LBLRES,
      STRRES = .data$STRRES
    ) |>
    dplyr::semi_join(
      candidate_keys |>
        dplyr::select(dplyr::all_of(coarse_key)),
      by = coarse_key
    ) |>
    dplyr::left_join(
      mappings$species_lookup |>
        dplyr::select(dplyr::all_of(c("bacteria_local", "bact_norm"))),
      by = "bacteria_local",
      relationship = "many-to-one"
    ) |>
    dplyr::left_join(
      sample_type$mapping |>
        dplyr::mutate(.sample_type_mapping_found = TRUE),
      by = "sample_type_local",
      relationship = "many-to-one"
    ) |>
    dplyr::mutate(
      naturepvt_norm = orchidee_handoff_ascii_lower(.data$naturepvt_norm)
    )

  phenotype_lookup_raw <- build_phenotype_status_lookup(
    raw_for_phenotypes,
    key_cols = phenotype_key
  )
  phenotype_lookup <- candidate_keys |>
    dplyr::left_join(
      phenotype_lookup_raw,
      by = phenotype_key,
      relationship = "one-to-one"
    ) |>
    dplyr::mutate(
      blse_status_row = dplyr::coalesce(.data$blse_status_row, "no_signal"),
      carbapenemase_status_row = dplyr::coalesce(
        .data$carbapenemase_status_row,
        "no_signal"
      )
    )
  unsupported_blse <- setdiff(
    unique(phenotype_lookup$blse_status_row),
    c("positive", "negative", "no_signal")
  )
  unsupported_carbapenemase <- setdiff(
    unique(phenotype_lookup$carbapenemase_status_row),
    c("positive", "negative", "unknown", "no_signal")
  )
  if (length(unsupported_blse) > 0L ||
      length(unsupported_carbapenemase) > 0L) {
    stop(
      "Rouen phenotype status is outside the ratified vocabulary. ",
      "BLSE: ", paste(unsupported_blse, collapse = ", "),
      "; carbapenemase: ",
      paste(unsupported_carbapenemase, collapse = ", "),
      call. = FALSE
    )
  }

  signal_rows <- raw_for_phenotypes |>
    dplyr::mutate(
      blse_status_line = classify_blse_row(
        .data$LBLANA, .data$LBLRES, .data$STRRES
      ),
      carbapenemase_status_line = classify_carbapenemase_row(
        .data$LBLANA, .data$LBLRES, .data$STRRES
      )
    ) |>
    dplyr::filter(
      !is.na(.data$blse_status_line) |
        !is.na(.data$carbapenemase_status_line)
    )
  signal_key_failures <- signal_rows |>
    dplyr::anti_join(candidate_keys, by = phenotype_key)
  signal_gate <- tibble::tibble(
    n_signal_rows = nrow(signal_rows),
    n_nonmissing_sample_labels_without_mapping = sum(
      !is.na(signal_rows$sample_type_local) &
        !(signal_rows$.sample_type_mapping_found %in% TRUE)
    ),
    n_signal_rows_without_bact_norm = sum(is.na(signal_rows$bact_norm)),
    n_signal_rows_without_exact_candidate_key = nrow(signal_key_failures)
  )
  if (any(signal_gate[1L, -1L] != 0L)) {
    stop(
      "Rouen phenotype signals do not all resolve to an exact candidate ",
      "isolate key; inspect the adapter audit before building a bundle.",
      call. = FALSE
    )
  }

  diagnostic_observations <- supported_rows |>
    dplyr::left_join(
      sample_type$mapping,
      by = "sample_type_local",
      relationship = "many-to-one"
    ) |>
    dplyr::mutate(
      naturepvt_norm = orchidee_handoff_ascii_lower(.data$naturepvt_norm)
    ) |>
    dplyr::left_join(
      phenotype_lookup |>
        dplyr::select(dplyr::all_of(c(
          phenotype_key, "blse_status_row", "carbapenemase_status_row"
        ))),
      by = phenotype_key,
      relationship = "many-to-one"
    ) |>
    dplyr::transmute(
      .data$PATID, .data$EVTID, .data$ELTID, .data$DATEPRELEV,
      .data$HEUREPRELEV, .data$microbiology_SEJUM,
      .data$microbiology_SEJUF, .data$SEJUF, .data$souche_id,
      .data$bacteria_local, .data$sample_type_local,
      antibiotic_local_source = .data$antibiotic_local,
      antibiotic_local = .data$atb_norm,
      .data$sir_result_source, .data$sir_result,
      .data$ratb_diagnostic_scope, .data$blse_status_row,
      .data$carbapenemase_status_row, .data$atb_match_origin,
      .data$source_tri, .data$source_row_order, .data$handoff_row_order
    )

  screening_observations <- observations |>
    dplyr::filter(!.data$ratb_diagnostic_scope) |>
    dplyr::mutate(
      antibiotic_local_source = .data$antibiotic_local,
      blse_status_row = NA_character_,
      carbapenemase_status_row = NA_character_,
      atb_match_origin = NA_character_,
      handoff_row_order = NA_integer_
    ) |>
    dplyr::select(dplyr::all_of(names(diagnostic_observations)))

  microbiology_observations <- dplyr::bind_rows(
    screening_observations,
    diagnostic_observations
  )
  bacteria_mapping <- supported_rows |>
    dplyr::distinct(.data$bacteria_local, .data$bact_norm) |>
    dplyr::arrange(.data$bacteria_local)
  antibiotic_mapping <- supported_rows |>
    dplyr::distinct(.data$atb_norm) |>
    dplyr::transmute(
      antibiotic_local = .data$atb_norm,
      atb_norm = .data$atb_norm
    ) |>
    dplyr::arrange(.data$antibiotic_local)

  audit_summary <- tibble::tibble(
    metric = c(
      "raw_rows_received",
      "raw_rows_missing_date",
      "raw_rows_invalid_date",
      "raw_rows_before_target_period",
      "raw_rows_at_or_after_target_end",
      "raw_rows_in_target_period",
      "sir_rows_before_screening",
      "screening_document_occurrences_all_raw",
      "screening_document_occurrences_with_sir",
      "screening_rows_all_raw",
      "screening_sir_rows",
      "rows_evtid_filled_from_document",
      "document_occurrences_without_evtid",
      "diagnostic_rows_with_supported_species_atb",
      "sample_type_labels_unresolved",
      "phenotype_signal_rows"
    ),
    value = c(
      raw_rows_received,
      n_missing_date,
      n_invalid_date,
      raw_rows_before_target,
      raw_rows_after_target,
      nrow(target_raw),
      nrow(sir_rows),
      nrow(screening_documents),
      nrow(screening_documents_with_sir),
      nrow(screening_rows_all_raw),
      nrow(screening_sir_rows),
      evtid_rows_filled_from_document,
      sum(is.na(document_scope$EVTID)),
      nrow(diagnostic_observations),
      sum(is.na(sample_type$mapping$naturepvt_norm)),
      nrow(signal_rows)
    ),
    meaning = c(
      "All raw Rouen bacteriology rows supplied to the adapter.",
      "Rows whose sample date is missing; successful runs require zero.",
      "Rows whose sample date cannot be parsed; successful runs require zero.",
      "Rows dated before the configured target interval.",
      "Rows dated at or after the exclusive target end.",
      "All raw Rouen bacteriology rows inside the configured half-open window.",
      "Long SIR rows before document-occurrence screening is applied.",
      "All document occurrences carrying at least one screening marker.",
      "Screening document occurrences that also contain at least one SIR row.",
      "All raw rows belonging to document occurrences marked as screening.",
      "SIR rows belonging to document occurrences marked as screening.",
      "Rows whose missing EVTID was filled from one unambiguous PATID + ELTID document occurrence.",
      "Occurrences using the conservative PATID + ELTID document fallback.",
      "Expanded long rows retained after supported species/ATB filtering.",
      "Exact local sample labels deliberately left without a canonical type.",
      "Raw BLSE/carbapenemase signal rows attributed to candidate isolates."
    )
  )

  list(
    site_inputs = list(
      microbiology_observations = microbiology_observations,
      bacteria_mapping = bacteria_mapping,
      sample_type_mapping = sample_type$mapping,
      antibiotic_mapping = antibiotic_mapping
    ),
    sample_context = sample_context,
    audit = list(
      summary = audit_summary,
      document_scope = document_scope,
      sample_type_review = sample_type$review,
      sample_type_rule_hits = sample_type$rule_hits,
      bacteria_review = mappings$bacteria_review,
      antibiotic_review = mappings$antibiotic_review,
      phenotype_signal_gate = signal_gate,
      enterobacterales_extension = mappings$enterobacterales_extension
    )
  )
}
