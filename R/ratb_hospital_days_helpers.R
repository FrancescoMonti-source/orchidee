## RATB hospitalization scope and hospital-days helpers
##
## These helpers keep three concerns explicit and separate from the main notebook:
## 1. derive the downstream RATB microbiology analysis scope from each sample's
##    `SEJUF` and the CONSORES TA/DE perimeter
## 2. build a generic validation-first `hospital_days` layer for future
##    incidence-density indicators, without yet locking the final denominator
##    convention
## 3. build a PMSI-based ORCHIDEE incidence denominator using the same TA/DE
##    perimeter independently from microbiology rows

ratb_normalize_pmsi_status <- function(x) {
  x <- toupper(trimws(as.character(x)))
  x[!nzchar(x)] <- NA_character_
  x
}

ratb_resolve_posix_tz <- function(x) {
  tz <- attr(x, "tzone")
  if (length(tz) == 0L || is.na(tz[[1]]) || !nzchar(tz[[1]])) {
    return("Europe/Paris")
  }
  tz[[1]]
}

ratb_safe_min_datetime <- function(x) {
  tz <- ratb_resolve_posix_tz(x)
  if (length(x) == 0L || all(is.na(x))) {
    return(as.POSIXct(NA_real_, origin = "1970-01-01", tz = tz))
  }
  min(x, na.rm = TRUE)
}

ratb_safe_max_datetime <- function(x) {
  tz <- ratb_resolve_posix_tz(x)
  if (length(x) == 0L || all(is.na(x))) {
    return(as.POSIXct(NA_real_, origin = "1970-01-01", tz = tz))
  }
  max(x, na.rm = TRUE)
}

ratb_trim_or_na_local <- function(x) {
  x <- trimws(as.character(x))
  x[!nzchar(x)] <- NA_character_
  x
}

ratb_collapse_unique <- function(x) {
  x <- ratb_trim_or_na_local(x)
  vals <- sort(unique(x[!is.na(x)]))
  if (length(vals) == 0L) {
    return(NA_character_)
  }
  paste(vals, collapse = "|")
}

ratb_detect_delimiter_local <- function(path) {
  header <- readLines(path, n = 1L, warn = FALSE, encoding = "UTF-8")
  if (length(header) == 0L) {
    stop("Empty delimited file: ", path, call. = FALSE)
  }

  header <- sub("^\ufeff", "", header[[1]], useBytes = TRUE)
  semicolon_pos <- gregexpr(";", header, fixed = TRUE)[[1]]
  comma_pos <- gregexpr(",", header, fixed = TRUE)[[1]]
  n_semicolon <- sum(semicolon_pos > 0L)
  n_comma <- sum(comma_pos > 0L)
  if (n_semicolon > n_comma) ";" else ","
}

ratb_read_semicolon_reference <- function(path, col_names) {
  stopifnot(length(col_names) >= 2L)

  utils::read.table(
    file = path,
    header = FALSE,
    sep = ";",
    quote = "\"",
    comment.char = "",
    stringsAsFactors = FALSE,
    check.names = FALSE,
    fill = TRUE,
    col.names = col_names,
    fileEncoding = "UTF-8"
  ) %>%
    tibble::as_tibble() %>%
    mutate(across(everything(), ratb_trim_or_na_local))
}

load_ratb_unit_references <- function(ref_dir = "ref") {
  uf_path <- file.path(ref_dir, "ref_uf.txt")
  um_path <- file.path(ref_dir, "ref_um.txt")
  uf2um_path <- file.path(ref_dir, "ref_uf2um.txt")

  required <- c(uf_path, um_path, uf2um_path)
  if (!all(file.exists(required))) {
    missing <- required[!file.exists(required)]
    stop(
      "Missing unit reference files: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }

  uf_ref <- ratb_read_semicolon_reference(uf_path, c("SEJUF", "uf_label")) %>%
    distinct(SEJUF, .keep_all = TRUE)
  um_ref <- ratb_read_semicolon_reference(um_path, c("SEJUM", "um_label")) %>%
    distinct(SEJUM, .keep_all = TRUE)
  uf2um_ref <- ratb_read_semicolon_reference(uf2um_path, c("SEJUF", "SEJUM_from_ref")) %>%
    distinct(SEJUF, .keep_all = TRUE)

  list(
    uf_ref = uf_ref,
    um_ref = um_ref,
    uf2um_ref = uf2um_ref
  )
}

ratb_normalize_code_de <- function(x) {
  x <- ratb_trim_or_na_local(x)
  out <- x
  numeric_code <- !is.na(out) & grepl("^[0-9]+$", out)
  out[numeric_code] <- sub("^0+", "", out[numeric_code])
  out[numeric_code & !nzchar(out)] <- "0"
  out
}

ratb_normalize_code_ta <- function(x) {
  x <- ratb_trim_or_na_local(x)
  out <- x
  numeric_code <- !is.na(out) & grepl("^[0-9]+$", out)
  out[numeric_code] <- sprintf("%02d", as.integer(out[numeric_code]))
  out
}

ratb_read_delimited_reference <- function(path) {
  if (!file.exists(path)) {
    stop("Missing reference file: ", path, call. = FALSE)
  }

  delimiter <- ratb_detect_delimiter_local(path)
  out <- utils::read.table(
    file = path,
    header = TRUE,
    sep = delimiter,
    quote = "\"",
    comment.char = "",
    stringsAsFactors = FALSE,
    check.names = FALSE,
    fill = TRUE,
    fileEncoding = "UTF-8"
  ) %>%
    tibble::as_tibble()

  if (length(names(out)) > 0L) {
    names(out)[1] <- sub("^\ufeff", "", names(out)[1], useBytes = TRUE)
  }

  out %>%
    mutate(across(everything(), ratb_trim_or_na_local))
}

ratb_included_ta_de_domains <- function() {
  c(
    "MÉDECINE",
    "URGENCES",
    "CHIRURGIE",
    "RÉANIMATION",
    "PÉDIATRIE",
    "GYNÉCOLOGIE-OBSTÉTRIQUE",
    "SOINS MÉDICAUX ET DE RÉADAPTATION",
    "SOINS DE LONGUE DURÉE",
    "PSYCHIATRIE",
    "ÉTABLISSEMENT D'HÉBERGEMENT POUR PERSONNES ÂGÉES DÉPENDANTES"
  )
}

build_ratb_ta_de_policy_table <- function() {
  tibble(
    policy_dimension = c(
      "eligible_ta_codes",
      "eligible_de_domains",
      "microbiology_scope_rule",
      "incidence_denominator_rule",
      "bloc_policy",
      "unmapped_de_policy",
      "pmsi_status_policy"
    ),
    included_values = c(
      "03|20",
      paste(ratb_included_ta_de_domains(), collapse = "|"),
      "keep microbiology row when sample SEJUF is eligible by TA and DE",
      "count all PMSI episode nights when any UF is eligible by TA and DE",
      "TA=08 is not an eligibility trigger",
      "TA=03/20 with missing or unmapped CODE_DE is review/drop",
      "PMSISTATUT is audit context only, not an inclusion gate"
    )
  )
}

load_ratb_consores_ta_de_reference <- function(
    structure_path,
    codes_ta_path,
    codes_de_path
  ) {
  required <- c(structure_path, codes_ta_path, codes_de_path)
  if (!all(file.exists(required))) {
    missing <- required[!file.exists(required)]
    stop(
      "Missing CONSORES TA/DE reference files: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  if (!requireNamespace("readxl", quietly = TRUE)) {
    stop("Package 'readxl' is required to read the CONSORES structure workbook.", call. = FALSE)
  }

  structure <- readxl::read_excel(
    structure_path,
    sheet = 1,
    .name_repair = "minimal"
  ) %>%
    tibble::as_tibble()
  structure[] <- lapply(structure, ratb_trim_or_na_local)

  required_structure_cols <- c(
    "UF",
    "Libellé UF (libellé de référence)",
    "CODE_TA",
    "Libellé type activité - Uf",
    "CODE_DE",
    "Nom discipline - Ds",
    "Type prise en charge"
  )
  missing_structure_cols <- setdiff(required_structure_cols, names(structure))
  if (length(missing_structure_cols) > 0L) {
    stop(
      "CONSORES structure workbook is missing required columns: ",
      paste(missing_structure_cols, collapse = ", "),
      call. = FALSE
    )
  }

  codes_ta <- ratb_read_delimited_reference(codes_ta_path)
  codes_de <- ratb_read_delimited_reference(codes_de_path)
  missing_ta_cols <- setdiff(c("CODE_TA", "LIBELLE_TA"), names(codes_ta))
  missing_de_cols <- setdiff(c("DOMAINE", "CODE_DE", "LIBELLE_DE"), names(codes_de))
  if (length(missing_ta_cols) > 0L) {
    stop(
      "CONSORES TA code reference is missing required columns: ",
      paste(missing_ta_cols, collapse = ", "),
      call. = FALSE
    )
  }
  if (length(missing_de_cols) > 0L) {
    stop(
      "CONSORES DE code reference is missing required columns: ",
      paste(missing_de_cols, collapse = ", "),
      call. = FALSE
    )
  }

  codes_ta <- codes_ta %>%
    mutate(CODE_TA = ratb_normalize_code_ta(CODE_TA)) %>%
    distinct(CODE_TA, .keep_all = TRUE)
  codes_de <- codes_de %>%
    mutate(CODE_DE_norm = ratb_normalize_code_de(CODE_DE)) %>%
    group_by(CODE_DE_norm) %>%
    summarise(
      de_domain_ref = paste(sort(unique(DOMAINE[!is.na(DOMAINE)])), collapse = "|"),
      de_label_ref = paste(sort(unique(LIBELLE_DE[!is.na(LIBELLE_DE)])), collapse = "|"),
      .groups = "drop"
    ) %>%
    mutate(
      de_domain_ref = if_else(nzchar(de_domain_ref), de_domain_ref, NA_character_),
      de_label_ref = if_else(nzchar(de_label_ref), de_label_ref, NA_character_)
    )

  included_domains <- ratb_included_ta_de_domains()

  structure %>%
    transmute(
      SEJUF = UF,
      consores_uf_label = .data[["Libellé UF (libellé de référence)"]],
      consores_uf_short_label = .data[["Libellé court UF"]],
      CODE_TA = ratb_normalize_code_ta(CODE_TA),
      consores_ta_label = .data[["Libellé type activité - Uf"]],
      CODE_DE = CODE_DE,
      CODE_DE_norm = ratb_normalize_code_de(CODE_DE),
      consores_de_label = .data[["Nom discipline - Ds"]],
      consores_care_type = .data[["Type prise en charge"]]
    ) %>%
    left_join(
      codes_ta %>%
        rename(consores_ta_label_ref = LIBELLE_TA),
      by = "CODE_TA"
    ) %>%
    left_join(codes_de, by = "CODE_DE_norm") %>%
    mutate(
      uf_ta_eligible = CODE_TA %in% c("03", "20"),
      uf_de_mapped = !is.na(de_domain_ref),
      uf_de_eligible = de_domain_ref %in% included_domains,
      uf_is_eligible_by_ta_de = uf_ta_eligible & uf_de_eligible,
      uf_ta_de_status = case_when(
        uf_is_eligible_by_ta_de ~ "eligible_ta_de",
        is.na(CODE_TA) ~ "review_unmapped_uf",
        uf_ta_eligible & !uf_de_mapped ~ "review_unmapped_de",
        uf_ta_eligible & !uf_de_eligible ~ "excluded_de_domain",
        TRUE ~ "excluded_ta"
      ),
      uf_ta_de_reason = case_when(
        uf_is_eligible_by_ta_de ~ "eligible_ta_de",
        is.na(CODE_TA) ~ "uf_absent_from_consores_structure",
        uf_ta_eligible & !uf_de_mapped ~ "ta_03_20_unmapped_de",
        uf_ta_eligible & !uf_de_eligible ~ "ta_03_20_de_domain_not_included",
        TRUE ~ "ta_not_03_20"
      )
    ) %>%
    distinct(SEJUF, .keep_all = TRUE)
}

load_ratb_perimeter_rules <- function(rule_path) {
  required_cols <- c(
    "rule_level",
    "code_pattern",
    "label_pattern",
    "perimeter_status",
    "reason",
    "priority"
  )

  if (!file.exists(rule_path)) {
    stop("Missing RATB perimeter rule file: ", rule_path, call. = FALSE)
  }

  delimiter <- ratb_detect_delimiter_local(rule_path)

  rules <- utils::read.table(
    file = rule_path,
    header = TRUE,
    sep = delimiter,
    quote = "\"",
    comment.char = "",
    stringsAsFactors = FALSE,
    check.names = FALSE,
    fill = TRUE,
    fileEncoding = "UTF-8"
  ) %>%
    tibble::as_tibble()

  if (length(names(rules)) > 0L) {
    names(rules)[1] <- sub("^\ufeff", "", names(rules)[1], useBytes = TRUE)
  }

  missing_cols <- setdiff(required_cols, names(rules))
  if (length(missing_cols) > 0L) {
    stop(
      "RATB perimeter rule file is missing required columns: ",
      paste(missing_cols, collapse = ", "),
      call. = FALSE
    )
  }

  allowed_levels <- c("UF", "UM", "GHM")
  allowed_statuses <- c("include", "exclude", "review")

  rules <- rules %>%
    mutate(
      rule_level = toupper(trimws(as.character(rule_level))),
      code_pattern = ratb_trim_or_na_local(code_pattern),
      label_pattern = ratb_trim_or_na_local(label_pattern),
      perimeter_status = tolower(trimws(as.character(perimeter_status))),
      reason = ratb_trim_or_na_local(reason),
      priority = suppressWarnings(as.integer(priority))
    ) %>%
    arrange(rule_level, priority, reason)

  bad_levels <- setdiff(unique(stats::na.omit(rules$rule_level)), allowed_levels)
  if (length(bad_levels) > 0L) {
    stop(
      "Unsupported rule_level values in RATB perimeter rules: ",
      paste(bad_levels, collapse = ", "),
      call. = FALSE
    )
  }

  bad_statuses <- setdiff(unique(stats::na.omit(rules$perimeter_status)), allowed_statuses)
  if (length(bad_statuses) > 0L) {
    stop(
      "Unsupported perimeter_status values in RATB perimeter rules: ",
      paste(bad_statuses, collapse = ", "),
      call. = FALSE
    )
  }

  if (any(is.na(rules$priority))) {
    stop("All perimeter rules must have an integer priority.", call. = FALSE)
  }

  rules
}

ratb_match_rule_row <- function(code_values, label_values, code_pattern, label_pattern) {
  code_values <- ratb_trim_or_na_local(code_values)
  label_values <- ratb_trim_or_na_local(label_values)

  code_match <- TRUE
  label_match <- TRUE

  if (!is.na(code_pattern)) {
    code_match <- any(grepl(code_pattern, code_values, ignore.case = TRUE, perl = TRUE), na.rm = TRUE)
  }
  if (!is.na(label_pattern)) {
    label_match <- any(grepl(label_pattern, label_values, ignore.case = TRUE, perl = TRUE), na.rm = TRUE)
  }

  isTRUE(code_match) && isTRUE(label_match)
}

ratb_pick_level_rule <- function(code_values, label_values, rules, rule_level) {
  level_rules <- rules %>%
    filter(rule_level == !!rule_level) %>%
    arrange(priority, reason)

  if (nrow(level_rules) == 0L) {
    return(list(
      rule_level = rule_level,
      matched = FALSE,
      perimeter_status = NA_character_,
      reason = NA_character_,
      priority = NA_integer_,
      code_pattern = NA_character_,
      label_pattern = NA_character_
    ))
  }

  matches <- purrr::pmap_lgl(
    level_rules %>% select(code_pattern, label_pattern),
    function(code_pattern, label_pattern) {
      ratb_match_rule_row(
        code_values = code_values,
        label_values = label_values,
        code_pattern = code_pattern,
        label_pattern = label_pattern
      )
    }
  )

  if (!any(matches)) {
    return(list(
      rule_level = rule_level,
      matched = FALSE,
      perimeter_status = NA_character_,
      reason = NA_character_,
      priority = NA_integer_,
      code_pattern = NA_character_,
      label_pattern = NA_character_
    ))
  }

  hit <- level_rules[matches, , drop = FALSE][1, , drop = FALSE]
  list(
    rule_level = hit$rule_level[[1]],
    matched = TRUE,
    perimeter_status = hit$perimeter_status[[1]],
    reason = hit$reason[[1]],
    priority = hit$priority[[1]],
    code_pattern = hit$code_pattern[[1]],
    label_pattern = hit$label_pattern[[1]]
  )
}

ratb_apply_rule_set <- function(code_values, label_values, rules, rule_level) {
  level_rules <- rules %>%
    filter(rule_level == !!rule_level) %>%
    arrange(priority, reason)

  n <- length(code_values)
  out_status <- rep(NA_character_, n)
  out_reason <- rep(NA_character_, n)
  out_priority <- rep(NA_integer_, n)

  if (nrow(level_rules) == 0L || n == 0L) {
    return(tibble(
      perimeter_status = out_status,
      reason = out_reason,
      priority = out_priority
    ))
  }

  code_values <- dplyr::coalesce(ratb_trim_or_na_local(code_values), "")
  label_values <- dplyr::coalesce(ratb_trim_or_na_local(label_values), "")

  for (i in seq_len(nrow(level_rules))) {
    unmatched <- is.na(out_status)
    if (!any(unmatched)) {
      break
    }

    rule <- level_rules[i, , drop = FALSE]
    code_match <- rep(TRUE, n)
    label_match <- rep(TRUE, n)

    if (!is.na(rule$code_pattern[[1]])) {
      code_match[unmatched] <- grepl(
        rule$code_pattern[[1]],
        code_values[unmatched],
        ignore.case = TRUE,
        perl = TRUE
      )
    }
    if (!is.na(rule$label_pattern[[1]])) {
      label_match[unmatched] <- grepl(
        rule$label_pattern[[1]],
        label_values[unmatched],
        ignore.case = TRUE,
        perl = TRUE
      )
    }

    hit <- unmatched & code_match & label_match
    if (any(hit)) {
      out_status[hit] <- rule$perimeter_status[[1]]
      out_reason[hit] <- rule$reason[[1]]
      out_priority[hit] <- rule$priority[[1]]
    }
  }

  tibble(
    perimeter_status = out_status,
    reason = out_reason,
    priority = out_priority
  )
}

ratb_is_pure_urgences <- function(um_values) {
  um_values <- ratb_trim_or_na_local(um_values)
  um_values <- sort(unique(um_values[!is.na(um_values)]))
  if (length(um_values) == 0L) {
    return(FALSE)
  }
  all(um_values %in% c("URGE", "URGP"))
}

ratb_split_one_stay_nights_by_year <- function(patid, evtid, datent_min, datsort_max, cross_year = FALSE) {
  if (is.na(datent_min) || is.na(datsort_max)) {
    return(tibble())
  }

  admit_date <- as.Date(datent_min)
  discharge_date <- as.Date(datsort_max)
  if (is.na(admit_date) || is.na(discharge_date) || discharge_date < admit_date) {
    return(tibble())
  }

  years <- seq.int(lubridate::year(admit_date), lubridate::year(discharge_date))

  purrr::map_dfr(years, function(year_val) {
    year_start <- as.Date(sprintf("%04d-01-01", year_val))
    next_year_start <- as.Date(sprintf("%04d-01-01", year_val + 1L))
    overlap_start <- max(admit_date, year_start)
    overlap_end <- min(discharge_date, next_year_start)
    overlap_nights <- as.integer(overlap_end - overlap_start)

    tibble(
      PATID = patid,
      EVTID = evtid,
      calendar_year = year_val,
      overlap_start = overlap_start,
      overlap_end = overlap_end,
      overlap_nights = overlap_nights,
      cross_year = cross_year
    )
  })
}

ratb_split_stays_nights_by_year <- function(stays) {
  stopifnot(all(c("PATID", "EVTID", "datent_min", "datsort_max", "cross_year") %in% names(stays)))

  if (nrow(stays) == 0L) {
    return(tibble(
      PATID = character(),
      EVTID = character(),
      calendar_year = integer(),
      overlap_start = as.Date(character()),
      overlap_end = as.Date(character()),
      overlap_nights = integer(),
      cross_year = logical()
    ))
  }

  stays <- stays %>%
    mutate(
      datent_date = as.Date(datent_min),
      datsort_date = as.Date(datsort_max)
    ) %>%
    filter(!is.na(datent_date), !is.na(datsort_date), datsort_date >= datent_date)

  if (nrow(stays) == 0L) {
    return(tibble(
      PATID = character(),
      EVTID = character(),
      calendar_year = integer(),
      overlap_start = as.Date(character()),
      overlap_end = as.Date(character()),
      overlap_nights = integer(),
      cross_year = logical()
    ))
  }

  year_range <- seq.int(
    min(lubridate::year(stays$datent_date), na.rm = TRUE),
    max(lubridate::year(stays$datsort_date), na.rm = TRUE)
  )
  years <- tibble(
    calendar_year = year_range,
    year_start = as.Date(sprintf("%04d-01-01", year_range)),
    next_year_start = as.Date(sprintf("%04d-01-01", year_range + 1L))
  )

  tidyr::crossing(stays, years) %>%
    mutate(
      overlap_start = pmax(datent_date, year_start),
      overlap_end = pmin(datsort_date, next_year_start),
      overlap_nights = as.integer(pmax(overlap_end - overlap_start, 0))
    ) %>%
    filter(overlap_nights > 0L) %>%
    select(PATID, EVTID, calendar_year, overlap_start, overlap_end, overlap_nights, cross_year)
}

build_pmsi_status_lookup <- function(pmsi_main) {
  stopifnot(is.data.frame(pmsi_main))
  stopifnot(all(c("PATID", "EVTID", "PMSISTATUT") %in% names(pmsi_main)))

  evtid_audit <- pmsi_main %>%
    transmute(
      PATID = as.character(PATID),
      EVTID = as.character(EVTID)
    ) %>%
    group_by(EVTID) %>%
    summarise(
      n_patid_for_evtid = n_distinct(PATID, na.rm = TRUE),
      evtid_multi_pat = n_patid_for_evtid > 1L,
      .groups = "drop"
    )

  pmsi_main %>%
    transmute(
      PATID = as.character(PATID),
      EVTID = as.character(EVTID),
      PMSISTATUT_norm = ratb_normalize_pmsi_status(PMSISTATUT)
    ) %>%
    group_by(PATID, EVTID) %>%
    summarise(
      n_pmsi_rows = n(),
      n_status_non_missing = sum(!is.na(PMSISTATUT_norm)),
      n_distinct_status = n_distinct(PMSISTATUT_norm, na.rm = TRUE),
      pmsi_status_values = {
        vals <- sort(unique(PMSISTATUT_norm[!is.na(PMSISTATUT_norm)]))
        if (length(vals) == 0L) NA_character_ else paste(vals, collapse = "|")
      },
      ratb_scope_status = {
        vals <- sort(unique(PMSISTATUT_norm[!is.na(PMSISTATUT_norm)]))
        if (length(vals) == 0L) {
          "no_usable_status"
        } else if (identical(vals, "H")) {
          "eligible_hospitalization"
        } else if (identical(vals, "E")) {
          "excluded_external"
        } else {
          "mixed_status"
        }
      },
      .groups = "drop"
    ) %>%
    left_join(evtid_audit, by = "EVTID") %>%
    mutate(
      n_patid_for_evtid = dplyr::coalesce(n_patid_for_evtid, 0L),
      evtid_multi_pat = dplyr::coalesce(evtid_multi_pat, FALSE)
    )
}

build_ratb_scope_tables <- function(sir_wide, pmsi_main) {
  stopifnot(is.data.frame(sir_wide), is.data.frame(pmsi_main))
  stopifnot(all(c("PATID", "EVTID", "ELTID") %in% names(sir_wide)))

  pmsi_status_lookup <- build_pmsi_status_lookup(pmsi_main)

  sir_base <- sir_wide %>%
    mutate(
      PATID = as.character(PATID),
      EVTID = as.character(EVTID)
    )

  ratb_scope_join_audit <- sir_base %>%
    group_by(PATID, EVTID) %>%
    summarise(
      n_micro_rows = n(),
      n_eltid = n_distinct(ELTID, na.rm = TRUE),
      n_bact_norm = n_distinct(bact_norm, na.rm = TRUE),
      n_naturepvt_norm = n_distinct(naturepvt_norm, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    left_join(pmsi_status_lookup, by = c("PATID", "EVTID")) %>%
    mutate(
      ratb_scope_status = dplyr::coalesce(ratb_scope_status, "no_pmsi_match"),
      included_in_ratb_scope = ratb_scope_status != "no_pmsi_match",
      n_status_non_missing = dplyr::coalesce(n_status_non_missing, 0L),
      n_distinct_status = dplyr::coalesce(n_distinct_status, 0L),
      n_pmsi_rows = dplyr::coalesce(n_pmsi_rows, 0L),
      n_patid_for_evtid = dplyr::coalesce(n_patid_for_evtid, 0L),
      evtid_multi_pat = dplyr::coalesce(evtid_multi_pat, FALSE)
    ) %>%
    arrange(desc(included_in_ratb_scope), ratb_scope_status, PATID, EVTID)

  ratb_scope_exclusion_summary <- ratb_scope_join_audit %>%
    group_by(ratb_scope_status, included_in_ratb_scope) %>%
    summarise(
      n_patid_evtid = n(),
      n_micro_rows = sum(n_micro_rows, na.rm = TRUE),
      n_eltid = sum(n_eltid, na.rm = TRUE),
      n_evtid_multi_pat = sum(evtid_multi_pat, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(
      pct_patid_evtid = 100 * n_patid_evtid / sum(n_patid_evtid),
      pct_micro_rows = 100 * n_micro_rows / sum(n_micro_rows)
    ) %>%
    arrange(desc(included_in_ratb_scope), desc(n_micro_rows), ratb_scope_status)

  sir_wide_ratb_scope <- sir_base %>%
    left_join(
      ratb_scope_join_audit %>%
        select(
          PATID, EVTID, ratb_scope_status, included_in_ratb_scope,
          pmsi_status_values, n_status_non_missing, n_distinct_status,
          n_pmsi_rows, n_patid_for_evtid, evtid_multi_pat
        ),
      by = c("PATID", "EVTID")
    ) %>%
    mutate(
      ratb_scope_status = dplyr::coalesce(ratb_scope_status, "no_pmsi_match"),
      included_in_ratb_scope = dplyr::coalesce(included_in_ratb_scope, FALSE),
      n_status_non_missing = dplyr::coalesce(n_status_non_missing, 0L),
      n_distinct_status = dplyr::coalesce(n_distinct_status, 0L),
      n_pmsi_rows = dplyr::coalesce(n_pmsi_rows, 0L),
      n_patid_for_evtid = dplyr::coalesce(n_patid_for_evtid, 0L),
      evtid_multi_pat = dplyr::coalesce(evtid_multi_pat, FALSE)
    ) %>%
    select(-included_in_ratb_scope)

  list(
    sir_wide_ratb_scope = sir_wide_ratb_scope,
    ratb_scope_join_audit = ratb_scope_join_audit,
    ratb_scope_exclusion_summary = ratb_scope_exclusion_summary,
    pmsi_status_lookup = pmsi_status_lookup
  )
}

build_ratb_analytic_scope_dataset <- function(sir_wide_ratb_scope) {
  stopifnot(
    is.data.frame(sir_wide_ratb_scope),
    all(c("PATID", "EVTID") %in% names(sir_wide_ratb_scope)),
    "sample_uf_is_eligible_by_ta_de" %in% names(sir_wide_ratb_scope)
  )

  sir_wide_ratb_scope %>%
    filter(sample_uf_is_eligible_by_ta_de)
}

ratb_split_one_stay_by_year <- function(patid, evtid, datent_min, datsort_max, cross_year = FALSE) {
  if (is.na(datent_min) || is.na(datsort_max) || datsort_max < datent_min) {
    return(tibble())
  }

  tz <- ratb_resolve_posix_tz(datent_min)
  years <- seq.int(lubridate::year(datent_min), lubridate::year(datsort_max))

  purrr::map_dfr(years, function(year_val) {
    year_start <- as.POSIXct(
      sprintf("%04d-01-01 00:00:00", year_val),
      tz = tz
    )
    next_year_start <- as.POSIXct(
      sprintf("%04d-01-01 00:00:00", year_val + 1L),
      tz = tz
    )
    overlap_start <- max(datent_min, year_start)
    overlap_end <- min(datsort_max, next_year_start)
    overlap_days_exact <- as.numeric(difftime(overlap_end, overlap_start, units = "days"))

    tibble(
      PATID = patid,
      EVTID = evtid,
      calendar_year = year_val,
      overlap_start = overlap_start,
      overlap_end = overlap_end,
      overlap_days_exact = overlap_days_exact,
      overlap_days_floor = floor(overlap_days_exact),
      overlap_days_ceiling = ceiling(overlap_days_exact),
      overlap_days_round = round(overlap_days_exact),
      cross_year = cross_year
    )
  })
}

build_hospital_stays_raw <- function(pmsi_main, status_lookup = NULL) {
  stopifnot(is.data.frame(pmsi_main))
  stopifnot(all(c("PATID", "EVTID", "PMSISTATUT", "DATENT", "DATSORT", "SEJDUR") %in% names(pmsi_main)))

  if (is.null(status_lookup)) {
    status_lookup <- build_pmsi_status_lookup(pmsi_main)
  }

  pmsi_main %>%
    transmute(
      PATID = as.character(PATID),
      EVTID = as.character(EVTID),
      PMSISTATUT_norm = ratb_normalize_pmsi_status(PMSISTATUT),
      DATENT = DATENT,
      DATSORT = DATSORT,
      SEJDUR_num = suppressWarnings(as.numeric(SEJDUR))
    ) %>%
    group_by(PATID, EVTID) %>%
    summarise(
      n_pmsi_activity_rows = n(),
      datent_min = ratb_safe_min_datetime(DATENT),
      datsort_max = ratb_safe_max_datetime(DATSORT),
      sejdur_min = if (all(is.na(SEJDUR_num))) NA_real_ else min(SEJDUR_num, na.rm = TRUE),
      sejdur_max = if (all(is.na(SEJDUR_num))) NA_real_ else max(SEJDUR_num, na.rm = TRUE),
      sejdur_values = {
        vals <- sort(unique(SEJDUR_num[!is.na(SEJDUR_num)]))
        if (length(vals) == 0L) NA_character_ else paste(vals, collapse = "|")
      },
      n_distinct_sejdur = n_distinct(SEJDUR_num, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    left_join(
      status_lookup %>%
        select(
          PATID, EVTID, ratb_scope_status, pmsi_status_values,
          n_status_non_missing, n_distinct_status, n_pmsi_rows,
          n_patid_for_evtid, evtid_multi_pat
        ),
      by = c("PATID", "EVTID")
    ) %>%
    mutate(
      exact_elapsed_days = as.numeric(difftime(datsort_max, datent_min, units = "days")),
      missing_bounds = is.na(datent_min) | is.na(datsort_max),
      negative_elapsed = !is.na(exact_elapsed_days) & exact_elapsed_days < 0,
      zero_elapsed = !is.na(exact_elapsed_days) & exact_elapsed_days == 0,
      cross_year = !is.na(datent_min) & !is.na(datsort_max) &
        lubridate::year(datent_min) != lubridate::year(datsort_max),
      elapsed_floor_days = if_else(is.na(exact_elapsed_days), NA_real_, floor(exact_elapsed_days)),
      elapsed_ceiling_days = if_else(is.na(exact_elapsed_days), NA_real_, ceiling(exact_elapsed_days)),
      elapsed_round_days = if_else(is.na(exact_elapsed_days), NA_real_, round(exact_elapsed_days)),
      validation_status = case_when(
        missing_bounds ~ "invalid_missing_bounds",
        negative_elapsed ~ "invalid_negative_elapsed",
        TRUE ~ "validated"
      ),
      valid_for_denominator = validation_status == "validated"
    ) %>%
    arrange(validation_status, PATID, EVTID)
}

build_hospital_days_validation <- function(pmsi_main, status_lookup = NULL) {
  if (is.null(status_lookup)) {
    status_lookup <- build_pmsi_status_lookup(pmsi_main)
  }

  hospital_stays_raw <- build_hospital_stays_raw(
    pmsi_main = pmsi_main,
    status_lookup = status_lookup
  )

  hospital_stays_validated <- hospital_stays_raw %>%
    filter(valid_for_denominator)

  hospital_days_year_split <- purrr::pmap_dfr(
    hospital_stays_validated %>%
      select(PATID, EVTID, datent_min, datsort_max, cross_year),
    function(PATID, EVTID, datent_min, datsort_max, cross_year) {
      ratb_split_one_stay_by_year(
        patid = PATID,
        evtid = EVTID,
        datent_min = datent_min,
        datsort_max = datsort_max,
        cross_year = cross_year
      )
    }
  )

  hospital_days_year_summary <- hospital_days_year_split %>%
    group_by(calendar_year) %>%
    summarise(
      n_stays = n_distinct(PATID, EVTID),
      n_cross_year_stays = n_distinct(PATID[cross_year], EVTID[cross_year]),
      hospital_days_exact = sum(overlap_days_exact, na.rm = TRUE),
      hospital_days_floor = sum(overlap_days_floor, na.rm = TRUE),
      hospital_days_ceiling = sum(overlap_days_ceiling, na.rm = TRUE),
      hospital_days_round = sum(overlap_days_round, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    arrange(calendar_year)

  hospital_stay_validation_summary <- tibble(
    metric = c(
      "n_pmsi_stays_raw",
      "n_pmsi_stays_validated",
      "n_pmsi_stays_excluded",
      "n_invalid_missing_bounds",
      "n_invalid_negative_elapsed",
      "n_zero_elapsed_validated",
      "n_cross_year_validated",
      "n_evtid_multi_pat_validated",
      "sum_exact_elapsed_days_validated",
      "sum_floor_elapsed_days_validated",
      "sum_ceiling_elapsed_days_validated",
      "sum_round_elapsed_days_validated",
      "sum_sejdur_max_validated",
      "sum_year_split_exact_days"
    ),
    value = c(
      nrow(hospital_stays_raw),
      nrow(hospital_stays_validated),
      nrow(hospital_stays_raw) - nrow(hospital_stays_validated),
      sum(hospital_stays_raw$missing_bounds, na.rm = TRUE),
      sum(hospital_stays_raw$negative_elapsed, na.rm = TRUE),
      sum(hospital_stays_validated$zero_elapsed, na.rm = TRUE),
      sum(hospital_stays_validated$cross_year, na.rm = TRUE),
      sum(hospital_stays_validated$evtid_multi_pat, na.rm = TRUE),
      sum(hospital_stays_validated$exact_elapsed_days, na.rm = TRUE),
      sum(hospital_stays_validated$elapsed_floor_days, na.rm = TRUE),
      sum(hospital_stays_validated$elapsed_ceiling_days, na.rm = TRUE),
      sum(hospital_stays_validated$elapsed_round_days, na.rm = TRUE),
      sum(hospital_stays_validated$sejdur_max, na.rm = TRUE),
      sum(hospital_days_year_split$overlap_days_exact, na.rm = TRUE)
    ),
    unit = c(
      rep("stays", 8),
      rep("days", 6)
    )
  )

  list(
    hospital_stays_raw = hospital_stays_raw,
    hospital_stays_validated = hospital_stays_validated,
    hospital_stay_validation_summary = hospital_stay_validation_summary,
    hospital_days_year_split = hospital_days_year_split,
    hospital_days_year_summary = hospital_days_year_summary
  )
}

build_ratb_provisional_perimeter_audit <- function(
    sir_wide_ratb_scope,
    pmsi_main,
    status_lookup = NULL,
    structure_path = file.path("ref", "consores_structure_intranet_maj_2025.xlsx"),
    codes_ta_path = file.path("ref", "consores_codes_ta.csv"),
    codes_de_path = file.path("ref", "consores_codes_de.csv"),
    ref_dir = "ref"
  ) {
  stopifnot(is.data.frame(sir_wide_ratb_scope), is.data.frame(pmsi_main))
  stopifnot(all(c("PATID", "EVTID", "ELTID", "SEJUF", "SEJUM") %in% names(sir_wide_ratb_scope)))
  stopifnot(all(c("PATID", "EVTID", "PMSISTATUT", "DATENT", "DATSORT", "SEJUM", "SEJUF", "GHM") %in% names(pmsi_main)))

  if (is.null(status_lookup)) {
    status_lookup <- build_pmsi_status_lookup(pmsi_main)
  }

  refs <- load_ratb_unit_references(ref_dir = ref_dir)
  consores_ta_de_ref <- load_ratb_consores_ta_de_reference(
    structure_path = structure_path,
    codes_ta_path = codes_ta_path,
    codes_de_path = codes_de_path
  )
  ratb_perimeter_rules <- build_ratb_ta_de_policy_table()

  sample_uf_ta_de_reference <- consores_ta_de_ref %>%
    transmute(
      SEJUF,
      sample_consores_uf_label = consores_uf_label,
      sample_CODE_TA = CODE_TA,
      sample_CODE_DE = CODE_DE,
      sample_de_domain_ref = de_domain_ref,
      sample_uf_is_eligible_by_ta_de = uf_is_eligible_by_ta_de,
      sample_uf_ta_de_status = uf_ta_de_status,
      sample_uf_ta_de_reason = uf_ta_de_reason
    )

  sir_wide_ratb_scope <- sir_wide_ratb_scope %>%
    mutate(
      PATID = as.character(PATID),
      EVTID = as.character(EVTID),
      SEJUF = ratb_trim_or_na_local(SEJUF),
      SEJUM = ratb_trim_or_na_local(SEJUM)
    ) %>%
    left_join(sample_uf_ta_de_reference, by = "SEJUF") %>%
    mutate(
      sample_uf_is_eligible_by_ta_de = dplyr::coalesce(sample_uf_is_eligible_by_ta_de, FALSE),
      sample_uf_ta_de_status = case_when(
        is.na(SEJUF) ~ "review_missing_sample_uf",
        is.na(sample_CODE_TA) ~ "review_unmapped_uf",
        TRUE ~ sample_uf_ta_de_status
      ),
      sample_uf_ta_de_reason = case_when(
        is.na(SEJUF) ~ "missing_sample_uf",
        is.na(sample_CODE_TA) ~ "uf_absent_from_consores_structure",
        TRUE ~ sample_uf_ta_de_reason
      )
    )

  scope_status_lookup <- status_lookup %>%
    select(
      PATID, EVTID, ratb_scope_status, pmsi_status_values,
      n_status_non_missing, n_distinct_status, n_pmsi_rows,
      evtid_multi_pat, n_patid_for_evtid
    )

  episode_base <- pmsi_main %>%
    transmute(
      PATID = as.character(PATID),
      EVTID = as.character(EVTID),
      PMSISTATUT_norm = ratb_normalize_pmsi_status(PMSISTATUT),
      DATENT = DATENT,
      DATSORT = DATSORT,
      SEJUM = ratb_trim_or_na_local(SEJUM),
      SEJUF = ratb_trim_or_na_local(SEJUF),
      GHM = ratb_trim_or_na_local(GHM)
    ) %>%
    left_join(refs$uf_ref, by = "SEJUF") %>%
    left_join(refs$uf2um_ref, by = "SEJUF") %>%
    left_join(refs$um_ref, by = "SEJUM") %>%
    left_join(consores_ta_de_ref, by = "SEJUF") %>%
    mutate(
      uf_ta_eligible = dplyr::coalesce(uf_ta_eligible, FALSE),
      uf_de_mapped = dplyr::coalesce(uf_de_mapped, FALSE),
      uf_de_eligible = dplyr::coalesce(uf_de_eligible, FALSE),
      uf_is_eligible_by_ta_de = dplyr::coalesce(uf_is_eligible_by_ta_de, FALSE),
      uf_ta_de_status = dplyr::coalesce(uf_ta_de_status, "review_unmapped_uf"),
      uf_ta_de_reason = dplyr::coalesce(
        uf_ta_de_reason,
        "uf_absent_from_consores_structure"
      )
    ) %>%
    group_by(PATID, EVTID) %>%
    summarise(
      n_pmsi_rows = n(),
      datent_min = ratb_safe_min_datetime(DATENT),
      datsort_max = ratb_safe_max_datetime(DATSORT),
      uf_codes_list = list(sort(unique(SEJUF[!is.na(SEJUF)]))),
      uf_labels_list = list(sort(unique(uf_label[!is.na(uf_label)]))),
      um_codes_list = list(sort(unique(SEJUM[!is.na(SEJUM)]))),
      um_labels_list = list(sort(unique(um_label[!is.na(um_label)]))),
      ghm_values_list = list(sort(unique(GHM[!is.na(GHM)]))),
      episode_uf_codes = ratb_collapse_unique(SEJUF),
      episode_uf_labels = ratb_collapse_unique(uf_label),
      episode_um_codes = ratb_collapse_unique(SEJUM),
      episode_um_labels = ratb_collapse_unique(um_label),
      episode_ghm_values = ratb_collapse_unique(GHM),
      eligible_uf_codes = ratb_collapse_unique(SEJUF[uf_is_eligible_by_ta_de %in% TRUE]),
      noneligible_uf_codes = ratb_collapse_unique(SEJUF[!(uf_is_eligible_by_ta_de %in% TRUE)]),
      episode_ta_codes = ratb_collapse_unique(CODE_TA),
      episode_de_codes = ratb_collapse_unique(CODE_DE),
      episode_de_domains = ratb_collapse_unique(de_domain_ref),
      episode_ta_de_statuses = ratb_collapse_unique(paste(SEJUF, uf_ta_de_status, sep = ":")),
      episode_ta_de_reasons = ratb_collapse_unique(uf_ta_de_reason),
      n_uf_codes = n_distinct(SEJUF, na.rm = TRUE),
      n_um_codes = n_distinct(SEJUM, na.rm = TRUE),
      n_ghm_values = n_distinct(GHM, na.rm = TRUE),
      n_uf_unmapped = n_distinct(SEJUF[!is.na(SEJUF) & is.na(CODE_TA)]),
      n_uf_label_unmapped = n_distinct(SEJUF[!is.na(SEJUF) & is.na(uf_label)]),
      n_um_unmapped = n_distinct(SEJUM[!is.na(SEJUM) & is.na(um_label)]),
      n_ta_de_eligible_uf = n_distinct(SEJUF[uf_is_eligible_by_ta_de %in% TRUE]),
      n_ta_eligible_unmapped_de = n_distinct(SEJUF[
        !is.na(SEJUF) &
          uf_ta_eligible %in% TRUE &
          !(uf_de_mapped %in% TRUE)
      ]),
      n_uf_um_ref_mismatch = n_distinct(SEJUF[
        !is.na(SEJUF) &
          !is.na(SEJUM_from_ref) &
          !is.na(SEJUM) &
          SEJUM_from_ref != SEJUM
      ]),
      .groups = "drop"
    ) %>%
    left_join(
      scope_status_lookup,
      by = c("PATID", "EVTID"),
      suffix = c("", "_status")
    ) %>% 
    mutate(
      nights_provisional = as.integer(as.Date(datsort_max) - as.Date(datent_min)),
      missing_bounds = is.na(datent_min) | is.na(datsort_max),
      negative_nights = !is.na(nights_provisional) & nights_provisional < 0L,
      zero_nights = !is.na(nights_provisional) & nights_provisional == 0L,
      cross_year = !is.na(datent_min) & !is.na(datsort_max) &
        lubridate::year(datent_min) != lubridate::year(datsort_max),
      pure_urgences_episode = purrr::map_lgl(um_codes_list, ratb_is_pure_urgences)
    )

  ratb_episode_scope_audit <- episode_base %>%
    mutate(
      provisional_perimeter_status = case_when(
        missing_bounds ~ "review_missing_bounds",
        negative_nights ~ "review_negative_nights",
        n_ta_de_eligible_uf > 0L ~ "included",
        n_uf_codes == 0L ~ "excluded_no_uf",
        n_uf_unmapped > 0L ~ "review_unmapped_uf",
        n_ta_eligible_unmapped_de > 0L ~ "review_unmapped_de",
        TRUE ~ "excluded_no_ta_de_eligible_uf"
      ),
      final_rule_level = case_when(
        missing_bounds | negative_nights ~ "stay_bounds",
        TRUE ~ "TA_DE"
      ),
      final_reason = case_when(
        missing_bounds ~ "missing_bounds",
        negative_nights ~ "negative_nights",
        n_ta_de_eligible_uf > 0L ~ "eligible_ta_de_uf",
        n_uf_codes == 0L ~ "no_uf",
        n_uf_unmapped > 0L ~ "unmapped_uf",
        n_ta_eligible_unmapped_de > 0L ~ "unmapped_de",
        TRUE ~ "no_ta_de_eligible_uf"
      ),
      included_in_provisional_perimeter = provisional_perimeter_status == "included"
    ) %>%
    select(
      PATID, EVTID, ratb_scope_status, pmsi_status_values,
      provisional_perimeter_status, included_in_provisional_perimeter,
      final_rule_level, final_reason,
      datent_min, datsort_max, nights_provisional, zero_nights, cross_year,
      missing_bounds, negative_nights, pure_urgences_episode,
      n_pmsi_rows, n_status_non_missing, n_distinct_status, evtid_multi_pat,
      n_patid_for_evtid, episode_uf_codes, episode_uf_labels,
      episode_um_codes, episode_um_labels, episode_ghm_values,
      eligible_uf_codes, noneligible_uf_codes, episode_ta_codes,
      episode_de_codes, episode_de_domains, episode_ta_de_statuses,
      episode_ta_de_reasons,
      n_uf_codes, n_um_codes, n_ghm_values, n_uf_unmapped,
      n_uf_label_unmapped, n_um_unmapped, n_ta_de_eligible_uf,
      n_ta_eligible_unmapped_de, n_uf_um_ref_mismatch
    ) %>%
    arrange(desc(included_in_provisional_perimeter), provisional_perimeter_status, PATID, EVTID)

  ratb_episode_exclusion_summary <- ratb_episode_scope_audit %>%
    group_by(
      provisional_perimeter_status,
      included_in_provisional_perimeter,
      final_rule_level,
      final_reason
    ) %>%
    summarise(
      n_episodes = n(),
      n_zero_nights = sum(zero_nights, na.rm = TRUE),
      n_cross_year = sum(cross_year, na.rm = TRUE),
      total_nights_provisional = sum(nights_provisional, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(
      pct_episodes = 100 * n_episodes / sum(n_episodes)
    ) %>%
    arrange(desc(included_in_provisional_perimeter), desc(n_episodes), provisional_perimeter_status)

  hospital_days_year_split_provisional <- ratb_split_stays_nights_by_year(
    ratb_episode_scope_audit %>%
      filter(included_in_provisional_perimeter, !missing_bounds, !negative_nights) %>%
      select(PATID, EVTID, datent_min, datsort_max, cross_year)
  )

  hospital_days_year_summary_provisional <- hospital_days_year_split_provisional %>%
    mutate(.episode_key = paste(PATID, EVTID, sep = "\r")) %>%
    group_by(calendar_year) %>%
    summarise(
      n_episodes = n_distinct(.episode_key),
      n_cross_year_episodes = n_distinct(.episode_key[cross_year]),
      hospital_nights_provisional = sum(overlap_nights, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    arrange(calendar_year)

  ratb_numerator_scope_impact_audit <- sir_wide_ratb_scope %>%
    mutate(
      PATID = as.character(PATID),
      EVTID = as.character(EVTID)
    ) %>%
    group_by(
      sample_uf_ta_de_status,
      sample_uf_is_eligible_by_ta_de,
      sample_uf_ta_de_reason
    ) %>%
    summarise(
      n_micro_rows = n(),
      n_eltid = n_distinct(ELTID, na.rm = TRUE),
      n_patid_evtid = n_distinct(paste(PATID, EVTID, sep = "\r")),
      .groups = "drop"
    ) %>%
    mutate(
      pct_micro_rows = 100 * n_micro_rows / sum(n_micro_rows),
      pct_eltid = 100 * n_eltid / sum(n_eltid)
    ) %>%
    arrange(desc(sample_uf_is_eligible_by_ta_de), desc(n_micro_rows), sample_uf_ta_de_status)

  list(
    sir_wide_ratb_scope = sir_wide_ratb_scope,
    ratb_perimeter_rules = ratb_perimeter_rules,
    ratb_uf_ta_de_reference = consores_ta_de_ref,
    ratb_episode_scope_audit = ratb_episode_scope_audit,
    ratb_episode_exclusion_summary = ratb_episode_exclusion_summary,
    hospital_days_year_split_provisional = hospital_days_year_split_provisional,
    hospital_days_year_summary_provisional = hospital_days_year_summary_provisional,
    ratb_numerator_scope_impact_audit = ratb_numerator_scope_impact_audit
  )
}

