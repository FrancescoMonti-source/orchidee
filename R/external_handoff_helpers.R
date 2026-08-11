## Rennes/external-site handoff helpers.
##
## These helpers build ORCHIDEE's canonical runtime bundle from simpler,
## site-owned input blocks. They deliberately sit upstream of the canonical
## runtime contract validated in `R/external_bundle_validation_helpers.R`.

orchidee_handoff_site_input_spec <- function() {
  microbiology_required <- c(
    "PATID",
    "ELTID",
    "DATEPRELEV",
    "SEJUF",
    "bacteria_local",
    "sample_type_local",
    "antibiotic_local",
    "sir_result"
  )
  diagnostic_scope_columns <- c(
    "ratb_diagnostic_scope",
    "diagnostic_scope",
    "is_diagnostic"
  )
  spec <- list(
    microbiology_observations = list(
      required_columns = microbiology_required,
      required_one_of = list(
        diagnostic_scope = diagnostic_scope_columns
      ),
      template_columns = c(
        "PATID",
        "EVTID",
        "ELTID",
        "DATEPRELEV",
        "HEUREPRELEV",
        "SEJUF",
        "souche_id",
        "bacteria_local",
        "sample_type_local",
        "antibiotic_local",
        "sir_result",
        "ratb_diagnostic_scope",
        "blse_status_row",
        "carbapenemase_status_row"
      )
    ),
    bacteria_mapping = list(
      required_columns = c("bacteria_local", "bact_norm"),
      required_one_of = list(),
      template_columns = c("bacteria_local", "bact_norm")
    ),
    sample_type_mapping = list(
      required_columns = c("sample_type_local", "naturepvt_norm"),
      required_one_of = list(),
      template_columns = c("sample_type_local", "naturepvt_norm")
    ),
    antibiotic_mapping = list(
      required_columns = c("antibiotic_local", "atb_norm"),
      required_one_of = list(),
      template_columns = c("antibiotic_local", "atb_norm")
    ),
    unit_mapping = list(
      required_columns = c("SEJUF", "CODE_TA", "CODE_DE", "de_domain_ref"),
      required_one_of = list(),
      template_columns = c("SEJUF", "CODE_TA", "CODE_DE", "de_domain_ref")
    )
  )

  denominator_columns <- c(
    "calendar_year",
    "SEJUM",
    "SEJUF",
    "CODE_TA",
    "CODE_DE",
    "de_domain_ref",
    "denominator_profile_id",
    "exposure_value",
    "exposure_unit"
  )
  spec$incidence_exposure_by_year_um_uf_ta_de_profile <- list(
    required_columns = denominator_columns,
    required_one_of = list(),
    template_columns = denominator_columns
  )
  spec
}

orchidee_handoff_validate_site_input_columns <- function(site_inputs) {
  spec <- orchidee_handoff_site_input_spec()
  if (!is.list(site_inputs)) {
    stop("site_inputs must be a named list.", call. = FALSE)
  }
  if (
    is.null(names(site_inputs)) ||
      any(!nzchar(names(site_inputs))) ||
      anyDuplicated(names(site_inputs))
  ) {
    stop(
      "site_inputs must have unique, non-empty block names.",
      call. = FALSE
    )
  }
  missing_blocks <- setdiff(names(spec), names(site_inputs))
  if (length(missing_blocks) > 0L) {
    stop(
      "Missing site handoff blocks: ",
      paste(missing_blocks, collapse = ", "),
      call. = FALSE
    )
  }
  extra_blocks <- setdiff(names(site_inputs), names(spec))
  if (length(extra_blocks) > 0L) {
    stop(
      "Unexpected site handoff blocks: ",
      paste(extra_blocks, collapse = ", "),
      call. = FALSE
    )
  }

  for (block_name in names(spec)) {
    block <- site_inputs[[block_name]]
    if (!is.data.frame(block)) {
      stop(block_name, " must be a data frame.", call. = FALSE)
    }
    duplicate_columns <- unique(names(block)[duplicated(names(block))])
    if (length(duplicate_columns) > 0L) {
      stop(
        block_name,
        " contains duplicate column names: ",
        paste(duplicate_columns, collapse = ", "),
        call. = FALSE
      )
    }
    missing_columns <- setdiff(
      spec[[block_name]]$required_columns,
      names(block)
    )
    if (length(missing_columns) > 0L) {
      stop(
        block_name,
        " is missing required columns: ",
        paste(missing_columns, collapse = ", "),
        call. = FALSE
      )
    }
    for (one_of_name in names(spec[[block_name]]$required_one_of)) {
      candidates <- spec[[block_name]]$required_one_of[[one_of_name]]
      present_candidates <- intersect(candidates, names(block))
      if (length(present_candidates) != 1L) {
        stop(
          block_name,
          " must contain exactly one of these ",
          one_of_name,
          " columns: ",
          paste(candidates, collapse = ", "),
          call. = FALSE
        )
      }
    }
  }

  invisible(spec)
}

orchidee_handoff_trim_or_na <- function(x) {
  x <- trimws(as.character(x))
  x[!nzchar(x)] <- NA_character_
  x
}

orchidee_handoff_detect_delimiter <- function(path) {
  header <- readLines(path, n = 1L, warn = FALSE, encoding = "UTF-8")
  if (length(header) == 0L) {
    stop("Empty delimited file: ", path, call. = FALSE)
  }
  header <- sub("^\ufeff", "", header[[1]], useBytes = TRUE)
  n_semicolon <- lengths(regmatches(header, gregexpr(";", header, fixed = TRUE)))
  n_comma <- lengths(regmatches(header, gregexpr(",", header, fixed = TRUE)))
  if (n_semicolon > n_comma) ";" else ","
}

orchidee_handoff_read_table <- function(path) {
  if (!file.exists(path)) {
    stop("Missing handoff input file: ", path, call. = FALSE)
  }

  ext <- tolower(tools::file_ext(path))
  if (identical(ext, "rds")) {
    return(readRDS(path))
  }

  if (ext %in% c("csv", "txt")) {
    delimiter <- orchidee_handoff_detect_delimiter(path)
    return(utils::read.table(
      file = path,
      header = TRUE,
      sep = delimiter,
      quote = "\"",
      comment.char = "",
      stringsAsFactors = FALSE,
      check.names = FALSE,
      fill = TRUE,
      colClasses = "character",
      fileEncoding = "UTF-8"
    ))
  }

  if (ext %in% c("tsv", "tab")) {
    return(utils::read.delim(
      file = path,
      stringsAsFactors = FALSE,
      check.names = FALSE,
      colClasses = "character",
      fileEncoding = "UTF-8"
    ))
  }

  stop(
    "Unsupported handoff input extension for ",
    path,
    ". Use .rds, .csv, .tsv, .tab, or .txt.",
    call. = FALSE
  )
}

orchidee_handoff_read_table_schema <- function(path) {
  if (!file.exists(path)) {
    stop("Missing handoff input file: ", path, call. = FALSE)
  }

  ext <- tolower(tools::file_ext(path))
  if (identical(ext, "rds")) {
    object <- readRDS(path)
    if (!is.data.frame(object)) {
      stop("Handoff RDS input must contain a data frame: ", path, call. = FALSE)
    }
    return(object[0, , drop = FALSE])
  }

  if (ext %in% c("csv", "txt")) {
    delimiter <- orchidee_handoff_detect_delimiter(path)
    return(utils::read.table(
      file = path,
      header = TRUE,
      nrows = 0L,
      sep = delimiter,
      quote = "\"",
      comment.char = "",
      stringsAsFactors = FALSE,
      check.names = FALSE,
      fill = TRUE,
      colClasses = "character",
      fileEncoding = "UTF-8"
    ))
  }

  if (ext %in% c("tsv", "tab")) {
    return(utils::read.delim(
      file = path,
      header = TRUE,
      nrows = 0L,
      stringsAsFactors = FALSE,
      check.names = FALSE,
      colClasses = "character",
      fileEncoding = "UTF-8"
    ))
  }

  stop(
    "Unsupported handoff input extension for ",
    path,
    ". Use .rds, .csv, .tsv, .tab, or .txt.",
    call. = FALSE
  )
}

orchidee_handoff_require_functions <- function(required_funs) {
  missing <- required_funs[!vapply(required_funs, exists, logical(1), mode = "function")]
  if (length(missing) > 0L) {
    stop(
      "Missing required helper functions: ",
      paste(missing, collapse = ", "),
      ". Source the relevant ORCHIDEE helper scripts first.",
      call. = FALSE
    )
  }
}

orchidee_handoff_mapping_reference_tables <- function(project_root = ".") {
  orchidee_handoff_require_functions(c(
    "orchidee_external_contract_v3",
    "ratb_analysis_context_profile",
    "ratb_denominator_profile_registry",
    "ratb_normalize_code_ta",
    "ratb_normalize_code_de"
  ))

  project_root <- normalizePath(
    project_root,
    winslash = "/",
    mustWork = TRUE
  )
  contract <- orchidee_external_contract_v3()
  context <- ratb_analysis_context_profile()

  species_taxonomy <- orchidee_handoff_read_table(file.path(
    project_root,
    "mappings",
    "species_regex_map.csv"
  ))
  required_taxonomy_columns <- c(
    "bact_norm",
    "bact_order",
    "bact_family",
    "bact_genus"
  )
  missing_taxonomy_columns <- setdiff(
    required_taxonomy_columns,
    names(species_taxonomy)
  )
  if (length(missing_taxonomy_columns) > 0L) {
    stop(
      "mappings/species_regex_map.csv is missing columns: ",
      paste(missing_taxonomy_columns, collapse = ", "),
      call. = FALSE
    )
  }
  species_taxonomy <- species_taxonomy[required_taxonomy_columns]
  species_taxonomy[] <- lapply(
    species_taxonomy,
    orchidee_handoff_trim_or_na
  )
  species_taxonomy <- unique(species_taxonomy[
    !is.na(species_taxonomy$bact_norm),
    ,
    drop = FALSE
  ])
  if (anyDuplicated(species_taxonomy$bact_norm)) {
    stop(
      "mappings/species_regex_map.csv has non-unique taxonomy for bact_norm.",
      call. = FALSE
    )
  }
  species_taxonomy <- species_taxonomy[
    order(species_taxonomy$bact_norm),
    ,
    drop = FALSE
  ]
  rownames(species_taxonomy) <- NULL

  config_env <- new.env(parent = baseenv())
  sys.source(
    file.path(project_root, "config", "pipeline.R"),
    envir = config_env
  )
  if (
    !exists("orchidee_config", envir = config_env, inherits = FALSE) ||
      is.null(config_env$orchidee_config$ratb$indicator_sample_types)
  ) {
    stop(
      "config/pipeline.R must define ratb$indicator_sample_types.",
      call. = FALSE
    )
  }
  current_sample_types <- unique(orchidee_handoff_trim_or_na(
    config_env$orchidee_config$ratb$indicator_sample_types
  ))
  current_sample_types <- current_sample_types[!is.na(current_sample_types)]

  ta_reference <- orchidee_handoff_read_table(file.path(
    project_root,
    "ref",
    "consores",
    "codes_ta.csv"
  ))
  missing_ta_columns <- setdiff(
    c("CODE_TA", "LIBELLE_TA"),
    names(ta_reference)
  )
  if (length(missing_ta_columns) > 0L) {
    stop(
      "ref/consores/codes_ta.csv is missing columns: ",
      paste(missing_ta_columns, collapse = ", "),
      call. = FALSE
    )
  }
  ta_reference <- ta_reference[c("CODE_TA", "LIBELLE_TA")]
  ta_reference$CODE_TA <- ratb_normalize_code_ta(ta_reference$CODE_TA)
  ta_reference$LIBELLE_TA <- orchidee_handoff_trim_or_na(
    ta_reference$LIBELLE_TA
  )
  ta_reference$included_in_spares_current <-
    ta_reference$CODE_TA %in% context$eligible_ta_codes
  ta_order <- order(
    suppressWarnings(as.integer(ta_reference$CODE_TA)),
    ta_reference$CODE_TA
  )
  ta_reference <- ta_reference[ta_order, , drop = FALSE]
  rownames(ta_reference) <- NULL

  de_reference <- orchidee_handoff_read_table(file.path(
    project_root,
    "ref",
    "consores",
    "codes_de.csv"
  ))
  missing_de_columns <- setdiff(
    c("DOMAINE", "CODE_DE", "LIBELLE_DE"),
    names(de_reference)
  )
  if (length(missing_de_columns) > 0L) {
    stop(
      "ref/consores/codes_de.csv is missing columns: ",
      paste(missing_de_columns, collapse = ", "),
      call. = FALSE
    )
  }
  de_reference <- de_reference[c("DOMAINE", "CODE_DE", "LIBELLE_DE")]
  de_reference$DOMAINE <- orchidee_handoff_trim_or_na(
    de_reference$DOMAINE
  )
  de_reference$CODE_DE <- ratb_normalize_code_de(de_reference$CODE_DE)
  de_reference$LIBELLE_DE <- orchidee_handoff_trim_or_na(
    de_reference$LIBELLE_DE
  )
  de_reference$included_in_spares_current <-
    de_reference$DOMAINE %in% context$eligible_de_domains
  de_order <- order(
    de_reference$DOMAINE,
    suppressWarnings(as.integer(de_reference$CODE_DE)),
    de_reference$CODE_DE
  )
  de_reference <- de_reference[de_order, , drop = FALSE]
  rownames(de_reference) <- NULL

  list(
    supported_atb_norm = data.frame(
      atb_norm = contract$sir_wide$atb_cols,
      stringsAsFactors = FALSE
    ),
    recognized_bact_norm = species_taxonomy,
    current_indicator_naturepvt_norm = data.frame(
      naturepvt_norm = current_sample_types,
      stringsAsFactors = FALSE
    ),
    reference_code_ta = ta_reference,
    reference_code_de = de_reference,
    allowed_denominator_profiles = ratb_denominator_profile_registry()
  )
}

orchidee_handoff_integerish_vector <- function(x, col_name) {
  if (is.factor(x)) x <- as.character(x)

  if (is.numeric(x)) {
    bad <- is.na(x) | !is.finite(x) |
      abs(x - round(x)) >= sqrt(.Machine$double.eps)
    if (any(bad)) {
      stop(col_name, " must contain non-missing integer-like values.", call. = FALSE)
    }
    return(as.integer(x))
  }

  if (is.character(x)) {
    x <- orchidee_handoff_trim_or_na(x)
    bad <- is.na(x) | !grepl("^-?[0-9]+$", x)
    if (any(bad)) {
      stop(col_name, " must contain non-missing integer-like values.", call. = FALSE)
    }
    return(as.integer(x))
  }

  stop(col_name, " must be numeric/integer-like or character integer values.", call. = FALSE)
}

orchidee_handoff_logical_vector <- function(x, col_name) {
  if (is.logical(x)) {
    if (any(is.na(x))) {
      stop(col_name, " must not contain missing values.", call. = FALSE)
    }
    return(x)
  }

  if (is.numeric(x)) {
    bad <- is.na(x) | !x %in% c(0, 1)
    if (any(bad)) {
      stop(col_name, " must contain TRUE/FALSE or 1/0 values.", call. = FALSE)
    }
    return(x == 1)
  }

  x_chr <- orchidee_handoff_ascii_lower(x)
  out <- dplyr::case_when(
    x_chr %in% c("true", "t", "1", "yes", "y", "oui", "o") ~ TRUE,
    x_chr %in% c("false", "f", "0", "no", "n", "non") ~ FALSE,
    TRUE ~ NA
  )
  if (any(is.na(out))) {
    stop(col_name, " must contain TRUE/FALSE or 1/0 values.", call. = FALSE)
  }
  out
}

orchidee_handoff_domain_key <- function(x) {
  x <- orchidee_handoff_trim_or_na(x)
  x <- iconv(x, from = "", to = "ASCII//TRANSLIT")
  toupper(x)
}

orchidee_handoff_normalize_included_de_domain <- function(x) {
  orchidee_handoff_require_functions("ratb_included_ta_de_domains")
  included_domains <- ratb_included_ta_de_domains()
  domain_key <- orchidee_handoff_domain_key(x)
  included_key <- orchidee_handoff_domain_key(included_domains)
  matched <- included_domains[match(domain_key, included_key)]
  ifelse(is.na(matched), orchidee_handoff_trim_or_na(x), matched)
}

orchidee_handoff_ascii_lower <- function(x) {
  x <- orchidee_handoff_trim_or_na(x)
  x <- iconv(x, from = "", to = "ASCII//TRANSLIT")
  tolower(x)
}

# What a valid time of day looks like is written once, because two callers need
# it: HEUREPRELEV, and the time-of-day suffix tolerated on a date. Stating it
# twice let the two disagree. The date suffix range-checked its groups while
# HEUREPRELEV counted digits and left the ranges to strptime, which accepts a
# leap second and hour 24, so "09:15:60" was refused inside a date and accepted
# as a time of day, where it silently became 09:16.
# The fraction stays inside the seconds group for both callers, so neither
# accepts a fractional minute.
orchidee_handoff_clock_pattern <- function(seconds_required) {
  seconds <- ":[0-5][0-9](\\.[0-9]+)?"
  paste0(
    "([01]?[0-9]|2[0-3]):[0-5][0-9]",
    if (seconds_required) seconds else paste0("(", seconds, ")?")
  )
}

# Each accepted text form is matched against an anchored shape before it is
# parsed. The shapes are disjoint -- a four-digit leading group means the year
# comes first -- so a value is read the same way whatever its neighbours look
# like. This replaces as.Date(x) with no format, which derived one format for
# the whole column from R's tryFormats and made the documented DD/MM/YYYY
# silently wrong: strptime ignores trailing characters, so %Y/%m/%d matched
# "12/03/2024" as year 12 month 03 day 20 without an NA, and the %d/%m/%Y branch
# that was meant to handle it was never reached. A uniformly French column built
# a bundle dated in year 12 rather than failing.
orchidee_handoff_date_shapes <- function() {
  # A trailing time of day is allowed and ignored: an HDW export commonly carries
  # a timestamp in the date column, the time of day belongs to HEUREPRELEV, and
  # dropping it is unambiguous. Anything else after the date is not. Nothing
  # downstream validates this suffix -- as.Date() ignores it whole -- so the
  # hour, minute and second ranges are checked here rather than merely counted,
  # otherwise "2024-03-12 25:99:99" would be accepted as a date.
  # The fraction belongs to the seconds, not to the time: outside that group it
  # would also accept a fractional minute, "09:15.123", which is not a form
  # anyone writes and not what this tolerates. That is a property of the shared
  # clock shape now, so HEUREPRELEV cannot lose it either.
  time_of_day <- paste0(
    "([ T]",
    orchidee_handoff_clock_pattern(seconds_required = FALSE),
    ")?"
  )
  list(
    list(
      pattern = paste0("^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}", time_of_day, "$"),
      format = "%Y-%m-%d"
    ),
    list(
      pattern = paste0("^[0-9]{4}/[0-9]{1,2}/[0-9]{1,2}", time_of_day, "$"),
      format = "%Y/%m/%d"
    ),
    list(
      pattern = paste0("^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}", time_of_day, "$"),
      format = "%d/%m/%Y"
    )
  )
}

# A Date is a day number, and R lets that number carry a fraction. Neither
# format() nor as.character() shows it, so half a day travels to the bundle
# behind an ordinary-looking date: 19815 and 19815.5 both print as 2024-04-02
# while remaining two distinct values in the row grain. No documented delivery
# produces one -- parsing text always yields a whole day -- so it is refused
# rather than rounded away, which would silently change what the site delivered.
# The comparison is exact because a tolerance leaves a hole its own size, and
# every value in that hole is the case being refused: 19815 + 1e-9 is a double
# of its own, prints as 2024-04-02, and splits the grain exactly as 19815.5
# does. Nothing legitimate lands there -- a day number arrives as written, not
# as the result of arithmetic that could leave a rounding residue.
orchidee_handoff_non_whole_days <- function(days) {
  is.finite(days) & days != trunc(days)
}

# Returns the parsed values alongside the elements that could not be read, so a
# caller reporting on a column does not have to stop at the first bad value.
orchidee_handoff_parse_date_values <- function(x) {
  # A typed input skips the text shapes entirely, so it is checked on its own
  # terms rather than trusted for arriving pre-parsed: an .rds is as much a site
  # handoff as a CSV, and an infinite day number is not a date.
  if (inherits(x, "Date")) {
    days <- unclass(x)
    return(list(
      values = x,
      bad = !is.finite(days) | orchidee_handoff_non_whole_days(days)
    ))
  }
  if (is.factor(x)) x <- as.character(x)
  if (is.numeric(x)) {
    bad <- !is.finite(x) | orchidee_handoff_non_whole_days(x)
    values <- rep(as.Date(NA), length(x))
    values[!bad] <- as.Date(x[!bad], origin = "1970-01-01")
    return(list(values = values, bad = bad | is.na(values)))
  }
  x_chr <- orchidee_handoff_trim_or_na(x)
  values <- rep(as.Date(NA), length(x_chr))
  for (shape in orchidee_handoff_date_shapes()) {
    pending <- is.na(values) & !is.na(x_chr) & grepl(shape$pattern, x_chr)
    if (!any(pending)) {
      next
    }
    values[pending] <- suppressWarnings(
      as.Date(x_chr[pending], format = shape$format)
    )
  }
  list(values = values, bad = is.na(values))
}

orchidee_handoff_parse_date <- function(x, col_name = "DATEPRELEV") {
  parsed <- orchidee_handoff_parse_date_values(x)
  if (any(parsed$bad)) {
    stop(
      col_name, " must contain non-missing dates on whole days.",
      call. = FALSE
    )
  }
  parsed$values
}

# Times are anchored for the same reason as dates: strptime ignores trailing
# characters, so an unanchored "%H:%M:%S" accepted "09:15:00 (approx)" as 09:15
# and dropped the rest without a word. The accepted forms are the two the
# contract documents.
# A time of day has a domain, and only the text shapes enforced it: an .rds
# carrying a difftime was accepted whatever it held, so a negative or a 90000
# would pass here and survive validation downstream, which checks the class and
# not the interval. A missing time stays acceptable -- the column is optional.
orchidee_handoff_time_of_day_out_of_range <- function(seconds) {
  !is.na(seconds) & (!is.finite(seconds) | seconds < 0 | seconds >= 86400)
}

orchidee_handoff_parse_time_values <- function(x) {
  if (inherits(x, "difftime")) {
    bad <- orchidee_handoff_time_of_day_out_of_range(
      as.numeric(x, units = "secs")
    )
    x[bad] <- NA_real_
    return(list(values = x, bad = bad))
  }
  if (missing(x) || is.null(x)) {
    return(list(
      values = as.difftime(rep(NA_real_, 0L), units = "secs"),
      bad = logical(0)
    ))
  }
  if (is.factor(x)) x <- as.character(x)
  if (is.numeric(x)) {
    bad <- orchidee_handoff_time_of_day_out_of_range(x)
    x[bad] <- NA_real_
    return(list(values = as.difftime(x, units = "secs"), bad = bad))
  }

  x_chr <- orchidee_handoff_trim_or_na(x)
  values <- as.difftime(rep(NA_real_, length(x_chr)), units = "secs")
  has_value <- !is.na(x_chr)
  padded <- x_chr
  hh_mm <- has_value & grepl("^[0-9]{1,2}:[0-9]{2}$", padded)
  padded[hh_mm] <- paste0(padded[hh_mm], ":00")
  # Fractional seconds are allowed and ignored for the same reason as a trailing
  # time of day on a date: unambiguous, and previously accepted. The ranges are
  # part of the shape rather than left to strptime, which reads a leap second and
  # hour 24 as the following minute and the following midnight -- 86400 seconds,
  # the very value the difftime branch above refuses. Counting digits here made
  # the same clock legal or illegal depending on whether the site sent text or a
  # difftime, and on whether it sent it in HEUREPRELEV or after a date.
  parseable <- has_value &
    grepl(
      paste0("^", orchidee_handoff_clock_pattern(seconds_required = TRUE), "$"),
      padded
    )
  if (any(parseable)) {
    values[parseable] <- suppressWarnings(
      as.difftime(padded[parseable], format = "%H:%M:%S")
    )
  }
  list(values = values, bad = has_value & is.na(values))
}

orchidee_handoff_parse_time <- function(x, col_name = "HEUREPRELEV") {
  parsed <- orchidee_handoff_parse_time_values(x)
  if (any(parsed$bad)) {
    stop(col_name, " must use HH:MM or HH:MM:SS when provided.", call. = FALSE)
  }
  parsed$values
}

orchidee_handoff_normalize_sir <- function(x) {
  x <- toupper(orchidee_handoff_trim_or_na(x))
  dplyr::case_when(
    x %in% c("S", "SFP", "---S") ~ "S",
    x %in% c("R", "---R") ~ "R",
    x %in% c("I", "ZIT") ~ "ZIT",
    x %in% c("NC", "NA", "N/A") | is.na(x) ~ NA_character_,
    TRUE ~ x
  )
}

orchidee_handoff_prepare_mapping <- function(
    mapping,
    local_col,
    canonical_col,
    label,
    allow_missing_canonical = FALSE
  ) {
  if (!is.data.frame(mapping)) {
    stop(label, " must be a data frame.", call. = FALSE)
  }
  required_cols <- c(local_col, canonical_col)
  missing_cols <- setdiff(required_cols, names(mapping))
  if (length(missing_cols) > 0L) {
    stop(
      label, " is missing required columns: ",
      paste(missing_cols, collapse = ", "),
      call. = FALSE
    )
  }

  out <- data.frame(
    local_key = orchidee_handoff_trim_or_na(mapping[[local_col]]),
    canonical_value = orchidee_handoff_trim_or_na(mapping[[canonical_col]]),
    stringsAsFactors = FALSE
  )
  out <- out[!is.na(out$local_key), , drop = FALSE]
  if (!isTRUE(allow_missing_canonical) && any(is.na(out$canonical_value))) {
    stop(label, " contains missing canonical values.", call. = FALSE)
  }
  duplicated_keys <- unique(out$local_key[duplicated(out$local_key)])
  if (length(duplicated_keys) > 0L) {
    conflicting_keys <- duplicated_keys[vapply(duplicated_keys, function(key) {
      values <- out$canonical_value[out$local_key == key]
      values_for_compare <- ifelse(is.na(values), "<missing>", values)
      length(unique(values_for_compare)) > 1L
    }, logical(1))]
    if (length(conflicting_keys) > 0L) {
      stop(
        label, " contains duplicate local keys with conflicting canonical values: ",
        paste(utils::head(conflicting_keys, 10L), collapse = ", "),
        if (length(conflicting_keys) > 10L) ", ..." else "",
        call. = FALSE
      )
    }
    out <- out[!duplicated(out$local_key), , drop = FALSE]
  }
  out
}

orchidee_handoff_map_values <- function(
    x,
    mapping,
    label,
    allow_missing_canonical = FALSE
  ) {
  x_key <- orchidee_handoff_trim_or_na(x)
  match_idx <- match(x_key, mapping$local_key)
  missing_map <- is.na(match_idx) & !is.na(x_key)
  if (any(missing_map)) {
    missing_values <- sort(unique(x_key[missing_map]))
    stop(
      label, " has unmapped values: ",
      paste(utils::head(missing_values, 10L), collapse = ", "),
      if (length(missing_values) > 10L) ", ..." else "",
      call. = FALSE
    )
  }

  mapped <- mapping$canonical_value[match_idx]
  if (!isTRUE(allow_missing_canonical)) {
    missing_canonical <- is.na(mapped) & !is.na(x_key)
    if (any(missing_canonical)) {
      missing_values <- sort(unique(x_key[missing_canonical]))
      stop(
        label, " maps to missing canonical values: ",
        paste(utils::head(missing_values, 10L), collapse = ", "),
        if (length(missing_values) > 10L) ", ..." else "",
        call. = FALSE
      )
    }
  }

  mapped
}

# Screening exclusion follows the most specific usable document identity.
# Complete PATID + ELTID groups use PATID + EVTID + ELTID. If any row in a
# PATID + ELTID group lacks EVTID, that group conservatively falls back to
# PATID + ELTID. ELTID alone is never propagated across patients. Rows without
# a usable PATID + ELTID pair receive NA and never carry screening.
orchidee_handoff_document_occurrence_key <- function(PATID, EVTID, ELTID) {
  document_key <- rep(NA_character_, length(PATID))
  usable <- !is.na(PATID) & !is.na(ELTID)
  usable_rows <- which(usable)
  if (length(usable_rows) == 0L) {
    return(document_key)
  }

  patient_sample_key <- paste(
    PATID[usable_rows],
    ELTID[usable_rows],
    sep = "\r"
  )
  fallback_to_patient_sample <- ave(
    is.na(EVTID[usable_rows]),
    patient_sample_key,
    FUN = any
  )
  document_key[usable_rows] <- ifelse(
    fallback_to_patient_sample,
    paste(
      "patient_sample",
      PATID[usable_rows],
      ELTID[usable_rows],
      sep = "\r"
    ),
    paste(
      "event_sample",
      PATID[usable_rows],
      EVTID[usable_rows],
      ELTID[usable_rows],
      sep = "\r"
    )
  )
  document_key
}

orchidee_handoff_collapse_phenotype <- function(x, allowed, col_name) {
  orchidee_handoff_require_functions(c(
    "normalize_phenotype_status",
    "collapse_phenotype_status"
  ))
  status <- normalize_phenotype_status(x)
  bad <- is.na(status) & !is.na(orchidee_handoff_trim_or_na(x))
  if (any(bad)) {
    bad_vals <- sort(unique(as.character(x)[bad]))
    stop(
      col_name, " contains unsupported phenotype statuses: ",
      paste(utils::head(bad_vals, 10L), collapse = ", "),
      if (length(bad_vals) > 10L) ", ..." else "",
      call. = FALSE
    )
  }
  out <- collapse_phenotype_status(status)
  if (!out %in% allowed) {
    stop(col_name, " collapsed to unsupported value: ", out, call. = FALSE)
  }
  out
}

orchidee_handoff_build_sir_wide_from_microbiology <- function(
    microbiology_observations,
    bacteria_mapping,
    sample_type_mapping,
    antibiotic_mapping
  ) {
  orchidee_handoff_require_functions("phenotype_status_to_flag")
  if (!is.data.frame(microbiology_observations)) {
    stop("microbiology_observations must be a data frame.", call. = FALSE)
  }
  contract <- orchidee_external_contract_v3()
  site_spec <- orchidee_handoff_site_input_spec()
  microbiology_spec <- site_spec$microbiology_observations

  required_obs_cols <- microbiology_spec$required_columns
  missing_obs_cols <- setdiff(required_obs_cols, names(microbiology_observations))
  if (length(missing_obs_cols) > 0L) {
    stop(
      "microbiology_observations is missing required columns: ",
      paste(missing_obs_cols, collapse = ", "),
      call. = FALSE
    )
  }
  diagnostic_cols <-
    microbiology_spec$required_one_of$diagnostic_scope
  diagnostic_present <- diagnostic_cols[
    diagnostic_cols %in% names(microbiology_observations)
  ]
  if (length(diagnostic_present) != 1L) {
    stop(
      "microbiology_observations must contain exactly one diagnostic-scope ",
      "column: ",
      paste(diagnostic_cols, collapse = ", "),
      call. = FALSE
    )
  }
  diagnostic_col <- diagnostic_present[[1L]]

  bacteria_columns <- site_spec$bacteria_mapping$required_columns
  sample_type_columns <- site_spec$sample_type_mapping$required_columns
  antibiotic_columns <- site_spec$antibiotic_mapping$required_columns
  bacteria_map <- orchidee_handoff_prepare_mapping(
    bacteria_mapping,
    bacteria_columns[[1L]],
    bacteria_columns[[2L]],
    "bacteria_mapping"
  )
  sample_type_map <- orchidee_handoff_prepare_mapping(
    sample_type_mapping,
    sample_type_columns[[1L]],
    sample_type_columns[[2L]],
    "sample_type_mapping",
    allow_missing_canonical = TRUE
  )
  antibiotic_map <- orchidee_handoff_prepare_mapping(
    antibiotic_mapping,
    antibiotic_columns[[1L]],
    antibiotic_columns[[2L]],
    "antibiotic_mapping"
  )

  obs <- microbiology_observations
  diagnostic_scope <- orchidee_handoff_logical_vector(
    obs[[diagnostic_col]],
    paste0("microbiology_observations$", diagnostic_col)
  )
  obs$PATID <- orchidee_handoff_trim_or_na(obs$PATID)
  obs$EVTID <- if ("EVTID" %in% names(obs)) {
    orchidee_handoff_trim_or_na(obs$EVTID)
  } else {
    rep(NA_character_, nrow(obs))
  }
  obs$ELTID <- orchidee_handoff_trim_or_na(obs$ELTID)

  document_key <- orchidee_handoff_document_occurrence_key(
    obs$PATID,
    obs$EVTID,
    obs$ELTID
  )
  propagate_screening <- rep(FALSE, nrow(obs))
  usable_key <- !is.na(document_key)
  if (any(usable_key)) {
    screening_document_keys <- unique(
      document_key[usable_key & !diagnostic_scope]
    )
    propagate_screening[usable_key] <-
      document_key[usable_key] %in% screening_document_keys
  }

  drop_mask <- (!diagnostic_scope) | propagate_screening
  obs <- obs[!drop_mask, , drop = FALSE]
  if (nrow(obs) == 0L) {
    stop(
      "No rows remain after excluding screening document occurrences from ",
      "microbiology_observations (", diagnostic_col, " exclusion).",
      call. = FALSE
    )
  }

  obs$DATEPRELEV <- orchidee_handoff_parse_date(obs$DATEPRELEV)
  obs$HEUREPRELEV <- if ("HEUREPRELEV" %in% names(obs)) {
    orchidee_handoff_parse_time(obs$HEUREPRELEV)
  } else {
    as.difftime(rep(NA_real_, nrow(obs)), units = "secs")
  }
  obs$souche_id <- if ("souche_id" %in% names(obs)) {
    orchidee_handoff_trim_or_na(obs$souche_id)
  } else if ("isolate_local_id" %in% names(obs)) {
    orchidee_handoff_trim_or_na(obs$isolate_local_id)
  } else {
    rep(NA_character_, nrow(obs))
  }
  obs$SEJUF <- orchidee_handoff_trim_or_na(obs$SEJUF)
  obs$bact_norm <- orchidee_handoff_map_values(
    obs$bacteria_local,
    bacteria_map,
    "microbiology_observations$bacteria_local"
  )
  obs$naturepvt_norm <- orchidee_handoff_ascii_lower(orchidee_handoff_map_values(
    obs$sample_type_local,
    sample_type_map,
    "microbiology_observations$sample_type_local",
    allow_missing_canonical = TRUE
  ))
  obs$atb_norm <- orchidee_handoff_map_values(
    obs$antibiotic_local,
    antibiotic_map,
    "microbiology_observations$antibiotic_local"
  )
  obs$sir_result <- orchidee_handoff_normalize_sir(obs$sir_result)

  missing_souche <- is.na(obs$souche_id)
  if (any(missing_souche)) {
    sample_type_for_souche <- dplyr::coalesce(
      obs$naturepvt_norm[missing_souche],
      "missing_sample_type"
    )
    obs$souche_id[missing_souche] <- paste(
      "derived",
      sample_type_for_souche,
      obs$bact_norm[missing_souche],
      sep = "__"
    )
  }

  non_missing_key_cols <- c("PATID", "ELTID", "DATEPRELEV", "souche_id", "bact_norm")
  key_na <- vapply(non_missing_key_cols, function(col) any(is.na(obs[[col]])), logical(1))
  if (any(key_na)) {
    stop(
      "microbiology_observations required non-missing fields contain NA: ",
      paste(non_missing_key_cols[key_na], collapse = ", "),
      call. = FALSE
    )
  }

  supported_atb <- contract$sir_wide$atb_cols
  unsupported_atb <- setdiff(unique(obs$atb_norm[!is.na(obs$atb_norm)]), supported_atb)
  if (length(unsupported_atb) > 0L) {
    stop(
      "antibiotic_mapping maps to unsupported ORCHIDEE ATB columns: ",
      paste(unsupported_atb, collapse = ", "),
      ". See mapping_reference/supported_atb_norm.csv generated by ",
      "build_site.ps1 -EmitTemplates.",
      call. = FALSE
    )
  }
  unsupported_sir <- setdiff(unique(obs$sir_result[!is.na(obs$sir_result)]), contract$sir_wide$allowed_atb_values)
  if (length(unsupported_sir) > 0L) {
    stop(
      "microbiology_observations$sir_result contains unsupported values: ",
      paste(unsupported_sir, collapse = ", "),
      call. = FALSE
    )
  }

  row_key_cols <- contract$sir_wide$row_grain_key
  row_key <- do.call(paste, c(obs[row_key_cols], sep = "\r"))
  row_key_levels <- unique(row_key)
  row_id <- match(row_key, row_key_levels)
  row_groups <- unname(split(
    seq_len(nrow(obs)),
    factor(row_id, levels = seq_along(row_key_levels))
  ))

  for (attr_col in c("SEJUF", "HEUREPRELEV")) {
    attr_conflict <- vapply(row_groups, function(idx) {
      vals <- obs[[attr_col]][idx]
      vals <- vals[!is.na(vals)]
      length(unique(vals)) > 1L
    }, logical(1))
    if (any(attr_conflict)) {
      stop(
        "microbiology_observations has conflicting ", attr_col,
        " values within the same ORCHIDEE row key.",
        call. = FALSE
      )
    }
  }

  row_base_idx <- match(row_key_levels, row_key)
  sir_wide <- obs[row_base_idx, c(
    "PATID", "EVTID", "ELTID", "DATEPRELEV", "HEUREPRELEV", "souche_id",
    "naturepvt_norm", "bact_norm", "SEJUF"
  ), drop = FALSE]
  sir_wide$SEJUF <- vapply(row_groups, function(idx) {
    vals <- obs$SEJUF[idx]
    vals <- vals[!is.na(vals)]
    if (length(vals) == 0L) NA_character_ else vals[[1L]]
  }, character(1))
  sir_wide$HEUREPRELEV <- as.difftime(vapply(row_groups, function(idx) {
    vals <- obs$HEUREPRELEV[idx]
    vals <- vals[!is.na(vals)]
    if (length(vals) == 0L) NA_real_ else as.numeric(vals[[1L]], units = "secs")
  }, numeric(1)), units = "secs")

  sir_matrix <- matrix(
    NA_character_,
    nrow = nrow(sir_wide),
    ncol = length(supported_atb),
    dimnames = list(NULL, supported_atb)
  )
  result_rows <- which(!is.na(obs$atb_norm) & !is.na(obs$sir_result))
  if (length(result_rows) > 0L) {
    result_key <- paste(row_id[result_rows], obs$atb_norm[result_rows], sep = "\r")
    split_rows <- split(result_rows, result_key)
    for (idx in split_rows) {
      # Apply the shared handoff pivot rule: keep the last non-missing value.
      vals <- obs$sir_result[idx]
      vals <- vals[!is.na(vals)]
      if (length(vals) > 0L) {
        sir_matrix[row_id[idx[[1L]]], obs$atb_norm[idx[[1L]]]] <- vals[[length(vals)]]
      }
    }
  }
  sir_wide <- cbind(sir_wide, as.data.frame(sir_matrix, stringsAsFactors = FALSE))

  blse_col <- c("blse_status_row", "blse_status")
  blse_col <- blse_col[blse_col %in% names(obs)][1]
  carba_col <- c("carbapenemase_status_row", "carbapenemase_status")
  carba_col <- carba_col[carba_col %in% names(obs)][1]
  phenotype_allowed <- contract$sir_wide$phenotype_status_allowed

  blse_status <- rep("no_signal", nrow(sir_wide))
  carba_status <- rep("no_signal", nrow(sir_wide))
  for (i in seq_along(row_groups)) {
    idx <- row_groups[[i]]
    if (!is.na(blse_col)) {
      blse_status[[i]] <- orchidee_handoff_collapse_phenotype(
        obs[[blse_col]][idx],
        phenotype_allowed$blse_status_row,
        blse_col
      )
    }
    if (!is.na(carba_col)) {
      carba_status[[i]] <- orchidee_handoff_collapse_phenotype(
        obs[[carba_col]][idx],
        phenotype_allowed$carbapenemase_status_row,
        carba_col
      )
    }
  }

  sir_wide$blse_status_row <- blse_status
  sir_wide$carbapenemase_status_row <- carba_status
  sir_wide$blse_flag <- phenotype_status_to_flag(sir_wide$blse_status_row)
  sir_wide$carbapenemase_flag <- phenotype_status_to_flag(sir_wide$carbapenemase_status_row)
  tested_matrix <- as.data.frame(
    lapply(sir_wide[supported_atb], function(x) x %in% c("S", "R")),
    stringsAsFactors = FALSE
  )
  sir_wide$nb_resultats <- rowSums(tested_matrix, na.rm = TRUE)

  preferred_order <- c(
    "PATID", "EVTID", "ELTID", "DATEPRELEV", "HEUREPRELEV", "souche_id",
    "nb_resultats", "naturepvt_norm", "bact_norm", "SEJUF",
    supported_atb,
    "blse_status_row", "carbapenemase_status_row", "blse_flag", "carbapenemase_flag"
  )
  sir_wide <- sir_wide[, preferred_order, drop = FALSE]
  row.names(sir_wide) <- NULL
  sir_wide
}

orchidee_handoff_build_sir_wide_meta <- function(
    sir_wide,
    contract = orchidee_external_contract_v2(),
    artifact_version = 4L,
    created_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    source_label = "external_handoff"
  ) {
  stopifnot(is.data.frame(sir_wide), is.list(contract))
  if (!"ELTID" %in% names(sir_wide)) {
    stop("sir_wide must contain ELTID to derive metadata.", call. = FALSE)
  }

  sir_spec <- contract$sir_wide
  supported_atb_cols <- sir_spec$atb_cols
  observed_atb_cols <- supported_atb_cols[vapply(
    supported_atb_cols,
    function(col) any(sir_wide[[col]] %in% sir_spec$allowed_atb_values, na.rm = TRUE),
    logical(1)
  )]

  metadata <- list(
    artifact_version = as.integer(artifact_version),
    created_at = as.character(created_at),
    sir_wide_n_rows = nrow(sir_wide),
    sir_wide_n_eltid = length(unique(sir_wide$ELTID)),
    atb_cols = observed_atb_cols,
    supported_atb_cols = supported_atb_cols,
    phenotype_status_cols = sir_spec$phenotype_status_cols,
    phenotype_flag_cols = sir_spec$phenotype_flag_cols,
    filtre_atb = supported_atb_cols,
    handoff_source = source_label,
    handoff_generated_by = "R/external_handoff_helpers.R"
  )

  if (!is.null(sir_spec$required_meta_values)) {
    metadata[names(sir_spec$required_meta_values)] <-
      sir_spec$required_meta_values
  }

  metadata
}

orchidee_handoff_build_sample_scope_reference <- function(unit_mapping) {
  orchidee_handoff_require_functions(c(
    "ratb_normalize_code_ta",
    "ratb_normalize_code_de",
    "ratb_included_ta_de_domains"
  ))
  if (!is.data.frame(unit_mapping)) {
    stop("unit_mapping must be a data frame.", call. = FALSE)
  }

  required_unit_cols <- orchidee_handoff_site_input_spec()$unit_mapping$required_columns
  missing_unit_cols <- setdiff(required_unit_cols, names(unit_mapping))
  if (length(missing_unit_cols) > 0L) {
    stop(
      "unit_mapping is missing required columns: ",
      paste(missing_unit_cols, collapse = ", "),
      call. = FALSE
    )
  }

  unit <- data.frame(
    SEJUF = orchidee_handoff_trim_or_na(unit_mapping$SEJUF),
    CODE_TA = ratb_normalize_code_ta(unit_mapping$CODE_TA),
    stringsAsFactors = FALSE
  )

  if (any(is.na(unit$SEJUF))) {
    stop("unit_mapping$SEJUF contains missing values.", call. = FALSE)
  }
  if (any(duplicated(unit$SEJUF))) {
    duplicate_sejuf <- unique(unit$SEJUF[duplicated(unit$SEJUF)])
    stop(
      "unit_mapping contains duplicate SEJUF values: ",
      paste(utils::head(duplicate_sejuf, 10L), collapse = ", "),
      if (length(duplicate_sejuf) > 10L) ", ..." else "",
      call. = FALSE
    )
  }

  unit$CODE_DE_norm <- ratb_normalize_code_de(unit_mapping$CODE_DE)
  unit$de_domain_ref <- orchidee_handoff_trim_or_na(
    unit_mapping$de_domain_ref
  )
  unit$de_domain_ref <- orchidee_handoff_normalize_included_de_domain(
    unit$de_domain_ref
  )

  if (all(is.na(unit$de_domain_ref))) {
    stop(
      "No de_domain_ref information available in unit_mapping.",
      call. = FALSE
    )
  }

  included_domains <- ratb_included_ta_de_domains()
  uf_ta_eligible <- unit$CODE_TA %in% c("03", "20")
  uf_de_mapped <- !is.na(unit$de_domain_ref)
  uf_de_eligible <- unit$de_domain_ref %in% included_domains
  uf_is_eligible <- uf_ta_eligible & uf_de_eligible

  status <- ifelse(
    uf_is_eligible,
    "eligible_ta_de",
    ifelse(
      is.na(unit$CODE_TA),
      "review_unmapped_uf",
      ifelse(
        uf_ta_eligible & !uf_de_mapped,
        "review_unmapped_de",
        ifelse(uf_ta_eligible & !uf_de_eligible, "excluded_de_domain", "excluded_ta")
      )
    )
  )

  reason <- ifelse(
    uf_is_eligible,
    "eligible_ta_de",
    ifelse(
      is.na(unit$CODE_TA),
      "uf_absent_from_consores_structure",
      ifelse(
        uf_ta_eligible & !uf_de_mapped,
        "ta_03_20_unmapped_de",
        ifelse(
          uf_ta_eligible & !uf_de_eligible,
          "ta_03_20_de_domain_not_included",
          "ta_not_03_20"
        )
      )
    )
  )

  sample_scope_reference <- data.frame(
    SEJUF = unit$SEJUF,
    sample_CODE_TA = unit$CODE_TA,
    sample_CODE_DE = unit$CODE_DE_norm,
    sample_de_domain_ref = unit$de_domain_ref,
    sample_uf_is_eligible_by_ta_de = uf_is_eligible,
    sample_uf_ta_de_status = status,
    sample_uf_ta_de_reason = reason,
    stringsAsFactors = FALSE
  )
  contract <- orchidee_external_contract_v3()
  required_columns <- contract$sample_scope_reference$required_columns
  sample_scope_reference[required_columns]
}

orchidee_handoff_build_denominator_bundle <- function(
    incidence_exposure_by_year_um_uf_ta_de_profile
  ) {
  orchidee_handoff_require_functions(c(
    "ratb_normalize_code_ta",
    "ratb_normalize_code_de"
  ))
  exposure <- incidence_exposure_by_year_um_uf_ta_de_profile
  if (!is.data.frame(exposure)) {
    stop(
      "incidence_exposure_by_year_um_uf_ta_de_profile must be a data frame.",
      call. = FALSE
    )
  }
  spec <- orchidee_handoff_site_input_spec()
  denominator_spec <-
    spec$incidence_exposure_by_year_um_uf_ta_de_profile
  required_cols <- denominator_spec$required_columns
  missing_cols <- setdiff(required_cols, names(exposure))
  if (length(missing_cols) > 0L) {
    stop(
      "incidence_exposure_by_year_um_uf_ta_de_profile is missing required ",
      "columns: ",
      paste(missing_cols, collapse = ", "),
      call. = FALSE
    )
  }

  canonical_exposure <- data.frame(
    calendar_year = orchidee_handoff_integerish_vector(
      exposure$calendar_year,
      "incidence_exposure_by_year_um_uf_ta_de_profile$calendar_year"
    ),
    SEJUM = orchidee_handoff_trim_or_na(exposure$SEJUM),
    SEJUF = orchidee_handoff_trim_or_na(exposure$SEJUF),
    CODE_TA = ratb_normalize_code_ta(exposure$CODE_TA),
    CODE_DE = ratb_normalize_code_de(exposure$CODE_DE),
    de_domain_ref = orchidee_handoff_normalize_included_de_domain(
      exposure$de_domain_ref
    ),
    denominator_profile_id = orchidee_handoff_trim_or_na(
      exposure$denominator_profile_id
    ),
    exposure_value = orchidee_handoff_integerish_vector(
      exposure$exposure_value,
      "incidence_exposure_by_year_um_uf_ta_de_profile$exposure_value"
    ),
    exposure_unit = orchidee_handoff_trim_or_na(exposure$exposure_unit),
    stringsAsFactors = FALSE
  )
  missing_dimension <- vapply(
    canonical_exposure[required_cols],
    function(x) any(is.na(x)),
    logical(1)
  )
  if (any(missing_dimension)) {
    stop(
      "incidence_exposure_by_year_um_uf_ta_de_profile must not contain ",
      "missing values in: ",
      paste(names(missing_dimension)[missing_dimension], collapse = ", "),
      call. = FALSE
    )
  }
  if (any(canonical_exposure$exposure_value < 0L)) {
    stop(
      "incidence_exposure_by_year_um_uf_ta_de_profile$exposure_value must ",
      "be non-negative.",
      call. = FALSE
    )
  }
  profiles <- ratb_denominator_profile_registry()
  profile_match <- match(
    canonical_exposure$denominator_profile_id,
    profiles$denominator_profile_id
  )
  invalid_profile <- is.na(profile_match)
  invalid_unit <- !invalid_profile &
    canonical_exposure$exposure_unit != profiles$exposure_unit[profile_match]
  if (any(invalid_profile | invalid_unit)) {
    stop(
      "incidence_exposure_by_year_um_uf_ta_de_profile contains an ",
      "unsupported denominator profile/exposure unit pair.",
      call. = FALSE
    )
  }
  grain_cols <- c(
    "calendar_year", "SEJUM", "SEJUF", "CODE_TA", "CODE_DE",
    "de_domain_ref", "denominator_profile_id"
  )
  if (any(duplicated(canonical_exposure[grain_cols]))) {
    stop(
      "incidence_exposure_by_year_um_uf_ta_de_profile contains duplicate ",
      "rows at grain ",
      paste(grain_cols, collapse = " + "),
      ".",
      call. = FALSE
    )
  }
  canonical_exposure <- canonical_exposure[
    do.call(order, canonical_exposure[grain_cols]),
    ,
    drop = FALSE
  ]
  row.names(canonical_exposure) <- NULL

  list(incidence_exposure_by_year_um_uf_ta_de_profile = canonical_exposure)
}

orchidee_handoff_build_external_bundle <- function(
    sir_wide,
    unit_mapping,
    incidence_exposure_by_year_um_uf_ta_de_profile
  ) {
  contract <- orchidee_external_contract_v3()
  list(
    sir_wide = sir_wide,
    sir_wide_meta = orchidee_handoff_build_sir_wide_meta(
      sir_wide = sir_wide,
      contract = contract
    ),
    sample_scope_reference = orchidee_handoff_build_sample_scope_reference(
      unit_mapping = unit_mapping
    ),
    denominator_bundle = orchidee_handoff_build_denominator_bundle(
      incidence_exposure_by_year_um_uf_ta_de_profile =
        incidence_exposure_by_year_um_uf_ta_de_profile
    )
  )
}

orchidee_handoff_build_external_bundle_from_site_inputs <- function(
    microbiology_observations,
    bacteria_mapping,
    sample_type_mapping,
    antibiotic_mapping,
    unit_mapping,
    incidence_exposure_by_year_um_uf_ta_de_profile
  ) {
  site_inputs <- list(
    microbiology_observations = microbiology_observations,
    bacteria_mapping = bacteria_mapping,
    sample_type_mapping = sample_type_mapping,
    antibiotic_mapping = antibiotic_mapping,
    unit_mapping = unit_mapping,
    incidence_exposure_by_year_um_uf_ta_de_profile =
      incidence_exposure_by_year_um_uf_ta_de_profile
  )
  orchidee_handoff_validate_site_input_columns(site_inputs)

  sir_wide <- orchidee_handoff_build_sir_wide_from_microbiology(
    microbiology_observations = microbiology_observations,
    bacteria_mapping = bacteria_mapping,
    sample_type_mapping = sample_type_mapping,
    antibiotic_mapping = antibiotic_mapping
  )

  orchidee_handoff_build_external_bundle(
    sir_wide = sir_wide,
    unit_mapping = unit_mapping,
    incidence_exposure_by_year_um_uf_ta_de_profile =
      incidence_exposure_by_year_um_uf_ta_de_profile
  )
}
