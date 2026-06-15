# Shared SPARES/completion helper primitives.
# These functions are intentionally internal (prefixed) and reused by:
# - spares_dedup.R
# - completion_helpers.R

#' Normalize non-informative codes to NA
#'
#' Converts all values in `zit_values` to `NA_character_`.
#'
#' @param x Character-like vector of ATB values.
#' @param zit_values Values treated as non-informative.
#' @return Character vector with non-informative values replaced by `NA`.
.spares_normalize_noninformative <- function(x, zit_values = "ZIT") {
  y <- as.character(x)
  for (z in zit_values) y[y == z] <- NA_character_
  y
}

#' Detect pairwise major S<->R conflict
#'
#' After normalizing non-informative values, returns `TRUE` if two
#' same-length ATB vectors contain at least one `S<->R` discordance.
#'
#' @param a Character vector of ATB values for one document.
#' @param b Character vector of ATB values for one document.
#' @param zit_values Values treated as non-informative.
#' @return Logical scalar.
.spares_sr_conflict_pair <- function(a, b, zit_values = "ZIT") {
  stopifnot(length(a) == length(b))
  aa <- .spares_normalize_noninformative(a, zit_values = zit_values)
  bb <- .spares_normalize_noninformative(b, zit_values = zit_values)
  any((aa == "S" & bb == "R") | (aa == "R" & bb == "S"), na.rm = TRUE)
}

#' Build pairwise discordance matrix for one group
#'
#' Computes an `n x n` logical matrix where entry `(i, j)` is `TRUE`
#' when rows `i` and `j` have at least one major `S<->R` conflict on
#' overlapping informative ATB values.
#'
#' @param g Data frame containing one episode/group.
#' @param atb_cols Character vector of ATB columns.
#' @param zit_values Values treated as non-informative.
#' @return Logical matrix (`nrow(g)` by `nrow(g)`).
.spares_discord_matrix <- function(g, atb_cols, zit_values = "ZIT") {
  m <- nrow(g)
  if (m <= 1L) {
    return(matrix(FALSE, nrow = m, ncol = m))
  }

  # Build X = ATB matrix, treat ZIT as NA (non-informative).
  X <- as.data.frame(lapply(g[, atb_cols, drop = FALSE], as.character), stringsAsFactors = FALSE)
  X[] <- lapply(X, .spares_normalize_noninformative, zit_values = zit_values)

  # Logical matrices without NAs.
  Rmat <- as.matrix((!is.na(X)) & (X == "R"))
  Smat <- as.matrix((!is.na(X)) & (X == "S"))

  # discordant(i,j) if any ATB with R_i & S_j OR S_i & R_j.
  D <- (Rmat %*% t(Smat)) + (Smat %*% t(Rmat))
  diag(D) <- 0
  D > 0
}

#' Normalize time strings into sortable keys
#'
#' Attempts to parse time-like inputs (`H:MM`, `HH:MM:SS`,
#' or strings containing a time token). Parsed values are normalized to
#' `HH:MM:SS`; unparseable non-missing values are kept as-is.
#'
#' @param x Character-like time vector.
#' @return Character vector suitable as deterministic time sort key.
.spares_time_sort_key <- function(x) {
  x_chr <- trimws(as.character(x))
  x_chr[x_chr %in% c("", "NA", "N/A")] <- NA_character_
  out <- rep(NA_character_, length(x_chr))

  idx <- !is.na(x_chr)
  if (!any(idx)) return(out)

  token <- x_chr[idx]
  token <- sub(".*?(\\d{1,2}:\\d{2}(?::\\d{2})?).*", "\\1", token, perl = TRUE)
  has_token <- grepl("^\\d{1,2}:\\d{2}(?::\\d{2})?$", token)
  token[!has_token] <- x_chr[idx][!has_token]

  parsed_hms <- strptime(token, format = "%H:%M:%S", tz = "UTC")
  parsed_hm <- strptime(token, format = "%H:%M", tz = "UTC")

  norm <- rep(NA_character_, length(token))
  ok_hms <- !is.na(parsed_hms)
  norm[ok_hms] <- format(parsed_hms[ok_hms], "%H:%M:%S")
  ok_hm <- is.na(norm) & !is.na(parsed_hm)
  norm[ok_hm] <- format(parsed_hm[ok_hm], "%H:%M:%S")
  norm[is.na(norm)] <- token[is.na(norm)]

  out[idx] <- norm
  out
}

#' Derive stable per-EVT ordering key, with support for explicit evt_order
#'
#' @param g Group data frame.
#' @param date_sort Date sort key.
#' @param time_sort Time sort key.
#' @param document_sort Document id sort key.
#' @param row_sort Stable row-id tie-breaker.
#' @return Numeric vector (length nrow(g)).
.spares_derive_evt_order_sort <- function(g, date_sort, time_sort, document_sort, row_sort) {
  n <- nrow(g)
  out <- rep(NA_real_, n)

  if ("evt_order" %in% names(g)) {
    out <- suppressWarnings(as.numeric(as.character(g[["evt_order"]])))
    if (!any(is.na(out))) return(out)
  }

  if (!"EVTID" %in% names(g)) return(out)

  evtid <- as.character(g[["EVTID"]])
  valid_evt <- which(!is.na(evtid) & evtid != "")
  if (length(valid_evt) == 0L) return(out)

  evt_levels <- unique(evtid[valid_evt])
  rep_idx <- integer(length(evt_levels))

  for (k in seq_along(evt_levels)) {
    idx <- valid_evt[evtid[valid_evt] == evt_levels[k]]
    idx_ord <- idx[order(
      date_sort[idx],
      time_sort[idx],
      document_sort[idx],
      row_sort[idx],
      na.last = TRUE
    )]
    rep_idx[k] <- idx_ord[1L]
  }

  evt_ord <- order(
    date_sort[rep_idx],
    time_sort[rep_idx],
    document_sort[rep_idx],
    row_sort[rep_idx],
    evt_levels,
    na.last = TRUE
  )

  evt_rank <- seq_along(evt_levels)
  names(evt_rank) <- evt_levels[evt_ord]
  derived <- unname(evt_rank[evtid])
  out[is.na(out)] <- derived[is.na(out)]
  out
}

#' Derive stable per-ELT ordering key (within EVT), with support for explicit elt_order
#'
#' @param g Group data frame.
#' @param evt_order_sort Numeric EVT ordering key.
#' @param date_sort Date sort key.
#' @param time_sort Time sort key.
#' @param document_sort Document id sort key.
#' @param row_sort Stable row-id tie-breaker.
#' @return Numeric vector (length nrow(g)).
.spares_derive_elt_order_sort <- function(g, evt_order_sort, date_sort, time_sort, document_sort, row_sort) {
  n <- nrow(g)
  out <- rep(NA_real_, n)

  if ("elt_order" %in% names(g)) {
    out <- suppressWarnings(as.numeric(as.character(g[["elt_order"]])))
    if (!any(is.na(out))) return(out)
  }

  if (!"ELTID" %in% names(g)) return(out)

  evtid <- if ("EVTID" %in% names(g)) as.character(g[["EVTID"]]) else rep("", n)
  evtid[is.na(evtid)] <- ""
  eltid <- as.character(g[["ELTID"]])

  valid_elt <- which(!is.na(eltid) & eltid != "")
  if (length(valid_elt) == 0L) return(out)

  key <- paste(evtid[valid_elt], eltid[valid_elt], sep = "\r")
  key_levels <- unique(key)
  rep_idx <- integer(length(key_levels))
  key_evt <- character(length(key_levels))
  key_elt <- character(length(key_levels))

  for (k in seq_along(key_levels)) {
    idx <- valid_elt[key == key_levels[k]]
    idx_ord <- idx[order(
      date_sort[idx],
      time_sort[idx],
      row_sort[idx],
      na.last = TRUE
    )]
    rep_idx[k] <- idx_ord[1L]
    key_evt[k] <- evtid[rep_idx[k]]
    key_elt[k] <- eltid[rep_idx[k]]
  }

  key_tbl <- data.frame(
    key = key_levels,
    evt = key_evt,
    eltid = key_elt,
    evt_order = evt_order_sort[rep_idx],
    date_sort = date_sort[rep_idx],
    time_sort = time_sort[rep_idx],
    row_sort = row_sort[rep_idx],
    stringsAsFactors = FALSE
  )
  key_tbl <- key_tbl[order(
    key_tbl$evt_order,
    key_tbl$date_sort,
    key_tbl$time_sort,
    key_tbl$eltid,
    key_tbl$row_sort,
    na.last = TRUE
  ), , drop = FALSE]

  evt_block <- paste(key_tbl$evt_order, key_tbl$evt, sep = "\r")
  key_tbl$elt_rank <- ave(seq_len(nrow(key_tbl)), evt_block, FUN = seq_along)

  elt_rank <- key_tbl$elt_rank
  names(elt_rank) <- key_tbl$key
  derived <- rep(NA_real_, n)
  derived[valid_elt] <- unname(elt_rank[paste(evtid[valid_elt], eltid[valid_elt], sep = "\r")])
  out[is.na(out)] <- derived[is.na(out)]
  out
}
