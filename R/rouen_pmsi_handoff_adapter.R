# Rouen PMSI handoff and v2/v3 bundle composition.
#
# redsan owns PMSI source normalization. This adapter owns the Rouen unit
# attribution audit and conversion to the two PMSI-backed site inputs selected
# by each bundle contract.

rouen_pmsi_calendar_night_bound <- function(x, source_tz) {
  local_date <- as.Date(x, tz = source_tz)
  as.POSIXct(as.character(local_date), tz = "UTC")
}

build_rouen_pmsi_handoff_v1 <- function(
    sample_context,
    pmsi_main,
    unit_refs,
    ta_de_ref,
    target_start,
    target_end_exclusive
  ) {
  if (!requireNamespace("redsan", quietly = TRUE) ||
      utils::packageVersion("redsan") < numeric_version("0.2.0")) {
    stop("The Rouen PMSI adapter requires redsan >= 0.2.0.", call. = FALSE)
  }
  stopifnot(is.data.frame(sample_context), is.data.frame(pmsi_main))
  if (!is.list(unit_refs) ||
      !all(c("uf_ref", "uf2um_ref", "um_ref") %in% names(unit_refs))) {
    stop("unit_refs must contain uf_ref, uf2um_ref and um_ref.", call. = FALSE)
  }
  if (!is.data.frame(ta_de_ref)) {
    stop("ta_de_ref must be a data frame.", call. = FALSE)
  }
  if (!inherits(target_start, "Date") ||
      !inherits(target_end_exclusive, "Date") ||
      target_start >= target_end_exclusive) {
    stop("The Rouen PMSI target interval must be a valid half-open Date range.", call. = FALSE)
  }

  input_main_rows <- nrow(pmsi_main)
  pmsi_main <- redsan::prefer_pmsi_src_c_over_dw(pmsi_main)
  sample_attribution <- build_chu_sample_hospitalization_unit_attribution(
    sir_wide = sample_context,
    pmsi_main = pmsi_main
  )

  interval_tz <- ratb_resolve_posix_tz(pmsi_main$DATENT)
  target_start_datetime <- as.POSIXct(
    paste(target_start, "00:00:00"),
    tz = interval_tz
  )
  target_end_datetime <- as.POSIXct(
    paste(target_end_exclusive, "00:00:00"),
    tz = interval_tz
  )
  interval_bounds_missing <- is.na(pmsi_main$DATENT) | is.na(pmsi_main$DATSORT)
  interval_overlaps_target <- !interval_bounds_missing &
    pmsi_main$DATSORT > target_start_datetime &
    pmsi_main$DATENT < target_end_datetime
  pmsi_denominator_main <- pmsi_main |>
    dplyr::filter(interval_overlaps_target) |>
    dplyr::mutate(
      DATENT = rouen_pmsi_calendar_night_bound(
        pmax(.data$DATENT, target_start_datetime),
        interval_tz
      ),
      DATSORT = rouen_pmsi_calendar_night_bound(
        pmin(.data$DATSORT, target_end_datetime),
        interval_tz
      )
    )
  if (nrow(pmsi_denominator_main) == 0L) {
    stop("No PMSI intervals overlap the Rouen target window.", call. = FALSE)
  }

  status_lookup <- build_pmsi_status_lookup(pmsi_denominator_main)
  hospital_days <- build_hospital_days_validation(
    pmsi_main = pmsi_denominator_main,
    status_lookup = status_lookup
  )
  denominator <- build_ratb_pmsi_ta_de_denominator(
    pmsi_main = pmsi_denominator_main,
    pmsi_event_bounds = hospital_days$hospital_stays_raw |>
      dplyr::select(dplyr::all_of(c(
        "PATID", "EVTID", "datent_min", "datsort_max"
      ))),
    status_lookup = status_lookup,
    refs = unit_refs,
    consores_ta_de_ref = ta_de_ref
  )

  unit_mapping <- ta_de_ref |>
    dplyr::transmute(
      SEJUF = ratb_trim_or_na_local(.data$SEJUF),
      CODE_TA = .data$CODE_TA,
      CODE_DE = .data$CODE_DE,
      de_domain_ref = .data$de_domain_ref
    ) |>
    dplyr::filter(!is.na(.data$SEJUF)) |>
    dplyr::distinct()
  conflicting_unit_mapping <- unit_mapping |>
    dplyr::count(.data$SEJUF, name = "n_mapping_variants") |>
    dplyr::filter(.data$n_mapping_variants > 1L)
  if (nrow(conflicting_unit_mapping) > 0L) {
    stop(
      "ta_de_ref contains conflicting mappings for SEJUF: ",
      paste(utils::head(conflicting_unit_mapping$SEJUF, 10L), collapse = ", "),
      call. = FALSE
    )
  }
  missing_pmsi_units <- pmsi_denominator_main |>
    dplyr::transmute(SEJUF = ratb_trim_or_na_local(.data$SEJUF)) |>
    dplyr::filter(!is.na(.data$SEJUF)) |>
    dplyr::distinct() |>
    dplyr::anti_join(unit_mapping, by = "SEJUF") |>
    dplyr::mutate(
      CODE_TA = NA_character_,
      CODE_DE = NA_character_,
      de_domain_ref = NA_character_
    )
  unit_mapping <- dplyr::bind_rows(unit_mapping, missing_pmsi_units) |>
    dplyr::arrange(.data$SEJUF)
  denominator_by_year <- denominator$hospital_days_year_summary_provisional |>
    dplyr::transmute(
      calendar_year = as.integer(.data$calendar_year),
      hospital_nights = as.integer(.data$hospital_nights_provisional)
    ) |>
    dplyr::arrange(.data$calendar_year)
  denominator_by_year_um_uf_ta_de <-
    denominator$hospital_nights_by_year_um_uf_ta_de |>
    dplyr::transmute(
      calendar_year = as.integer(.data$calendar_year),
      SEJUM = ratb_trim_or_na_local(.data$SEJUM),
      SEJUF = ratb_trim_or_na_local(.data$SEJUF),
      CODE_TA = ratb_trim_or_na_local(.data$CODE_TA),
      CODE_DE = ratb_trim_or_na_local(.data$CODE_DE),
      hospital_nights = as.integer(.data$hospital_nights)
    ) |>
    dplyr::arrange(
      .data$calendar_year,
      .data$SEJUM,
      .data$SEJUF,
      .data$CODE_TA,
      .data$CODE_DE
    )

  denominator_identity <- denominator$hospital_nights_by_year_unit |>
    dplyr::group_by(.data$calendar_year) |>
    dplyr::summarise(
      unit_hospital_nights = sum(.data$hospital_nights, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::full_join(denominator_by_year, by = "calendar_year") |>
    dplyr::mutate(
      unit_hospital_nights = dplyr::coalesce(
        .data$unit_hospital_nights,
        0L
      ),
      hospital_nights = dplyr::coalesce(.data$hospital_nights, 0L),
      difference = .data$unit_hospital_nights - .data$hospital_nights
    ) |>
    dplyr::arrange(.data$calendar_year)
  if (any(denominator_identity$difference != 0L)) {
    stop(
      "Rouen annual denominator differs from the sum of unit-year nights.",
      call. = FALSE
    )
  }

  attribution_summary <- sample_attribution |>
    dplyr::count(
      .data$attribution_status,
      .data$attribution_reason,
      name = "n_document_occurrences"
    ) |>
    dplyr::mutate(
      meaning = dplyr::case_when(
        .data$attribution_status == "assigned_hebergement" ~
          "The sample is assigned to one hospitalization UM/UF pair.",
        .data$attribution_status == "ambiguous_hebergement" ~
          "Several hospitalization unit pairs remain active after tie-break.",
        TRUE ~
          "No hospitalization unit is assigned; canonical SEJUF stays missing."
      )
    ) |>
    dplyr::arrange(.data$attribution_status, .data$attribution_reason)
  source_policy_summary <- tibble::tibble(
    metric = c("pmsi_main_rows_before_c_over_dw", "pmsi_main_rows_after_c_over_dw"),
    value = c(input_main_rows, nrow(pmsi_main)),
    meaning = c(
      "PMSI main rows supplied to the adapter before redsan source policy.",
      "PMSI main rows retained by redsan C-over-DW source normalization."
    )
  )
  time_window_summary <- tibble::tibble(
    metric = c(
      "pmsi_rows_missing_interval_bounds",
      "pmsi_rows_ending_before_or_at_target_start",
      "pmsi_rows_starting_at_or_after_target_end",
      "pmsi_rows_overlapping_target_window"
    ),
    value = c(
      sum(interval_bounds_missing),
      sum(!is.na(pmsi_main$DATSORT) &
        pmsi_main$DATSORT <= target_start_datetime),
      sum(!is.na(pmsi_main$DATENT) &
        pmsi_main$DATENT >= target_end_datetime),
      nrow(pmsi_denominator_main)
    ),
    meaning = c(
      "Source-normalized rows whose overlap with the target window is unknowable.",
      "Rows entirely before the configured denominator window.",
      "Rows entirely after the configured denominator window.",
      paste0(
        "Rows retained and clipped to the configured half-open window; ",
        "night bounds use local calendar dates."
      )
    )
  )

  list(
    site_inputs = list(
      unit_mapping = unit_mapping,
      denominator_by_year = denominator_by_year,
      denominator_by_year_um_uf_ta_de = denominator_by_year_um_uf_ta_de
    ),
    sample_attribution = sample_attribution,
    audit = list(
      source_policy = "c_over_dw",
      source_policy_summary = source_policy_summary,
      time_window_summary = time_window_summary,
      attribution_summary = attribution_summary,
      unmapped_pmsi_units = missing_pmsi_units,
      denominator_identity = denominator_identity,
      ratb_unit_stay_scope_audit = denominator$ratb_unit_stay_scope_audit,
      hospital_nights_by_year_unit = denominator$hospital_nights_by_year_unit,
      hospital_nights_by_year_um_uf_ta_de =
        denominator$hospital_nights_by_year_um_uf_ta_de,
      hospital_days_year_summary =
        denominator$hospital_days_year_summary_provisional
    )
  )
}

compose_rouen_external_bundle <- function(
    microbiology_handoff,
    pmsi_handoff,
    contract
  ) {
  if (!is.list(microbiology_handoff) ||
      !is.list(microbiology_handoff$site_inputs) ||
      !is.list(pmsi_handoff) ||
      !is.list(pmsi_handoff$site_inputs) ||
      !is.data.frame(pmsi_handoff$sample_attribution)) {
    stop("Rouen bundle composition requires both adapter handoff objects.", call. = FALSE)
  }
  microbiology_names <- c(
    "microbiology_observations", "bacteria_mapping",
    "sample_type_mapping", "antibiotic_mapping"
  )
  contract_version <- if (is.list(contract)) contract$version else NULL
  if (!is.character(contract_version) || length(contract_version) != 1L ||
      !contract_version %in% c("v2", "v3")) {
    stop("Rouen bundle composition requires contract v2 or v3.", call. = FALSE)
  }
  denominator_input_name <- if (identical(contract_version, "v3")) {
    "denominator_by_year_um_uf_ta_de"
  } else {
    "denominator_by_year"
  }
  pmsi_names <- c("unit_mapping", denominator_input_name)
  if (!all(microbiology_names %in% names(microbiology_handoff$site_inputs)) ||
      !all(pmsi_names %in% names(pmsi_handoff$site_inputs))) {
    stop("Rouen handoff objects do not expose the expected six inputs.", call. = FALSE)
  }

  document_key <- c("PATID", "EVTID", "ELTID")
  attribution_for_join <- pmsi_handoff$sample_attribution |>
    dplyr::select(dplyr::all_of(c(
      document_key,
      "hospitalization_SEJUM_at_sampling",
      "hospitalization_SEJUF_at_sampling",
      "attribution_status",
      "attribution_reason"
    ))) |>
    dplyr::mutate(.attribution_record_found = TRUE)
  if (anyDuplicated(attribution_for_join[document_key])) {
    stop("PMSI attribution contains duplicate document occurrences.", call. = FALSE)
  }

  attributed_observations <- microbiology_handoff$site_inputs$microbiology_observations |>
    dplyr::left_join(
      attribution_for_join,
      by = document_key,
      relationship = "many-to-one"
    )
  if (any(!(attributed_observations$.attribution_record_found %in% TRUE))) {
    stop("Some microbiology observations have no PMSI attribution audit row.", call. = FALSE)
  }
  attributed_observations <- attributed_observations |>
    dplyr::mutate(
      SEJUF = dplyr::if_else(
        .data$attribution_status == "assigned_hebergement",
        .data$hospitalization_SEJUF_at_sampling,
        NA_character_
      )
    ) |>
    dplyr::select(-dplyr::all_of(".attribution_record_found"))

  site_inputs <- list(
    microbiology_observations = attributed_observations,
    bacteria_mapping = microbiology_handoff$site_inputs$bacteria_mapping,
    sample_type_mapping = microbiology_handoff$site_inputs$sample_type_mapping,
    antibiotic_mapping = microbiology_handoff$site_inputs$antibiotic_mapping,
    unit_mapping = pmsi_handoff$site_inputs$unit_mapping
  )
  site_inputs[[denominator_input_name]] <-
    pmsi_handoff$site_inputs[[denominator_input_name]]
  bundle <- orchidee_handoff_build_external_bundle_from_site_inputs(
    microbiology_observations = site_inputs$microbiology_observations,
    bacteria_mapping = site_inputs$bacteria_mapping,
    sample_type_mapping = site_inputs$sample_type_mapping,
    antibiotic_mapping = site_inputs$antibiotic_mapping,
    unit_mapping = site_inputs$unit_mapping,
    denominator_by_year = if (identical(contract$version, "v2")) {
      site_inputs$denominator_by_year
    } else {
      NULL
    },
    contract = contract,
    denominator_by_year_um_uf_ta_de = if (identical(contract$version, "v3")) {
      site_inputs$denominator_by_year_um_uf_ta_de
    } else {
      NULL
    }
  )

  validation <- list(
    sir_wide = external_bundle_validate_sir_wide(
      bundle$sir_wide,
      bundle$sir_wide_meta,
      contract = contract
    ),
    sample_scope_reference = external_bundle_validate_sample_scope_reference(
      bundle$sample_scope_reference,
      contract = contract
    ),
    denominator_bundle = external_bundle_validate_denominator_bundle(
      bundle$denominator_bundle,
      contract = contract
    )
  )
  validation_ok <- vapply(validation, function(x) isTRUE(x$ok), logical(1))
  if (!all(validation_ok)) {
    errors <- unique(unlist(lapply(validation[!validation_ok], `[[`, "errors")))
    stop(
      "Rouen ", contract$version, " bundle failed in-memory validation: ",
      paste(errors, collapse = " | "),
      call. = FALSE
    )
  }

  diagnostic_years <- sort(unique(lubridate::year(
    attributed_observations$DATEPRELEV[
      attributed_observations$ratb_diagnostic_scope %in% TRUE
    ]
  )))
  missing_denominator_years <- setdiff(
    diagnostic_years,
    site_inputs[[denominator_input_name]]$calendar_year
  )
  if (length(missing_denominator_years) > 0L) {
    stop(
      "Rouen denominator does not cover diagnostic sample years: ",
      paste(missing_denominator_years, collapse = ", "),
      call. = FALSE
    )
  }

  composition_summary <- tibble::tibble(
    metric = c(
      "six_site_inputs",
      "microbiology_observation_rows",
      "assigned_observation_rows",
      "unassigned_or_ambiguous_observation_rows",
      "canonical_sir_wide_rows"
    ),
    value = c(
      length(site_inputs),
      nrow(attributed_observations),
      sum(attributed_observations$attribution_status == "assigned_hebergement"),
      sum(attributed_observations$attribution_status != "assigned_hebergement"),
      nrow(bundle$sir_wide)
    ),
    meaning = c(
      "The four microbiology and two PMSI blocks passed to the shared builder.",
      "Long rows available before shared screening/document collapse.",
      "Long rows whose canonical SEJUF comes from active PMSI hospitalization.",
      "Long rows kept visible with missing canonical SEJUF and no fallback.",
      "Canonical isolates in the validated v2 bundle."
    )
  )

  list(
    site_inputs = site_inputs,
    bundle = bundle,
    validation = validation,
    audit = list(
      microbiology = microbiology_handoff$audit,
      pmsi = pmsi_handoff$audit,
      sample_attribution = pmsi_handoff$sample_attribution,
      composition_summary = composition_summary
    )
  )
}

compose_rouen_external_bundle_v2 <- function(
    microbiology_handoff,
    pmsi_handoff
  ) {
  compose_rouen_external_bundle(
    microbiology_handoff = microbiology_handoff,
    pmsi_handoff = pmsi_handoff,
    contract = orchidee_external_contract_v2()
  )
}

compose_rouen_external_bundle_v3 <- function(
    microbiology_handoff,
    pmsi_handoff
  ) {
  compose_rouen_external_bundle(
    microbiology_handoff = microbiology_handoff,
    pmsi_handoff = pmsi_handoff,
    contract = orchidee_external_contract_v3()
  )
}
