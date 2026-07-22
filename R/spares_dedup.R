#' SPARES-like class definition and deduplication (wide format)
#'
#' This file exposes three public functions built on the same class logic:
#' - `spares_define_classes()`: compute phenotype classes only.
#' - `spares_select_representatives()`: pick one representative per class.
#' - `spares_dedup()`: convenience wrapper that runs both steps.
#'
#' The compatibility rule is shared across all steps:
#' two rows are incompatible if at least one `S<->R` conflict exists on
#' overlapping informative ATB values (`ZIT` treated as non-informative).
#'
#' Determinism note:
#' class assignment is greedy first-fit, so stable ordering is part of the
#' algorithm definition (not only a display concern).

source("R/bootstrap.R")

# Load shared primitives used by SPARES class definition and deduplication.
orchidee_source_script_if_missing(
  "spares_shared_primitives.R",
  c(
    ".spares_normalize_noninformative",
    ".spares_sr_conflict_pair",
    ".spares_discord_matrix",
    ".spares_time_sort_key",
    ".spares_derive_evt_order_sort",
    ".spares_derive_elt_order_sort"
  ),
  "shared helper script"
)

ensure_spares_phenotype_helpers_available <- function() {
  required_funs <- c(
    "prepare_phenotype_sr_columns",
    "summarise_class_phenotype_status"
  )
  orchidee_source_script_if_missing(
    "phenotype_flag_helpers.R",
    required_funs,
    "phenotype helper script"
  )
}

ensure_spares_phenotype_helpers_available()

.spares_order_keys <- function(g, completeness_col, date_col, time_col, document_id_col) {
  n <- nrow(g)
  out <- list(
    completeness_sort = suppressWarnings(as.numeric(as.character(g[[completeness_col]]))),
    souche_sort = if ("souche_id" %in% names(g)) as.character(g[["souche_id"]]) else rep(NA_character_, n),
    eltid_sort = if ("ELTID" %in% names(g)) as.character(g[["ELTID"]]) else as.character(g[[document_id_col]]),
    document_sort = as.character(g[[document_id_col]]),
    row_sort = if (".row_id_global" %in% names(g)) g[[".row_id_global"]] else seq_len(n)
  )
  date_sort <- as.Date(g[[date_col]])
  time_sort <- .spares_time_sort_key(g[[time_col]])
  out$evt_order_sort <- .spares_derive_evt_order_sort(
    g = g,
    date_sort = date_sort,
    time_sort = time_sort,
    document_sort = out$document_sort,
    row_sort = out$row_sort
  )
  out$elt_order_sort <- .spares_derive_elt_order_sort(
    g = g,
    evt_order_sort = out$evt_order_sort,
    date_sort = date_sort,
    time_sort = time_sort,
    document_sort = out$document_sort,
    row_sort = out$row_sort
  )
  out
}

.spares_class_order_sort <- function(g, completeness_col, date_col, time_col, document_id_col) {
  # Deterministic order for greedy first-fit class assignment.
  # Hard anti-mix boundaries are group_keys (outside this function).
  #
  # Priority (within a group):
  # 1) evt_order (explicit or derived)
  # 2) elt_order (explicit or derived)
  # 3) souche_id
  # 4) -completeness
  # 5) ELTID
  # 6) stable row id (technical tie-break)
  k <- .spares_order_keys(
    g = g,
    completeness_col = completeness_col,
    date_col = date_col,
    time_col = time_col,
    document_id_col = document_id_col
  )
  order(
    k$evt_order_sort,
    k$elt_order_sort,
    k$souche_sort,
    -k$completeness_sort,
    k$eltid_sort,
    k$row_sort,
    na.last = TRUE
  )
}

.spares_representative_order_sort <- function(g, completeness_col, date_col, time_col, document_id_col) {
  # Deterministic order for representative selection inside each class.
  #
  # Priority (within one class):
  # 1) -completeness (the active raw runtime uses nb_resultats)
  # 2) evt_order (explicit or derived)
  # 3) elt_order (explicit or derived)
  # 4) ELTID
  # 5) souche_id
  # 6) stable row id (technical tie-break)
  k <- .spares_order_keys(
    g = g,
    completeness_col = completeness_col,
    date_col = date_col,
    time_col = time_col,
    document_id_col = document_id_col
  )
  order(
    -k$completeness_sort,
    k$evt_order_sort,
    k$elt_order_sort,
    k$eltid_sort,
    k$souche_sort,
    k$row_sort,
    na.last = TRUE
  )
}

# Greedy first-fit over discordance matrix: assign each row to first compatible class.
.spares_assign_classes_first_fit <- function(discord, ord) {
  m <- nrow(discord)
  if (m == 0L) return(integer(0))

  cls <- integer(m)
  class_members <- list()
  n_classes <- 0L

  for (idx in ord) {
    placed <- FALSE
    if (n_classes > 0L) {
      for (cc in seq_len(n_classes)) {
        members <- class_members[[cc]]
        if (!any(discord[idx, members])) {
          cls[idx] <- cc
          class_members[[cc]] <- c(members, idx)
          placed <- TRUE
          break
        }
      }
    }
    if (!placed) {
      n_classes <- n_classes + 1L
      cls[idx] <- n_classes
      class_members[[n_classes]] <- idx
    }
  }

  cls
}

# Audit helper: count discordant pairs that ended up within classes.
.spares_count_within_class_discord_pairs <- function(discord, cls) {
  if (length(cls) < 2L) return(0L)
  total <- 0L

  for (cc in unique(cls)) {
    members <- which(cls == cc)
    if (length(members) < 2L) next
    dsub <- discord[members, members, drop = FALSE]
    total <- total + sum(dsub[upper.tri(dsub)])
  }

  as.integer(total)
}

# Prepare completeness column and report whether a temporary one was created.
.spares_prepare_completeness <- function(df, atb_cols, completeness_col = NULL) {
  created_tmp_completeness <- FALSE
  out <- df
  resolved_col <- completeness_col

  if (is.null(resolved_col)) {
    info <- as.matrix(out[, atb_cols, drop = FALSE] %in% c("S", "R"))
    out$.completeness_tmp <- rowSums(info, na.rm = TRUE)
    resolved_col <- ".completeness_tmp"
    created_tmp_completeness <- TRUE
  } else {
    stopifnot(resolved_col %in% names(out))
  }

  list(
    df = out,
    completeness_col = resolved_col,
    created_tmp_completeness = created_tmp_completeness
  )
}

#' Define phenotype classes without deduplication collapse
#'
#' @param df Data frame (1 row = 1 isolate record in wide format).
#' @param atb_cols Character vector of ATB columns in `df`.
#' @param group_keys Character vector of episode grouping columns.
#' @param time_col Column name for sample time.
#' @param date_col Column name for sample date/datetime.
#' @param document_id_col Stable document identifier column.
#' @param completeness_col Completeness column for deterministic ranking.
#'        If `NULL`, a temporary S/R count is computed.
#' @param zit_values Values treated as non-informative.
#' @param keep_class_members If TRUE, return row-level class mapping.
#' @param keep_audit If TRUE, return order-sensitivity diagnostics.
#'
#' @details
#' Class assignment is greedy first-fit over a pairwise discordance matrix.
#' With sparse panels (`NA`/`ZIT`), compatibility is not strictly transitive,
#' so different valid partitions may appear under different row orders.
#' `keep_audit = TRUE` reports reverse-order sensitivity per episode.
#'
#' @return A list with:
#' - `class_map` (optional): row-to-class mapping.
#' - `episode_summary`: n_docs, n_classes, has_multiple_classes by episode.
#' - `audit` (optional): per-episode class assignment diagnostics.
spares_define_classes <- function(df,
                                  atb_cols,
                                  group_keys,
                                  time_col = "HEUREPRELEV",
                                  date_col = "DATEPRELEV",
                                  document_id_col = "ELTID",
                                  completeness_col = NULL,
                                  conflict_cols = NULL,
                                  zit_values = "ZIT",
                                  keep_class_members = TRUE,
                                  keep_audit = FALSE
                                 ) {
  stopifnot(is.data.frame(df))
  stopifnot(all(atb_cols %in% names(df)))
  stopifnot(all(group_keys %in% names(df)))
  stopifnot(time_col %in% names(df))
  stopifnot(date_col %in% names(df))
  stopifnot(document_id_col %in% names(df))

  prep <- .spares_prepare_completeness(df, atb_cols = atb_cols, completeness_col = completeness_col)
  work <- prep$df
  resolved_completeness_col <- prep$completeness_col
  created_tmp_completeness <- prep$created_tmp_completeness

  if (is.null(conflict_cols)) {
    pheno_prep <- prepare_phenotype_sr_columns(work, prefer_final = TRUE)
    work <- pheno_prep$data
    resolved_conflict_cols <- unique(c(atb_cols, pheno_prep$sr_cols))
  } else {
    resolved_conflict_cols <- unique(conflict_cols)
  }
  stopifnot(all(resolved_conflict_cols %in% names(work)))

  split_keys <- work[, group_keys, drop = FALSE]
  key_str <- do.call(paste, c(split_keys, sep = "\r"))
  groups <- split(work, key_str, drop = TRUE)

  class_map_list <- vector("list", length(groups))
  episode_sum_list <- vector("list", length(groups))
  audit_list <- vector("list", length(groups))

  idx <- 0L
  for (k in names(groups)) {
    idx <- idx + 1L
    g <- groups[[k]]

    discord <- .spares_discord_matrix(g, atb_cols = resolved_conflict_cols, zit_values = zit_values)
    ord <- .spares_class_order_sort(
      g,
      completeness_col = resolved_completeness_col,
      date_col = date_col,
      time_col = time_col,
      document_id_col = document_id_col
    )
    cls <- .spares_assign_classes_first_fit(discord, ord)

    g2 <- g
    g2$.phenotype_class <- cls
    g2o <- g2[ord, , drop = FALSE]

    n_docs <- nrow(g2o)
    n_classes <- length(unique(g2o$.phenotype_class))
    episode_sum <- cbind(
      g2o[1, group_keys, drop = FALSE],
      data.frame(
        n_docs = n_docs,
        n_classes = n_classes,
        has_multiple_classes = n_classes > 1,
        stringsAsFactors = FALSE
      )
    )
    episode_sum_list[[idx]] <- episode_sum

    if (keep_class_members) {
      keep_cols <- unique(c(
        ".row_id_global", "PATID", "EVTID", document_id_col, group_keys, "souche_id",
        date_col, time_col, resolved_completeness_col, ".phenotype_class"
      ))
      keep_cols <- keep_cols[keep_cols %in% names(g2o)]
      class_map_list[[idx]] <- g2o[, keep_cols, drop = FALSE]
    }

    if (keep_audit) {
      cls_reverse <- .spares_assign_classes_first_fit(discord, rev(ord))
      n_discord_pairs <- .spares_count_within_class_discord_pairs(discord, cls)
      n_classes_reverse <- length(unique(cls_reverse))
      audit_list[[idx]] <- cbind(
        g2o[1, group_keys, drop = FALSE],
        data.frame(
          n_docs = n_docs,
          n_classes = n_classes,
          any_within_class_discord = n_discord_pairs > 0L,
          n_within_class_discord_pairs = n_discord_pairs,
          n_classes_reverse_order = n_classes_reverse,
          order_sensitive = n_classes_reverse != n_classes,
          stringsAsFactors = FALSE
        )
      )
    }
  }

  episode_summary <- dplyr::bind_rows(episode_sum_list)
  class_map <- if (keep_class_members) dplyr::bind_rows(class_map_list) else NULL
  audit <- if (keep_audit) dplyr::bind_rows(audit_list) else NULL

  if (created_tmp_completeness && !is.null(class_map)) {
    class_map$.completeness_tmp <- NULL
  }

  if (!is.null(class_map) && ".phenotype_class" %in% names(class_map)) {
    names(class_map)[names(class_map) == ".phenotype_class"] <- "phenotype_class"
  }

  out <- list(
    class_map = class_map,
    episode_summary = episode_summary
  )
  if (keep_audit) out$audit <- audit
  out
}

#' Select one representative row per (episode, phenotype_class)
#'
#' @param df Input data frame.
#' @param class_map Output class map from `spares_define_classes()`.
#' @param group_keys Episode grouping keys.
#' @param atb_cols ATB columns, required only when `completeness_col = NULL`.
#' @param time_col,date_col,document_id_col Tie-break columns.
#' @param completeness_col Completeness ranking column (or NULL for computed S/R count).
#'
#' @return Data frame with one retained representative per class.
spares_select_representatives <- function(df,
                                          class_map,
                                          group_keys,
                                          atb_cols = NULL,
                                          time_col = "HEUREPRELEV",
                                          date_col = "DATEPRELEV",
                                          document_id_col = "ELTID",
                                          completeness_col = NULL
                                         ) {
  stopifnot(is.data.frame(df))
  stopifnot(is.data.frame(class_map))
  stopifnot(all(group_keys %in% names(df)))
  stopifnot(all(group_keys %in% names(class_map)))
  stopifnot(time_col %in% names(df))
  stopifnot(date_col %in% names(df))
  stopifnot(document_id_col %in% names(df))
  stopifnot(".row_id_global" %in% names(df))
  stopifnot(".row_id_global" %in% names(class_map))
  stopifnot("phenotype_class" %in% names(class_map))
  if (is.null(completeness_col)) {
    stopifnot(!is.null(atb_cols), all(atb_cols %in% names(df)))
  }
  if (is.null(atb_cols)) atb_cols <- character(0)

  prep <- .spares_prepare_completeness(df, atb_cols = atb_cols, completeness_col = completeness_col)
  work <- prep$df
  resolved_completeness_col <- prep$completeness_col
  created_tmp_completeness <- prep$created_tmp_completeness

  class_keys <- class_map %>%
    select(.row_id_global, phenotype_class) %>%
    distinct()

  x <- work %>%
    inner_join(class_keys, by = ".row_id_global")

  reps <- x %>%
    group_by(across(all_of(c(group_keys, "phenotype_class")))) %>%
    group_modify(~ {
      ord <- .spares_representative_order_sort(
        .x,
        completeness_col = resolved_completeness_col,
        date_col = date_col,
        time_col = time_col,
        document_id_col = document_id_col
      )
      .x[ord[1], , drop = FALSE]
    }) %>%
    ungroup()

  phenotype_summary <- summarise_class_phenotype_status(
    x,
    class_cols = c(group_keys, "phenotype_class"),
    prefer_final = TRUE
  )
  if (!is.null(phenotype_summary)) {
    reps <- reps %>%
      select(-any_of(c(
        "blse_status_final", "carbapenemase_status_final",
        "blse_flag", "carbapenemase_flag"
      ))) %>%
      left_join(phenotype_summary, by = c(group_keys, "phenotype_class"))
  }

  if (created_tmp_completeness) {
    reps$.completeness_tmp <- NULL
  }

  reps
}

#' SPARES-like deduplication wrapper
#'
#' This wrapper keeps backward compatibility with older usage while delegating
#' class definition and representative selection to dedicated functions.
#'
#' @param df Data frame (1 row = 1 isolate record in wide format).
#' @param atb_cols Character vector of ATB columns in `df`.
#' @param group_keys Character vector of episode grouping columns.
#' @param time_col,date_col,document_id_col Tie-break columns.
#' @param completeness_col Completeness ranking column (or NULL for computed S/R count).
#' @param zit_values Values treated as non-informative.
#' @param keep_class_members If TRUE, include row-level class mapping in output.
#' @param keep_audit If TRUE, include class-audit diagnostics.
#' @param return_dedup Legacy switch: if FALSE, return class-only output.
#'
#' @details
#' Backward-compatible wrapper around:
#' 1) `spares_define_classes()`
#' 2) `spares_select_representatives()`
#'
#' Keeping the pipeline layered aligns class definition and representative
#' selection.
#'
#' @return A list with:
#' - `dedup` (unless `return_dedup = FALSE`)
#' - `class_map` (optional)
#' - `episode_summary`
#' - `audit` (optional)
spares_dedup <- function(df,
                         atb_cols,
                         group_keys,
                         time_col = "HEUREPRELEV",
                         date_col = "DATEPRELEV",
                         document_id_col = "ELTID",
                         completeness_col = NULL,
                         zit_values = "ZIT",
                         keep_class_members = TRUE,
                         keep_audit = FALSE,
                         return_dedup = TRUE
                        ) {
  stopifnot(is.data.frame(df))
  stopifnot(all(atb_cols %in% names(df)))
  stopifnot(all(group_keys %in% names(df)))
  stopifnot(time_col %in% names(df))
  stopifnot(date_col %in% names(df))
  stopifnot(document_id_col %in% names(df))

  had_row_id <- ".row_id_global" %in% names(df)
  work <- df
  if (!had_row_id) {
    work$.row_id_global <- seq_len(nrow(work))
  }

  internal_keep_class_members <- keep_class_members || isTRUE(return_dedup)
  class_res <- spares_define_classes(
    df = work,
    atb_cols = atb_cols,
    group_keys = group_keys,
    time_col = time_col,
    date_col = date_col,
    document_id_col = document_id_col,
    completeness_col = completeness_col,
    zit_values = zit_values,
    keep_class_members = internal_keep_class_members,
    keep_audit = keep_audit
  )

  if (!isTRUE(return_dedup)) {
    out_class_map <- if (keep_class_members) class_res$class_map else NULL
    if (!had_row_id && !is.null(out_class_map) && ".row_id_global" %in% names(out_class_map)) {
      out_class_map$.row_id_global <- NULL
    }
    out <- list(
      class_map = out_class_map,
      episode_summary = class_res$episode_summary
    )
    if (keep_audit) out$audit <- class_res$audit
    return(out)
  }

  dedup <- spares_select_representatives(
    df = work,
    class_map = class_res$class_map,
    group_keys = group_keys,
    atb_cols = atb_cols,
    time_col = time_col,
    date_col = date_col,
    document_id_col = document_id_col,
    completeness_col = completeness_col
  )

  out_class_map <- if (keep_class_members) class_res$class_map else NULL
  if (!had_row_id) {
    if (".row_id_global" %in% names(dedup)) dedup$.row_id_global <- NULL
    if (!is.null(out_class_map) && ".row_id_global" %in% names(out_class_map)) {
      out_class_map$.row_id_global <- NULL
    }
  }

  out <- list(
    dedup = dedup,
    class_map = out_class_map,
    episode_summary = class_res$episode_summary
  )
  if (keep_audit) out$audit <- class_res$audit
  out
}

