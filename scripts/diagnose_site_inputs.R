#!/usr/bin/env Rscript

## Aggregated diagnostics for the six site-owned handoff blocks.
##
## This CLI answers exactly one question: do the six blocks satisfy the
## handoff contract, and where do they not? It reads each block once, collects
## every finding instead of stopping at the first one, and classifies each
## finding as BLOCKING, WARNING or INFO.
##
## Soundness rule: a run without BLOCKING findings must mean the operator
## build completes, that is the whole path build_site.ps1 runs -- bundle v3,
## the closed spares_current projection to operational v2, and strict
## validation of both. Every check below therefore mirrors a rule the builder,
## the v3 contract or that projection actually enforces, and any check added
## here must keep the invariant, which
## `tests/test_site_input_diagnostics.R` asserts by running that same build on
## each passing fixture.
##
## It deliberately stays inside the handoff contract. It does not load the
## indicator specification, the taxonomy or the publication contract, and it
## therefore makes no claim about which indicators would be published.

resolve_project_root <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0L) {
    script_file <- sub("^--file=", "", file_arg[[1]])
    script_dir <- dirname(normalizePath(
      script_file,
      winslash = "/",
      mustWork = TRUE
    ))
    return(normalizePath(
      file.path(script_dir, ".."),
      winslash = "/",
      mustWork = TRUE
    ))
  }
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

project_root <- resolve_project_root()
setwd(project_root)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 7L || any(args %in% c("-h", "--help"))) {
  cat(
    "Usage (PowerShell):\n",
    "  & .\\scripts\\run_r.ps1 scripts/diagnose_site_inputs.R `\n",
    "    <microbiology_observations.{rds,csv,tsv,tab,txt}> `\n",
    "    <bacteria_mapping.{rds,csv,tsv,tab,txt}> `\n",
    "    <sample_type_mapping.{rds,csv,tsv,tab,txt}> `\n",
    "    <antibiotic_mapping.{rds,csv,tsv,tab,txt}> `\n",
    "    <unit_mapping.{rds,csv,tsv,tab,txt}> `\n",
    "    <incidence_exposure_by_year_um_uf_ta_de_profile",
    ".{rds,csv,tsv,tab,txt}> `\n",
    "    <report_dir>\n\n",
    "Reads the six blocks once and writes an aggregated report classified as\n",
    "BLOCKING, WARNING and INFO. Exit status is 0 when no BLOCKING finding\n",
    "remains, 1 when at least one does, and 2 when the diagnostics could not\n",
    "run or publish their report, which is not a verdict on the blocks. A run\n",
    "without BLOCKING findings means the operator build completes: bundle v3,\n",
    "its spares_current projection to operational v2, and strict validation of\n",
    "both.\n\n",
    "Beyond the six input paths it records for provenance, the report contains\n",
    "aggregate counts and local vocabulary only. It never writes patient\n",
    "identifiers.\n",
    sep = ""
  )
  # 0 is reserved for a published report with no blocking finding, so only an
  # explicit help request may use it. Any other invocation is a technical
  # failure: a caller that mistakenly passed no arguments must not read success,
  # and a wrong argument count is not a verdict on anybody's data.
  quit(status = if (any(args %in% c("-h", "--help"))) 0L else 2L)
}

# Exit status is part of the interface: 1 means the blocks carry blocking
# findings, 2 means the diagnostics could not run or publish. An operator
# wrapper must not report a technical failure as a data verdict.

# A run that stops after taking the publication lock must not leave it behind,
# and its staging directory must not outlive it either: the previous report is
# still in place and has to stay the only one an operator can find. What a run
# owns lives in publication_state, which is emptied by the release itself, so
# the handler below cannot release twice -- the second call would otherwise
# reach a lock another run has taken since.
release_publication_resources <- function() {
  if (exists("publication_state", envir = globalenv(), inherits = FALSE)) {
    orchidee_publication_release(
      get("publication_state", envir = globalenv(), inherits = FALSE)
    )
  }
  invisible(NULL)
}

quit_technical <- function(...) {
  release_publication_resources()
  message(...)
  quit(status = 2L, runLast = FALSE)
}

# Installed before the R sources are read: a failure there is technical too, and
# nothing is owned yet, so the release has nothing to do.
options(error = function() {
  message(
    "Site input diagnostics stopped before publishing a report. ",
    "This is a technical failure, not a verdict on the six blocks."
  )
  release_publication_resources()
  quit(status = 2L, runLast = FALSE)
})

suppressPackageStartupMessages(library(dplyr))
source("R/bootstrap.R")
orchidee_source_required_script("helpers.R")
orchidee_source_required_script("phenotype_flag_helpers.R")
orchidee_source_required_script("external_bundle_validation_helpers.R")
orchidee_source_required_script("ratb_hospital_days_helpers.R")
orchidee_source_required_script("external_handoff_helpers.R")
orchidee_source_required_script("site_input_report_publication_helpers.R")

contract <- orchidee_external_contract_v3()
spec <- orchidee_handoff_site_input_spec("v3")
block_names <- names(spec)
input_paths <- args[seq_along(block_names)]
names(input_paths) <- block_names
report_dir <- args[[7L]]

## ---------------------------------------------------------------------------
## Finding accumulation
## ---------------------------------------------------------------------------

findings <- list()
finding_values <- list()

add_finding <- function(
    severity,
    block,
    check,
    detail,
    n_rows = NA_integer_,
    n_document_occurrences = NA_integer_,
    values = character()
  ) {
  # Several checks are emitted once per field -- non_integer_value for both
  # calendar_year and exposure_value, unsupported_phenotype_status for both
  # phenotypes -- so block and check do not identify an occurrence. The id does,
  # and it is what joins the two tables.
  finding_id <- length(findings) + 1L
  findings[[finding_id]] <<- data.frame(
    finding_id = finding_id,
    severity = severity,
    block = block,
    check = check,
    detail = detail,
    n_rows = as.integer(n_rows),
    n_document_occurrences = as.integer(n_document_occurrences),
    stringsAsFactors = FALSE
  )
  # The summary text truncates long lists, so every value a finding refers to
  # is also kept in full. A site with more unmapped labels than the summary
  # shows must still be able to correct them all in one round.
  values <- sort(unique(as.character(values)))
  if (length(values) > 0L) {
    finding_values[[length(finding_values) + 1L]] <<- data.frame(
      finding_id = finding_id,
      severity = severity,
      block = block,
      check = check,
      value = values,
      stringsAsFactors = FALSE
    )
  }
  invisible(NULL)
}

collected_finding_values <- function() {
  if (length(finding_values) == 0L) {
    return(NULL)
  }
  out <- do.call(rbind, finding_values)
  severity_rank <- match(out$severity, c("BLOCKING", "WARNING", "INFO"))
  out[
    order(severity_rank, out$block, out$check, out$finding_id, out$value), ,
    drop = FALSE
  ]
}

collected_findings <- function() {
  if (length(findings) == 0L) {
    return(data.frame(
      finding_id = integer(),
      severity = character(),
      block = character(),
      check = character(),
      detail = character(),
      n_rows = integer(),
      n_document_occurrences = integer(),
      stringsAsFactors = FALSE
    ))
  }
  out <- do.call(rbind, findings)
  severity_rank <- match(out$severity, c("BLOCKING", "WARNING", "INFO"))
  out[order(severity_rank, out$block, out$check, out$finding_id), , drop = FALSE]
}

# NA must never decide a branch or silently drop a row from a count: an
# unparseable value is a finding, not an absence of one.
any_true <- function(x) isTRUE(any(x %in% TRUE))
count_true <- function(x) sum(x %in% TRUE)

format_values <- function(x, limit = 10L) {
  x <- sort(unique(as.character(x)))
  shown <- utils::head(x, limit)
  paste0(
    paste(shown, collapse = ", "),
    if (length(x) > limit) {
      paste0(
        " (+",
        length(x) - limit,
        " more; the complete list is in finding_values.csv)"
      )
    } else {
      ""
    }
  )
}

## ---------------------------------------------------------------------------
## Element-wise parsing
## ---------------------------------------------------------------------------
##
## The builder stops on the first unparseable value in a column. Reporting one
## bad value must not blind the run to independent problems on the other rows,
## so these mirror the builder's accepted forms per element and return the
## valid values alongside the offending ones.

parse_integerish <- function(x) {
  if (is.factor(x)) x <- as.character(x)
  raw <- as.character(x)
  if (is.numeric(x)) {
    bad <- is.na(x) | !is.finite(x) |
      abs(x - round(x)) >= sqrt(.Machine$double.eps)
    values <- rep(NA_integer_, length(x))
    values[!bad] <- suppressWarnings(as.integer(x[!bad]))
  } else if (is.character(x)) {
    trimmed <- orchidee_handoff_trim_or_na(x)
    raw <- trimmed
    bad <- is.na(trimmed) | !grepl("^-?[0-9]+$", trimmed)
    values <- rep(NA_integer_, length(trimmed))
    values[!bad] <- suppressWarnings(as.integer(trimmed[!bad]))
  } else {
    bad <- rep(TRUE, length(x))
    values <- rep(NA_integer_, length(x))
  }
  # A value outside the integer range converts to NA; the builder stores that
  # missing value and fails later, so treat it as unusable here too.
  bad <- bad | is.na(values)
  list(values = values, bad = bad, raw = raw)
}

raw_text_of <- function(x) {
  if (is.factor(x)) x <- as.character(x)
  if (is.character(x)) {
    return(orchidee_handoff_trim_or_na(x))
  }
  # A typed column has no raw text, and as.character() on a Date drops exactly
  # what makes some values unreadable: an infinite day number prints as NA and a
  # fractional one as an ordinary date. Quoting "2024-04-02" back at a site as a
  # value ORCHIDEE cannot read would read as a broken tool, so those values are
  # reported as the day numbers they are. Seventeen significant digits, because
  # that is what round-trips a double: format() shows seven and would quote
  # 19815 + 1e-9 back as "19815", a whole day number refused for not being one.
  if (inherits(x, "Date")) {
    days <- unclass(x)
    text <- as.character(x)
    opaque <- (is.na(text) & !is.na(days)) | orchidee_handoff_non_whole_days(days)
    text[opaque] <- paste0("day number ", sprintf("%.17g", days[opaque]))
    return(text)
  }
  # The same reason one branch over. Only dates and times reach this function,
  # so a bare numeric column here is day or second numbers, and as.character()
  # stops at fifteen significant digits -- enough to print a day number carrying
  # a fraction of 1e-12 as the whole day it is not.
  if (is.numeric(x)) {
    text <- sprintf("%.17g", x)
    text[is.na(x)] <- NA_character_
    return(text)
  }
  as.character(x)
}

# Dates and times are parsed by the builder's own element-wise helpers, so the
# report cannot describe a value the build would read differently. Only the raw
# text for the message is added here.
parse_dates <- function(x) {
  parsed <- orchidee_handoff_parse_date_values(x)
  list(values = parsed$values, bad = parsed$bad, raw = raw_text_of(x))
}

parse_times <- function(x) {
  parsed <- orchidee_handoff_parse_time_values(x)
  list(values = parsed$values, bad = parsed$bad, raw = raw_text_of(x))
}


## ---------------------------------------------------------------------------
## Read the six blocks once
## ---------------------------------------------------------------------------

blocks <- list()
for (block_name in block_names) {
  block <- tryCatch(
    orchidee_handoff_read_table(input_paths[[block_name]]),
    error = function(e) {
      add_finding(
        "BLOCKING",
        block_name,
        "unreadable_input",
        conditionMessage(e)
      )
      NULL
    }
  )
  if (!is.null(block) && !is.data.frame(block)) {
    add_finding(
      "BLOCKING",
      block_name,
      "not_a_table",
      "The input did not contain a table."
    )
    block <- NULL
  }
  blocks[[block_name]] <- block
}

## ---------------------------------------------------------------------------
## Column contract
## ---------------------------------------------------------------------------
##
## Validity is tracked per block so that a schema error in one block never
## suppresses the content checks of the others.

block_ok <- stats::setNames(rep(FALSE, length(block_names)), block_names)
for (block_name in block_names) {
  block <- blocks[[block_name]]
  if (is.null(block)) {
    next
  }

  add_finding(
    "INFO",
    block_name,
    "rows_read",
    paste0(nrow(block), " rows, ", ncol(block), " columns."),
    n_rows = nrow(block)
  )

  block_is_ok <- TRUE
  duplicate_columns <- unique(names(block)[duplicated(names(block))])
  if (length(duplicate_columns) > 0L) {
    block_is_ok <- FALSE
    add_finding(
      "BLOCKING",
      block_name,
      "duplicate_columns",
      paste0("Duplicate column names: ", format_values(duplicate_columns), "."),
      values = duplicate_columns
    )
  }

  missing_columns <- setdiff(spec[[block_name]]$required_columns, names(block))
  if (length(missing_columns) > 0L) {
    block_is_ok <- FALSE
    add_finding(
      "BLOCKING",
      block_name,
      "missing_required_columns",
      paste0("Missing required columns: ", format_values(missing_columns), "."),
      values = missing_columns
    )
  }

  for (one_of_name in names(spec[[block_name]]$required_one_of)) {
    candidates <- spec[[block_name]]$required_one_of[[one_of_name]]
    present <- intersect(candidates, names(block))
    if (length(present) != 1L) {
      block_is_ok <- FALSE
      add_finding(
        "BLOCKING",
        block_name,
        "diagnostic_scope_column",
        paste0(
          "Exactly one ",
          one_of_name,
          " column is required; found ",
          length(present),
          " of: ",
          paste(candidates, collapse = ", "),
          "."
        )
      )
    }
  }

  block_ok[[block_name]] <- block_is_ok
}

# An empty local label is not blocking everywhere: the builder only requires a
# resolved bacterium, because bact_norm belongs to the canonical row grain. An
# empty sample type or antibiotic costs analytic value, not the build.
mapping_dimensions <- list(
  bacteria = list(
    block = "bacteria_mapping",
    local_column = "bacteria_local",
    canonical_column = "bact_norm",
    canonical_may_be_blank = FALSE,
    missing_local_blocks = TRUE,
    missing_local_consequence = paste0(
      " bact_norm belongs to the ORCHIDEE row grain, so the build cannot ",
      "place those rows."
    )
  ),
  sample_type = list(
    block = "sample_type_mapping",
    local_column = "sample_type_local",
    canonical_column = "naturepvt_norm",
    canonical_may_be_blank = TRUE,
    missing_local_blocks = FALSE,
    missing_local_consequence = paste0(
      " Those rows still enter the build and remain available for global ",
      "indicators, but cannot contribute to analyses that require a known ",
      "sample type."
    )
  ),
  antibiotic = list(
    block = "antibiotic_mapping",
    local_column = "antibiotic_local",
    canonical_column = "atb_norm",
    canonical_may_be_blank = FALSE,
    missing_local_blocks = FALSE,
    missing_local_consequence = paste0(
      " Those rows still enter the build but populate no antibiotic column."
    )
  )
)

## ---------------------------------------------------------------------------
## Mapping tables, independent of the observations
## ---------------------------------------------------------------------------
##
## The builder validates a whole mapping table before joining it, so a blank
## or conflicting target stops the build even on a row no observation uses.

prepared_mappings <- list()
for (dimension in names(mapping_dimensions)) {
  definition <- mapping_dimensions[[dimension]]
  if (!block_ok[[definition$block]]) {
    next
  }
  mapping <- blocks[[definition$block]]
  keys <- orchidee_handoff_trim_or_na(mapping[[definition$local_column]])
  values <- orchidee_handoff_trim_or_na(mapping[[definition$canonical_column]])
  keep <- !is.na(keys)
  keys <- keys[keep]
  values <- values[keep]

  if (count_true(!keep) > 0L) {
    add_finding(
      "WARNING",
      definition$block,
      "blank_local_label",
      paste0(
        count_true(!keep),
        " mapping rows have an empty ",
        definition$local_column,
        " and are ignored."
      ),
      n_rows = count_true(!keep)
    )
  }

  if (!definition$canonical_may_be_blank && any_true(is.na(values))) {
    add_finding(
      "BLOCKING",
      definition$block,
      "missing_canonical_value",
      paste0(
        count_true(is.na(values)),
        " mapping rows have an empty ",
        definition$canonical_column,
        ": ",
        format_values(keys[is.na(values)]),
        ". The builder rejects a missing target even on a row no observation ",
        "uses."
      ),
      n_rows = count_true(is.na(values)),
      values = keys[is.na(values)]
    )
  }

  duplicate_keys <- unique(keys[duplicated(keys)])
  if (length(duplicate_keys) > 0L) {
    comparable <- ifelse(is.na(values), "<missing>", values)
    conflicting <- duplicate_keys[vapply(
      duplicate_keys,
      function(key) length(unique(comparable[keys == key])) > 1L,
      logical(1)
    )]
    if (length(conflicting) > 0L) {
      add_finding(
        "BLOCKING",
        definition$block,
        "conflicting_duplicate_keys",
        paste0(
          "These local labels appear more than once with different ",
          definition$canonical_column,
          " values: ",
          format_values(conflicting),
          "."
        ),
        values = conflicting
      )
    }
    if (length(conflicting) < length(duplicate_keys)) {
      add_finding(
        "INFO",
        definition$block,
        "duplicate_keys",
        paste0(
          length(duplicate_keys) - length(conflicting),
          " local labels are listed more than once with the same ",
          definition$canonical_column,
          " value."
        )
      )
    }
  }

  prepared_mappings[[dimension]] <- data.frame(
    local_key = keys,
    canonical_value = values,
    stringsAsFactors = FALSE
  )[!duplicated(keys), , drop = FALSE]
}

## ---------------------------------------------------------------------------
## Microbiology observations
## ---------------------------------------------------------------------------

label_coverage <- NULL
unit_coverage <- NULL
year_coverage <- NULL
obs_in_scope <- NULL
document_key_in_scope <- character()
sample_dates <- NULL
mapped_values <- list()

count_occurrences <- function(keys) {
  keys <- keys[!is.na(keys)]
  length(unique(keys))
}

if (block_ok[["microbiology_observations"]]) {
  obs <- blocks$microbiology_observations
  diagnostic_candidates <-
    spec$microbiology_observations$required_one_of$diagnostic_scope
  diagnostic_col <- intersect(diagnostic_candidates, names(obs))[[1L]]

  obs$PATID <- orchidee_handoff_trim_or_na(obs$PATID)
  obs$ELTID <- orchidee_handoff_trim_or_na(obs$ELTID)
  obs$EVTID <- if ("EVTID" %in% names(obs)) {
    orchidee_handoff_trim_or_na(obs$EVTID)
  } else {
    rep(NA_character_, nrow(obs))
  }
  obs$SEJUF <- orchidee_handoff_trim_or_na(obs$SEJUF)

  document_key <- orchidee_handoff_document_occurrence_key(
    obs$PATID,
    obs$EVTID,
    obs$ELTID
  )

  add_finding(
    "INFO",
    "microbiology_observations",
    "population",
    paste0(
      length(unique(obs$PATID[!is.na(obs$PATID)])),
      " distinct patients, ",
      count_occurrences(document_key),
      " document occurrences before screening exclusion."
    ),
    n_rows = nrow(obs),
    n_document_occurrences = count_occurrences(document_key)
  )

  if ("EVTID" %in% names(blocks$microbiology_observations)) {
    fallback_rows <- !is.na(document_key) &
      startsWith(document_key, "patient_sample")
    if (any_true(fallback_rows)) {
      add_finding(
        "INFO",
        "microbiology_observations",
        "document_identity_fallback",
        paste0(
          count_occurrences(document_key[fallback_rows]),
          " document occurrences fall back to PATID + ELTID because at least ",
          "one row of the group has no EVTID."
        ),
        n_rows = count_true(fallback_rows),
        n_document_occurrences = count_occurrences(document_key[fallback_rows])
      )
    }
  } else {
    add_finding(
      "INFO",
      "microbiology_observations",
      "document_identity_fallback",
      paste0(
        "No EVTID column: every document occurrence is identified by ",
        "PATID + ELTID."
      )
    )
  }

  ## Diagnostic scope and screening exclusion ---------------------------------

  diagnostic_scope <- tryCatch(
    orchidee_handoff_logical_vector(
      obs[[diagnostic_col]],
      paste0("microbiology_observations$", diagnostic_col)
    ),
    error = function(e) {
      add_finding(
        "BLOCKING",
        "microbiology_observations",
        "diagnostic_scope_values",
        conditionMessage(e)
      )
      NULL
    }
  )

  if (!is.null(diagnostic_scope)) {
    usable_key <- !is.na(document_key)
    propagate_screening <- rep(FALSE, nrow(obs))
    if (any_true(usable_key)) {
      screening_keys <- unique(document_key[usable_key & !diagnostic_scope])
      propagate_screening[usable_key] <-
        document_key[usable_key] %in% screening_keys
    }
    drop_mask <- (!diagnostic_scope) | propagate_screening

    add_finding(
      "INFO",
      "microbiology_observations",
      "diagnostic_scope_excluded",
      paste0(
        count_true(!diagnostic_scope),
        " rows are flagged outside the diagnostic scope; excluding their whole ",
        "document occurrences removes ",
        count_true(drop_mask),
        " rows (",
        count_occurrences(document_key[drop_mask]),
        " occurrences)."
      ),
      n_rows = count_true(drop_mask),
      n_document_occurrences = count_occurrences(document_key[drop_mask])
    )

    collateral <- count_true(drop_mask) - count_true(!diagnostic_scope)
    if (collateral > 0L) {
      add_finding(
        "WARNING",
        "microbiology_observations",
        "screening_propagation",
        paste0(
          collateral,
          " additional rows flagged inside the diagnostic scope are removed ",
          "because another row of the same document occurrence is flagged as ",
          "screening. Confirm the flag is consistent within each occurrence."
        ),
        n_rows = collateral
      )
    }

    obs_in_scope <- obs[!drop_mask, , drop = FALSE]
    document_key_in_scope <- document_key[!drop_mask]

    if (nrow(obs_in_scope) == 0L) {
      add_finding(
        "BLOCKING",
        "microbiology_observations",
        "no_rows_in_scope",
        paste0(
          "No rows remain after excluding screening document occurrences. ",
          "The build cannot produce a bundle."
        )
      )
      obs_in_scope <- NULL
    } else {
      add_finding(
        "INFO",
        "microbiology_observations",
        "rows_in_scope",
        paste0(
          nrow(obs_in_scope),
          " rows and ",
          count_occurrences(document_key_in_scope),
          " document occurrences enter the build. All coverage counts below ",
          "are computed on these rows."
        ),
        n_rows = nrow(obs_in_scope),
        n_document_occurrences = count_occurrences(document_key_in_scope)
      )
    }
  }
}

if (!is.null(obs_in_scope)) {
  ## The builder drops screening rows before checking key identity, so this
  ## check belongs to the surviving rows only.
  unusable_key <- is.na(document_key_in_scope)
  if (any_true(unusable_key)) {
    add_finding(
      "BLOCKING",
      "microbiology_observations",
      "missing_document_identity",
      paste0(
        count_true(unusable_key),
        " rows entering the build have a missing PATID or ELTID."
      ),
      n_rows = count_true(unusable_key)
    )
  }

  missing_sejuf <- is.na(obs_in_scope$SEJUF)
  if (any_true(missing_sejuf)) {
    add_finding(
      "WARNING",
      "microbiology_observations",
      "missing_sejuf",
      paste0(
        count_true(missing_sejuf),
        " rows entering the build have no SEJUF. They stay auditable but ",
        "cannot receive a TA/DE perimeter and are excluded from the analytic ",
        "scope."
      ),
      n_rows = count_true(missing_sejuf),
      n_document_occurrences = count_occurrences(
        document_key_in_scope[missing_sejuf]
      )
    )
  }

  parsed_dates <- parse_dates(obs_in_scope$DATEPRELEV)
  if (any_true(parsed_dates$bad)) {
    add_finding(
      "BLOCKING",
      "microbiology_observations",
      "dateprelev_format",
      paste0(
        count_true(parsed_dates$bad),
        " rows have a DATEPRELEV value ORCHIDEE cannot read. Use YYYY-MM-DD ",
        "or DD/MM/YYYY: ",
        format_values(parsed_dates$raw[parsed_dates$bad]),
        "."
      ),
      n_rows = count_true(parsed_dates$bad),
      values = parsed_dates$raw[parsed_dates$bad]
    )
  }
  sample_dates <- parsed_dates$values

  parsed_times <- if ("HEUREPRELEV" %in% names(obs_in_scope)) {
    parse_times(obs_in_scope$HEUREPRELEV)
  } else {
    list(
      values = as.difftime(rep(NA_real_, nrow(obs_in_scope)), units = "secs"),
      bad = rep(FALSE, nrow(obs_in_scope)),
      raw = rep(NA_character_, nrow(obs_in_scope))
    )
  }
  if (any_true(parsed_times$bad)) {
    add_finding(
      "BLOCKING",
      "microbiology_observations",
      "heureprelev_format",
      paste0(
        count_true(parsed_times$bad),
        " rows have a HEUREPRELEV value ORCHIDEE cannot read. Use HH:MM or ",
        "HH:MM:SS: ",
        format_values(parsed_times$raw[parsed_times$bad]),
        "."
      ),
      n_rows = count_true(parsed_times$bad),
      values = parsed_times$raw[parsed_times$bad]
    )
  }
  sample_times <- parsed_times$values

  normalized_sir <- orchidee_handoff_normalize_sir(obs_in_scope$sir_result)
  raw_sir <- orchidee_handoff_trim_or_na(obs_in_scope$sir_result)
  unsupported_sir <- setdiff(
    unique(normalized_sir[!is.na(normalized_sir)]),
    contract$sir_wide$allowed_atb_values
  )
  if (length(unsupported_sir) > 0L) {
    unsupported_rows <- normalized_sir %in% unsupported_sir
    add_finding(
      "BLOCKING",
      "microbiology_observations",
      "unsupported_sir_values",
      paste0(
        "sir_result contains values ORCHIDEE does not recognize: ",
        format_values(raw_sir[unsupported_rows]),
        "."
      ),
      n_rows = count_true(unsupported_rows),
      values = raw_sir[unsupported_rows]
    )
  }
  if (any_true(is.na(normalized_sir))) {
    add_finding(
      "INFO",
      "microbiology_observations",
      "missing_sir_values",
      paste0(
        count_true(is.na(normalized_sir)),
        " rows have an empty or non-interpretable S/I/R result and will not ",
        "populate an antibiotic column."
      ),
      n_rows = count_true(is.na(normalized_sir))
    )
  }

  ## Optional phenotype statuses ---------------------------------------------

  phenotype_columns <- list(
    blse_status_row = c("blse_status_row", "blse_status"),
    carbapenemase_status_row = c(
      "carbapenemase_status_row",
      "carbapenemase_status"
    )
  )
  resolved_phenotype_columns <- list()
  for (status_name in names(phenotype_columns)) {
    present <- intersect(phenotype_columns[[status_name]], names(obs_in_scope))
    if (length(present) == 0L) {
      next
    }
    column <- present[[1L]]
    resolved_phenotype_columns[[status_name]] <- column
    raw_status <- obs_in_scope[[column]]
    normalized_status <- normalize_phenotype_status(raw_status)
    unsupported <- is.na(normalized_status) &
      !is.na(orchidee_handoff_trim_or_na(raw_status))
    if (any_true(unsupported)) {
      add_finding(
        "BLOCKING",
        "microbiology_observations",
        "unsupported_phenotype_status",
        paste0(
          column,
          " contains values ORCHIDEE does not recognize: ",
          format_values(as.character(raw_status)[unsupported]),
          ". Accepted values are positive, negative, unknown and no_signal."
        ),
        n_rows = count_true(unsupported),
        values = as.character(raw_status)[unsupported]
      )
    }
  }

  ## Canonical row grain ------------------------------------------------------

  # Resolution state is carried as a separate logical vector, never encoded in
  # the value itself: a site is free to use any string, including one that
  # looks like an internal marker, and no check may be fooled by it.
  mapped_unmatched <- list()
  mapped_local <- list()
  for (dimension in names(mapping_dimensions)) {
    definition <- mapping_dimensions[[dimension]]
    local_values <- orchidee_handoff_trim_or_na(
      obs_in_scope[[definition$local_column]]
    )
    mapping <- prepared_mappings[[dimension]]
    match_idx <- if (is.null(mapping)) {
      rep(NA_integer_, length(local_values))
    } else {
      match(local_values, mapping$local_key)
    }
    canonical <- if (is.null(mapping)) {
      rep(NA_character_, length(local_values))
    } else {
      mapping$canonical_value[match_idx]
    }
    # Only a label with no mapping row at all is unmatched. A label mapped to a
    # blank target is resolved: the builder carries the blank through, and two
    # different local labels mapped to blank collapse onto the same canonical
    # value. Treating those as distinct would hide a real row-grain conflict.
    mapped_unmatched[[definition$canonical_column]] <-
      is.na(match_idx) & !is.na(local_values)
    mapped_values[[definition$canonical_column]] <- canonical
    mapped_local[[definition$canonical_column]] <- local_values
  }
  mapped_values$naturepvt_norm <- orchidee_handoff_ascii_lower(
    mapped_values$naturepvt_norm
  )

  # An unmatched label is already BLOCKING, but the row-grain check should still
  # run on every other row. Standing in the local label keeps rows sharing an
  # unmatched label together, and the match state travels as a separate leading
  # marker so a canonical value can never be mistaken for one.
  row_grain_value <- function(canonical_column) {
    values <- mapped_values[[canonical_column]]
    unmatched <- mapped_unmatched[[canonical_column]]
    values[unmatched] <- mapped_local[[canonical_column]][unmatched]
    out <- paste(ifelse(unmatched, "u", "m"), values, sep = "\r")
    # A missing value must stay missing so the row-grain check still reports
    # it, and so blank targets collapse exactly as the builder collapses them.
    out[is.na(values)] <- NA_character_
    out
  }

  souche_column <- intersect(
    c("souche_id", "isolate_local_id"),
    names(obs_in_scope)
  )
  souche_id <- if (length(souche_column) == 0L) {
    rep(NA_character_, nrow(obs_in_scope))
  } else {
    orchidee_handoff_trim_or_na(obs_in_scope[[souche_column[[1L]]]])
  }
  derived_souche <- is.na(souche_id)
  if (length(souche_column) == 0L) {
    add_finding(
      "WARNING",
      "microbiology_observations",
      "isolate_identifier_absent",
      paste0(
        "No souche_id or isolate_local_id column. Two isolates of the same ",
        "species in one sample would be merged into a single ORCHIDEE row."
      )
    )
  } else if (any_true(derived_souche)) {
    add_finding(
      "WARNING",
      "microbiology_observations",
      "isolate_identifier_missing",
      paste0(
        count_true(derived_souche),
        " rows have no ",
        souche_column[[1L]],
        " value; ORCHIDEE derives one from sample type and bacterium, which ",
        "merges distinct isolates of the same species."
      ),
      n_rows = count_true(derived_souche)
    )
  }
  souche_id[derived_souche] <- paste(
    "derived",
    dplyr::coalesce(
      mapped_values$naturepvt_norm[derived_souche],
      "missing_sample_type"
    ),
    mapped_values$bact_norm[derived_souche],
    sep = "__"
  )

  # Rows with an unreadable date are already BLOCKING and cannot take part in a
  # row key, but they must not stop the remaining rows from being checked.
  gradable <- !parsed_dates$bad
  if (any_true(gradable)) {
    row_key_frame <- data.frame(
      PATID = obs_in_scope$PATID,
      EVTID = obs_in_scope$EVTID,
      ELTID = obs_in_scope$ELTID,
      DATEPRELEV = as.character(sample_dates),
      souche_id = souche_id,
      naturepvt_norm = row_grain_value("naturepvt_norm"),
      bact_norm = row_grain_value("bact_norm"),
      stringsAsFactors = FALSE
    )[gradable, , drop = FALSE]
    row_key <- do.call(
      paste,
      c(row_key_frame[contract$sir_wide$row_grain_key], sep = "\r")
    )

    conflict_columns <- list(
      SEJUF = obs_in_scope$SEJUF[gradable],
      HEUREPRELEV = as.numeric(sample_times)[gradable]
    )
    for (attribute in names(conflict_columns)) {
      values <- conflict_columns[[attribute]]
      if (is.null(values)) {
        next
      }
      conflicted <- tapply(
        values,
        row_key,
        function(group) length(unique(group[!is.na(group)])) > 1L
      )
      if (any_true(conflicted)) {
        add_finding(
          "BLOCKING",
          "microbiology_observations",
          "conflicting_row_grain_attribute",
          paste0(
            count_true(conflicted),
            " ORCHIDEE row keys carry more than one ",
            attribute,
            " value. The row grain is ",
            paste(contract$sir_wide$row_grain_key, collapse = " + "),
            "; add souche_id to keep distinct isolates apart, or correct the ",
            attribute,
            " value."
          )
        )
      }
    }

    # One cell of the antibiogram, two different answers. The builder keeps
    # whichever row comes last, so the published value depends on the order the
    # rows happen to be written in -- and nothing in this contract asks a site
    # to make that order mean anything. Reported by cause, because the
    # correction is not the same: one label contradicting itself is a question
    # for the laboratory, two labels landing on one ORCHIDEE antibiotic is a
    # question for the mapping.
    cell_atb <- mapped_values$atb_norm[gradable]
    cell_local_atb <- mapped_local$atb_norm[gradable]
    cell_sir <- normalized_sir[gradable]
    # A value ORCHIDEE cannot read is already reported as such, and it is not
    # evidence that the laboratory said two things: pairing it with a real
    # result would report one defect twice and name the wrong correction.
    cell_sir[
      !cell_sir %in% contract$sir_wide$allowed_atb_values
    ] <- NA_character_
    graded_cells <- which(!is.na(cell_atb) & !is.na(cell_sir))
    if (length(graded_cells) > 0L) {
      cells <- split(
        graded_cells,
        paste(row_key[graded_cells], cell_atb[graded_cells], sep = "\r")
      )
      discordant <- cells[vapply(
        cells,
        function(idx) length(unique(cell_sir[idx])) > 1L,
        logical(1)
      )]
      one_label <- vapply(
        discordant,
        function(idx) length(unique(cell_local_atb[idx])) == 1L,
        logical(1)
      )

      if (any(one_label)) {
        contradicting_labels <- vapply(
          discordant[one_label],
          function(idx) cell_local_atb[idx][[1L]],
          character(1)
        )
        add_finding(
          "BLOCKING",
          "microbiology_observations",
          "contradictory_sir_result",
          paste0(
            sum(one_label),
            " isolate-antibiotic cells carry more than one S/I/R result for ",
            "the same antibiotic_local label. The row grain is ",
            paste(contract$sir_wide$row_grain_key, collapse = " + "),
            ", and one cell holds one result; add souche_id to keep distinct ",
            "isolates apart, or correct the contradictory results. Labels ",
            "involved: ",
            format_values(contradicting_labels),
            "."
          ),
          values = contradicting_labels
        )
      }

      if (any(!one_label)) {
        collapsed_groups <- vapply(
          discordant[!one_label],
          function(idx) {
            paste0(
              paste(sort(unique(cell_local_atb[idx])), collapse = " + "),
              " -> ",
              cell_atb[idx][[1L]]
            )
          },
          character(1)
        )
        add_finding(
          "BLOCKING",
          "microbiology_observations",
          "conflicting_sir_after_atb_mapping",
          paste0(
            sum(!one_label),
            " isolate-antibiotic cells are fed by several antibiotic_local ",
            "labels that antibiotic_mapping sends to the same ORCHIDEE ",
            "antibiotic, and those labels disagree. Tests read against ",
            "different breakpoints, or on different molecules, cannot be ",
            "merged into one defensible value. Map each label to the ",
            "antibiotic it actually tested, or keep only the one RATB should ",
            "count. Groups involved: ",
            format_values(collapsed_groups),
            "."
          ),
          values = collapsed_groups
        )
      }
    }

    for (status_name in names(resolved_phenotype_columns)) {
      column <- resolved_phenotype_columns[[status_name]]
      allowed <- contract$sir_wide$phenotype_status_allowed[[status_name]]
      collapsed <- tapply(
        obs_in_scope[[column]][gradable],
        row_key,
        function(group) collapse_phenotype_status(group)
      )
      unsupported_collapse <- !(collapsed %in% allowed)
      if (any_true(unsupported_collapse)) {
        add_finding(
          "BLOCKING",
          "microbiology_observations",
          "unsupported_collapsed_phenotype",
          paste0(
            count_true(unsupported_collapse),
            " ORCHIDEE row keys collapse ",
            column,
            " to a value the contract does not accept: ",
            format_values(collapsed[unsupported_collapse]),
            ". Accepted collapsed values are ",
            paste(allowed, collapse = ", "),
            "."
          ),
          values = collapsed[unsupported_collapse]
        )
      }
    }

    missing_key_columns <- names(row_key_frame)[vapply(
      row_key_frame,
      function(column) any_true(is.na(column)),
      logical(1)
    )]
    missing_key_columns <- intersect(
      missing_key_columns,
      c("PATID", "ELTID", "DATEPRELEV", "souche_id", "bact_norm")
    )
    if (length(missing_key_columns) > 0L) {
      add_finding(
        "BLOCKING",
        "microbiology_observations",
        "missing_row_grain_value",
        paste0(
          "These fields must be present on every row entering the build: ",
          paste(missing_key_columns, collapse = ", "),
          "."
        )
      )
    }
  }

  ## Mapping coverage ---------------------------------------------------------

  coverage_for_dimension <- function(dimension) {
    definition <- mapping_dimensions[[dimension]]
    local_values <- orchidee_handoff_trim_or_na(
      obs_in_scope[[definition$local_column]]
    )
    mapping <- prepared_mappings[[dimension]]
    match_idx <- match(local_values, mapping$local_key)
    canonical <- mapping$canonical_value[match_idx]
    status <- ifelse(
      is.na(local_values),
      "missing_local_label",
      ifelse(
        is.na(match_idx),
        "unmapped",
        ifelse(is.na(canonical), "blank_canonical", "mapped")
      )
    )

    summary_table <- data.frame(
      dimension = dimension,
      local_label = ifelse(is.na(local_values), "<missing>", local_values),
      canonical_value = ifelse(is.na(canonical), "", canonical),
      status = status,
      document_key = document_key_in_scope,
      stringsAsFactors = FALSE
    ) %>%
      dplyr::group_by(
        .data$dimension,
        .data$local_label,
        .data$canonical_value,
        .data$status
      ) %>%
      dplyr::summarise(
        n_rows = dplyr::n(),
        n_document_occurrences = length(unique(
          .data$document_key[!is.na(.data$document_key)]
        )),
        .groups = "drop"
      ) %>%
      dplyr::arrange(
        .data$status,
        dplyr::desc(.data$n_rows),
        .data$local_label
      ) %>%
      as.data.frame()

    # Totals count distinct occurrences over the matching rows. Summing the
    # per-label counts would count a document once per label it carries.
    occurrences_for <- function(mask) {
      count_occurrences(document_key_in_scope[mask])
    }

    unmapped_mask <- status == "unmapped"
    if (any_true(unmapped_mask)) {
      unmapped_labels <- unique(local_values[unmapped_mask])
      add_finding(
        "BLOCKING",
        definition$block,
        "unmapped_local_labels",
        paste0(
          length(unmapped_labels),
          " local labels present in microbiology_observations have no row in ",
          definition$block,
          ": ",
          format_values(unmapped_labels),
          "."
        ),
        n_rows = count_true(unmapped_mask),
        n_document_occurrences = occurrences_for(unmapped_mask),
        values = unmapped_labels
      )
    }

    missing_local_mask <- status == "missing_local_label"
    if (any_true(missing_local_mask)) {
      add_finding(
        if (definition$missing_local_blocks) "BLOCKING" else "WARNING",
        "microbiology_observations",
        paste0("missing_", definition$local_column),
        paste0(
          count_true(missing_local_mask),
          " rows have an empty ",
          definition$local_column,
          " value.",
          definition$missing_local_consequence
        ),
        n_rows = count_true(missing_local_mask),
        n_document_occurrences = occurrences_for(missing_local_mask)
      )
    }

    blank_mask <- status == "blank_canonical"
    if (any_true(blank_mask)) {
      blank_labels <- unique(local_values[blank_mask])
      consequence <- if (definition$canonical_may_be_blank) {
        paste0(
          ". Those rows stay available for global indicators but cannot ",
          "contribute to analyses that require a known sample type."
        )
      } else {
        ". The build requires a canonical value for every mapped label."
      }
      add_finding(
        if (definition$canonical_may_be_blank) "WARNING" else "BLOCKING",
        definition$block,
        "blank_canonical_value_in_use",
        paste0(
          length(blank_labels),
          " local labels used by the observations are listed with an empty ",
          definition$canonical_column,
          ": ",
          format_values(blank_labels),
          consequence
        ),
        n_rows = count_true(blank_mask),
        n_document_occurrences = occurrences_for(blank_mask),
        values = blank_labels
      )
    }

    mapped_mask <- status == "mapped"
    add_finding(
      "INFO",
      definition$block,
      "mapped_local_labels",
      paste0(
        length(unique(local_values[mapped_mask])),
        " local labels are mapped, covering ",
        count_true(mapped_mask),
        " rows and ",
        occurrences_for(mapped_mask),
        " document occurrences."
      ),
      n_rows = count_true(mapped_mask),
      n_document_occurrences = occurrences_for(mapped_mask)
    )

    unused <- setdiff(mapping$local_key, local_values)
    if (length(unused) > 0L) {
      add_finding(
        "INFO",
        definition$block,
        "unused_mapping_rows",
        paste0(
          length(unused),
          " mapping rows describe local labels absent from the observations ",
          "that enter the build."
        )
      )
    }

    summary_table[
      ,
      setdiff(names(summary_table), "document_key"),
      drop = FALSE
    ]
  }

  coverage_tables <- lapply(
    names(mapping_dimensions)[vapply(
      names(mapping_dimensions),
      function(dimension) !is.null(prepared_mappings[[dimension]]),
      logical(1)
    )],
    coverage_for_dimension
  )
  if (length(coverage_tables) > 0L) {
    label_coverage <- do.call(rbind, coverage_tables)
  }

  if (!is.null(prepared_mappings$antibiotic)) {
    resolved_atb <- !mapped_unmatched$atb_norm & !is.na(mapped_values$atb_norm)
    used_atb <- unique(mapped_values$atb_norm[resolved_atb])
    unsupported_atb <- setdiff(
      used_atb,
      contract$sir_wide$atb_cols
    )
    if (length(unsupported_atb) > 0L) {
      affected <- mapped_values$atb_norm %in% unsupported_atb
      add_finding(
        "BLOCKING",
        "antibiotic_mapping",
        "unsupported_atb_norm",
        paste0(
          "These atb_norm targets are not ORCHIDEE antibiotic columns: ",
          format_values(unsupported_atb),
          ". The closed list is generated as ",
          "mapping_reference/supported_atb_norm.csv by ",
          "build_site.ps1 -EmitTemplates."
        ),
        n_rows = count_true(affected),
        values = unsupported_atb
      )
    }
  }
}

## ---------------------------------------------------------------------------
## Unit mapping
## ---------------------------------------------------------------------------

unit <- NULL
context <- ratb_analysis_context_profile("spares_current")

if (block_ok[["unit_mapping"]]) {
  unit_mapping <- blocks$unit_mapping
  unit <- data.frame(
    SEJUF = orchidee_handoff_trim_or_na(unit_mapping$SEJUF),
    CODE_TA = ratb_normalize_code_ta(unit_mapping$CODE_TA),
    CODE_DE = ratb_normalize_code_de(unit_mapping$CODE_DE),
    de_domain_ref = orchidee_handoff_normalize_included_de_domain(
      orchidee_handoff_trim_or_na(unit_mapping$de_domain_ref)
    ),
    stringsAsFactors = FALSE
  )

  if (any_true(is.na(unit$SEJUF))) {
    add_finding(
      "BLOCKING",
      "unit_mapping",
      "missing_sejuf",
      paste0(
        count_true(is.na(unit$SEJUF)),
        " rows have an empty SEJUF value."
      ),
      n_rows = count_true(is.na(unit$SEJUF))
    )
  }

  duplicate_sejuf <- unique(unit$SEJUF[duplicated(unit$SEJUF) & !is.na(unit$SEJUF)])
  if (length(duplicate_sejuf) > 0L) {
    add_finding(
      "BLOCKING",
      "unit_mapping",
      "duplicate_sejuf",
      paste0(
        "unit_mapping must contain one row per SEJUF; these are repeated: ",
        format_values(duplicate_sejuf),
        "."
      ),
      values = duplicate_sejuf
    )
  }

  if (all(is.na(unit$de_domain_ref))) {
    add_finding(
      "BLOCKING",
      "unit_mapping",
      "no_de_domain_ref",
      "No usable de_domain_ref value is present in unit_mapping."
    )
  }

  unit$eligible <- unit$CODE_TA %in% context$eligible_ta_codes &
    unit$de_domain_ref %in% context$eligible_de_domains
}

## ---------------------------------------------------------------------------
## Profiled incidence exposure
## ---------------------------------------------------------------------------

exposure_norm <- NULL

if (block_ok[["incidence_exposure_by_year_um_uf_ta_de_profile"]]) {
  exposure <- blocks$incidence_exposure_by_year_um_uf_ta_de_profile
  exposure_block <- "incidence_exposure_by_year_um_uf_ta_de_profile"

  # The builder requires integer-like years and exposures. Parsing per element
  # keeps one bad value from blanking the whole column and hiding an
  # independent problem, such as a negative exposure on another row.
  parsed_columns <- list(
    calendar_year = parse_integerish(exposure$calendar_year),
    exposure_value = parse_integerish(exposure$exposure_value)
  )
  for (column in names(parsed_columns)) {
    parsed <- parsed_columns[[column]]
    # An empty value is a missing required value, reported below as such.
    non_integer <- parsed$bad & !is.na(parsed$raw)
    if (any_true(non_integer)) {
      add_finding(
        "BLOCKING",
        exposure_block,
        "non_integer_value",
        paste0(
          count_true(non_integer),
          " rows have a ",
          column,
          " value that is not an integer: ",
          format_values(parsed$raw[non_integer]),
          "."
        ),
        n_rows = count_true(non_integer),
        values = parsed$raw[non_integer]
      )
    }
  }

  exposure_norm <- data.frame(
    calendar_year = parsed_columns$calendar_year$values,
    SEJUM = orchidee_handoff_trim_or_na(exposure$SEJUM),
    SEJUF = orchidee_handoff_trim_or_na(exposure$SEJUF),
    CODE_TA = ratb_normalize_code_ta(exposure$CODE_TA),
    CODE_DE = ratb_normalize_code_de(exposure$CODE_DE),
    de_domain_ref = orchidee_handoff_normalize_included_de_domain(
      orchidee_handoff_trim_or_na(exposure$de_domain_ref)
    ),
    denominator_profile_id = orchidee_handoff_trim_or_na(
      exposure$denominator_profile_id
    ),
    exposure_value = parsed_columns$exposure_value$values,
    exposure_unit = orchidee_handoff_trim_or_na(exposure$exposure_unit),
    stringsAsFactors = FALSE
  )

  for (column in spec[[exposure_block]]$required_columns) {
    missing_values <- is.na(exposure_norm[[column]])
    # A non-integer value is already reported; do not report it twice as a
    # missing one.
    parsed <- parsed_columns[[column]]
    if (!is.null(parsed)) {
      missing_values <- missing_values & is.na(parsed$raw)
    }
    if (any_true(missing_values)) {
      add_finding(
        "BLOCKING",
        exposure_block,
        "missing_required_value",
        paste0(
          count_true(missing_values),
          " rows have a missing or non-interpretable ",
          column,
          " value; all nine columns are required and non-missing."
        ),
        n_rows = count_true(missing_values)
      )
    }
  }

  negative_exposure <- exposure_norm$exposure_value < 0
  if (any_true(negative_exposure)) {
    add_finding(
      "BLOCKING",
      exposure_block,
      "negative_exposure_value",
      paste0(
        count_true(negative_exposure),
        " rows have a negative exposure_value."
      ),
      n_rows = count_true(negative_exposure)
    )
  }

  profiles <- ratb_denominator_profile_registry()
  profile_match <- match(
    exposure_norm$denominator_profile_id,
    profiles$denominator_profile_id
  )
  invalid_pair <- is.na(profile_match) |
    is.na(exposure_norm$exposure_unit) |
    exposure_norm$exposure_unit != profiles$exposure_unit[profile_match]
  invalid_pair <- invalid_pair %in% TRUE
  # A row whose profile or unit is simply absent is already reported as a
  # missing required value.
  invalid_pair <- invalid_pair &
    !is.na(exposure_norm$denominator_profile_id) &
    !is.na(exposure_norm$exposure_unit)
  if (any_true(invalid_pair)) {
    add_finding(
      "BLOCKING",
      exposure_block,
      "unsupported_denominator_profile",
      paste0(
        count_true(invalid_pair),
        " rows use an unsupported denominator_profile_id / exposure_unit ",
        "pair. Accepted pairs are: ",
        paste(
          paste0(
            profiles$denominator_profile_id,
            " / ",
            profiles$exposure_unit
          ),
          collapse = ", "
        ),
        "."
      ),
      n_rows = count_true(invalid_pair)
    )
  }

  grain_columns <- c(
    "calendar_year", "SEJUM", "SEJUF", "CODE_TA", "CODE_DE",
    "de_domain_ref", "denominator_profile_id"
  )
  duplicated_grain <- duplicated(exposure_norm[grain_columns])
  if (any_true(duplicated_grain)) {
    add_finding(
      "BLOCKING",
      exposure_block,
      "duplicate_grain_rows",
      paste0(
        count_true(duplicated_grain),
        " rows repeat the expected grain ",
        paste(grain_columns, collapse = " + "),
        ". Aggregate them before handoff."
      ),
      n_rows = count_true(duplicated_grain)
    )
  }
}

## ---------------------------------------------------------------------------
## Cross-block coverage and perimeter
## ---------------------------------------------------------------------------

if (!is.null(unit) && !is.null(exposure_norm)) {
  exposure_block <- "incidence_exposure_by_year_um_uf_ta_de_profile"
  # A duplicated SEJUF is already BLOCKING. Join on its first row so the
  # remaining checks stay one-to-one and their counts keep describing the
  # exposure block rather than the duplication.
  unit_lookup <- unit[!duplicated(unit$SEJUF) & !is.na(unit$SEJUF), , drop = FALSE]

  incomplete_unit <- is.na(unit_lookup$CODE_TA) |
    is.na(unit_lookup$CODE_DE) |
    is.na(unit_lookup$de_domain_ref)
  incomplete_used_by_exposure <- incomplete_unit &
    unit_lookup$SEJUF %in% exposure_norm$SEJUF
  if (any_true(incomplete_used_by_exposure)) {
    add_finding(
      "BLOCKING",
      "unit_mapping",
      "incomplete_ta_de_mapping",
      paste0(
        count_true(incomplete_used_by_exposure),
        " units used by profiled exposure have an empty CODE_TA, CODE_DE or ",
        "de_domain_ref: ",
        format_values(unit_lookup$SEJUF[incomplete_used_by_exposure]),
        ". Strict v3 validation rejects an incomplete perimeter mapping."
      ),
      n_rows = count_true(incomplete_used_by_exposure),
      values = unit_lookup$SEJUF[incomplete_used_by_exposure]
    )
  }
  if (any_true(incomplete_unit & !incomplete_used_by_exposure)) {
    add_finding(
      "WARNING",
      "unit_mapping",
      "incomplete_ta_de_mapping_unused",
      paste0(
        count_true(incomplete_unit & !incomplete_used_by_exposure),
        " units have an empty CODE_TA, CODE_DE or de_domain_ref but carry no ",
        "profiled exposure. Their microbiology rows stay outside the analytic ",
        "perimeter."
      ),
      n_rows = count_true(incomplete_unit & !incomplete_used_by_exposure)
    )
  }

  exposure_uf <- unique(exposure_norm$SEJUF[!is.na(exposure_norm$SEJUF)])
  observed_uf <- if (is.null(obs_in_scope)) {
    character()
  } else {
    unique(obs_in_scope$SEJUF[!is.na(obs_in_scope$SEJUF)])
  }

  uncovered_exposure_uf <- setdiff(exposure_uf, unit_lookup$SEJUF)
  if (length(uncovered_exposure_uf) > 0L) {
    affected <- exposure_norm$SEJUF %in% uncovered_exposure_uf
    add_finding(
      "BLOCKING",
      "unit_mapping",
      "exposure_uf_not_covered",
      paste0(
        length(uncovered_exposure_uf),
        " SEJUF values used by profiled exposure are absent from ",
        "unit_mapping: ",
        format_values(uncovered_exposure_uf),
        ". unit_mapping must cover every SEJUF in the exposure block."
      ),
      n_rows = count_true(affected),
      values = uncovered_exposure_uf
    )
  }

  uncovered_observed_uf <- setdiff(observed_uf, unit_lookup$SEJUF)
  if (length(uncovered_observed_uf) > 0L) {
    affected <- obs_in_scope$SEJUF %in% uncovered_observed_uf
    add_finding(
      "WARNING",
      "unit_mapping",
      "microbiology_uf_not_covered",
      paste0(
        length(uncovered_observed_uf),
        " SEJUF values observed in microbiology have no unit_mapping row: ",
        format_values(uncovered_observed_uf),
        ". These rows stay auditable but fall outside the analytic perimeter; ",
        "ORCHIDEE never infers a mapping for them. This does not stop the ",
        "build."
      ),
      n_rows = count_true(affected),
      n_document_occurrences = count_occurrences(
        document_key_in_scope[affected]
      ),
      values = uncovered_observed_uf
    )
  }

  matched_unit <- match(exposure_norm$SEJUF, unit_lookup$SEJUF)
  # The runtime treats an unresolved comparison as a disagreement, so an
  # incomplete mapping must not read as agreement here either.
  discordant <- !is.na(matched_unit) & !(
    (exposure_norm$CODE_TA == unit_lookup$CODE_TA[matched_unit]) %in% TRUE &
      (exposure_norm$CODE_DE == unit_lookup$CODE_DE[matched_unit]) %in% TRUE &
      (
        exposure_norm$de_domain_ref ==
          unit_lookup$de_domain_ref[matched_unit]
      ) %in% TRUE
  )
  # Rows whose unit mapping is incomplete are reported by that check instead.
  discordant <- discordant &
    !(exposure_norm$SEJUF %in% unit_lookup$SEJUF[incomplete_unit])
  if (any_true(discordant)) {
    add_finding(
      "BLOCKING",
      exposure_block,
      "ta_de_disagrees_with_unit_mapping",
      paste0(
        count_true(discordant),
        " exposure rows carry CODE_TA, CODE_DE or de_domain_ref values that ",
        "differ from unit_mapping for the same SEJUF: ",
        format_values(exposure_norm$SEJUF[discordant]),
        ". The two blocks must agree exactly."
      ),
      n_rows = count_true(discordant),
      values = exposure_norm$SEJUF[discordant]
    )
  }

  unit_coverage <- data.frame(
    SEJUF = unit_lookup$SEJUF,
    CODE_TA = unit_lookup$CODE_TA,
    CODE_DE = unit_lookup$CODE_DE,
    de_domain_ref = unit_lookup$de_domain_ref,
    included_in_spares_current = unit_lookup$eligible %in% TRUE,
    in_exposure = unit_lookup$SEJUF %in% exposure_uf,
    in_microbiology = unit_lookup$SEJUF %in% observed_uf,
    stringsAsFactors = FALSE
  )

  add_finding(
    "INFO",
    "unit_mapping",
    "perimeter_summary",
    paste0(
      count_true(unit_lookup$eligible),
      " of ",
      nrow(unit_lookup),
      " distinct mapped units fall inside the current spares_current perimeter ",
      "(TA ",
      paste(context$eligible_ta_codes, collapse = "/"),
      " and a ratified DE domain). Units outside it remain valid v3 activity."
    )
  )

  ## Exposure totals and year coverage ---------------------------------------
  ##
  ## Mirror the runtime projection: it keeps an exposure row only when the
  ## row's own TA/DE is eligible and the unit is eligible in the scope
  ## reference.
  unit_eligibility <- unit_lookup$eligible[matched_unit]
  in_context <- (exposure_norm$CODE_TA %in% context$eligible_ta_codes) &
    (exposure_norm$de_domain_ref %in% context$eligible_de_domains) &
    (exposure_norm$denominator_profile_id %in% context$denominator_profile_id) &
    (exposure_norm$exposure_unit %in% context$exposure_unit) &
    (unit_eligibility %in% TRUE)

  exposure_years <- sort(unique(
    exposure_norm$calendar_year[!is.na(exposure_norm$calendar_year)]
  ))
  microbiology_years <- if (is.null(sample_dates)) {
    integer()
  } else {
    sort(unique(as.integer(format(sample_dates, "%Y"))))
  }

  if (length(exposure_years) > 0L) {
    sum_for_year <- function(year, mask) {
      selected <- (exposure_norm$calendar_year %in% year) & mask
      sum(exposure_norm$exposure_value[selected], na.rm = TRUE)
    }
    year_coverage <- data.frame(
      calendar_year = exposure_years,
      exposure_total = vapply(
        exposure_years,
        sum_for_year,
        numeric(1),
        mask = rep(TRUE, nrow(exposure_norm))
      ),
      exposure_in_spares_current = vapply(
        exposure_years,
        sum_for_year,
        numeric(1),
        mask = in_context
      ),
      microbiology_rows = vapply(
        exposure_years,
        function(year) {
          if (is.null(sample_dates)) {
            return(NA_real_)
          }
          sum(as.integer(format(sample_dates, "%Y")) %in% year)
        },
        numeric(1)
      ),
      stringsAsFactors = FALSE
    )

    add_finding(
      "INFO",
      exposure_block,
      "exposure_totals",
      paste0(
        "Years ",
        paste(exposure_years, collapse = ", "),
        ". Total profiled exposure ",
        format(sum(year_coverage$exposure_total), scientific = FALSE),
        "; the spares_current projection retains ",
        format(
          sum(year_coverage$exposure_in_spares_current),
          scientific = FALSE
        ),
        ", which becomes hospital_nights in the operational v2 bundle. Only ",
        "units mapped inside the perimeter contribute."
      )
    )

    # The projection stores the annual total with as.integer(), so a year whose
    # in-perimeter total exceeds the integer range would silently become NA and
    # fail v2 validation after the diagnostics had passed.
    overflow_years <- year_coverage$calendar_year[
      year_coverage$exposure_in_spares_current > .Machine$integer.max
    ]
    if (length(overflow_years) > 0L) {
      add_finding(
        "BLOCKING",
        exposure_block,
        "annual_exposure_overflow",
        paste0(
          "These years total more in-perimeter exposure than the operational ",
          "v2 denominator can hold (",
          format(.Machine$integer.max, scientific = FALSE),
          " patient-days): ",
          paste(overflow_years, collapse = ", "),
          ". The projection would store a missing hospital_nights value."
        ),
        values = as.character(overflow_years)
      )
    }

    empty_context_years <- year_coverage$calendar_year[
      year_coverage$exposure_in_spares_current == 0
    ]
    if (length(empty_context_years) > 0L) {
      add_finding(
        "WARNING",
        exposure_block,
        "no_exposure_in_perimeter",
        paste0(
          "These years carry exposure but none inside the current perimeter: ",
          paste(empty_context_years, collapse = ", "),
          ". Their incidence denominator would be zero."
        )
      )
    }
  }

  missing_exposure_years <- setdiff(microbiology_years, exposure_years)
  if (length(missing_exposure_years) > 0L) {
    add_finding(
      "WARNING",
      exposure_block,
      "year_not_covered",
      paste0(
        "Microbiology rows exist for years without any profiled exposure: ",
        paste(missing_exposure_years, collapse = ", "),
        ". Incidence cannot be computed for them."
      )
    )
  }
  missing_microbiology_years <- setdiff(exposure_years, microbiology_years)
  if (length(missing_microbiology_years) > 0L) {
    add_finding(
      "INFO",
      exposure_block,
      "year_without_microbiology",
      paste0(
        "Profiled exposure exists for years without microbiology rows: ",
        paste(missing_microbiology_years, collapse = ", "),
        "."
      )
    )
  }
}

## ---------------------------------------------------------------------------
## Report
## ---------------------------------------------------------------------------

all_findings <- collected_findings()
n_blocking <- sum(all_findings$severity == "BLOCKING")
n_warning <- sum(all_findings$severity == "WARNING")
n_info <- sum(all_findings$severity == "INFO")

dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)
if (!dir.exists(report_dir)) {
  stop(
    "Could not create the diagnostics report directory: ", report_dir,
    call. = FALSE
  )
}
report_dir <- normalizePath(report_dir, winslash = "/", mustWork = TRUE)

# Everything below writes into the report directory, and the manifest's promise
# is only as good as the assumption that one run owns it. Two runs publishing at
# once would interleave -- one deleting the other's staging, then a manifest
# certifying the mixture -- which the write-last ordering cannot prevent because
# it guards against interruption, not concurrency. How the lock is taken, marked
# and given up is in R/site_input_report_publication_helpers.R.
publication_state <- orchidee_publication_state()
lock_path <- file.path(report_dir, orchidee_diagnostics_lock_name())
lock_outcome <- orchidee_publication_acquire(publication_state, report_dir)
if (!identical(lock_outcome, "acquired")) {
  # Plain quit, not quit_technical(): this run owns nothing, and the lock that
  # is there belongs to somebody else. A lock that could not be created at all
  # is a different problem, and telling the operator to wait for a run that does
  # not exist would send them looking in the wrong place.
  if (identical(lock_outcome, "held")) {
    message(
      "Another diagnostics run is publishing into ", report_dir,
      ". Wait for it to finish. Remove ", lock_path,
      " only after establishing that no diagnostics run is still running: ",
      "removing it under a live run is not supported."
    )
  } else {
    message(
      "The diagnostics report directory cannot be locked for writing: ",
      lock_path, " could not be created. Check that ", report_dir,
      " is a writable directory."
    )
  }
  quit(status = 2L, runLast = FALSE)
}

# Remove any artifact of a previous run first: a run that stops at the schema
# writes fewer tables, and a stale one beside fresh findings would be read as
# current.
report_manifest_name <- "report_manifest.txt"
report_artifacts <- c(
  report_manifest_name,
  "site_input_diagnostics.txt",
  "findings.csv",
  "finding_values.csv",
  "label_coverage.csv",
  "unit_coverage.csv",
  "year_coverage.csv"
)
stale_artifacts <- file.path(report_dir, report_artifacts)
existing_artifacts <- stale_artifacts[file.exists(stale_artifacts)]

# Publishing beside a table this run did not write would present stale coverage
# as current, but destroying half of the previous report before discovering the
# problem is worse. Check every artifact is writable first and leave the
# directory untouched when one is not.
locked_artifacts <- existing_artifacts[!vapply(
  existing_artifacts,
  function(path) {
    connection <- tryCatch(file(path, open = "ab"), error = function(e) NULL)
    if (is.null(connection)) {
      return(FALSE)
    }
    close(connection)
    TRUE
  },
  logical(1)
)]
if (length(locked_artifacts) > 0L) {
  quit_technical(
    "Report artifacts from a previous run cannot be replaced: ",
    paste(basename(locked_artifacts), collapse = ", "),
    ". Close whatever holds them open, or choose another report directory. ",
    "The previous report was left untouched."
  )
}

# The previous report is deleted only once the complete new one exists in
# staging, so a failure while composing it cannot leave the directory empty. The
# name is unique to this run: a fixed one would be a path this process does not
# own and may not delete.
staging_dir <- tempfile(pattern = ".orchidee_staging_", tmpdir = report_dir)
if (!dir.create(staging_dir, recursive = TRUE, showWarnings = FALSE)) {
  quit_technical(
    "Could not create the diagnostics staging directory: ", staging_dir,
    ". The previous report was left untouched."
  )
}
orchidee_publication_track_staging(publication_state, staging_dir)

report_lines <- c(
  "ORCHIDEE site input diagnostics",
  paste0("generated_at_utc: ", format(Sys.time(), tz = "UTC", usetz = TRUE)),
  "contract: site handoff blocks for external_bundle v3",
  "scope: handoff contract only; this report makes no claim about which",
  "       indicators would be published.",
  ""
)
for (block_name in block_names) {
  report_lines <- c(
    report_lines,
    paste0("  ", block_name, ": ", input_paths[[block_name]])
  )
}
report_lines <- c(
  report_lines,
  "",
  paste0(
    "Findings: ", n_blocking, " BLOCKING, ",
    n_warning, " WARNING, ", n_info, " INFO"
  ),
  ""
)
for (severity in c("BLOCKING", "WARNING", "INFO")) {
  subset_findings <- all_findings[
    all_findings$severity == severity, ,
    drop = FALSE
  ]
  if (nrow(subset_findings) == 0L) {
    next
  }
  report_lines <- c(
    report_lines,
    paste0(severity, " (", nrow(subset_findings), ")")
  )
  for (index in seq_len(nrow(subset_findings))) {
    row <- subset_findings[index, ]
    counts <- character()
    if (!is.na(row$n_rows)) {
      counts <- c(counts, paste0("n_rows=", row$n_rows))
    }
    if (!is.na(row$n_document_occurrences)) {
      counts <- c(
        counts,
        paste0("n_document_occurrences=", row$n_document_occurrences)
      )
    }
    suffix <- if (length(counts) > 0L) {
      paste0(" [", paste(counts, collapse = ", "), "]")
    } else {
      ""
    }
    report_lines <- c(
      report_lines,
      paste0("  [#", row$finding_id, "] ", row$block, " / ", row$check),
      paste0("    ", row$detail, suffix)
    )
  }
  report_lines <- c(report_lines, "")
}

staged_report <- file.path(staging_dir, "site_input_diagnostics.txt")
report_connection <- file(staged_report, open = "wt", encoding = "UTF-8")
writeLines(report_lines, con = report_connection)
close(report_connection)
utils::write.csv(
  all_findings,
  file.path(staging_dir, "findings.csv"),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)

staged_names <- c("site_input_diagnostics.txt", "findings.csv")
optional_tables <- list(
  finding_values.csv = collected_finding_values(),
  label_coverage.csv = label_coverage,
  unit_coverage.csv = unit_coverage,
  year_coverage.csv = year_coverage
)
for (file_name in names(optional_tables)) {
  table <- optional_tables[[file_name]]
  if (is.null(table)) {
    next
  }
  utils::write.csv(
    table,
    file.path(staging_dir, file_name),
    row.names = FALSE,
    fileEncoding = "UTF-8"
  )
  staged_names <- c(staged_names, file_name)
}

# The complete report now exists in staging, so replacing the previous one is
# safe to start. The set of renames is not a single transaction, though, and a
# half-replaced directory carries ordinary file names with nothing to say it is
# incomplete. The manifest closes that: it names the files a complete report is
# made of, it is removed before anything else is touched, and it is written
# last. A report directory without it was interrupted, whatever its contents
# look like.
manifest_lines <- c(
  "ORCHIDEE site input diagnostics report manifest",
  paste0("generated_at_utc: ", format(Sys.time(), tz = "UTC", usetz = TRUE)),
  "",
  "A complete report consists of the files listed below. If this manifest is",
  "absent from a report directory, the run that wrote it was interrupted and",
  "the files beside it must not be read as a current verdict.",
  "",
  staged_names
)
manifest_connection <- file(
  file.path(staging_dir, report_manifest_name),
  open = "wt",
  encoding = "UTF-8"
)
writeLines(manifest_lines, con = manifest_connection)
close(manifest_connection)

# The previous manifest goes first, and its removal is verified rather than
# assumed: unlink() reports nothing useful when the file is held open, and a
# surviving manifest would certify the artifacts replaced after it. Until it is
# gone nothing else is touched, so the previous report stays whole.
manifest_target <- file.path(report_dir, report_manifest_name)
unlink(manifest_target, force = TRUE)
if (file.exists(manifest_target)) {
  quit_technical(
    "The manifest of the previous report cannot be removed: ", manifest_target,
    ". Close whatever holds it open, or choose another report directory. ",
    "The previous report was left untouched."
  )
}

unlink(setdiff(existing_artifacts, manifest_target), force = TRUE)
written_files <- character()
publication_failures <- character()
for (file_name in staged_names) {
  target_path <- file.path(report_dir, file_name)
  renamed <- suppressWarnings(
    file.rename(file.path(staging_dir, file_name), target_path)
  )
  if (isTRUE(renamed)) {
    written_files <- c(written_files, target_path)
  } else {
    publication_failures <- c(publication_failures, file_name)
  }
}
if (length(publication_failures) > 0L) {
  quit_technical(
    "The diagnostics report could not be published in full; ", report_dir,
    " now holds an incomplete report and no ", report_manifest_name,
    ". Missing: ", paste(publication_failures, collapse = ", "),
    ". Rerun once the directory is writable."
  )
}

# Only now, with every artifact in place, may the directory be marked complete.
manifest_published <- suppressWarnings(
  file.rename(file.path(staging_dir, report_manifest_name), manifest_target)
)
if (!isTRUE(manifest_published)) {
  quit_technical(
    "The diagnostics report was written to ", report_dir,
    " but could not be marked complete: ", report_manifest_name,
    " could not be published. Treat the report as incomplete and rerun."
  )
}
written_files <- c(written_files, manifest_target)
release_publication_resources()

cat(paste(report_lines, collapse = "\n"), "\n", sep = "")
cat("Report files:\n")
for (path in written_files) {
  cat("  ", path, "\n", sep = "")
}

if (n_blocking > 0L) {
  cat(
    "\nFAIL: ", n_blocking,
    " blocking findings must be corrected before the site build can complete.\n",
    sep = ""
  )
  quit(status = 1L)
}

cat(
  "\nPASS: the six blocks satisfy the handoff contract. ",
  n_warning,
  " warnings remain for review.\n",
  sep = ""
)
