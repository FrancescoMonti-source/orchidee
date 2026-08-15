# Helpers for the canonical raw RATB operational path.
#
# The canonical antibiotic value alphabet belongs to the external bundle
# contract. This layer reads it from there instead of restating it, so the
# runtime cannot recognize a value the contract refuses.

source("R/bootstrap.R")

orchidee_source_script_if_missing(
  "external_bundle_validation_helpers.R",
  "orchidee_external_contract_v2",
  "external bundle validation helpers"
)

ratb_raw_allowed_atb_values <- function() {
  orchidee_external_contract_v2()$sir_wide$allowed_atb_values
}

ratb_raw_is_atb_column <- function(x, allowed_values = ratb_raw_allowed_atb_values()) {
  values <- unique(stats::na.omit(as.character(x)))
  length(values) > 0L && all(values %in% allowed_values)
}

resolve_ratb_raw_atb_columns <- function(sir_wide, sir_wide_meta) {
  stopifnot(is.data.frame(sir_wide), is.list(sir_wide_meta))
  allowed_values <- ratb_raw_allowed_atb_values()

  candidates <- sir_wide_meta$filtre_atb
  if (is.null(candidates) || length(candidates) == 0L) {
    candidates <- sir_wide_meta$atb_cols
  }
  if (is.null(candidates) || length(candidates) == 0L) {
    identifiers <- c(
      "PATID", "EVTID", "ELTID", "DATEPRELEV", "HEUREPRELEV",
      "souche_id", "naturepvt_norm", "bact_norm", "nb_resultats"
    )
    candidates <- setdiff(names(sir_wide), identifiers)
  }

  candidates <- intersect(as.character(candidates), names(sir_wide))
  atb_cols <- candidates[vapply(
    sir_wide[candidates],
    ratb_raw_is_atb_column,
    logical(1),
    allowed_values = allowed_values
  )]
  if (length(atb_cols) == 0L) {
    stop(
      "No observed ",
      paste(allowed_values, collapse = "/"),
      " antibiotic column is available for raw RATB deduplication.",
      call. = FALSE
    )
  }
  atb_cols
}

prepare_ratb_raw_dataset <- function(sir_df, atb_cols) {
  required <- c(
    "PATID", "EVTID", "ELTID", "DATEPRELEV", "HEUREPRELEV",
    "naturepvt_norm", "bact_norm", "nb_resultats"
  )
  missing <- setdiff(c(required, atb_cols), names(sir_df))
  if (length(missing) > 0L) {
    stop(
      "Raw RATB dataset is missing required columns: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }

  out <- sir_df |>
    dplyr::mutate(.date_prelev_raw = as.Date(.data$DATEPRELEV)) |>
    dplyr::group_by(.data$PATID, .data$EVTID) |>
    dplyr::mutate(
      .evt_start_date_raw = if (all(is.na(.data$.date_prelev_raw))) {
        as.Date(NA)
      } else {
        min(.data$.date_prelev_raw, na.rm = TRUE)
      },
      completion_evt_start_year = lubridate::year(.data$.evt_start_date_raw)
    ) |>
    dplyr::ungroup() |>
    dplyr::mutate(
      nb_resultats_post = .data$nb_resultats,
      completion_strategy = "raw",
      n_cells_filled = 0L,
      n_passes_touched = 0L,
      dedup_year = lubridate::year(as.Date(.data$DATEPRELEV))
    ) |>
    dplyr::select(-dplyr::all_of(c(
      ".date_prelev_raw",
      ".evt_start_date_raw"
    )))

  if (any(is.na(out$dedup_year))) {
    stop(
      "Missing dedup_year detected: DATEPRELEV must be non-missing/date-coercible for PATID+year dedup.",
      call. = FALSE
    )
  }

  front_cols <- c(
    "PATID", "EVTID", "ELTID", "DATEPRELEV", "HEUREPRELEV",
    "souche_id", "naturepvt_norm", "bact_norm"
  )
  metric_cols <- c(
    "nb_resultats", "nb_resultats_post", "completion_strategy",
    "n_cells_filled", "n_passes_touched"
  )
  middle_cols <- setdiff(
    names(out),
    c(front_cols, metric_cols, atb_cols)
  )

  out |>
    dplyr::select(dplyr::any_of(unique(c(
      front_cols,
      metric_cols,
      middle_cols,
      atb_cols
    ))))
}

ratb_raw_dedup_scope_definitions <- function() {
  list(
    by_type = c("PATID", "dedup_year", "naturepvt_norm", "bact_norm"),
    global = c("PATID", "dedup_year", "bact_norm")
  )
}

build_ratb_raw_dedup_results <- function(
    sir_df,
    atb_cols,
    zit_values = "ZIT") {
  stopifnot(exists("spares_dedup", mode = "function"))

  raw <- prepare_ratb_raw_dataset(sir_df, atb_cols = atb_cols)
  scope_defs <- ratb_raw_dedup_scope_definitions()
  scope_results <- purrr::imap(
    scope_defs,
    function(scope_keys, scope_name) {
      result <- spares_dedup(
        df = raw,
        atb_cols = atb_cols,
        group_keys = scope_keys,
        time_col = "HEUREPRELEV",
        date_col = "DATEPRELEV",
        document_id_col = "ELTID",
        completeness_col = "nb_resultats",
        zit_values = zit_values,
        keep_class_members = TRUE,
        keep_audit = TRUE
      )
      result
    }
  )

  list(
    raw_dataset = raw,
    dedup_results = list(sir_wide_raw = scope_results),
    scope_definitions = scope_defs
  )
}

validate_ratb_raw_dedup_results <- function(result) {
  errors <- character()
  if (!is.list(result) || !is.data.frame(result$raw_dataset)) {
    return(list(ok = FALSE, errors = "Raw RATB result has no raw_dataset."))
  }
  if (!identical(names(result$dedup_results), "sir_wide_raw")) {
    errors <- c(errors, "Operational dedup results must contain only sir_wide_raw.")
  }

  raw_results <- result$dedup_results$sir_wide_raw
  scope_defs <- result$scope_definitions
  if (!is.list(raw_results) || !setequal(names(raw_results), names(scope_defs))) {
    errors <- c(errors, "Raw RATB result does not contain the expected dedup scopes.")
  } else {
    for (scope_name in names(scope_defs)) {
      scope_result <- raw_results[[scope_name]]
      required_parts <- c("dedup", "class_map", "episode_summary", "audit")
      if (!is.list(scope_result) || !all(required_parts %in% names(scope_result))) {
        errors <- c(errors, paste0("Incomplete dedup result for scope ", scope_name, "."))
        next
      }
      if (nrow(scope_result$dedup) > nrow(result$raw_dataset)) {
        errors <- c(errors, paste0("Dedup scope ", scope_name, " retains more rows than its input."))
      }
      if (any(scope_result$audit$n_within_class_discord_pairs != 0L, na.rm = TRUE)) {
        errors <- c(errors, paste0("Dedup scope ", scope_name, " contains within-class S/R conflicts."))
      }
    }
  }

  list(ok = length(errors) == 0L, errors = unique(errors))
}

# The species map is read while the cache is built, so it belongs to the
# cache's inputs exactly like the scripts do. It is a parameter rather than a
# constant because the builder takes it as one.
ratb_raw_cache_species_regex_map_path <- function(mappings_dir) {
  file.path(mappings_dir, "species_regex_map.csv")
}

# A cached dedup result is only reusable while both of its inputs are
# unchanged. The bundle side travels in runtime_input_signature; this is
# everything else the cache was built from. Script paths are relative to the
# project root, which every entry point already sets before sourcing.
ratb_raw_cache_input_hashes <- function(species_regex_map_path) {
  stopifnot(
    is.character(species_regex_map_path),
    length(species_regex_map_path) == 1L
  )
  script_paths <- c(
    raw_runtime = file.path("R", "ratb_raw_runtime_helpers.R"),
    spares_dedup = file.path("R", "spares_dedup.R"),
    shared_primitives = file.path("R", "spares_shared_primitives.R"),
    phenotype = file.path("R", "phenotype_flag_helpers.R"),
    plausibility = file.path("R", "ratb_plausibility_qc_helpers.R"),
    species_regex_map = species_regex_map_path
  )
  # Hash content with carriage returns removed, not the file bytes. This
  # repository is checked out with core.autocrlf, so md5sum of the file itself
  # changes with the line endings a given clone happens to use, and would
  # report a code change where there is none. Working on raw bytes keeps this
  # independent of the file's text encoding.
  normalized <- tempfile(pattern = "ratb_raw_cache_script_")
  on.exit(unlink(normalized), add = TRUE)
  hashes <- lapply(script_paths, function(path) {
    bytes <- readBin(path, "raw", file.size(path))
    writeBin(bytes[bytes != as.raw(13L)], normalized)
    as.character(unname(tools::md5sum(normalized)))
  })
  names(hashes) <- names(script_paths)
  hashes
}

# Returns the reasons a cache cannot be reused, empty when it is current. The
# caller decides whether to rebuild or to stop; both need the same verdict.
ratb_raw_cache_staleness_reasons <- function(
    cache_meta,
    runtime_input_signature,
    species_regex_map_path) {
  if (!is.list(cache_meta)) {
    return("its metadata is unreadable")
  }

  reasons <- character(0)
  if (!identical(
    cache_meta[["runtime_input_signature"]],
    runtime_input_signature
  )) {
    reasons <- c(reasons, "the input bundle changed")
  }
  if (!identical(
    cache_meta[["cache_input_hashes"]],
    ratb_raw_cache_input_hashes(species_regex_map_path)
  )) {
    reasons <- c(reasons, "the code or mapping that builds it changed")
  }
  reasons
}

build_ratb_raw_cache_meta <- function(
    result,
    atb_cols,
    runtime_input_signature,
    species_regex_map_path,
    zit_values = "ZIT") {
  dataset_signatures <- tibble::tibble(
    dataset = "sir_wide_raw",
    n_rows = nrow(result$raw_dataset),
    n_distinct_eltid = dplyr::n_distinct(result$raw_dataset$ELTID)
  )

  payload <- list(
    contract = "ratb_raw_dedup_cache_v1",
    runtime_input_signature = runtime_input_signature,
    atb_cols = atb_cols,
    zit_values = zit_values,
    dedup_scope_defs = result$scope_definitions,
    dataset_signatures = dataset_signatures,
    cache_input_hashes = ratb_raw_cache_input_hashes(species_regex_map_path)
  )
  fingerprint_file <- tempfile(pattern = "ratb_raw_cache_", fileext = ".rds")
  on.exit(unlink(fingerprint_file), add = TRUE)
  saveRDS(payload, fingerprint_file, version = 2)

  c(
    list(
      fingerprint = as.character(unname(tools::md5sum(fingerprint_file))),
      method_profile = "raw_patient_year_v1"
    ),
    payload,
    list(created_at = format(Sys.time(), tz = "UTC", usetz = TRUE))
  )
}

build_ratb_raw_operational_cache <- function(
    operational_runtime,
    sir_wide_meta,
    species_regex_map_path,
    cache_dir,
    zit_values = "ZIT") {
  stopifnot(
    is.list(operational_runtime),
    is.list(operational_runtime$runtime_inputs),
    is.list(operational_runtime$runtime_input_signature),
    is.list(sir_wide_meta),
    is.character(cache_dir),
    length(cache_dir) == 1L
  )

  analytic_scope <- operational_runtime$runtime_inputs$sir_wide_ratb_analytic_scope
  plausibility <- build_ratb_plausibility_qc(
    sir_df = analytic_scope,
    species_regex_map_path = species_regex_map_path
  )
  atb_cols <- resolve_ratb_raw_atb_columns(
    sir_wide = plausibility$data,
    sir_wide_meta = sir_wide_meta
  )
  result <- build_ratb_raw_dedup_results(
    sir_df = plausibility$data,
    atb_cols = atb_cols,
    zit_values = zit_values
  )
  validation <- validate_ratb_raw_dedup_results(result)
  if (!isTRUE(validation$ok)) {
    stop(
      "Raw RATB runtime validation failed: ",
      paste(validation$errors, collapse = " | "),
      call. = FALSE
    )
  }

  cache_meta <- build_ratb_raw_cache_meta(
    result = result,
    atb_cols = atb_cols,
    runtime_input_signature = operational_runtime$runtime_input_signature,
    species_regex_map_path = species_regex_map_path,
    zit_values = zit_values
  )
  population_summary <- tibble::tibble(
    stage = c(
      "analytic_scope",
      "after_plausibility_qc",
      "dedup_global_representatives",
      "dedup_by_type_representatives"
    ),
    n_rows = as.integer(c(
      nrow(analytic_scope),
      nrow(plausibility$data),
      nrow(result$dedup_results$sir_wide_raw$global$dedup),
      nrow(result$dedup_results$sir_wide_raw$by_type$dedup)
    ))
  )
  audit <- list(
    contract = "ratb_raw_runtime_audit_v1",
    input_source = operational_runtime$input_source,
    population_summary = population_summary,
    plausibility_summary = plausibility$summary,
    plausibility_unavailable_rules = plausibility$unavailable_rules,
    atb_cols = atb_cols,
    validation = validation
  )

  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  saveRDS(result$dedup_results, file.path(cache_dir, "dedup_results"))
  saveRDS(cache_meta, file.path(cache_dir, "dedup_cache_meta"))
  saveRDS(audit, file.path(cache_dir, "ratb_raw_runtime_audit"))

  list(
    dedup_results = result$dedup_results,
    dedup_cache_meta = cache_meta,
    audit = audit,
    raw_dataset = result$raw_dataset
  )
}
