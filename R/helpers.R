`%||%` <- function(x, y) if (!is.null(x)) x else y

.edsan_is_limit_error <- function(err) {
  if (is.null(err)) return(FALSE)
  err <- paste(err, collapse = " ")
  stringr::str_detect(
    stringr::str_to_lower(err),
    "(too many|limit|quota|max results|max rows|allowed size limit exceeded)"
  )
}

.pmsi_has_time <- function(x) {
  x <- as.character(x %||% "")
  stringr::str_detect(x, "\\d{2}:\\d{2}")
}

.pmsi_parse_datetime <- function(x, tz = "Europe/Paris") {
  # Robust parsing for both date-only and datetime strings.
  # Returns POSIXct (NA where parsing fails).
  if (is.null(x)) return(x)
  if (inherits(x, "POSIXt")) return(x)
  x <- as.character(x)
  lubridate::parse_date_time(
    x,
    orders = c(
      "Y-m-d H:M:S", "Y-m-d H:M", "Y-m-d",
      "d/m/Y H:M:S", "d/m/Y H:M", "d/m/Y",
      "Ymd HMS", "Ymd HM", "Ymd"
    ),
    quiet = TRUE,
    tz = tz
  )
}

.pmsi_time_hms <- function(dt, raw) {
  # Return hms time if raw had an explicit time component, else NA.
  out <- rep(NA_character_, length(dt))
  ok <- !is.na(dt) & .pmsi_has_time(raw)
  out[ok] <- format(dt[ok], "%H:%M:%S")
  hms::as_hms(out)
}

resolve_existing_path <- function(candidates, what = "file", must_exist = TRUE) {
  stopifnot(length(candidates) > 0L)
  existing <- candidates[file.exists(candidates)]
  if (length(existing) == 0L) {
    if (isTRUE(must_exist)) {
      stop(
        "Missing ", what, ". Checked: ",
        paste(candidates, collapse = ", "),
        call. = FALSE
      )
    }
    return(NA_character_)
  }
  normalizePath(existing[[1]], winslash = "/", mustWork = TRUE)
}

.file_info_signature <- function(path) {
  info <- file.info(path)
  if (nrow(info) == 0L || is.na(info$size[[1]]) || is.na(info$mtime[[1]])) {
    stop("Cannot read file metadata for: ", path, call. = FALSE)
  }
  list(
    path = normalizePath(path, winslash = "/", mustWork = TRUE),
    size = as.numeric(info$size[[1]]),
    mtime_utc = format(as.POSIXct(info$mtime[[1]], tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ")
  )
}

compute_upstream_signature <- function(raw_input_paths = character(), hashed_paths = character()) {
  raw_input_paths <- sort(unique(as.character(raw_input_paths)))
  hashed_paths <- sort(unique(as.character(hashed_paths)))

  if (length(raw_input_paths) > 0L && any(!file.exists(raw_input_paths))) {
    missing <- raw_input_paths[!file.exists(raw_input_paths)]
    stop("Missing raw input path(s): ", paste(missing, collapse = ", "), call. = FALSE)
  }
  if (length(hashed_paths) > 0L && any(!file.exists(hashed_paths))) {
    missing <- hashed_paths[!file.exists(hashed_paths)]
    stop("Missing hashed path(s): ", paste(missing, collapse = ", "), call. = FALSE)
  }

  raw_inputs <- purrr::set_names(
    lapply(raw_input_paths, .file_info_signature),
    raw_input_paths
  )
  hashed_files <- purrr::set_names(
    as.list(as.character(unname(tools::md5sum(hashed_paths)))),
    hashed_paths
  )

  list(
    raw_inputs = raw_inputs,
    hashed_files = hashed_files
  )
}

validate_sir_wide_artifact <- function(meta, current_signature) {
  reasons <- character(0)
  required_meta <- c(
    "artifact_version", "created_at", "sir_wide_n_rows", "sir_wide_n_eltid",
    "atb_cols", "filtre_atb", "upstream_signature"
  )

  if (!is.list(meta)) {
    reasons <- c(reasons, "metadata object is not a list")
    return(list(ok = FALSE, reasons = reasons))
  }

  missing_meta <- setdiff(required_meta, names(meta))
  if (length(missing_meta) > 0L) {
    reasons <- c(reasons, paste0("metadata missing fields: ", paste(missing_meta, collapse = ", ")))
  }

  if (!is.list(current_signature)) {
    reasons <- c(reasons, "current signature is not a list")
    return(list(ok = FALSE, reasons = reasons))
  }

  sig_required <- c("raw_inputs", "hashed_files")
  if (!all(sig_required %in% names(current_signature))) {
    reasons <- c(reasons, "current signature missing raw_inputs and/or hashed_files")
    return(list(ok = FALSE, reasons = reasons))
  }

  meta_sig <- meta$upstream_signature
  if (!is.list(meta_sig) || !all(sig_required %in% names(meta_sig))) {
    reasons <- c(reasons, "metadata upstream_signature missing raw_inputs and/or hashed_files")
    return(list(ok = FALSE, reasons = reasons))
  }

  meta_raw_names <- names(meta_sig$raw_inputs %||% list())
  cur_raw_names <- names(current_signature$raw_inputs %||% list())
  meta_hash_names <- names(meta_sig$hashed_files %||% list())
  cur_hash_names <- names(current_signature$hashed_files %||% list())

  if (!identical(meta_raw_names, cur_raw_names)) {
    reasons <- c(reasons, "raw input file set differs from artifact metadata")
  }
  if (!identical(meta_hash_names, cur_hash_names)) {
    reasons <- c(reasons, "hashed file set differs from artifact metadata")
  }

  raw_names <- intersect(meta_raw_names, cur_raw_names)
  for (nm in raw_names) {
    meta_entry <- meta_sig$raw_inputs[[nm]]
    cur_entry <- current_signature$raw_inputs[[nm]]
    if (!identical(meta_entry$size, cur_entry$size)) {
      reasons <- c(reasons, paste0("raw input size changed: ", nm))
    }
    if (!identical(meta_entry$mtime_utc, cur_entry$mtime_utc)) {
      reasons <- c(reasons, paste0("raw input mtime changed: ", nm))
    }
  }

  hash_names <- intersect(meta_hash_names, cur_hash_names)
  for (nm in hash_names) {
    if (!identical(meta_sig$hashed_files[[nm]], current_signature$hashed_files[[nm]])) {
      reasons <- c(reasons, paste0("hashed file content changed: ", nm))
    }
  }

  list(
    ok = length(reasons) == 0L,
    reasons = unique(reasons)
  )
}
