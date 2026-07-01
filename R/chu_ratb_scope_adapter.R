# CHU native RATB scope adapter.
#
# This file keeps the current local PMSI-backed cache recompute path explicit.
# It produces the canonical sample-scope reference and denominator bundle that
# the notebook applies through the shared downstream RATB scope helper, while
# preserving native QA tables.

load_chu_pmsi_main <- function(
    path_candidates = c("pmsi", file.path("data", "pmsi"))
  ) {
  pmsi_runtime_path <- resolve_existing_path(
    path_candidates,
    what = "pmsi raw input"
  )
  pmsi <- readRDS(pmsi_runtime_path)
  stopifnot(is.list(pmsi), "main" %in% names(pmsi), is.data.frame(pmsi$main))

  list(
    main = pmsi$main,
    path = pmsi_runtime_path
  )
}

build_chu_incidence_denominator_by_year <- function(
    hospital_days_year_summary_provisional
  ) {
  stopifnot(is.data.frame(hospital_days_year_summary_provisional))
  required_cols <- c("calendar_year", "hospital_nights_provisional")
  missing_cols <- setdiff(required_cols, names(hospital_days_year_summary_provisional))
  if (length(missing_cols) > 0L) {
    stop(
      "CHU provisional denominator is missing columns: ",
      paste(missing_cols, collapse = ", "),
      call. = FALSE
    )
  }

  hospital_days_year_summary_provisional |>
    dplyr::transmute(
      calendar_year = as.integer(.data$calendar_year),
      hospital_nights = as.integer(.data$hospital_nights_provisional)
    )
}

build_chu_native_ratb_scope_cache_payload <- function(
    sir_wide,
    pmsi_path_candidates = c("pmsi", file.path("data", "pmsi")),
    structure_path = file.path("ref", "consores_structure_intranet_maj_2025.xlsx"),
    codes_ta_path = file.path("ref", "consores_codes_ta.csv"),
    codes_de_path = file.path("ref", "consores_codes_de.csv"),
    ref_dir = "ref"
  ) {
  stopifnot(is.data.frame(sir_wide))

  pmsi <- load_chu_pmsi_main(path_candidates = pmsi_path_candidates)

  ratb_scope_objects <- build_ratb_scope_tables(
    sir_wide = sir_wide,
    pmsi_main = pmsi$main
  )

  hospital_days_objects <- build_hospital_days_validation(
    pmsi_main = pmsi$main,
    status_lookup = ratb_scope_objects$pmsi_status_lookup
  )

  ratb_provisional_perimeter_objects <- build_ratb_provisional_perimeter_audit(
    sir_wide_ratb_scope = ratb_scope_objects$sir_wide_ratb_scope,
    pmsi_main = pmsi$main,
    status_lookup = ratb_scope_objects$pmsi_status_lookup,
    structure_path = structure_path,
    codes_ta_path = codes_ta_path,
    codes_de_path = codes_de_path,
    ref_dir = ref_dir
  )

  sample_scope_reference <- build_ratb_sample_scope_reference(
    ratb_provisional_perimeter_objects$ratb_uf_ta_de_reference
  )
  incidence_denominator_by_year <- build_chu_incidence_denominator_by_year(
    ratb_provisional_perimeter_objects$hospital_days_year_summary_provisional
  )
  denominator_bundle <- list(
    incidence_denominator_by_year = incidence_denominator_by_year
  )
  list(
    payload = list(
      sample_scope_reference = sample_scope_reference,
      denominator_bundle = denominator_bundle,
      sir_wide_ratb_scope_base = ratb_scope_objects$sir_wide_ratb_scope,
      ratb_scope_join_audit = ratb_scope_objects$ratb_scope_join_audit,
      ratb_scope_exclusion_summary = ratb_scope_objects$ratb_scope_exclusion_summary,
      hospital_stays_raw = hospital_days_objects$hospital_stays_raw,
      hospital_stays_validated = hospital_days_objects$hospital_stays_validated,
      hospital_stay_validation_summary =
        hospital_days_objects$hospital_stay_validation_summary,
      hospital_days_year_split = hospital_days_objects$hospital_days_year_split,
      hospital_days_year_summary = hospital_days_objects$hospital_days_year_summary,
      ratb_perimeter_rules = ratb_provisional_perimeter_objects$ratb_perimeter_rules,
      ratb_uf_ta_de_reference = ratb_provisional_perimeter_objects$ratb_uf_ta_de_reference,
      ratb_episode_scope_audit = ratb_provisional_perimeter_objects$ratb_episode_scope_audit,
      ratb_episode_exclusion_summary =
        ratb_provisional_perimeter_objects$ratb_episode_exclusion_summary,
      hospital_days_year_split_provisional =
        ratb_provisional_perimeter_objects$hospital_days_year_split_provisional,
      hospital_days_year_summary_provisional =
        ratb_provisional_perimeter_objects$hospital_days_year_summary_provisional,
      ratb_numerator_scope_impact_audit =
        ratb_provisional_perimeter_objects$ratb_numerator_scope_impact_audit
    ),
    pmsi_runtime_path = pmsi$path
  )
}
