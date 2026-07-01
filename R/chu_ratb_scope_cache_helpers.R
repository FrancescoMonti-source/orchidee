# CHU native RATB scope cache helpers.
#
# This file owns cache loading, freshness checks, refresh and recompute control
# for the current CHU PMSI-backed RATB scope payload. It deliberately lives next
# to, but outside, the CHU producer adapter so cache-control edits do not look
# like producer-method changes.

chu_ratb_file_signature <- function(path) {
  info <- file.info(path)
  list(
    size_bytes = unname(as.numeric(info$size)),
    md5 = as.character(unname(tools::md5sum(path)))
  )
}

build_chu_ratb_scope_cache_meta <- function(
    sir_wide,
    sir_wide_meta,
    sir_wide_artifact_signature,
    ratb_ref_paths,
    pmsi_input_signature,
    microbiology_scope_policy,
    incidence_denominator_policy
  ) {
  stopifnot(
    is.list(sir_wide_meta),
    is.list(sir_wide_artifact_signature),
    length(ratb_ref_paths) > 0L,
    is.list(pmsi_input_signature)
  )

  scope_script_names <- c(
    "ratb_canonical_runtime_helpers.R",
    "ratb_hospital_days_helpers.R",
    "chu_ratb_scope_adapter.R",
    "chu_ratb_scope_cache_helpers.R"
  )
  scope_script_paths <- vapply(
    scope_script_names,
    function(script_name) {
      orchidee_resolve_script_path(
        script_name,
        "script required for RATB scope cache fingerprint"
      )
    },
    character(1)
  )
  scope_script_hashes <- as.list(as.character(unname(tools::md5sum(scope_script_paths))))
  names(scope_script_hashes) <- scope_script_names
  reference_hashes <- as.list(as.character(unname(tools::md5sum(ratb_ref_paths))))
  names(reference_hashes) <- names(ratb_ref_paths)

  payload <- list(
    sir_wide_n_rows = nrow(sir_wide),
    sir_wide_n_eltid = dplyr::n_distinct(sir_wide$ELTID),
    artifact_created_at = sir_wide_meta$created_at,
    sir_wide_artifact_signature = sir_wide_artifact_signature,
    microbiology_scope_policy = microbiology_scope_policy,
    incidence_denominator_policy = incidence_denominator_policy,
    scope_script_hashes = scope_script_hashes,
    pmsi_input_signature = pmsi_input_signature,
    reference_hashes = reference_hashes
  )

  tmp_file <- tempfile(pattern = "ratb_scope_fingerprint_", fileext = ".rds")
  on.exit(unlink(tmp_file), add = TRUE)
  saveRDS(payload, tmp_file, version = 2)
  fingerprint <- as.character(unname(tools::md5sum(tmp_file)))

  list(
    fingerprint = fingerprint,
    sir_wide_n_rows = nrow(sir_wide),
    sir_wide_n_eltid = dplyr::n_distinct(sir_wide$ELTID),
    artifact_created_at = sir_wide_meta$created_at,
    sir_wide_artifact_signature = sir_wide_artifact_signature,
    microbiology_scope_policy = microbiology_scope_policy,
    incidence_denominator_policy = incidence_denominator_policy,
    scope_script_hashes = scope_script_hashes,
    pmsi_input_signature = pmsi_input_signature,
    reference_hashes = reference_hashes,
    created_at = format(Sys.time(), tz = "UTC", usetz = TRUE)
  )
}

chu_ratb_expected_scope_payload_names <- function() {
  c(
    "sample_scope_reference",
    "denominator_bundle",
    "ratb_scope_join_audit",
    "ratb_scope_exclusion_summary",
    "hospital_stays_raw",
    "hospital_stays_validated",
    "hospital_stay_validation_summary",
    "hospital_days_year_split",
    "hospital_days_year_summary",
    "ratb_perimeter_rules",
    "ratb_uf_ta_de_reference",
    "ratb_episode_scope_audit",
    "ratb_episode_exclusion_summary",
    "hospital_days_year_split_provisional",
    "hospital_days_year_summary_provisional",
    "ratb_numerator_scope_impact_audit"
  )
}

chu_ratb_scope_cache_script_hashes_match <- function(loaded_meta, current_meta, script_names) {
  is.list(loaded_meta$scope_script_hashes) &&
    is.list(current_meta$scope_script_hashes) &&
    all(vapply(
      script_names,
      function(script_name) {
        identical(
          loaded_meta$scope_script_hashes[[script_name]],
          current_meta$scope_script_hashes[[script_name]]
        )
      },
      logical(1)
    ))
}

chu_ratb_scope_cache_canonical_inputs_match <- function(loaded_meta, current_meta) {
  fields <- c(
    "sir_wide_n_rows",
    "sir_wide_n_eltid",
    "artifact_created_at",
    "sir_wide_artifact_signature",
    "microbiology_scope_policy",
    "incidence_denominator_policy",
    "pmsi_input_signature",
    "reference_hashes"
  )
  producer_script_names <- c(
    "ratb_hospital_days_helpers.R",
    "chu_ratb_scope_adapter.R"
  )

  is.list(loaded_meta) &&
    all(vapply(
      fields,
      function(field) identical(loaded_meta[[field]], current_meta[[field]]),
      logical(1)
    )) &&
    chu_ratb_scope_cache_script_hashes_match(
      loaded_meta = loaded_meta,
      current_meta = current_meta,
      script_names = producer_script_names
    )
}

chu_ratb_resolve_ref_paths <- function(
    ref_dir = "ref",
    structure_path = file.path(ref_dir, "consores_structure_intranet_maj_2025.xlsx"),
    codes_ta_path = file.path(ref_dir, "consores_codes_ta.csv"),
    codes_de_path = file.path(ref_dir, "consores_codes_de.csv")
  ) {
  vapply(
    c(
      ref_uf = file.path(ref_dir, "ref_uf.txt"),
      ref_um = file.path(ref_dir, "ref_um.txt"),
      ref_uf2um = file.path(ref_dir, "ref_uf2um.txt"),
      consores_structure = structure_path,
      consores_codes_ta = codes_ta_path,
      consores_codes_de = codes_de_path
    ),
    function(x) resolve_existing_path(c(x), what = paste0("reference ", x)),
    character(1)
  )
}

chu_ratb_cache_payload_is_usable <- function(payload, sir_wide) {
  if (!is.list(payload) ||
      !all(chu_ratb_expected_scope_payload_names() %in% names(payload))) {
    return(FALSE)
  }
  if (!is.data.frame(payload$sample_scope_reference)) {
    return(FALSE)
  }
  if (!is.list(payload$denominator_bundle) || !all(c(
    "hospital_days_year_summary",
    "hospital_days_year_summary_provisional"
  ) %in% names(payload$denominator_bundle))) {
    return(FALSE)
  }
  denominator_provisional <- payload$denominator_bundle$hospital_days_year_summary_provisional
  if (!is.data.frame(denominator_provisional) ||
      !"hospital_nights_provisional" %in% names(denominator_provisional)) {
    return(FALSE)
  }
  scope_base <- payload$sir_wide_ratb_scope_base
  if (!is.data.frame(scope_base) && is.data.frame(payload$sir_wide_ratb_scope)) {
    scope_base <- payload$sir_wide_ratb_scope
  }
  if (!is.data.frame(scope_base)) {
    return(FALSE)
  }
  if (nrow(scope_base) > nrow(sir_wide)) {
    return(FALSE)
  }
  if (!"ratb_scope_status" %in% names(scope_base)) {
    return(FALSE)
  }
  if (!all(scope_base$ratb_scope_status %in% c(
    "eligible_hospitalization",
    "excluded_external",
    "mixed_status",
    "no_usable_status",
    "no_pmsi_match"
  ))) {
    return(FALSE)
  }
  if (!is.data.frame(payload$hospital_stays_validated)) {
    return(FALSE)
  }
  if (!all(payload$hospital_stays_validated$validation_status == "validated")) {
    return(FALSE)
  }
  if (!all(!payload$hospital_stays_validated$missing_bounds)) {
    return(FALSE)
  }
  if (!all(!payload$hospital_stays_validated$negative_elapsed)) {
    return(FALSE)
  }
  if (!all(denominator_provisional$hospital_nights_provisional >= 0)) {
    return(FALSE)
  }

  TRUE
}

build_chu_legacy_hospital_days_year_summary <- function(
    denominator_bundle,
    incidence_denominator_by_year
  ) {
  legacy_tbl <- denominator_bundle$hospital_days_year_summary_provisional
  if (is.data.frame(legacy_tbl) &&
      all(c("calendar_year", "hospital_nights_provisional") %in% names(legacy_tbl))) {
    return(legacy_tbl)
  }

  data.frame(
    calendar_year = incidence_denominator_by_year$calendar_year,
    hospital_nights_provisional = incidence_denominator_by_year$hospital_nights,
    stringsAsFactors = FALSE
  )
}

build_chu_ratb_runtime_payload_from_cache_payload <- function(payload, sir_wide) {
  stopifnot(
    is.list(payload),
    is.data.frame(sir_wide),
    is.data.frame(payload$sample_scope_reference),
    is.list(payload$denominator_bundle)
  )

  runtime_base <- payload$sir_wide_ratb_scope_base
  if (!is.data.frame(runtime_base) && is.data.frame(payload$sir_wide_ratb_scope)) {
    runtime_base <- payload$sir_wide_ratb_scope
  }
  if (!is.data.frame(runtime_base)) {
    runtime_base <- sir_wide
  }

  overlapping_scope_cols <- setdiff(
    intersect(names(payload$sample_scope_reference), names(runtime_base)),
    "SEJUF"
  )
  if (length(overlapping_scope_cols) > 0L) {
    runtime_base <- runtime_base %>%
      dplyr::select(-dplyr::all_of(overlapping_scope_cols))
  }

  runtime_scope <- build_ratb_downstream_scope_from_canonical_inputs(
    sir_wide = runtime_base,
    sample_scope_reference = payload$sample_scope_reference,
    denominator_bundle = payload$denominator_bundle
  )

  payload$sir_wide_ratb_scope_base <- runtime_base
  payload$sir_wide_ratb_scope <- runtime_scope$sir_wide_ratb_scope
  payload$sir_wide_ratb_analytic_scope <- runtime_scope$sir_wide_ratb_analytic_scope
  payload$incidence_denominator_by_year <- runtime_scope$incidence_denominator_by_year
  payload$hospital_days_year_summary_provisional <- build_chu_legacy_hospital_days_year_summary(
    denominator_bundle = payload$denominator_bundle,
    incidence_denominator_by_year = runtime_scope$incidence_denominator_by_year
  )

  payload
}

load_or_build_chu_ratb_scope_cache <- function(
    sir_wide,
    sir_wide_meta,
    sir_wide_artifact_signature,
    data_dir = "data",
    recompute = FALSE,
    ref_dir = "ref",
    structure_path = file.path(ref_dir, "consores_structure_intranet_maj_2025.xlsx"),
    codes_ta_path = file.path(ref_dir, "consores_codes_ta.csv"),
    codes_de_path = file.path(ref_dir, "consores_codes_de.csv"),
    pmsi_path_candidates = c("pmsi", file.path(data_dir, "pmsi")),
    microbiology_scope_policy,
    incidence_denominator_policy,
    cache_payload_path = file.path(data_dir, "ratb_scope_cache"),
    cache_meta_path = file.path(data_dir, "ratb_scope_cache_meta")
  ) {
  stopifnot(is.data.frame(sir_wide), is.list(sir_wide_meta))

  ratb_ref_paths <- chu_ratb_resolve_ref_paths(
    ref_dir = ref_dir,
    structure_path = structure_path,
    codes_ta_path = codes_ta_path,
    codes_de_path = codes_de_path
  )
  pmsi_input_path <- resolve_existing_path(
    pmsi_path_candidates,
    what = "pmsi raw input"
  )
  meta_current <- build_chu_ratb_scope_cache_meta(
    sir_wide = sir_wide,
    sir_wide_meta = sir_wide_meta,
    sir_wide_artifact_signature = sir_wide_artifact_signature,
    ratb_ref_paths = ratb_ref_paths,
    pmsi_input_signature = chu_ratb_file_signature(pmsi_input_path),
    microbiology_scope_policy = microbiology_scope_policy,
    incidence_denominator_policy = incidence_denominator_policy
  )

  scope_cache_payload <- NULL
  scope_cache_meta <- NULL
  scope_cache_source <- NA_character_
  scope_cache_refresh_needed <- FALSE

  if (!isTRUE(recompute) && all(file.exists(c(cache_payload_path, cache_meta_path)))) {
    loaded_meta <- tryCatch(readRDS(cache_meta_path), error = function(e) NULL)
    if (is.list(loaded_meta) && !is.null(loaded_meta$fingerprint)) {
      cache_fingerprint_matches <- identical(
        as.character(loaded_meta$fingerprint),
        meta_current$fingerprint
      )
      cache_canonical_inputs_match <- cache_fingerprint_matches ||
        chu_ratb_scope_cache_canonical_inputs_match(
          loaded_meta = loaded_meta,
          current_meta = meta_current
        )
      if (cache_canonical_inputs_match) {
        loaded_payload <- tryCatch(readRDS(cache_payload_path), error = function(e) NULL)
        if (chu_ratb_cache_payload_is_usable(loaded_payload, sir_wide = sir_wide)) {
          scope_cache_payload <- loaded_payload
          scope_cache_meta <- loaded_meta
          scope_cache_source <- cache_payload_path
          scope_cache_refresh_needed <- !cache_fingerprint_matches
        }
      }
    }
  } else if (isTRUE(recompute)) {
    scope_cache_source <- "forced_recompute"
  }

  if (!isTRUE(recompute) && !is.null(scope_cache_payload)) {
    scope_cache_payload <- build_chu_ratb_runtime_payload_from_cache_payload(
      payload = scope_cache_payload,
      sir_wide = sir_wide
    )
    if (isTRUE(scope_cache_refresh_needed)) {
      scope_cache_meta <- meta_current
      saveRDS(scope_cache_payload, cache_payload_path)
      saveRDS(scope_cache_meta, cache_meta_path)
    }
    scope_cache_decision <- if (isTRUE(scope_cache_refresh_needed)) {
      "loaded_refreshed"
    } else {
      "loaded"
    }
    message("Loaded RATB scope artifacts from ", scope_cache_source)
  } else {
    if (isTRUE(recompute)) {
      message("Force recompute requested; building RATB scope artifacts.")
    } else {
      message("No valid RATB scope cache found; building RATB scope artifacts.")
    }

    native_scope_cache <- build_chu_native_ratb_scope_cache_payload(
      sir_wide = sir_wide,
      pmsi_path_candidates = pmsi_path_candidates,
      structure_path = structure_path,
      codes_ta_path = codes_ta_path,
      codes_de_path = codes_de_path,
      ref_dir = ref_dir
    )
    scope_cache_payload <- build_chu_ratb_runtime_payload_from_cache_payload(
      payload = native_scope_cache$payload,
      sir_wide = sir_wide
    )
    scope_cache_meta <- meta_current

    saveRDS(scope_cache_payload, cache_payload_path)
    saveRDS(scope_cache_meta, cache_meta_path)
    scope_cache_source <- "recomputed"
    scope_cache_decision <- "recomputed"
    message("Saved RATB scope artifacts to: ", cache_payload_path, ", ", cache_meta_path)
  }

  list(
    payload = scope_cache_payload,
    meta = scope_cache_meta,
    source = scope_cache_source,
    decision = scope_cache_decision,
    pmsi_input_path = pmsi_input_path,
    ref_paths = ratb_ref_paths,
    cache_payload_path = cache_payload_path,
    cache_meta_path = cache_meta_path
  )
}
