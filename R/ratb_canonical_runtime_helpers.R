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

extract_incidence_denominator_by_year <- function(denominator_bundle) {
  stopifnot(is.list(denominator_bundle))

  annual <- denominator_bundle[["incidence_denominator_by_year"]]
  if (is.data.frame(annual)) {
    return(annual)
  }

  fine <- denominator_bundle[[
    "incidence_denominator_by_year_um_uf_ta_de"
  ]]
  if (is.data.frame(fine)) {
    return(
      fine %>%
        dplyr::group_by(.data$calendar_year) %>%
        dplyr::summarise(
          hospital_nights = as.integer(sum(.data$hospital_nights)),
          .groups = "drop"
        ) %>%
        dplyr::arrange(.data$calendar_year)
    )
  }

  stop(
    "denominator_bundle must contain incidence_denominator_by_year or ",
    "incidence_denominator_by_year_um_uf_ta_de.",
    call. = FALSE
  )
}

extract_incidence_denominator_by_year_um_uf_ta_de <- function(
    denominator_bundle
  ) {
  stopifnot(is.list(denominator_bundle))
  fine <- denominator_bundle[[
    "incidence_denominator_by_year_um_uf_ta_de"
  ]]
  if (is.data.frame(fine)) fine else NULL
}

build_ratb_downstream_scope_from_canonical_inputs <- function(
    sir_wide,
    sample_scope_reference,
    denominator_bundle
  ) {
  stopifnot(
    is.data.frame(sir_wide),
    is.data.frame(sample_scope_reference),
    is.list(denominator_bundle)
  )

  incidence_denominator_by_year <- extract_incidence_denominator_by_year(
    denominator_bundle
  )
  incidence_denominator_by_year_um_uf_ta_de <-
    extract_incidence_denominator_by_year_um_uf_ta_de(denominator_bundle)

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
  if (is.data.frame(incidence_denominator_by_year_um_uf_ta_de)) {
    runtime_inputs$incidence_denominator_by_year_um_uf_ta_de <-
      incidence_denominator_by_year_um_uf_ta_de
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

  fine_denominator <-
    runtime_inputs$incidence_denominator_by_year_um_uf_ta_de
  if (!is.null(fine_denominator)) {
    fine_cols <- c(
      "calendar_year", "SEJUM", "SEJUF", "CODE_TA", "CODE_DE",
      "hospital_nights"
    )
    fine_key <- setdiff(fine_cols, "hospital_nights")
    if (!is.data.frame(fine_denominator)) {
      errors <- ratb_runtime_add_issue(
        errors,
        "incidence_denominator_by_year_um_uf_ta_de is not a data frame."
      )
    } else {
      missing_fine_cols <- setdiff(fine_cols, names(fine_denominator))
      if (length(missing_fine_cols) > 0L) {
        errors <- ratb_runtime_add_issue(
          errors,
          paste0(
            "incidence_denominator_by_year_um_uf_ta_de is missing columns: ",
            paste(missing_fine_cols, collapse = ", ")
          )
        )
      } else {
        if (!ratb_runtime_is_integerish(fine_denominator$calendar_year) ||
            !ratb_runtime_is_integerish(fine_denominator$hospital_nights)) {
          errors <- ratb_runtime_add_issue(
            errors,
            paste0(
              "incidence_denominator_by_year_um_uf_ta_de calendar_year and ",
              "hospital_nights must be integer-like."
            )
          )
        }
        bad_character <- c("SEJUM", "SEJUF", "CODE_TA", "CODE_DE")[
          !vapply(
            fine_denominator[c("SEJUM", "SEJUF", "CODE_TA", "CODE_DE")],
            is.character,
            logical(1)
          )
        ]
        if (length(bad_character) > 0L) {
          errors <- ratb_runtime_add_issue(
            errors,
            paste0(
              "incidence_denominator_by_year_um_uf_ta_de columns must be character: ",
              paste(bad_character, collapse = ", ")
            )
          )
        }
        if (any(vapply(
          fine_denominator[fine_cols],
          function(x) any(is.na(x)),
          logical(1)
        ))) {
          errors <- ratb_runtime_add_issue(
            errors,
            "incidence_denominator_by_year_um_uf_ta_de contains missing values."
          )
        }
        if (any(duplicated(fine_denominator[fine_key]))) {
          errors <- ratb_runtime_add_issue(
            errors,
            paste0(
              "incidence_denominator_by_year_um_uf_ta_de contains duplicate ",
              "rows at its declared grain."
            )
          )
        }
        if (is.numeric(fine_denominator$hospital_nights) &&
            any(fine_denominator$hospital_nights < 0, na.rm = TRUE)) {
          errors <- ratb_runtime_add_issue(
            errors,
            "incidence_denominator_by_year_um_uf_ta_de contains negative nights."
          )
        }
      }
    }
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
