## RATB canonical runtime helpers.
##
## This file is HDW-agnostic. It starts from canonical ORCHIDEE inputs:
## `sir_wide`, `sample_scope_reference`, and `denominator_bundle`.

ratb_canonical_trim_or_na <- function(x) {
  x <- trimws(as.character(x))
  x[!nzchar(x)] <- NA_character_
  x
}

apply_ratb_sample_ta_de_scope <- function(sir_wide, sample_scope_reference) {
  stopifnot(is.data.frame(sir_wide), is.data.frame(sample_scope_reference))
  stopifnot(all(c("PATID", "EVTID", "SEJUF", "SEJUM") %in% names(sir_wide)))

  required_ref_cols <- c(
    "SEJUF",
    "sample_CODE_TA",
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

  sir_wide %>%
    dplyr::mutate(
      PATID = as.character(PATID),
      EVTID = as.character(EVTID),
      SEJUF = ratb_canonical_trim_or_na(SEJUF),
      SEJUM = ratb_canonical_trim_or_na(SEJUM)
    ) %>%
    dplyr::left_join(
      sample_scope_reference %>% dplyr::distinct(SEJUF, .keep_all = TRUE),
      by = "SEJUF"
    ) %>%
    dplyr::mutate(
      sample_uf_is_eligible_by_ta_de = dplyr::coalesce(sample_uf_is_eligible_by_ta_de, FALSE),
      sample_uf_ta_de_status = dplyr::case_when(
        is.na(SEJUF) ~ "review_missing_sample_uf",
        is.na(sample_CODE_TA) ~ "review_unmapped_uf",
        TRUE ~ sample_uf_ta_de_status
      ),
      sample_uf_ta_de_reason = dplyr::case_when(
        is.na(SEJUF) ~ "missing_sample_uf",
        is.na(sample_CODE_TA) ~ "uf_absent_from_consores_structure",
        TRUE ~ sample_uf_ta_de_reason
      )
    )
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

build_ratb_downstream_scope_from_canonical_inputs <- function(
    sir_wide,
    sample_scope_reference,
    denominator_bundle
  ) {
  stopifnot(
    is.data.frame(sir_wide),
    is.data.frame(sample_scope_reference),
    is.list(denominator_bundle),
    all(c(
      "hospital_days_year_summary",
      "hospital_days_year_summary_provisional"
    ) %in% names(denominator_bundle))
  )

  sir_wide_ratb_scope <- apply_ratb_sample_ta_de_scope(
    sir_wide = sir_wide,
    sample_scope_reference = sample_scope_reference
  )

  list(
    sir_wide_ratb_scope = sir_wide_ratb_scope,
    sir_wide_ratb_analytic_scope = build_ratb_analytic_scope_dataset(
      sir_wide_ratb_scope
    ),
    hospital_days_year_summary = denominator_bundle$hospital_days_year_summary,
    hospital_days_year_summary_provisional = denominator_bundle$hospital_days_year_summary_provisional
  )
}
