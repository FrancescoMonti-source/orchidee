## Rennes/external-site handoff helpers.
##
## These helpers build ORCHIDEE's canonical runtime bundle from simpler,
## site-owned input blocks. They deliberately sit upstream of the canonical
## runtime contract validated in `R/external_bundle_validation_helpers.R`.

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
      fileEncoding = "UTF-8"
    ))
  }

  if (ext %in% c("tsv", "tab")) {
    return(utils::read.delim(
      file = path,
      stringsAsFactors = FALSE,
      check.names = FALSE,
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

orchidee_handoff_integerish_vector <- function(x, col_name) {
  if (is.factor(x)) x <- as.character(x)

  if (is.numeric(x)) {
    bad <- is.na(x) | abs(x - round(x)) >= sqrt(.Machine$double.eps)
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

orchidee_handoff_build_sir_wide_meta <- function(
    sir_wide,
    contract = orchidee_external_contract_v1(),
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

  list(
    artifact_version = as.integer(artifact_version),
    created_at = as.character(created_at),
    sir_wide_n_rows = nrow(sir_wide),
    sir_wide_n_eltid = length(unique(sir_wide$ELTID)),
    atb_cols = intersect(supported_atb_cols, names(sir_wide)),
    supported_atb_cols = supported_atb_cols,
    phenotype_status_cols = sir_spec$phenotype_status_cols,
    phenotype_flag_cols = sir_spec$phenotype_flag_cols,
    filtre_atb = supported_atb_cols,
    handoff_source = source_label,
    handoff_generated_by = "R/external_handoff_helpers.R"
  )
}

orchidee_handoff_prepare_de_reference <- function(de_reference) {
  if (is.null(de_reference)) {
    return(NULL)
  }
  if (!is.data.frame(de_reference)) {
    stop("de_reference must be a data frame when provided.", call. = FALSE)
  }
  if (!"CODE_DE" %in% names(de_reference)) {
    stop("de_reference must contain CODE_DE.", call. = FALSE)
  }

  domain_col <- NULL
  if ("de_domain_ref" %in% names(de_reference)) {
    domain_col <- "de_domain_ref"
  } else if ("DOMAINE" %in% names(de_reference)) {
    domain_col <- "DOMAINE"
  }
  if (is.null(domain_col)) {
    stop(
      "de_reference must contain de_domain_ref or DOMAINE.",
      call. = FALSE
    )
  }

  out <- data.frame(
    CODE_DE_norm = ratb_normalize_code_de(de_reference$CODE_DE),
    de_domain_ref = orchidee_handoff_trim_or_na(de_reference[[domain_col]]),
    stringsAsFactors = FALSE
  )
  out <- out[!is.na(out$CODE_DE_norm), , drop = FALSE]
  out <- stats::aggregate(
    de_domain_ref ~ CODE_DE_norm,
    data = out,
    FUN = function(x) {
      vals <- sort(unique(x[!is.na(x)]))
      if (length(vals) == 0L) NA_character_ else paste(vals, collapse = "|")
    }
  )
  out
}

orchidee_handoff_build_sample_scope_reference <- function(
    unit_mapping,
    de_reference = NULL
  ) {
  orchidee_handoff_require_functions(c(
    "ratb_normalize_code_ta",
    "ratb_normalize_code_de",
    "ratb_included_ta_de_domains"
  ))
  if (!is.data.frame(unit_mapping)) {
    stop("unit_mapping must be a data frame.", call. = FALSE)
  }

  required_unit_cols <- c("SEJUF", "CODE_TA")
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

  if ("CODE_DE" %in% names(unit_mapping)) {
    unit$CODE_DE_norm <- ratb_normalize_code_de(unit_mapping$CODE_DE)
  } else {
    unit$CODE_DE_norm <- NA_character_
  }

  if ("de_domain_ref" %in% names(unit_mapping)) {
    unit$de_domain_ref <- orchidee_handoff_trim_or_na(unit_mapping$de_domain_ref)
  } else {
    unit$de_domain_ref <- NA_character_
  }

  de_ref <- orchidee_handoff_prepare_de_reference(de_reference)
  if (!is.null(de_ref)) {
    de_ref_domain <- de_ref$de_domain_ref[match(unit$CODE_DE_norm, de_ref$CODE_DE_norm)]
    unit$de_domain_ref <- ifelse(
      is.na(unit$de_domain_ref),
      de_ref_domain,
      unit$de_domain_ref
    )
  }
  unit$de_domain_ref <- orchidee_handoff_normalize_included_de_domain(
    unit$de_domain_ref
  )

  if (all(is.na(unit$de_domain_ref))) {
    stop(
      "No de_domain_ref information available. Provide de_domain_ref in ",
      "unit_mapping or pass a de_reference table.",
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

  data.frame(
    SEJUF = unit$SEJUF,
    sample_uf_is_eligible_by_ta_de = uf_is_eligible,
    sample_uf_ta_de_status = status,
    sample_uf_ta_de_reason = reason,
    stringsAsFactors = FALSE
  )
}

orchidee_handoff_build_denominator_bundle <- function(denominator_by_year) {
  if (!is.data.frame(denominator_by_year)) {
    stop("denominator_by_year must be a data frame.", call. = FALSE)
  }
  required_cols <- c("calendar_year", "hospital_nights")
  missing_cols <- setdiff(required_cols, names(denominator_by_year))
  if (length(missing_cols) > 0L) {
    stop(
      "denominator_by_year is missing required columns: ",
      paste(missing_cols, collapse = ", "),
      call. = FALSE
    )
  }

  incidence_denominator_by_year <- data.frame(
    calendar_year = orchidee_handoff_integerish_vector(
      denominator_by_year$calendar_year,
      "denominator_by_year$calendar_year"
    ),
    hospital_nights = orchidee_handoff_integerish_vector(
      denominator_by_year$hospital_nights,
      "denominator_by_year$hospital_nights"
    ),
    stringsAsFactors = FALSE
  )
  if (any(incidence_denominator_by_year$hospital_nights < 0L)) {
    stop("denominator_by_year$hospital_nights must be non-negative.", call. = FALSE)
  }

  incidence_denominator_by_year <- incidence_denominator_by_year[
    order(incidence_denominator_by_year$calendar_year),
    ,
    drop = FALSE
  ]
  row.names(incidence_denominator_by_year) <- NULL

  list(incidence_denominator_by_year = incidence_denominator_by_year)
}

orchidee_handoff_build_external_bundle <- function(
    sir_wide,
    unit_mapping,
    denominator_by_year,
    de_reference = NULL,
    contract = orchidee_external_contract_v1()
  ) {
  list(
    sir_wide = sir_wide,
    sir_wide_meta = orchidee_handoff_build_sir_wide_meta(
      sir_wide = sir_wide,
      contract = contract
    ),
    sample_scope_reference = orchidee_handoff_build_sample_scope_reference(
      unit_mapping = unit_mapping,
      de_reference = de_reference
    ),
    denominator_bundle = orchidee_handoff_build_denominator_bundle(
      denominator_by_year = denominator_by_year
    )
  )
}
