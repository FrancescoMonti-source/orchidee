# Workflow-level helpers used by the completion/dedup notebook.
# These helpers keep orchestration, validation, and reporting plumbing
# out of the qmd so the report can focus on interpretation.

bootstrap_path <- c(file.path("R", "bootstrap.R"), "bootstrap.R")
bootstrap_path <- bootstrap_path[file.exists(bootstrap_path)][1]
if (is.na(bootstrap_path)) {
  stop("Missing bootstrap helper script.", call. = FALSE)
}
source(bootstrap_path)

build_raw_group_log <- function(raw_df) {
  tibble(
    strategy = "raw",
    max_days = NA_real_,
    group_definition = "none",
    n_rows = nrow(raw_df),
    n_classes = NA_integer_,
    n_rows_filled = 0L,
    n_cells_filled_total = 0L,
    n_pairs_unique = 0L,
    n_pairs_checked = 0L,
    n_pairs_conflict = 0L,
    n_iterations = 0L
  )
}

build_raw_row_log <- function(raw_df) {
  raw_df %>%
    mutate(.row_id_global = row_number()) %>%
    transmute(
      strategy = "raw",
      group_definition = "none",
      .row_id_global,
      PATID, EVTID, ELTID, DATEPRELEV, HEUREPRELEV, souche_id, naturepvt_norm, bact_norm,
      nb_resultats_pre = nb_resultats,
      phenotype_class = NA_integer_,
      nb_resultats_post = nb_resultats_post,
      n_cells_filled = 0L,
      n_passes_touched = 0L,
      max_gap_used_days = NA_real_,
      max_days = NA_real_
    )
}

validate_completion_payload <- function(
    completion_datasets,
    completion_logs,
    atb_cols,
    expected_dataset_prefix,
    expected_row_cols,
    expected_group_cols
  ) {
  dataset_schema_diag <- purrr::imap(completion_datasets, function(ds, nm) {
    cols <- names(ds)
    prefix_found <- utils::head(cols, length(expected_dataset_prefix))
    tail_found <- utils::tail(cols, length(atb_cols))
    has_prefix <- identical(prefix_found, expected_dataset_prefix)
    has_atb_tail <- identical(tail_found, atb_cols)
    list(
      name = nm,
      has_prefix = has_prefix,
      has_atb_tail = has_atb_tail,
      prefix_found = prefix_found,
      tail_found = tail_found
    )
  })
  dataset_schema_ok <- vapply(dataset_schema_diag, function(x) x$has_prefix && x$has_atb_tail, logical(1))

  row_log_schema_diag <- purrr::imap(completion_logs, function(x, nm) {
    cols <- names(x$row_log)
    list(
      name = nm,
      missing = setdiff(expected_row_cols, cols),
      duplicated = cols[duplicated(cols)]
    )
  })
  row_log_schema_ok <- vapply(
    row_log_schema_diag,
    function(x) length(x$missing) == 0L && length(x$duplicated) == 0L,
    logical(1)
  )

  group_log_schema_diag <- purrr::imap(completion_logs, function(x, nm) {
    cols <- names(x$group_log)
    list(
      name = nm,
      missing = setdiff(expected_group_cols, cols)
    )
  })
  group_log_schema_ok <- vapply(group_log_schema_diag, function(x) length(x$missing) == 0L, logical(1))

  list(
    ok = all(dataset_schema_ok) && all(row_log_schema_ok) && all(group_log_schema_ok),
    dataset_schema_ok = dataset_schema_ok,
    row_log_schema_ok = row_log_schema_ok,
    group_log_schema_ok = group_log_schema_ok,
    dataset_schema_diag = dataset_schema_diag,
    row_log_schema_diag = row_log_schema_diag,
    group_log_schema_diag = group_log_schema_diag
  )
}

format_completion_contract_errors <- function(contract) {
  dataset_fail <- names(contract$dataset_schema_ok)[!contract$dataset_schema_ok]
  row_fail <- names(contract$row_log_schema_ok)[!contract$row_log_schema_ok]
  group_fail <- names(contract$group_log_schema_ok)[!contract$group_log_schema_ok]

  dataset_msgs <- purrr::map_chr(dataset_fail, function(nm) {
    d <- contract$dataset_schema_diag[[nm]]
    issues <- character(0)
    if (!d$has_prefix) {
      issues <- c(issues, paste0("prefix mismatch [", paste(d$prefix_found, collapse = ", "), "]"))
    }
    if (!d$has_atb_tail) {
      issues <- c(issues, paste0("ATB tail mismatch [", paste(d$tail_found, collapse = ", "), "]"))
    }
    paste0(" - ", nm, ": ", paste(issues, collapse = "; "))
  })

  row_msgs <- purrr::map_chr(row_fail, function(nm) {
    d <- contract$row_log_schema_diag[[nm]]
    issues <- character(0)
    if (length(d$missing) > 0L) {
      issues <- c(issues, paste0("missing cols [", paste(d$missing, collapse = ", "), "]"))
    }
    if (length(d$duplicated) > 0L) {
      issues <- c(issues, paste0("duplicated cols [", paste(unique(d$duplicated), collapse = ", "), "]"))
    }
    paste0(" - ", nm, ": ", paste(issues, collapse = "; "))
  })

  group_msgs <- purrr::map_chr(group_fail, function(nm) {
    d <- contract$group_log_schema_diag[[nm]]
    paste0(" - ", nm, ": missing cols [", paste(d$missing, collapse = ", "), "]")
  })

  c(
    "Schema checks failed.",
    if (length(dataset_msgs) > 0L) "Completion dataset issues:" else character(0),
    dataset_msgs,
    if (length(row_msgs) > 0L) "Row log issues:" else character(0),
    row_msgs,
    if (length(group_msgs) > 0L) "Group log issues:" else character(0),
    group_msgs
  )
}

normalize_strategy_name <- function(x) {
  ifelse(x == "raw", "sir_wide_raw", x)
}

resolve_completion_fingerprint_cols <- function(df, atb_cols) {
  id_cols <- c(
    "PATID", "EVTID", "ELTID", "DATEPRELEV", "HEUREPRELEV",
    "souche_id", "naturepvt_norm", "bact_norm"
  )
  phenotype_cols <- intersect(
    c(
      "blse_status_row", "carbapenemase_status_row",
      "blse_status_final", "carbapenemase_status_final",
      "blse_flag", "carbapenemase_flag"
    ),
    names(df)
  )
  unique(c(id_cols, phenotype_cols, atb_cols))
}

resolve_completion_script_path <- function(script_name) {
  orchidee_resolve_script_path(
    script_name,
    what = paste0("completion cache dependency ", script_name)
  )
}

compute_completion_fingerprint <- function(df, atb_cols) {
  selected_cols <- resolve_completion_fingerprint_cols(df, atb_cols)
  missing_cols <- setdiff(selected_cols, names(df))
  if (length(missing_cols) > 0L) {
    stop(
      "Cannot compute completion fingerprint. Missing columns: ",
      paste(missing_cols, collapse = ", "),
      call. = FALSE
    )
  }

  payload <- df %>%
    dplyr::select(dplyr::all_of(selected_cols)) %>%
    dplyr::mutate(dplyr::across(dplyr::everything(), as.character))

  tmp_file <- tempfile(pattern = "completion_fingerprint_", fileext = ".rds")
  on.exit(unlink(tmp_file), add = TRUE)
  saveRDS(payload, tmp_file, version = 2)

  as.character(unname(tools::md5sum(tmp_file)))
}

build_completion_cache_meta <- function(raw_df, atb_cols) {
  script_paths <- c(
    completion_helpers = resolve_completion_script_path("completion_helpers.R"),
    spares_dedup = resolve_completion_script_path("spares_dedup.R"),
    spares_shared_primitives = resolve_completion_script_path("spares_shared_primitives.R"),
    phenotype_flag_helpers = resolve_completion_script_path("phenotype_flag_helpers.R")
  )
  script_hashes <- as.list(as.character(unname(tools::md5sum(script_paths))))
  names(script_hashes) <- names(script_paths)

  list(
    fingerprint = compute_completion_fingerprint(raw_df, atb_cols),
    n_rows = nrow(raw_df),
    n_distinct_eltid = dplyr::n_distinct(raw_df$ELTID),
    atb_cols = atb_cols,
    phenotype_cols = intersect(
      c(
        "blse_status_row", "carbapenemase_status_row",
        "blse_status_final", "carbapenemase_status_final",
        "blse_flag", "carbapenemase_flag"
      ),
      names(raw_df)
    ),
    script_hashes = script_hashes,
    created_at = format(Sys.time(), tz = "UTC", usetz = TRUE)
  )
}

count_non_na_overwrites <- function(raw_df, completed_df, atb_cols) {
  raw_mat <- as.matrix(raw_df[, atb_cols, drop = FALSE])
  new_mat <- as.matrix(completed_df[, atb_cols, drop = FALSE])
  changed_from_non_na <- !is.na(raw_mat) & (is.na(new_mat) | raw_mat != new_mat)
  sum(changed_from_non_na, na.rm = TRUE)
}

count_non_na_to_na_losses <- function(raw_df, completed_df, atb_cols) {
  raw_mat <- as.matrix(raw_df[, atb_cols, drop = FALSE])
  new_mat <- as.matrix(completed_df[, atb_cols, drop = FALSE])
  sum(!is.na(raw_mat) & is.na(new_mat), na.rm = TRUE)
}

count_new_zit_from_fill <- function(raw_df, completed_df, atb_cols) {
  raw_mat <- as.matrix(raw_df[, atb_cols, drop = FALSE])
  new_mat <- as.matrix(completed_df[, atb_cols, drop = FALSE])
  sum(is.na(raw_mat) & new_mat == "ZIT", na.rm = TRUE)
}

pct_rows_improved <- function(ds) {
  mean(ds$nb_resultats_post > ds$nb_resultats) * 100
}

