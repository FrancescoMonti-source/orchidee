operational_v2_gate_check <- function(name, ok, detail) {
  data.frame(
    name = as.character(name),
    ok = isTRUE(ok),
    detail = as.character(detail),
    stringsAsFactors = FALSE
  )
}

operational_v2_gate_read_rds <- function(path, label) {
  if (!file.exists(path)) {
    return(list(ok = FALSE, detail = paste0(label, " is missing.")))
  }

  value <- tryCatch(
    readRDS(path),
    error = function(error) error
  )
  if (inherits(value, "error")) {
    return(list(
      ok = FALSE,
      detail = paste0(label, " cannot be read: ", conditionMessage(value))
    ))
  }

  list(ok = TRUE, value = value)
}

operational_v2_gate_compare_rds <- function(
    name,
    baseline_path,
    candidate_path,
    normalize = identity) {
  baseline <- operational_v2_gate_read_rds(baseline_path, "Baseline artifact")
  candidate <- operational_v2_gate_read_rds(candidate_path, "Candidate artifact")

  if (!isTRUE(baseline$ok)) {
    return(operational_v2_gate_check(name, FALSE, baseline$detail))
  }
  if (!isTRUE(candidate$ok)) {
    return(operational_v2_gate_check(name, FALSE, candidate$detail))
  }

  baseline_value <- normalize(baseline$value)
  candidate_value <- normalize(candidate$value)
  same <- identical(baseline_value, candidate_value)
  operational_v2_gate_check(
    name,
    same,
    if (same) "Objects are identical." else "Objects differ."
  )
}

operational_v2_gate_normalize_sir_wide_meta <- function(value) {
  if (!is.list(value)) return(value)
  if ("created_at" %in% names(value)) value$created_at <- "<ignored>"
  value
}

operational_v2_gate_list_workbooks <- function(runtime_dir) {
  downloads_dir <- file.path(runtime_dir, "downloads")
  if (!dir.exists(downloads_dir)) return(character())

  paths <- list.files(
    downloads_dir,
    pattern = "\\.xlsx$",
    recursive = TRUE,
    full.names = FALSE,
    ignore.case = TRUE
  )
  sort(gsub("\\\\", "/", paths))
}

operational_v2_gate_read_sheet <- function(path, sheet) {
  suppressWarnings(openxlsx::read.xlsx(
    path,
    sheet = sheet,
    colNames = FALSE,
    skipEmptyRows = FALSE,
    skipEmptyCols = FALSE,
    check.names = FALSE,
    detectDates = FALSE,
    na.strings = character()
  ))
}

operational_v2_gate_compare_workbooks <- function(
    baseline_runtime_dir,
    candidate_runtime_dir) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    stop("Package 'openxlsx' is required for the v2 regression gate.", call. = FALSE)
  }

  baseline_files <- operational_v2_gate_list_workbooks(baseline_runtime_dir)
  candidate_files <- operational_v2_gate_list_workbooks(candidate_runtime_dir)
  same_files <- identical(baseline_files, candidate_files)
  set_detail <- if (same_files && length(baseline_files) > 0L) {
    paste0(length(baseline_files), " workbook(s) found in both runtimes.")
  } else if (same_files) {
    "No XLSX workbook found in either runtime."
  } else {
    paste0(
      "Workbook sets differ (baseline: ", length(baseline_files),
      "; candidate: ", length(candidate_files), ")."
    )
  }
  set_check <- operational_v2_gate_check(
    "report_workbook_set",
    same_files && length(baseline_files) > 0L,
    set_detail
  )

  if (!same_files || length(baseline_files) == 0L) {
    cell_check <- operational_v2_gate_check(
      "report_workbook_cells",
      FALSE,
      "Cell comparison was not run because the workbook set is invalid."
    )
    return(rbind(set_check, cell_check))
  }

  baseline_downloads <- file.path(baseline_runtime_dir, "downloads")
  candidate_downloads <- file.path(candidate_runtime_dir, "downloads")
  mismatch <- NULL

  for (relative_path in baseline_files) {
    baseline_path <- file.path(baseline_downloads, relative_path)
    candidate_path <- file.path(candidate_downloads, relative_path)
    baseline_sheets <- openxlsx::getSheetNames(baseline_path)
    candidate_sheets <- openxlsx::getSheetNames(candidate_path)

    if (!identical(baseline_sheets, candidate_sheets)) {
      mismatch <- paste0(relative_path, ": sheet sets differ.")
      break
    }

    for (sheet in baseline_sheets) {
      baseline_sheet <- operational_v2_gate_read_sheet(baseline_path, sheet)
      candidate_sheet <- operational_v2_gate_read_sheet(candidate_path, sheet)
      if (!identical(baseline_sheet, candidate_sheet)) {
        mismatch <- paste0(
          relative_path, ": cell values differ in sheet '", sheet, "'."
        )
        break
      }
    }
    if (!is.null(mismatch)) break
  }

  cell_check <- operational_v2_gate_check(
    "report_workbook_cells",
    is.null(mismatch),
    if (is.null(mismatch)) {
      "All workbook sheets are cell-identical."
    } else {
      mismatch
    }
  )
  rbind(set_check, cell_check)
}

compare_operational_v2_gate <- function(
    baseline_bundle_dir,
    baseline_runtime_dir,
    candidate_bundle_dir,
    candidate_runtime_dir) {
  directories <- c(
    baseline_bundle_dir = baseline_bundle_dir,
    baseline_runtime_dir = baseline_runtime_dir,
    candidate_bundle_dir = candidate_bundle_dir,
    candidate_runtime_dir = candidate_runtime_dir
  )
  missing_directories <- names(directories)[!dir.exists(directories)]
  if (length(missing_directories) > 0L) {
    stop(
      "Missing gate directory/directories: ",
      paste(missing_directories, collapse = ", "),
      call. = FALSE
    )
  }
  normalized_directories <- vapply(
    directories,
    normalizePath,
    character(1),
    winslash = "/",
    mustWork = TRUE
  )
  if (identical(
    normalized_directories[["baseline_bundle_dir"]],
    normalized_directories[["candidate_bundle_dir"]]
  )) {
    stop("Baseline and candidate bundle directories must differ.", call. = FALSE)
  }
  if (identical(
    normalized_directories[["baseline_runtime_dir"]],
    normalized_directories[["candidate_runtime_dir"]]
  )) {
    stop("Baseline and candidate runtime directories must differ.", call. = FALSE)
  }

  exact_bundle_files <- c(
    "sir_wide.rds",
    "sample_scope_reference.rds",
    "denominator_bundle.rds"
  )
  checks <- lapply(exact_bundle_files, function(file_name) {
    operational_v2_gate_compare_rds(
      paste0("bundle/", file_name),
      file.path(baseline_bundle_dir, file_name),
      file.path(candidate_bundle_dir, file_name)
    )
  })
  checks[[length(checks) + 1L]] <- operational_v2_gate_compare_rds(
    "bundle/sir_wide_meta.rds",
    file.path(baseline_bundle_dir, "sir_wide_meta.rds"),
    file.path(candidate_bundle_dir, "sir_wide_meta.rds"),
    normalize = operational_v2_gate_normalize_sir_wide_meta
  )

  for (file_name in c("dedup_results", "ratb_raw_runtime_audit")) {
    checks[[length(checks) + 1L]] <- operational_v2_gate_compare_rds(
      paste0("runtime/cache/", file_name),
      file.path(baseline_runtime_dir, "cache", file_name),
      file.path(candidate_runtime_dir, "cache", file_name)
    )
  }
  checks[[length(checks) + 1L]] <- operational_v2_gate_compare_workbooks(
    baseline_runtime_dir,
    candidate_runtime_dir
  )

  checks <- do.call(rbind, checks)
  rownames(checks) <- NULL
  list(
    ok = all(checks$ok),
    checks = checks
  )
}

print_operational_v2_gate_report <- function(report) {
  stopifnot(is.list(report), is.data.frame(report$checks))
  cat(if (isTRUE(report$ok)) {
    "PASS: operational v2 regression gate.\n"
  } else {
    "FAIL: operational v2 regression gate.\n"
  })
  for (index in seq_len(nrow(report$checks))) {
    check <- report$checks[index, , drop = FALSE]
    cat(
      if (isTRUE(check$ok)) "[PASS] " else "[FAIL] ",
      check$name,
      ": ",
      check$detail,
      "\n",
      sep = ""
    )
  }
  invisible(report)
}
