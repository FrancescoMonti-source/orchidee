#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
mode <- if (length(args) >= 1L) args[[1]] else "check"

allowed_modes <- c("write", "check")
if (!(mode %in% allowed_modes)) {
  stop(
    "Usage: Rscript scripts/characterize_current_outputs.R <write|check> [snapshot_path]",
    call. = FALSE
  )
}

snapshot_path <- if (length(args) >= 2L) {
  args[[2]]
} else {
  file.path("data", "characterization_baseline.rds")
}

find_repo_root <- function() {
  args_all <- commandArgs(trailingOnly = FALSE)
  file_arg <- "--file="
  script_arg <- args_all[startsWith(args_all, file_arg)]

  if (length(script_arg) > 0L) {
    script_path <- normalizePath(
      sub(file_arg, "", script_arg[[1]], fixed = TRUE),
      winslash = "/",
      mustWork = TRUE
    )
    return(normalizePath(file.path(dirname(script_path), ".."), winslash = "/"))
  }

  normalizePath(getwd(), winslash = "/")
}

repo_root <- find_repo_root()
setwd(repo_root)
source("R/bootstrap.R")

require_file <- function(path) {
  if (!file.exists(path)) {
    stop("Missing required file: ", path, call. = FALSE)
  }
  path
}

hash_object <- function(x) {
  tmp <- tempfile(fileext = ".rds")
  on.exit(unlink(tmp), add = TRUE)
  saveRDS(x, tmp, version = 2, compress = FALSE)
  unname(tools::md5sum(tmp))
}

canonicalize_df <- function(df) {
  df <- as.data.frame(df, stringsAsFactors = FALSE)

  for (col in names(df)) {
    if (inherits(df[[col]], "POSIXt")) {
      df[[col]] <- format(df[[col]], "%Y-%m-%dT%H:%M:%S", tz = "UTC")
    } else if (inherits(df[[col]], "Date")) {
      df[[col]] <- as.character(df[[col]])
    } else if (is.factor(df[[col]])) {
      df[[col]] <- as.character(df[[col]])
    } else if (is.list(df[[col]])) {
      df[[col]] <- vapply(
        df[[col]],
        function(x) paste(as.character(unlist(x, use.names = FALSE)), collapse = "|"),
        character(1)
      )
    }
    df[[col]] <- unname(df[[col]])
    attributes(df[[col]]) <- NULL
  }

  row.names(df) <- NULL
  df <- df[, sort(names(df)), drop = FALSE]

  if (nrow(df) > 1L && ncol(df) > 0L) {
    order_key <- do.call(
      paste,
      c(lapply(df, function(x) ifelse(is.na(x), "<NA>", as.character(x))), sep = "\r")
    )
    df <- df[order(order_key, na.last = TRUE), , drop = FALSE]
    row.names(df) <- NULL
  }

  df
}

signature_row <- function(name, object) {
  if (!is.data.frame(object)) {
    stop("Can only signature data-frame-like objects: ", name, call. = FALSE)
  }

  df <- canonicalize_df(object)
  data.frame(
    name = name,
    nrow = nrow(df),
    ncol = ncol(df),
    columns_hash = hash_object(names(df)),
    data_hash = hash_object(df),
    stringsAsFactors = FALSE
  )
}

safe_signature_row <- function(name, object) {
  tryCatch(
    signature_row(name, object),
    error = function(err) {
      stop("Failed while building signature for ", name, ": ", conditionMessage(err), call. = FALSE)
    }
  )
}

read_rds_artifact <- function(path) {
  readRDS(require_file(path))
}

build_indicator_panels <- function(sir_wide_meta, dedup_results, scope_cache) {
  orchidee_source_required_script("ratb_indicator_helpers.R", "RATB indicator helpers")

  paths <- orchidee_config$paths
  ratb_cfg <- orchidee_config$ratb

  species_taxonomy_path <- file.path(paths$dictionaries_dir, "species_regex_map.csv")
  indicator_spec_path <- paths$ratb_indicator_spec_path

  reference_dataset_name <- names(dedup_results)[[1]]
  reference_global_dedup <- dedup_results[[reference_dataset_name]]$global$dedup
  reference_by_type_dedup <- dedup_results[[reference_dataset_name]]$by_type$dedup

  atb_cols <- intersect(sir_wide_meta$atb_cols, names(reference_global_dedup))
  if (length(atb_cols) == 0L) {
    stop("No antibiotic columns available for indicator characterization.", call. = FALSE)
  }

  supported_atb_cols_meta <- sir_wide_meta$supported_atb_cols
  if (is.null(supported_atb_cols_meta)) {
    supported_atb_cols_meta <- sir_wide_meta$filtre_atb
  }
  if (is.null(supported_atb_cols_meta)) {
    supported_atb_cols_meta <- sir_wide_meta$atb_cols
  }

  supported_atb_cols <- intersect(
    as.character(supported_atb_cols_meta),
    names(reference_global_dedup)
  )
  if (length(supported_atb_cols) == 0L) {
    stop("No supported antibiotic columns available for indicator characterization.", call. = FALSE)
  }

  available_phenotype_cols <- intersect(
    c("blse_flag", "carbapenemase_flag"),
    names(reference_global_dedup)
  )

  available_sample_types <- sort(unique(na.omit(as.character(
    reference_by_type_dedup$naturepvt_norm
  ))))

  indicator_sample_types <- ratb_cfg$indicator_sample_types
  indicator_selected_sample_types <- indicator_sample_types[
    indicator_sample_types %in% available_sample_types
  ]
  if (length(indicator_selected_sample_types) == 0L) {
    stop("No configured indicator sample types are present in dedup outputs.", call. = FALSE)
  }

  indicator_spec <- load_ratb_indicator_spec(indicator_spec_path)
  indicator_spec_validation <- validate_ratb_indicator_spec(
    spec = indicator_spec,
    atb_cols = atb_cols,
    supported_atb_cols = supported_atb_cols,
    phenotype_cols = available_phenotype_cols,
    available_sample_types = available_sample_types
  )

  stopifnot(!any(indicator_spec_validation$duplicated_indicator_id))
  stopifnot(all(indicator_spec_validation$supported_indicator_kind))
  stopifnot(all(indicator_spec_validation$supported_sample_type_mode))
  stopifnot(all(indicator_spec_validation$supported_numerator_kind))
  stopifnot(all(indicator_spec_validation$supported_denominator_kind))
  stopifnot(all(indicator_spec_validation$has_scope_mode))
  stopifnot(all(indicator_spec_validation$has_filter_values))
  stopifnot(all(indicator_spec_validation$has_valid_indicator_payload))

  indicator_coverage_audit <- build_ratb_indicator_coverage_audit(
    spec = indicator_spec,
    validation = indicator_spec_validation
  )

  spec_proportion_exec <- indicator_spec |>
    dplyr::semi_join(
      indicator_coverage_audit |>
        dplyr::filter(.data$proportion_executable) |>
        dplyr::select("indicator_id"),
      by = "indicator_id"
    )

  spec_incidence_exec <- indicator_spec |>
    dplyr::semi_join(
      indicator_coverage_audit |>
        dplyr::filter(.data$incidence_executable) |>
        dplyr::select("indicator_id"),
      by = "indicator_id"
    )

  bact_order_map <- build_species_taxonomy_map(species_taxonomy_path)

  panel_annual <- build_ratb_indicator_panel_annual(
    dedup_results = dedup_results,
    spec = spec_proportion_exec,
    atb_cols = atb_cols,
    supported_atb_cols = supported_atb_cols,
    bact_order_map = bact_order_map
  )

  panel_incidence <- build_ratb_indicator_panel_incidence_annual(
    dedup_results = dedup_results,
    spec = spec_incidence_exec,
    atb_cols = atb_cols,
    supported_atb_cols = supported_atb_cols,
    bact_order_map = bact_order_map,
    incidence_denominator_by_year = scope_cache$incidence_denominator_by_year
  )

  incidence_excluded_years <- ratb_cfg$incidence_excluded_years
  if (length(incidence_excluded_years) > 0L && nrow(panel_incidence) > 0L) {
    panel_incidence <- panel_incidence |>
      dplyr::filter(!(.data$dedup_year %in% incidence_excluded_years))
  }

  list(
    indicator_spec_validation = indicator_spec_validation,
    indicator_coverage_audit = indicator_coverage_audit,
    indicator_panel_annual = panel_annual,
    indicator_panel_global = dplyr::filter(panel_annual, .data$scope == "global"),
    indicator_panel_by_type = dplyr::filter(panel_annual, .data$scope == "by_type"),
    indicator_panel_incidence = panel_incidence,
    indicator_panel_incidence_global = dplyr::filter(panel_incidence, .data$scope == "global")
  )
}

build_characterization <- function() {
  source("R/setup.R")

  sir_wide <- read_rds_artifact(file.path("data", "sir_wide.rds"))
  sir_wide_meta <- read_rds_artifact(file.path("data", "sir_wide_meta.rds"))
  scope_cache <- read_rds_artifact(file.path("data", "ratb_scope_cache"))
  completion_datasets <- read_rds_artifact(file.path("data", "completion_datasets"))
  dedup_results <- read_rds_artifact(file.path("data", "dedup_results"))

  signatures <- list(
    safe_signature_row("data/sir_wide", sir_wide)
  )

  scope_tables <- c(
    "sir_wide_ratb_scope",
    "sir_wide_ratb_analytic_scope",
    "ratb_scope_exclusion_summary",
    "hospital_stays_validated",
    "hospital_stay_validation_summary",
    "hospital_days_year_summary",
    "ratb_unit_stay_scope_audit",
    "hospital_nights_by_year_unit",
    "hospital_days_year_summary_provisional",
    "ratb_numerator_scope_impact_audit"
  )
  for (nm in intersect(scope_tables, names(scope_cache))) {
    signatures[[length(signatures) + 1L]] <- safe_signature_row(
      paste0("scope_cache/", nm),
      scope_cache[[nm]]
    )
  }

  for (dataset in names(completion_datasets)) {
    signatures[[length(signatures) + 1L]] <- safe_signature_row(
      paste0("completion_datasets/", dataset),
      completion_datasets[[dataset]]
    )
  }

  for (dataset in names(dedup_results)) {
    for (scope in names(dedup_results[[dataset]])) {
      for (component in names(dedup_results[[dataset]][[scope]])) {
        object <- dedup_results[[dataset]][[scope]][[component]]
        if (is.data.frame(object)) {
          signatures[[length(signatures) + 1L]] <- safe_signature_row(
            paste0("dedup_results/", dataset, "/", scope, "/", component),
            object
          )
        }
      }
    }
  }

  panels <- build_indicator_panels(
    sir_wide_meta = sir_wide_meta,
    dedup_results = dedup_results,
    scope_cache = scope_cache
  )
  for (nm in names(panels)) {
    signatures[[length(signatures) + 1L]] <- safe_signature_row(
      paste0("computed/", nm),
      panels[[nm]]
    )
  }

  signatures <- do.call(rbind, signatures)
  signatures <- signatures[order(signatures$name), , drop = FALSE]
  row.names(signatures) <- NULL

  git_head <- tryCatch(
    system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = FALSE),
    error = function(err) NA_character_
  )

  list(
    schema_version = 1L,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    repo_root = repo_root,
    git_head = if (length(git_head) > 0L) git_head[[1]] else NA_character_,
    signatures = signatures
  )
}

compare_characterizations <- function(baseline, current) {
  stopifnot(identical(baseline$schema_version, current$schema_version))

  lhs <- baseline$signatures
  rhs <- current$signatures

  missing_current <- setdiff(lhs$name, rhs$name)
  missing_baseline <- setdiff(rhs$name, lhs$name)

  common_names <- intersect(lhs$name, rhs$name)
  lhs_common <- lhs[match(common_names, lhs$name), , drop = FALSE]
  rhs_common <- rhs[match(common_names, rhs$name), , drop = FALSE]

  changed <- common_names[
    lhs_common$nrow != rhs_common$nrow |
      lhs_common$ncol != rhs_common$ncol |
      lhs_common$columns_hash != rhs_common$columns_hash |
      lhs_common$data_hash != rhs_common$data_hash
  ]

  list(
    ok = length(missing_current) == 0L &&
      length(missing_baseline) == 0L &&
      length(changed) == 0L,
    missing_current = missing_current,
    missing_baseline = missing_baseline,
    changed = changed,
    baseline = lhs_common[match(changed, common_names), , drop = FALSE],
    current = rhs_common[match(changed, common_names), , drop = FALSE]
  )
}

if (identical(mode, "write")) {
  baseline <- build_characterization()
  dir.create(dirname(snapshot_path), recursive = TRUE, showWarnings = FALSE)
  saveRDS(baseline, snapshot_path, version = 2)
  message("Wrote characterization baseline: ", snapshot_path)
  message("Signed objects: ", nrow(baseline$signatures))
} else {
  if (!file.exists(snapshot_path)) {
    stop(
      "Missing characterization baseline: ", snapshot_path,
      ". Create it with: Rscript scripts/characterize_current_outputs.R write",
      call. = FALSE
    )
  }

  baseline <- readRDS(snapshot_path)
  current <- build_characterization()
  cmp <- compare_characterizations(baseline, current)

  if (!isTRUE(cmp$ok)) {
    if (length(cmp$missing_current) > 0L) {
      message("Missing from current: ", paste(cmp$missing_current, collapse = ", "))
    }
    if (length(cmp$missing_baseline) > 0L) {
      message("Missing from baseline: ", paste(cmp$missing_baseline, collapse = ", "))
    }
    if (length(cmp$changed) > 0L) {
      message("Changed signatures:")
      print(data.frame(name = cmp$changed, stringsAsFactors = FALSE), row.names = FALSE)
    }
    stop("Characterization baseline check failed.", call. = FALSE)
  }

  message("Characterization baseline check passed.")
  message("Signed objects: ", nrow(current$signatures))
}
