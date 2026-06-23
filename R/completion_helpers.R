# Completion helper utilities for antibiogram completion workflows.
#
# These helpers are extracted from the notebook to keep the .qmd concise
# and to make completion logic reusable across scripts.
#
# Design invariants:
# - Only informative S/R values are propagated (never ZIT/non-informative).
# - Completion is class-aware and never crosses phenotype class boundaries.
# - Processing order is deterministic to keep first-fit behavior reproducible.

bootstrap_path <- c(file.path("R", "bootstrap.R"), "bootstrap.R")
bootstrap_path <- bootstrap_path[file.exists(bootstrap_path)][1]
if (is.na(bootstrap_path)) {
  stop("Missing bootstrap helper script.", call. = FALSE)
}
source(bootstrap_path)

# Load shared primitives used by both completion and SPARES.
ensure_shared_primitives_available <- function() {
  required_funs <- c(
    ".spares_normalize_noninformative",
    ".spares_sr_conflict_pair",
    ".spares_discord_matrix",
    ".spares_time_sort_key",
    ".spares_derive_evt_order_sort",
    ".spares_derive_elt_order_sort"
  )
  orchidee_source_script_if_missing(
    "spares_shared_primitives.R",
    required_funs,
    "shared helper script"
  )
}

ensure_shared_primitives_available()

ensure_phenotype_helpers_available <- function() {
  required_funs <- c(
    "prepare_phenotype_sr_columns",
    "finalize_phenotype_completion"
  )
  orchidee_source_script_if_missing(
    "phenotype_flag_helpers.R",
    required_funs,
    "phenotype helper script"
  )
}

ensure_phenotype_helpers_available()

#' Return informative S/R flags
#'
#' @param x Character-like vector of ATB values.
#' @return Logical vector, TRUE only for non-missing S or R.
is_sr <- function(x) {
  !is.na(x) & x %in% c("S", "R")
}

#' Check whether a pair is inside the allowed date gap
#'
#' @param date_i,date_j Date-like values.
#' @param max_days Maximum absolute day gap allowed (Inf disables the filter).
#' @return Logical scalar.
pair_gap_days_ok <- function(date_i, date_j, max_days = Inf) {
  if (is.infinite(max_days)) return(TRUE)
  if (is.na(date_i) || is.na(date_j)) return(FALSE)
  abs(as.numeric(difftime(as.Date(date_i), as.Date(date_j), units = "days"))) <= max_days
}

#' Transfer informative S/R values into missing target cells
#'
#' @param source_vals Character vector of source ATB values.
#' @param target_vals Character vector of target ATB values.
#' @param atb_cols Character vector of ATB column names (length check only).
#' @return List with updated target values and count of filled cells.
transfer_sr <- function(source_vals, target_vals, atb_cols) {
  stopifnot(length(source_vals) == length(target_vals), length(source_vals) == length(atb_cols))

  can_fill <- is.na(target_vals) & is_sr(source_vals)
  out <- target_vals
  out[can_fill] <- source_vals[can_fill]

  list(
    target_vals = out,
    n_filled = as.integer(sum(can_fill))
  )
}

#' Resolve completeness sort key for completion ordering
#'
#' Priority:
#' 1) nb_resultats_post
#' 2) nb_resultats
#' 3) computed informative S/R count over atb_cols
#'
#' @param g Data frame.
#' @param atb_cols Character vector of ATB columns.
#' @return Numeric vector.
completeness_sort_key <- function(g, atb_cols) {
  if ("nb_resultats_post" %in% names(g)) {
    return(suppressWarnings(as.numeric(as.character(g[["nb_resultats_post"]]))))
  }
  if ("nb_resultats" %in% names(g)) {
    return(suppressWarnings(as.numeric(as.character(g[["nb_resultats"]]))))
  }
  rowSums(as.matrix(g[, atb_cols, drop = FALSE] %in% c("S", "R")), na.rm = TRUE)
}

#' Ensure class-definition API is available
#'
#' Loads `spares_dedup.R` from common locations if needed.
#' Completion uses `spares_define_classes()` to build provisional phenotype classes
#' before applying within-class completion.
#'
#' @return Invisible TRUE if `spares_define_classes()` is available.
ensure_spares_dedup_available <- function() {
  orchidee_source_script_if_missing(
    "spares_dedup.R",
    "spares_define_classes",
    "spares_dedup script"
  )
}

#' Complete one group, constrained to provisional phenotype classes
#'
#' Class boundaries are computed by `spares_define_classes()` and completion is run
#' independently inside each provisional class.
#'
#' Workflow:
#' 1) build provisional classes with `spares_define_classes()`
#' 2) run iterative bidirectional completion inside each class independently
#' 3) merge class-wise outputs back on `.row_id_global`
#'
#' @param g One grouped data frame.
#' @param group_keys Grouping keys used for the strategy.
#' @param atb_cols Character vector of ATB columns.
#' @param max_days Maximum day gap for transfer (Inf = unlimited).
#' @param zit_values Values considered non-informative by conflict helper.
#' @return List(data, group_metrics, row_metrics).
complete_group_class_aware <- function(
    g,
    group_keys,
    atb_cols,
    max_days = Inf,
    zit_values = "ZIT"
  ) {
  n <- nrow(g)
  if (n == 0L) {
    return(list(
      data = g,
      group_metrics = tibble(
        n_rows = 0L,
        n_classes = 0L,
        n_pairs_unique = 0L,
        n_pairs_checked = 0L,
        n_pairs_conflict = 0L,
        n_cells_filled_total = 0L,
        n_iterations = 0L,
        n_rows_filled = 0L
      ),
      row_metrics = tibble(
        .row_id_global = integer(),
        phenotype_class = integer(),
        n_cells_filled = integer(),
        n_passes_touched = integer(),
        max_gap_used_days = numeric()
      )
    ))
  }

  ensure_spares_dedup_available()
  ensure_phenotype_helpers_available()

  g_work <- g
  temp_class_cols <- character(0)
  pheno_prep <- prepare_phenotype_sr_columns(g_work, prefer_final = TRUE)
  g_work <- pheno_prep$data
  transfer_cols <- unique(c(atb_cols, pheno_prep$sr_cols))

  class_date_col <- if ("DATEPRELEV" %in% names(g_work)) {
    "DATEPRELEV"
  } else {
    g_work$.date_tmp_class <- as.Date(rep(NA_character_, n))
    temp_class_cols <- c(temp_class_cols, ".date_tmp_class")
    ".date_tmp_class"
  }

  class_time_col <- if ("HEUREPRELEV" %in% names(g_work)) {
    "HEUREPRELEV"
  } else {
    g_work$.time_tmp_class <- rep(NA_character_, n)
    temp_class_cols <- c(temp_class_cols, ".time_tmp_class")
    ".time_tmp_class"
  }

  class_completeness_col <- if ("nb_resultats_post" %in% names(g_work)) {
    "nb_resultats_post"
  } else if ("nb_resultats" %in% names(g_work)) {
    "nb_resultats"
  } else {
    NULL
  }
  class_document_col <- if ("ELTID" %in% names(g_work)) "ELTID" else ".row_id_global"

  class_res <- spares_define_classes(
    df = g_work,
    atb_cols = atb_cols,
    conflict_cols = transfer_cols,
    group_keys = group_keys,
    time_col = class_time_col,
    date_col = class_date_col,
    document_id_col = class_document_col,
    completeness_col = class_completeness_col,
    zit_values = zit_values,
    keep_class_members = TRUE,
    keep_audit = FALSE
  )

  if (!".row_id_global" %in% names(class_res$class_map)) {
    stop("spares_define_classes() class_map must contain .row_id_global for class-aware completion.", call. = FALSE)
  }

  class_map <- class_res$class_map %>%
    select(.row_id_global, phenotype_class) %>%
    distinct()

  g_classed <- g_work %>%
    left_join(class_map, by = ".row_id_global")

  if (any(is.na(g_classed$phenotype_class))) {
    stop("Failed to assign phenotype_class for all rows in class-aware completion.", call. = FALSE)
  }

  class_splits <- split(g_classed, g_classed$phenotype_class, drop = TRUE)

  class_completed <- purrr::map(
    class_splits,
    ~ complete_group_bidirectional(
      .x,
      atb_cols = atb_cols,
      transfer_cols = transfer_cols,
      max_days = max_days,
      zit_values = zit_values
    )
  )

  data_out <- dplyr::bind_rows(purrr::map(class_completed, "data")) %>%
    arrange(.row_id_global)
  data_out <- finalize_phenotype_completion(
    data_out,
    status_sources = pheno_prep$status_sources,
    sr_col_names = pheno_prep$sr_col_names
  ) %>%
    select(-any_of(c("phenotype_class", temp_class_cols)))

  row_out <- dplyr::bind_rows(purrr::map(class_completed, "row_metrics")) %>%
    arrange(.row_id_global) %>%
    left_join(class_map, by = ".row_id_global")

  class_group_metrics <- dplyr::bind_rows(purrr::map(class_completed, "group_metrics"))

  group_out <- tibble(
    n_rows = n,
    n_classes = length(unique(class_map$phenotype_class)),
    n_pairs_unique = sum(class_group_metrics$n_pairs_unique, na.rm = TRUE),
    n_pairs_checked = sum(class_group_metrics$n_pairs_checked, na.rm = TRUE),
    n_pairs_conflict = sum(class_group_metrics$n_pairs_conflict, na.rm = TRUE),
    n_cells_filled_total = sum(class_group_metrics$n_cells_filled_total, na.rm = TRUE),
    n_iterations = max(class_group_metrics$n_iterations, na.rm = TRUE),
    n_rows_filled = sum(row_out$n_cells_filled > 0L, na.rm = TRUE)
  )

  list(
    data = data_out,
    group_metrics = group_out,
    row_metrics = row_out
  )
}

#' Bidirectional iterative completion within one group
#'
#' Sort order used before propagation:
#' evt_order, elt_order, souche_id, -completeness, ELTID, row_id.
#'
#' @param g Data frame for one group.
#' @param atb_cols Character vector of ATB columns.
#' @param max_days Maximum day gap for transfer (Inf = unlimited).
#' @param zit_values Values considered non-informative by conflict helper.
#' @param max_iterations Hard stop for iterative propagation.
#' @return List(data, group_metrics, row_metrics).
complete_group_bidirectional <- function(
    g,
    atb_cols,
    transfer_cols = atb_cols,
    max_days = Inf,
    zit_values = "ZIT",
    max_iterations = 100L
  ) {
  n <- nrow(g)
  if (n == 0L) {
    return(list(
      data = g,
      group_metrics = tibble(
        n_rows = 0L,
        n_pairs_unique = 0L,
        n_pairs_checked = 0L,
        n_pairs_conflict = 0L,
        n_cells_filled_total = 0L,
        n_iterations = 0L,
        n_rows_filled = 0L
      ),
      row_metrics = tibble(
        .row_id_global = integer(),
        n_cells_filled = integer(),
        n_passes_touched = integer(),
        max_gap_used_days = numeric()
      )
    ))
  }

  transfer_cols <- unique(transfer_cols)
  g[transfer_cols] <- lapply(g[transfer_cols], as.character)

  souche_sort <- if ("souche_id" %in% names(g)) as.character(g[["souche_id"]]) else rep(NA_character_, n)
  completeness_sort <- completeness_sort_key(g, atb_cols = atb_cols)
  date_sort <- if ("DATEPRELEV" %in% names(g)) as.Date(g[["DATEPRELEV"]]) else as.Date(rep(NA_character_, n))
  time_sort <- if ("HEUREPRELEV" %in% names(g)) .spares_time_sort_key(g[["HEUREPRELEV"]]) else rep(NA_character_, n)
  eltid_sort <- if ("ELTID" %in% names(g)) as.character(g[["ELTID"]]) else rep(NA_character_, n)
  row_id_sort <- if (".row_id_global" %in% names(g)) g[[".row_id_global"]] else seq_len(n)
  evt_order_sort <- .spares_derive_evt_order_sort(
    g = g,
    date_sort = date_sort,
    time_sort = time_sort,
    document_sort = eltid_sort,
    row_sort = row_id_sort
  )
  elt_order_sort <- .spares_derive_elt_order_sort(
    g = g,
    evt_order_sort = evt_order_sort,
    date_sort = date_sort,
    time_sort = time_sort,
    document_sort = eltid_sort,
    row_sort = row_id_sort
  )

  ord <- order(
    evt_order_sort,
    elt_order_sort,
    souche_sort,
    -completeness_sort,
    eltid_sort,
    row_id_sort,
    na.last = TRUE
  )
  g <- g[ord, , drop = FALSE]

  date_vec <- as.Date(g$DATEPRELEV)
  n_pairs_checked <- 0L
  n_pairs_conflict <- 0L
  n_cells_filled <- integer(n)
  n_passes_touched <- integer(n)
  max_gap_used_days <- rep(NA_real_, n)

  iteration <- 0L
  repeat {
    iteration <- iteration + 1L
    changed <- FALSE

    if (n >= 2L) {
      for (target in 2:n) {
        for (source in 1:(target - 1L)) {
          n_pairs_checked <- n_pairs_checked + 1L

          if (!pair_gap_days_ok(date_vec[source], date_vec[target], max_days)) next

          source_vals <- as.character(unlist(g[source, transfer_cols, drop = FALSE], use.names = FALSE))
          target_vals <- as.character(unlist(g[target, transfer_cols, drop = FALSE], use.names = FALSE))

          if (.spares_sr_conflict_pair(source_vals, target_vals, zit_values = zit_values)) {
            n_pairs_conflict <- n_pairs_conflict + 1L
            next
          }

          tr <- transfer_sr(source_vals, target_vals, transfer_cols)
          if (tr$n_filled > 0L) {
            g[target, transfer_cols] <- as.list(tr$target_vals)
            n_cells_filled[target] <- n_cells_filled[target] + tr$n_filled
            n_passes_touched[target] <- n_passes_touched[target] + 1L

            gap_days <- if (is.na(date_vec[source]) || is.na(date_vec[target])) {
              NA_real_
            } else {
              abs(as.numeric(difftime(date_vec[source], date_vec[target], units = "days")))
            }

            if (!is.na(gap_days)) {
              max_gap_used_days[target] <- if (is.na(max_gap_used_days[target])) {
                gap_days
              } else {
                max(max_gap_used_days[target], gap_days)
              }
            }

            changed <- TRUE
          }
        }
      }

      for (target in (n - 1L):1L) {
        for (source in (target + 1L):n) {
          n_pairs_checked <- n_pairs_checked + 1L

          if (!pair_gap_days_ok(date_vec[source], date_vec[target], max_days)) next

          source_vals <- as.character(unlist(g[source, transfer_cols, drop = FALSE], use.names = FALSE))
          target_vals <- as.character(unlist(g[target, transfer_cols, drop = FALSE], use.names = FALSE))

          if (.spares_sr_conflict_pair(source_vals, target_vals, zit_values = zit_values)) {
            n_pairs_conflict <- n_pairs_conflict + 1L
            next
          }

          tr <- transfer_sr(source_vals, target_vals, transfer_cols)
          if (tr$n_filled > 0L) {
            g[target, transfer_cols] <- as.list(tr$target_vals)
            n_cells_filled[target] <- n_cells_filled[target] + tr$n_filled
            n_passes_touched[target] <- n_passes_touched[target] + 1L

            gap_days <- if (is.na(date_vec[source]) || is.na(date_vec[target])) {
              NA_real_
            } else {
              abs(as.numeric(difftime(date_vec[source], date_vec[target], units = "days")))
            }

            if (!is.na(gap_days)) {
              max_gap_used_days[target] <- if (is.na(max_gap_used_days[target])) {
                gap_days
              } else {
                max(max_gap_used_days[target], gap_days)
              }
            }

            changed <- TRUE
          }
        }
      }
    }

    if (!changed || iteration >= max_iterations) break
  }

  row_metrics <- tibble(
    .row_id_global = g$.row_id_global,
    n_cells_filled = as.integer(n_cells_filled),
    n_passes_touched = as.integer(n_passes_touched),
    max_gap_used_days = max_gap_used_days
  ) %>%
    arrange(.row_id_global)

  g_out <- g %>%
    arrange(.row_id_global)

  group_metrics <- tibble(
    n_rows = n,
    n_pairs_unique = as.integer(n * (n - 1L) / 2L),
    n_pairs_checked = n_pairs_checked,
    n_pairs_conflict = n_pairs_conflict,
    n_cells_filled_total = sum(n_cells_filled),
    n_iterations = iteration,
    n_rows_filled = sum(n_cells_filled > 0L)
  )

  list(
    data = g_out,
    group_metrics = group_metrics,
    row_metrics = row_metrics
  )
}

#' Run one completion strategy over all groups
#'
#' Adds row-level diagnostics and group-level metrics, and returns the
#' completed dataset together with logs.
#'
#' @param df Input wide dataset.
#' @param group_keys Grouping keys for strategy.
#' @param atb_cols ATB columns to propagate.
#' @param strategy_name Label written to outputs.
#' @param max_days Maximum day gap for eligible pair propagation.
#' @param zit_values Values treated as non-informative in conflict checks.
#'
#' This implementation is class-aware:
#' 1) build provisional phenotype classes within each strategy group
#' 2) apply completion only inside each provisional class
#' 3) combine class-wise outputs back to the original row set
#'
#' @return List(dataset, group_log, row_log).
#' - `dataset`: original rows + completion outputs (`nb_resultats_post`,
#'   `completion_strategy`, `n_cells_filled`, `n_passes_touched`) in
#'   deterministic column order with ATB columns at the end
#' - `group_log`: one row per strategy-group with ordered keys, metadata
#'   (`strategy`, `max_days`, `group_definition`) and aggregate metrics
#' - `row_log`: one row per input row with ordered keys, completeness
#'   (`nb_resultats_pre`, `nb_resultats_post`), per-row metrics, and metadata
run_completion_strategy <- function(
    df,
    group_keys,
    atb_cols,
    strategy_name,
    max_days = Inf,
    zit_values = "ZIT"
  ) {
  stopifnot(all(group_keys %in% names(df)), all(atb_cols %in% names(df)))

  work <- df %>%
    mutate(.row_id_global = row_number())

  grouped <- work %>%
    group_by(across(all_of(group_keys)))

  group_splits <- dplyr::group_split(grouped, .keep = TRUE)
  group_key_df <- dplyr::group_keys(grouped)

  # Class-aware completion:
  # completion never propagates across provisional phenotype classes.
  completed_groups <- purrr::map(
    group_splits,
    ~ complete_group_class_aware(
      .x,
      group_keys = group_keys,
      atb_cols = atb_cols,
      max_days = max_days,
      zit_values = zit_values
    )
  )

  completed <- dplyr::bind_rows(purrr::map(completed_groups, "data")) %>%
    arrange(.row_id_global)

  group_definition <- paste(group_keys, collapse = ", ")
  max_days_out <- if (is.infinite(max_days)) NA_real_ else as.numeric(max_days)
  nb_resultats_pre <- if ("nb_resultats" %in% names(work)) {
    suppressWarnings(as.numeric(as.character(work[["nb_resultats"]])))
  } else {
    rowSums(as.matrix(work[, atb_cols, drop = FALSE] %in% c("S", "R")), na.rm = TRUE)
  }

  row_key_cols <- unique(c(
    group_keys,
    ".row_id_global",
    "PATID", "EVTID", "ELTID", "DATEPRELEV", "HEUREPRELEV",
    "souche_id", "naturepvt_norm", "bact_norm"
  ))
  row_context <- work %>%
    mutate(nb_resultats_pre = nb_resultats_pre) %>%
    select(any_of(row_key_cols), nb_resultats_pre)
  row_post <- completed %>%
    transmute(
      .row_id_global,
      nb_resultats_post = rowSums(across(all_of(atb_cols), ~ .x %in% c("S", "R")), na.rm = TRUE)
    )

  row_log <- dplyr::bind_rows(purrr::map(completed_groups, "row_metrics")) %>%
    arrange(.row_id_global) %>%
    left_join(
      row_context,
      by = ".row_id_global"
    ) %>%
    left_join(row_post, by = ".row_id_global") %>%
    mutate(
      strategy = strategy_name,
      max_days = max_days_out,
      group_definition = group_definition
    ) %>%
    select(any_of(unique(c(
      row_key_cols,
      "nb_resultats_pre", "nb_resultats_post",
      "phenotype_class",
      "n_cells_filled", "n_passes_touched", "max_gap_used_days",
      "strategy", "max_days", "group_definition"
    ))))

  group_log <- dplyr::bind_rows(purrr::map(completed_groups, "group_metrics"))
  if (nrow(group_log) == nrow(group_key_df)) {
    # Preserve explicit group identifiers beside computed metrics.
    group_log <- bind_cols(group_key_df, group_log)
  }
  group_log <- group_log %>%
    mutate(
      strategy = strategy_name,
      max_days = max_days_out,
      group_definition = group_definition
    ) %>%
    select(any_of(c(
      group_keys,
      "strategy", "max_days", "group_definition",
      "n_rows", "n_classes", "n_rows_filled", "n_cells_filled_total",
      "n_pairs_unique", "n_pairs_checked", "n_pairs_conflict", "n_iterations"
    )))

  # Avoid join suffixes (.x/.y) when raw inputs already carry completion metrics.
  completed <- completed %>%
    select(-any_of(c("nb_resultats_post", "n_cells_filled", "n_passes_touched", "completion_strategy"))) %>%
    left_join(
      row_log %>% select(.row_id_global, n_cells_filled, n_passes_touched, nb_resultats_post),
      by = ".row_id_global"
    ) %>%
    mutate(completion_strategy = strategy_name)

  dataset_front_cols <- c(
    "PATID", "EVTID", "ELTID", "DATEPRELEV", "HEUREPRELEV",
    "souche_id", "naturepvt_norm", "bact_norm"
  )
  dataset_metric_cols <- c(
    "nb_resultats", "nb_resultats_post", "completion_strategy",
    "n_cells_filled", "n_passes_touched"
  )
  dataset_middle_cols <- setdiff(
    names(completed),
    c(dataset_front_cols, dataset_metric_cols, ".row_id_global", atb_cols)
  )
  dataset_order <- unique(c(
    dataset_front_cols,
    dataset_metric_cols,
    dataset_middle_cols,
    atb_cols
  ))
  completed <- completed %>%
    select(any_of(dataset_order))

  list(
    dataset = completed,
    group_log = group_log,
    row_log = row_log
  )
}

