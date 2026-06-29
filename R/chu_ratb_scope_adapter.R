# CHU native RATB scope adapter.
#
# This file keeps the current local PMSI-backed cache recompute path explicit.
# The shared downstream core should prefer canonical scope and denominator
# artifacts once external runtime wiring is enabled.

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

  sir_wide_ratb_scope <- ratb_provisional_perimeter_objects$sir_wide_ratb_scope

  list(
    payload = list(
      sir_wide_ratb_scope = sir_wide_ratb_scope,
      sir_wide_ratb_analytic_scope = build_ratb_analytic_scope_dataset(
        sir_wide_ratb_scope = sir_wide_ratb_scope
      ),
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
