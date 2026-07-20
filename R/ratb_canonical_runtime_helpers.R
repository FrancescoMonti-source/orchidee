## RATB canonical runtime helpers.
##
## This file is HDW-agnostic. It starts from canonical ORCHIDEE inputs:
## `sir_wide`, `sample_scope_reference`, and `denominator_bundle`.

ratb_canonical_trim_or_na <- function(x) {
  x <- trimws(as.character(x))
  x[!nzchar(x)] <- NA_character_
  x
}

ratb_canonical_prepare_sample_scope_reference <- function(sample_scope_reference) {
  sample_scope_reference <- sample_scope_reference %>%
    dplyr::mutate(SEJUF = ratb_canonical_trim_or_na(SEJUF))

  if (any(is.na(sample_scope_reference$SEJUF))) {
    stop(
      "Sample scope reference contains missing SEJUF values.",
      call. = FALSE
    )
  }

  duplicate_sejuf <- unique(sample_scope_reference$SEJUF[
    duplicated(sample_scope_reference$SEJUF)
  ])
  if (length(duplicate_sejuf) > 0L) {
    stop(
      "Sample scope reference contains duplicate SEJUF values: ",
      paste(utils::head(duplicate_sejuf, 10L), collapse = ", "),
      if (length(duplicate_sejuf) > 10L) ", ..." else "",
      call. = FALSE
    )
  }

  sample_scope_reference
}

apply_ratb_sample_ta_de_scope <- function(sir_wide, sample_scope_reference) {
  stopifnot(is.data.frame(sir_wide), is.data.frame(sample_scope_reference))
  stopifnot(all(c("PATID", "EVTID", "SEJUF") %in% names(sir_wide)))

  required_ref_cols <- c(
    "SEJUF",
    "sample_uf_is_eligible_by_ta_de",
    "sample_uf_ta_de_status",
    "sample_uf_ta_de_reason"
  )
  missing_ref_cols <- setdiff(required_ref_cols, names(sample_scope_reference))
  if (length(missing_ref_cols) > 0L) {
    stop(
      "Sample scope reference is missing required columns: ",
      paste(missing_ref_cols, collapse = ", "),
      call. = FALSE
    )
  }

  sample_scope_reference <- ratb_canonical_prepare_sample_scope_reference(
    sample_scope_reference
  ) %>%
    dplyr::mutate(.orchidee_scope_reference_matched = TRUE)

  sir_wide %>%
    dplyr::mutate(
      PATID = as.character(PATID),
      EVTID = as.character(EVTID),
      SEJUF = ratb_canonical_trim_or_na(SEJUF)
    ) %>%
    dplyr::left_join(
      sample_scope_reference,
      by = "SEJUF"
    ) %>%
    dplyr::mutate(
      sample_uf_is_eligible_by_ta_de = dplyr::coalesce(sample_uf_is_eligible_by_ta_de, FALSE),
      sample_uf_ta_de_status = dplyr::case_when(
        is.na(SEJUF) ~ "review_missing_sample_uf",
        !(.orchidee_scope_reference_matched %in% TRUE) ~ "review_unmapped_uf",
        TRUE ~ sample_uf_ta_de_status
      ),
      sample_uf_ta_de_reason = dplyr::case_when(
        is.na(SEJUF) ~ "missing_sample_uf",
        !(.orchidee_scope_reference_matched %in% TRUE) ~ "uf_absent_from_consores_structure",
        TRUE ~ sample_uf_ta_de_reason
      )
    ) %>%
    dplyr::select(-.orchidee_scope_reference_matched)
}

build_ratb_analytic_scope_dataset <- function(sir_wide_ratb_scope) {
  stopifnot(
    is.data.frame(sir_wide_ratb_scope),
    all(c("PATID", "EVTID") %in% names(sir_wide_ratb_scope)),
    "sample_uf_is_eligible_by_ta_de" %in% names(sir_wide_ratb_scope)
  )

  sir_wide_ratb_scope %>%
    dplyr::filter(sample_uf_is_eligible_by_ta_de)
}

extract_incidence_denominator_by_year <- function(
    denominator_bundle,
    sample_scope_reference = NULL,
    analysis_context_id = "spares_current_v1"
  ) {
  stopifnot(is.list(denominator_bundle))

  annual <- denominator_bundle[["incidence_denominator_by_year"]]
  if (is.data.frame(annual)) {
    return(annual)
  }

  exposure <- denominator_bundle[[
    "incidence_exposure_by_year_um_uf_ta_de_profile"
  ]]
  if (is.data.frame(exposure)) {
    if (!is.data.frame(sample_scope_reference)) {
      stop(
        "sample_scope_reference is required to derive the v3 denominator.",
        call. = FALSE
      )
    }
    context <- ratb_analysis_context_profile(analysis_context_id)
    required_scope_cols <- c(
      "SEJUF", "sample_CODE_TA", "sample_CODE_DE",
      "sample_de_domain_ref", "sample_uf_is_eligible_by_ta_de"
    )
    missing_scope_cols <- setdiff(
      required_scope_cols,
      names(sample_scope_reference)
    )
    if (length(missing_scope_cols) > 0L) {
      stop(
        "v3 sample_scope_reference is missing columns: ",
        paste(missing_scope_cols, collapse = ", "),
        call. = FALSE
      )
    }
    scope_lookup <- sample_scope_reference %>%
      dplyr::select(dplyr::all_of(required_scope_cols)) %>%
      dplyr::mutate(.scope_reference_matched = TRUE)
    exposure_with_scope <- exposure %>%
      dplyr::left_join(scope_lookup, by = "SEJUF")
    inconsistent_scope <-
      !(exposure_with_scope$.scope_reference_matched %in% TRUE) |
      exposure_with_scope$CODE_TA != exposure_with_scope$sample_CODE_TA |
      exposure_with_scope$CODE_DE != exposure_with_scope$sample_CODE_DE |
      exposure_with_scope$de_domain_ref !=
        exposure_with_scope$sample_de_domain_ref
    inconsistent_scope[is.na(inconsistent_scope)] <- TRUE
    if (any(inconsistent_scope)) {
      stop(
        "v3 incidence exposure disagrees with sample scope TA/DE mapping.",
        call. = FALSE
      )
    }
    expected_scope <-
      exposure_with_scope$sample_CODE_TA %in% context$eligible_ta_codes &
      exposure_with_scope$sample_de_domain_ref %in%
        context$eligible_de_domains
    if (any(
      exposure_with_scope$sample_uf_is_eligible_by_ta_de != expected_scope
    )) {
      stop(
        "v3 sample scope eligibility disagrees with analysis context ",
        analysis_context_id,
        ".",
        call. = FALSE
      )
    }
    return(
      exposure_with_scope %>%
        dplyr::filter(
          .data$denominator_profile_id == context$denominator_profile_id,
          .data$exposure_unit == context$exposure_unit,
          .data$CODE_TA %in% context$eligible_ta_codes,
          .data$de_domain_ref %in% context$eligible_de_domains,
          .data$sample_uf_is_eligible_by_ta_de
        ) %>%
        dplyr::group_by(.data$calendar_year) %>%
        dplyr::summarise(
          hospital_nights = as.integer(sum(.data$exposure_value)),
          .groups = "drop"
        ) %>%
        dplyr::arrange(.data$calendar_year)
    )
  }

  stop(
    "denominator_bundle must contain incidence_denominator_by_year or ",
    "incidence_exposure_by_year_um_uf_ta_de_profile.",
    call. = FALSE
  )
}

# Internal construction bridge: keep the complete v3 bundle as the durable
# handoff, while materializing the exact v2 shape accepted by today's runtime.
project_external_bundle_v3_to_operational_v2 <- function(
    external_bundle_v3,
    analysis_context_id = "spares_current_v1"
  ) {
  required_bundle_objects <- c(
    "sir_wide",
    "sir_wide_meta",
    "sample_scope_reference",
    "denominator_bundle"
  )
  if (!is.list(external_bundle_v3)) {
    stop("external_bundle_v3 must be a list.", call. = FALSE)
  }
  missing_objects <- setdiff(required_bundle_objects, names(external_bundle_v3))
  if (length(missing_objects) > 0L) {
    stop(
      "external_bundle_v3 is missing objects: ",
      paste(missing_objects, collapse = ", "),
      call. = FALSE
    )
  }

  contract_v3 <- orchidee_external_contract_v3()
  validations <- list(
    external_bundle_validate_sir_wide(
      external_bundle_v3$sir_wide,
      external_bundle_v3$sir_wide_meta,
      contract = contract_v3
    ),
    external_bundle_validate_sample_scope_reference(
      external_bundle_v3$sample_scope_reference,
      contract = contract_v3
    ),
    external_bundle_validate_denominator_bundle(
      external_bundle_v3$denominator_bundle,
      contract = contract_v3
    ),
    external_bundle_validate_cross_artifacts(
      external_bundle_v3$sample_scope_reference,
      external_bundle_v3$denominator_bundle,
      contract = contract_v3
    )
  )
  validation_errors <- unique(unlist(lapply(validations, `[[`, "errors")))
  if (length(validation_errors) > 0L) {
    stop(
      "Cannot project an invalid external bundle v3:\n - ",
      paste(validation_errors, collapse = "\n - "),
      call. = FALSE
    )
  }

  contract_v2 <- orchidee_external_contract_v2()
  sir_wide <- external_bundle_v3$sir_wide
  source_meta <- external_bundle_v3$sir_wide_meta
  projected <- list(
    sir_wide = sir_wide,
    sir_wide_meta = orchidee_handoff_build_sir_wide_meta(
      sir_wide,
      contract = contract_v2,
      artifact_version = source_meta$artifact_version,
      created_at = source_meta$created_at,
      source_label = "external_handoff_v3_projection"
    ),
    sample_scope_reference = external_bundle_subset_sample_scope_reference(
      external_bundle_v3$sample_scope_reference,
      contract = contract_v2
    ),
    denominator_bundle = list(
      incidence_denominator_by_year = extract_incidence_denominator_by_year(
        external_bundle_v3$denominator_bundle,
        sample_scope_reference = external_bundle_v3$sample_scope_reference,
        analysis_context_id = analysis_context_id
      )
    )
  )

  projected
}

extract_incidence_exposure_by_year_um_uf_ta_de_profile <- function(
    denominator_bundle
  ) {
  stopifnot(is.list(denominator_bundle))
  exposure <- denominator_bundle[[
    "incidence_exposure_by_year_um_uf_ta_de_profile"
  ]]
  if (is.data.frame(exposure)) exposure else NULL
}

build_ratb_downstream_scope_from_canonical_inputs <- function(
    sir_wide,
    sample_scope_reference,
    denominator_bundle,
    analysis_context_id = "spares_current_v1"
  ) {
  stopifnot(
    is.data.frame(sir_wide),
    is.data.frame(sample_scope_reference),
    is.list(denominator_bundle)
  )

  incidence_denominator_by_year <- extract_incidence_denominator_by_year(
    denominator_bundle,
    sample_scope_reference = sample_scope_reference,
    analysis_context_id = analysis_context_id
  )
  incidence_exposure_by_year_um_uf_ta_de_profile <-
    extract_incidence_exposure_by_year_um_uf_ta_de_profile(
      denominator_bundle
    )

  sir_wide_ratb_scope <- apply_ratb_sample_ta_de_scope(
    sir_wide = sir_wide,
    sample_scope_reference = sample_scope_reference
  )

  runtime_inputs <- list(
    sir_wide_ratb_scope = sir_wide_ratb_scope,
    sir_wide_ratb_analytic_scope = build_ratb_analytic_scope_dataset(
      sir_wide_ratb_scope
    ),
    incidence_denominator_by_year = incidence_denominator_by_year
  )
  if (is.data.frame(incidence_exposure_by_year_um_uf_ta_de_profile)) {
    runtime_inputs$incidence_exposure_by_year_um_uf_ta_de_profile <-
      incidence_exposure_by_year_um_uf_ta_de_profile
  }
  runtime_inputs
}

ratb_runtime_add_issue <- function(issues, text) {
  c(issues, text)
}

ratb_runtime_is_integerish <- function(x) {
  is.numeric(x) &&
    all(is.na(x) | abs(x - round(x)) < sqrt(.Machine$double.eps))
}

validate_ratb_canonical_runtime_inputs <- function(runtime_inputs, sir_wide = NULL) {
  errors <- character(0)

  if (!is.list(runtime_inputs)) {
    return(list(
      ok = FALSE,
      errors = "runtime_inputs is not a list."
    ))
  }
  if (!is.null(sir_wide) && !is.data.frame(sir_wide)) {
    errors <- ratb_runtime_add_issue(errors, "sir_wide is not a data frame.")
  }

  required_scope_cols <- c(
    "PATID",
    "EVTID",
    "ELTID",
    "SEJUF",
    "sample_uf_is_eligible_by_ta_de",
    "sample_uf_ta_de_status",
    "sample_uf_ta_de_reason"
  )
  sir_wide_ratb_scope <- runtime_inputs$sir_wide_ratb_scope
  if (!is.data.frame(sir_wide_ratb_scope)) {
    errors <- ratb_runtime_add_issue(errors, "sir_wide_ratb_scope is not a data frame.")
  } else {
    missing_scope_cols <- setdiff(required_scope_cols, names(sir_wide_ratb_scope))
    if (length(missing_scope_cols) > 0L) {
      errors <- ratb_runtime_add_issue(
        errors,
        paste0(
          "sir_wide_ratb_scope is missing columns: ",
          paste(missing_scope_cols, collapse = ", ")
        )
      )
    }
    if (is.data.frame(sir_wide) && nrow(sir_wide_ratb_scope) != nrow(sir_wide)) {
      errors <- ratb_runtime_add_issue(
        errors,
        "sir_wide_ratb_scope row count differs from sir_wide."
      )
    }
  }

  sir_wide_ratb_analytic_scope <- runtime_inputs$sir_wide_ratb_analytic_scope
  if (!is.data.frame(sir_wide_ratb_analytic_scope)) {
    errors <- ratb_runtime_add_issue(
      errors,
      "sir_wide_ratb_analytic_scope is not a data frame."
    )
  } else {
    missing_analytic_cols <- setdiff(
      required_scope_cols,
      names(sir_wide_ratb_analytic_scope)
    )
    if (length(missing_analytic_cols) > 0L) {
      errors <- ratb_runtime_add_issue(
        errors,
        paste0(
          "sir_wide_ratb_analytic_scope is missing columns: ",
          paste(missing_analytic_cols, collapse = ", ")
        )
      )
    }
    if (is.data.frame(sir_wide_ratb_scope) &&
        nrow(sir_wide_ratb_analytic_scope) > nrow(sir_wide_ratb_scope)) {
      errors <- ratb_runtime_add_issue(
        errors,
        "sir_wide_ratb_analytic_scope has more rows than sir_wide_ratb_scope."
      )
    }
    if ("sample_uf_is_eligible_by_ta_de" %in% names(sir_wide_ratb_analytic_scope) &&
        any(!(sir_wide_ratb_analytic_scope$sample_uf_is_eligible_by_ta_de %in% TRUE))) {
      errors <- ratb_runtime_add_issue(
        errors,
        "sir_wide_ratb_analytic_scope contains non-eligible sample rows."
      )
    }
  }

  incidence_denominator_by_year <- runtime_inputs$incidence_denominator_by_year
  if (!is.data.frame(incidence_denominator_by_year)) {
    errors <- ratb_runtime_add_issue(
      errors,
      "incidence_denominator_by_year is not a data frame."
    )
  } else {
    required_runtime_denominator_cols <- c(
      "calendar_year",
      "hospital_nights"
    )
    missing_runtime_denominator_cols <- setdiff(
      required_runtime_denominator_cols,
      names(incidence_denominator_by_year)
    )
    if (length(missing_runtime_denominator_cols) > 0L) {
      errors <- ratb_runtime_add_issue(
        errors,
        paste0(
          "incidence_denominator_by_year is missing columns: ",
          paste(missing_runtime_denominator_cols, collapse = ", ")
        )
      )
    } else {
      bad_integerish <- required_runtime_denominator_cols[
        !vapply(
          incidence_denominator_by_year[required_runtime_denominator_cols],
          ratb_runtime_is_integerish,
          logical(1)
        )
      ]
      if (length(bad_integerish) > 0L) {
        errors <- ratb_runtime_add_issue(
          errors,
          paste0(
            "incidence_denominator_by_year columns must be integer-like: ",
            paste(bad_integerish, collapse = ", ")
          )
        )
      }
      if (any(is.na(incidence_denominator_by_year$calendar_year))) {
        errors <- ratb_runtime_add_issue(
          errors,
          "incidence_denominator_by_year$calendar_year contains missing values."
        )
      }
      denominator_years <- incidence_denominator_by_year$calendar_year
      denominator_years <- denominator_years[!is.na(denominator_years)]
      if (any(duplicated(denominator_years))) {
        errors <- ratb_runtime_add_issue(
          errors,
          "incidence_denominator_by_year contains duplicate calendar_year values."
        )
      }
      if (is.numeric(incidence_denominator_by_year$hospital_nights) &&
          any(incidence_denominator_by_year$hospital_nights < 0, na.rm = TRUE)) {
        errors <- ratb_runtime_add_issue(
          errors,
          "incidence_denominator_by_year contains negative nights."
        )
      }
    }
  }

  exposure <- runtime_inputs$incidence_exposure_by_year_um_uf_ta_de_profile
  if (!is.null(exposure)) {
    exposure_validation <- external_bundle_validate_denominator_bundle(
      list(incidence_exposure_by_year_um_uf_ta_de_profile = exposure),
      contract = orchidee_external_contract_v3()
    )
    errors <- c(errors, exposure_validation$errors)
  }

  list(
    ok = length(errors) == 0L,
    errors = unique(errors)
  )
}

stop_if_invalid_ratb_canonical_runtime_inputs <- function(runtime_inputs, sir_wide = NULL) {
  validation <- validate_ratb_canonical_runtime_inputs(
    runtime_inputs = runtime_inputs,
    sir_wide = sir_wide
  )
  if (!isTRUE(validation$ok)) {
    stop(
      "Canonical RATB runtime inputs are invalid:\n - ",
      paste(validation$errors, collapse = "\n - "),
      call. = FALSE
    )
  }

  invisible(validation)
}
