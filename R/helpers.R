`%||%` <- function(x, y) if (!is.null(x)) x else y

# Deterministic accent stripper vendored from the former `fmckage::rm_accent`
# dependency, so the project no longer needs that non-CRAN package. Uses
# `chartr` character maps, which are platform-independent (unlike a
# locale-sensitive `iconv(..., "ASCII//TRANSLIT")`). Call sites in
# normalisation_atb.R and phenotype_flag_helpers.R resolve to this through an
# `exists("rm_accent")` guard.
rm_accent <- function(str, pattern = "all") {
  if (!is.character(str)) {
    str <- as.character(str)
  }

  pattern <- unique(pattern)

  if (any(pattern == "Ç")) {
    pattern[pattern == "Ç"] <- "ç"
  }

  symbols <- c(
    acute = "áéíóúÁÉÍÓÚýÝ",
    grave = "àèìòùÀÈÌÒÙ",
    circunflex = "âêîôûÂÊÎÔÛ",
    tilde = "ãõÃÕñÑ",
    umlaut = "äëïöüÄËÏÖÜÿ",
    cedil = "çÇ"
  )

  nudeSymbols <- c(
    acute = "aeiouAEIOUyY",
    grave = "aeiouAEIOU",
    circunflex = "aeiouAEIOU",
    tilde = "aoAOnN",
    umlaut = "aeiouAEIOUy",
    cedil = "cC"
  )

  accentTypes <- c("´", "`", "^", "~", "¨", "ç")

  if (any(c("all", "al", "a", "todos", "t", "to", "tod", "todo") %in% pattern)) {
    return(chartr(paste(symbols, collapse = ""), paste(nudeSymbols, collapse = ""), str))
  }

  for (i in which(accentTypes %in% pattern)) {
    str <- chartr(symbols[i], nudeSymbols[i], str)
  }

  return(str)
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

resolve_dictionary_path <- function(
    filename,
    what,
    dictionaries_dir = "dictionaries",
    data_dir = "data"
  ) {
  resolve_existing_path(
    c(
      file.path(dictionaries_dir, filename),
      filename,
      file.path(data_dir, filename)
    ),
    what = what
  )
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

compute_sir_wide_artifact_signature <- function(
    sir_wide_path,
    sir_wide_meta_path,
    meta
  ) {
  list(
    canonical_artifacts = list(
      sir_wide = .file_info_signature(sir_wide_path),
      sir_wide_meta = .file_info_signature(sir_wide_meta_path)
    ),
    metadata = list(
      artifact_version = meta$artifact_version %||% NA,
      created_at = meta$created_at %||% NA,
      sir_wide_n_rows = meta$sir_wide_n_rows %||% NA,
      sir_wide_n_eltid = meta$sir_wide_n_eltid %||% NA,
      atb_cols = meta$atb_cols %||% character(),
      supported_atb_cols = meta$supported_atb_cols %||% character(),
      phenotype_status_cols = meta$phenotype_status_cols %||% character(),
      phenotype_flag_cols = meta$phenotype_flag_cols %||% character()
    )
  )
}

validate_loaded_sir_wide_artifact <- function(sir_wide, meta) {
  reasons <- character(0)
  required_meta <- c(
    "artifact_version",
    "created_at",
    "sir_wide_n_rows",
    "sir_wide_n_eltid",
    "atb_cols",
    "filtre_atb"
  )

  if (!is.data.frame(sir_wide)) {
    reasons <- c(reasons, "sir_wide object is not a data frame")
  }

  if (!is.list(meta)) {
    reasons <- c(reasons, "metadata object is not a list")
    return(list(ok = FALSE, reasons = unique(reasons)))
  }

  missing_meta <- setdiff(required_meta, names(meta))
  if (length(missing_meta) > 0L) {
    reasons <- c(reasons, paste0("metadata missing fields: ", paste(missing_meta, collapse = ", ")))
  }

  if (is.data.frame(sir_wide)) {
    if (!is.null(meta$sir_wide_n_rows) && !identical(as.integer(meta$sir_wide_n_rows), as.integer(nrow(sir_wide)))) {
      reasons <- c(reasons, "sir_wide row count differs from artifact metadata")
    }
    if (!is.null(meta$sir_wide_n_eltid)) {
      if (!"ELTID" %in% names(sir_wide)) {
        reasons <- c(reasons, "sir_wide is missing ELTID")
      } else if (!identical(
        as.integer(meta$sir_wide_n_eltid),
        as.integer(dplyr::n_distinct(sir_wide$ELTID))
      )) {
        reasons <- c(reasons, "sir_wide ELTID count differs from artifact metadata")
      }
    }

    for (field in c("atb_cols", "supported_atb_cols", "phenotype_status_cols", "phenotype_flag_cols")) {
      cols <- meta[[field]]
      if (is.null(cols)) next
      missing_cols <- setdiff(as.character(cols), names(sir_wide))
      if (length(missing_cols) > 0L) {
        reasons <- c(
          reasons,
          paste0(field, " columns missing from sir_wide: ", paste(missing_cols, collapse = ", "))
        )
      }
    }
  }

  list(
    ok = length(reasons) == 0L,
    reasons = unique(reasons)
  )
}
