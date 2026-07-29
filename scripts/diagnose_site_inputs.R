#!/usr/bin/env Rscript

## Aggregated diagnostics for the six site-owned handoff blocks.
##
## This CLI answers exactly one question: do the six blocks satisfy the
## handoff contract, and where do they not? It reads each block once, collects
## every finding instead of stopping at the first one, and classifies each
## finding as BLOCKING, WARNING or INFO.
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
    "BLOCKING, WARNING and INFO. Exit status is 1 when at least one BLOCKING\n",
    "finding remains, otherwise 0.\n\n",
    "The report contains aggregate counts and local vocabulary only. It never\n",
    "writes patient identifiers.\n",
    sep = ""
  )
  quit(status = if (length(args) == 0L || any(args %in% c("-h", "--help"))) {
    0L
  } else {
    1L
  })
}

suppressPackageStartupMessages(library(dplyr))
source("R/bootstrap.R")
orchidee_source_required_script("helpers.R")
orchidee_source_required_script("phenotype_flag_helpers.R")
orchidee_source_required_script("external_bundle_validation_helpers.R")
orchidee_source_required_script("ratb_hospital_days_helpers.R")
orchidee_source_required_script("external_handoff_helpers.R")

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

add_finding <- function(
    severity,
    block,
    check,
    detail,
    n_rows = NA_integer_,
    n_document_occurrences = NA_integer_
  ) {
  findings[[length(findings) + 1L]] <<- data.frame(
    severity = severity,
    block = block,
    check = check,
    detail = detail,
    n_rows = as.integer(n_rows),
    n_document_occurrences = as.integer(n_document_occurrences),
    stringsAsFactors = FALSE
  )
  invisible(NULL)
}

collected_findings <- function() {
  if (length(findings) == 0L) {
    return(data.frame(
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
  out[order(severity_rank, out$block, out$check), , drop = FALSE]
}

format_values <- function(x, limit = 10L) {
  x <- sort(unique(as.character(x)))
  shown <- utils::head(x, limit)
  paste0(
    paste(shown, collapse = ", "),
    if (length(x) > limit) {
      paste0(" (+", length(x) - limit, " more; see the report files)")
    } else {
      ""
    }
  )
}

## ---------------------------------------------------------------------------
## Read the six blocks once
## ---------------------------------------------------------------------------

blocks <- list()
read_failed <- FALSE
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
      read_failed <<- TRUE
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
    read_failed <- TRUE
    block <- NULL
  }
  blocks[[block_name]] <- block
}

## ---------------------------------------------------------------------------
## Column contract
## ---------------------------------------------------------------------------

column_contract_ok <- !read_failed
if (!read_failed) {
  for (block_name in block_names) {
    block <- blocks[[block_name]]
    add_finding(
      "INFO",
      block_name,
      "rows_read",
      paste0(nrow(block), " rows, ", ncol(block), " columns."),
      n_rows = nrow(block)
    )

    duplicate_columns <- unique(names(block)[duplicated(names(block))])
    if (length(duplicate_columns) > 0L) {
      column_contract_ok <- FALSE
      add_finding(
        "BLOCKING",
        block_name,
        "duplicate_columns",
        paste0(
          "Duplicate column names: ",
          format_values(duplicate_columns),
          "."
        )
      )
    }

    missing_columns <- setdiff(spec[[block_name]]$required_columns, names(block))
    if (length(missing_columns) > 0L) {
      column_contract_ok <- FALSE
      add_finding(
        "BLOCKING",
        block_name,
        "missing_required_columns",
        paste0(
          "Missing required columns: ",
          format_values(missing_columns),
          "."
        )
      )
    }

    for (one_of_name in names(spec[[block_name]]$required_one_of)) {
      candidates <- spec[[block_name]]$required_one_of[[one_of_name]]
      present <- intersect(candidates, names(block))
      if (length(present) != 1L) {
        column_contract_ok <- FALSE
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
  }
}

## ---------------------------------------------------------------------------
## Content checks
## ---------------------------------------------------------------------------

label_coverage <- NULL
unit_coverage <- NULL
year_coverage <- NULL

if (column_contract_ok) {
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

  count_occurrences <- function(keys) {
    keys <- keys[!is.na(keys)]
    length(unique(keys))
  }

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

  unusable_key <- is.na(document_key)
  if (any(unusable_key)) {
    add_finding(
      "BLOCKING",
      "microbiology_observations",
      "missing_document_identity",
      paste0(
        sum(unusable_key),
        " rows have a missing PATID or ELTID and cannot be assigned to a ",
        "document occurrence."
      ),
      n_rows = sum(unusable_key)
    )
  }

  if ("EVTID" %in% names(blocks$microbiology_observations)) {
    usable <- !is.na(document_key)
    fallback_rows <- usable & startsWith(document_key, "patient_sample")
    if (any(fallback_rows)) {
      add_finding(
        "INFO",
        "microbiology_observations",
        "document_identity_fallback",
        paste0(
          count_occurrences(document_key[fallback_rows]),
          " document occurrences fall back to PATID + ELTID because at least ",
          "one row of the group has no EVTID."
        ),
        n_rows = sum(fallback_rows),
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

  if (is.null(diagnostic_scope)) {
    obs_in_scope <- obs[0, , drop = FALSE]
    document_key_in_scope <- character()
  } else {
    usable_key <- !is.na(document_key)
    propagate_screening <- rep(FALSE, nrow(obs))
    if (any(usable_key)) {
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
        sum(!diagnostic_scope),
        " rows are flagged outside the diagnostic scope; excluding their whole ",
        "document occurrences removes ",
        sum(drop_mask),
        " rows (",
        count_occurrences(document_key[drop_mask]),
        " occurrences)."
      ),
      n_rows = sum(drop_mask),
      n_document_occurrences = count_occurrences(document_key[drop_mask])
    )

    collateral <- sum(drop_mask) - sum(!diagnostic_scope)
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

  ## Dates, times and results -------------------------------------------------

  sample_dates <- NULL
  if (nrow(obs_in_scope) > 0L) {
    sample_dates <- tryCatch(
      orchidee_handoff_parse_date(obs_in_scope$DATEPRELEV),
      error = function(e) {
        add_finding(
          "BLOCKING",
          "microbiology_observations",
          "dateprelev_format",
          conditionMessage(e)
        )
        NULL
      }
    )

    if ("HEUREPRELEV" %in% names(obs_in_scope)) {
      invisible(tryCatch(
        orchidee_handoff_parse_time(obs_in_scope$HEUREPRELEV),
        error = function(e) {
          add_finding(
            "BLOCKING",
            "microbiology_observations",
            "heureprelev_format",
            conditionMessage(e)
          )
          NULL
        }
      ))
    }

    normalized_sir <- orchidee_handoff_normalize_sir(obs_in_scope$sir_result)
    raw_sir <- orchidee_handoff_trim_or_na(obs_in_scope$sir_result)
    unsupported_sir <- setdiff(
      unique(normalized_sir[!is.na(normalized_sir)]),
      contract$sir_wide$allowed_atb_values
    )
    if (length(unsupported_sir) > 0L) {
      unsupported_rows <- sum(normalized_sir %in% unsupported_sir)
      add_finding(
        "BLOCKING",
        "microbiology_observations",
        "unsupported_sir_values",
        paste0(
          "sir_result contains values ORCHIDEE does not recognize: ",
          format_values(raw_sir[normalized_sir %in% unsupported_sir]),
          "."
        ),
        n_rows = unsupported_rows
      )
    }
    missing_sir <- sum(is.na(normalized_sir))
    if (missing_sir > 0L) {
      add_finding(
        "INFO",
        "microbiology_observations",
        "missing_sir_values",
        paste0(
          missing_sir,
          " rows have an empty or non-interpretable S/I/R result and will not ",
          "populate an antibiotic column."
        ),
        n_rows = missing_sir
      )
    }

    souche_col <- intersect(
      c("souche_id", "isolate_local_id"),
      names(obs_in_scope)
    )
    if (length(souche_col) == 0L) {
      add_finding(
        "WARNING",
        "microbiology_observations",
        "isolate_identifier_absent",
        paste0(
          "No souche_id or isolate_local_id column. Two isolates of the same ",
          "species in one sample would be merged into a single ORCHIDEE row."
        )
      )
    } else {
      derived <- is.na(orchidee_handoff_trim_or_na(
        obs_in_scope[[souche_col[[1L]]]]
      ))
      if (any(derived)) {
        add_finding(
          "WARNING",
          "microbiology_observations",
          "isolate_identifier_missing",
          paste0(
            sum(derived),
            " rows have no ",
            souche_col[[1L]],
            " value; ORCHIDEE derives one from sample type and bacterium, ",
            "which merges distinct isolates of the same species."
          ),
          n_rows = sum(derived)
        )
      }
    }
  }

  ## Mapping coverage --------------------------------------------------------

  coverage_for_dimension <- function(
      dimension,
      local_column,
      mapping_block,
      local_key_column,
      canonical_column,
      canonical_may_be_blank
    ) {
    mapping <- blocks[[mapping_block]]
    local_values <- orchidee_handoff_trim_or_na(obs_in_scope[[local_column]])
    mapping_keys <- orchidee_handoff_trim_or_na(mapping[[local_key_column]])
    mapping_values <- orchidee_handoff_trim_or_na(mapping[[canonical_column]])

    duplicate_keys <- unique(mapping_keys[
      duplicated(mapping_keys) & !is.na(mapping_keys)
    ])
    if (length(duplicate_keys) > 0L) {
      conflicting <- vapply(
        duplicate_keys,
        function(key) {
          length(unique(mapping_values[mapping_keys %in% key])) > 1L
        },
        logical(1)
      )
      if (any(conflicting)) {
        add_finding(
          "BLOCKING",
          mapping_block,
          "conflicting_duplicate_keys",
          paste0(
            "These local labels appear more than once with different ",
            canonical_column,
            " values: ",
            format_values(duplicate_keys[conflicting]),
            "."
          )
        )
      } else {
        add_finding(
          "INFO",
          mapping_block,
          "duplicate_keys",
          paste0(
            length(duplicate_keys),
            " local labels are listed more than once with the same ",
            canonical_column,
            " value."
          )
        )
      }
    }

    match_idx <- match(local_values, mapping_keys)
    canonical <- mapping_values[match_idx]
    status <- ifelse(
      is.na(local_values),
      "missing_local_label",
      ifelse(
        is.na(match_idx),
        "unmapped",
        ifelse(is.na(canonical), "blank_canonical", "mapped")
      )
    )

    per_label <- data.frame(
      dimension = dimension,
      local_label = ifelse(is.na(local_values), "<missing>", local_values),
      canonical_value = ifelse(is.na(canonical), "", canonical),
      status = status,
      document_key = document_key_in_scope,
      stringsAsFactors = FALSE
    )
    summary_table <- per_label %>%
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

    unmapped <- summary_table[summary_table$status == "unmapped", , drop = FALSE]
    if (nrow(unmapped) > 0L) {
      add_finding(
        "BLOCKING",
        mapping_block,
        "unmapped_local_labels",
        paste0(
          nrow(unmapped),
          " local labels present in microbiology_observations have no row in ",
          mapping_block,
          ": ",
          format_values(unmapped$local_label),
          "."
        ),
        n_rows = sum(unmapped$n_rows),
        n_document_occurrences = sum(unmapped$n_document_occurrences)
      )
    }

    missing_local <- summary_table[
      summary_table$status == "missing_local_label", ,
      drop = FALSE
    ]
    if (nrow(missing_local) > 0L) {
      add_finding(
        "BLOCKING",
        "microbiology_observations",
        paste0("missing_", local_column),
        paste0(
          sum(missing_local$n_rows),
          " rows have an empty ",
          local_column,
          " value."
        ),
        n_rows = sum(missing_local$n_rows)
      )
    }

    blank_canonical <- summary_table[
      summary_table$status == "blank_canonical", ,
      drop = FALSE
    ]
    if (nrow(blank_canonical) > 0L) {
      consequence <- if (canonical_may_be_blank) {
        paste0(
          ". Those rows stay available for global indicators but cannot ",
          "contribute to analyses that require a known sample type."
        )
      } else {
        ". The build requires a canonical value for every mapped label."
      }
      add_finding(
        if (canonical_may_be_blank) "WARNING" else "BLOCKING",
        mapping_block,
        "blank_canonical_value",
        paste0(
          nrow(blank_canonical),
          " local labels are listed with an empty ",
          canonical_column,
          ": ",
          format_values(blank_canonical$local_label),
          consequence
        ),
        n_rows = sum(blank_canonical$n_rows),
        n_document_occurrences = sum(blank_canonical$n_document_occurrences)
      )
    }

    mapped <- summary_table[summary_table$status == "mapped", , drop = FALSE]
    add_finding(
      "INFO",
      mapping_block,
      "mapped_local_labels",
      paste0(
        nrow(mapped),
        " local labels are mapped, covering ",
        sum(mapped$n_rows),
        " rows and ",
        sum(mapped$n_document_occurrences),
        " document occurrences."
      ),
      n_rows = sum(mapped$n_rows),
      n_document_occurrences = sum(mapped$n_document_occurrences)
    )

    unused <- setdiff(mapping_keys[!is.na(mapping_keys)], local_values)
    if (length(unused) > 0L) {
      add_finding(
        "INFO",
        mapping_block,
        "unused_mapping_rows",
        paste0(
          length(unused),
          " mapping rows describe local labels absent from the observations ",
          "that enter the build."
        )
      )
    }

    summary_table[, setdiff(names(summary_table), "document_key"), drop = FALSE]
  }

  if (nrow(obs_in_scope) > 0L) {
    label_coverage <- rbind(
      coverage_for_dimension(
        "bacteria",
        "bacteria_local",
        "bacteria_mapping",
        "bacteria_local",
        "bact_norm",
        canonical_may_be_blank = FALSE
      ),
      coverage_for_dimension(
        "sample_type",
        "sample_type_local",
        "sample_type_mapping",
        "sample_type_local",
        "naturepvt_norm",
        canonical_may_be_blank = TRUE
      ),
      coverage_for_dimension(
        "antibiotic",
        "antibiotic_local",
        "antibiotic_mapping",
        "antibiotic_local",
        "atb_norm",
        canonical_may_be_blank = FALSE
      )
    )

    mapped_atb <- label_coverage$canonical_value[
      label_coverage$dimension == "antibiotic" &
        label_coverage$status == "mapped"
    ]
    unsupported_atb <- setdiff(unique(mapped_atb), contract$sir_wide$atb_cols)
    if (length(unsupported_atb) > 0L) {
      affected <- label_coverage$dimension == "antibiotic" &
        label_coverage$canonical_value %in% unsupported_atb
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
        n_rows = sum(label_coverage$n_rows[affected])
      )
    }
  }

  ## Unit mapping and TA/DE coherence ----------------------------------------

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

  if (any(is.na(unit$SEJUF))) {
    add_finding(
      "BLOCKING",
      "unit_mapping",
      "missing_sejuf",
      paste0(sum(is.na(unit$SEJUF)), " rows have an empty SEJUF value."),
      n_rows = sum(is.na(unit$SEJUF))
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
      )
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

  context <- ratb_analysis_context_profile("spares_current")
  unit$eligible <- unit$CODE_TA %in% context$eligible_ta_codes &
    unit$de_domain_ref %in% context$eligible_de_domains

  exposure <- blocks$incidence_exposure_by_year_um_uf_ta_de_profile
  exposure_norm <- data.frame(
    calendar_year = suppressWarnings(as.integer(
      orchidee_handoff_trim_or_na(exposure$calendar_year)
    )),
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
    exposure_value = suppressWarnings(as.numeric(
      orchidee_handoff_trim_or_na(exposure$exposure_value)
    )),
    exposure_unit = orchidee_handoff_trim_or_na(exposure$exposure_unit),
    stringsAsFactors = FALSE
  )

  required_exposure_cols <-
    spec$incidence_exposure_by_year_um_uf_ta_de_profile$required_columns
  for (column in required_exposure_cols) {
    n_missing <- sum(is.na(exposure_norm[[column]]))
    if (n_missing > 0L) {
      add_finding(
        "BLOCKING",
        "incidence_exposure_by_year_um_uf_ta_de_profile",
        "missing_required_value",
        paste0(
          n_missing,
          " rows have a missing or non-interpretable ",
          column,
          " value; all nine columns are required and non-missing."
        ),
        n_rows = n_missing
      )
    }
  }

  negative_exposure <- sum(exposure_norm$exposure_value < 0, na.rm = TRUE)
  if (negative_exposure > 0L) {
    add_finding(
      "BLOCKING",
      "incidence_exposure_by_year_um_uf_ta_de_profile",
      "negative_exposure_value",
      paste0(negative_exposure, " rows have a negative exposure_value."),
      n_rows = negative_exposure
    )
  }

  profiles <- ratb_denominator_profile_registry()
  profile_match <- match(
    exposure_norm$denominator_profile_id,
    profiles$denominator_profile_id
  )
  invalid_profile <- is.na(profile_match) &
    !is.na(exposure_norm$denominator_profile_id)
  invalid_unit <- !is.na(profile_match) &
    exposure_norm$exposure_unit != profiles$exposure_unit[profile_match]
  if (any(invalid_profile | invalid_unit)) {
    add_finding(
      "BLOCKING",
      "incidence_exposure_by_year_um_uf_ta_de_profile",
      "unsupported_denominator_profile",
      paste0(
        "Unsupported denominator_profile_id / exposure_unit pairs. Accepted ",
        "pairs are: ",
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
      n_rows = sum(invalid_profile | invalid_unit)
    )
  }

  grain_cols <- c(
    "calendar_year", "SEJUM", "SEJUF", "CODE_TA", "CODE_DE",
    "de_domain_ref", "denominator_profile_id"
  )
  duplicated_grain <- duplicated(exposure_norm[grain_cols])
  if (any(duplicated_grain)) {
    add_finding(
      "BLOCKING",
      "incidence_exposure_by_year_um_uf_ta_de_profile",
      "duplicate_grain_rows",
      paste0(
        sum(duplicated_grain),
        " rows repeat the expected grain ",
        paste(grain_cols, collapse = " + "),
        ". Aggregate them before handoff."
      ),
      n_rows = sum(duplicated_grain)
    )
  }

  ## Cross-block unit coverage ------------------------------------------------

  exposure_uf <- unique(exposure_norm$SEJUF[!is.na(exposure_norm$SEJUF)])
  observed_uf <- if (nrow(obs_in_scope) > 0L) {
    unique(obs_in_scope$SEJUF[!is.na(obs_in_scope$SEJUF)])
  } else {
    character()
  }

  uncovered_exposure_uf <- setdiff(exposure_uf, unit$SEJUF)
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
      n_rows = sum(affected)
    )
  }

  uncovered_observed_uf <- setdiff(observed_uf, unit$SEJUF)
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
      n_rows = sum(affected),
      n_document_occurrences = length(unique(
        document_key_in_scope[affected & !is.na(document_key_in_scope)]
      ))
    )
  }

  # A duplicated SEJUF is already reported as BLOCKING above. Join on its first
  # row so the remaining cross-block checks stay one-to-one and their counts
  # keep describing the exposure block rather than the duplication.
  unit_lookup <- unit[!duplicated(unit$SEJUF), , drop = FALSE]
  exposure_with_unit <- exposure_norm %>%
    dplyr::left_join(
      unit_lookup %>%
        dplyr::select(
          SEJUF,
          unit_CODE_TA = "CODE_TA",
          unit_CODE_DE = "CODE_DE",
          unit_de_domain_ref = "de_domain_ref"
        ),
      by = "SEJUF"
    )
  discordant <- !is.na(exposure_with_unit$unit_CODE_TA) & (
    exposure_with_unit$CODE_TA != exposure_with_unit$unit_CODE_TA |
      exposure_with_unit$CODE_DE != exposure_with_unit$unit_CODE_DE |
      exposure_with_unit$de_domain_ref != exposure_with_unit$unit_de_domain_ref
  )
  discordant[is.na(discordant)] <- FALSE
  if (any(discordant)) {
    add_finding(
      "BLOCKING",
      "incidence_exposure_by_year_um_uf_ta_de_profile",
      "ta_de_disagrees_with_unit_mapping",
      paste0(
        sum(discordant),
        " exposure rows carry CODE_TA, CODE_DE or de_domain_ref values that ",
        "differ from unit_mapping for the same SEJUF: ",
        format_values(exposure_with_unit$SEJUF[discordant]),
        ". The two blocks must agree exactly."
      ),
      n_rows = sum(discordant)
    )
  }

  unit_coverage <- unit_lookup %>%
    dplyr::mutate(
      in_exposure = .data$SEJUF %in% exposure_uf,
      in_microbiology = .data$SEJUF %in% observed_uf,
      included_in_spares_current = .data$eligible
    ) %>%
    dplyr::select(
      "SEJUF",
      "CODE_TA",
      "CODE_DE",
      "de_domain_ref",
      "included_in_spares_current",
      "in_exposure",
      "in_microbiology"
    ) %>%
    as.data.frame()

  add_finding(
    "INFO",
    "unit_mapping",
    "perimeter_summary",
    paste0(
      sum(unit_lookup$eligible, na.rm = TRUE),
      " of ",
      nrow(unit_lookup),
      " distinct mapped units fall inside the current spares_current perimeter ",
      "(TA ",
      paste(context$eligible_ta_codes, collapse = "/"),
      " and a ratified DE domain). Units outside it remain valid v3 activity."
    )
  )

  ## Exposure totals and year coverage ---------------------------------------

  # Mirror the runtime projection: it keeps an exposure row only when the row's
  # own TA/DE is eligible and the unit is eligible in the scope reference. An
  # exposure row whose SEJUF has no unit_mapping row is already reported as
  # BLOCKING and cannot contribute.
  unit_eligibility <- unit_lookup$eligible[
    match(exposure_norm$SEJUF, unit_lookup$SEJUF)
  ]
  in_context <- exposure_norm$CODE_TA %in% context$eligible_ta_codes &
    exposure_norm$de_domain_ref %in% context$eligible_de_domains &
    exposure_norm$denominator_profile_id %in% context$denominator_profile_id &
    exposure_norm$exposure_unit %in% context$exposure_unit &
    unit_eligibility %in% TRUE
  in_context[is.na(in_context)] <- FALSE

  exposure_years <- sort(unique(
    exposure_norm$calendar_year[!is.na(exposure_norm$calendar_year)]
  ))
  microbiology_years <- if (!is.null(sample_dates)) {
    sort(unique(as.integer(format(sample_dates, "%Y"))))
  } else {
    integer()
  }

  if (length(exposure_years) > 0L) {
    year_coverage <- data.frame(
      calendar_year = exposure_years,
      exposure_total = vapply(
        exposure_years,
        function(year) {
          sum(
            exposure_norm$exposure_value[
              exposure_norm$calendar_year %in% year
            ],
            na.rm = TRUE
          )
        },
        numeric(1)
      ),
      exposure_in_spares_current = vapply(
        exposure_years,
        function(year) {
          sum(
            exposure_norm$exposure_value[
              exposure_norm$calendar_year %in% year & in_context
            ],
            na.rm = TRUE
          )
        },
        numeric(1)
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
      "incidence_exposure_by_year_um_uf_ta_de_profile",
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
        ", which becomes hospital_nights in the operational v2 bundle."
      )
    )

    empty_context_years <- year_coverage$calendar_year[
      year_coverage$exposure_in_spares_current == 0
    ]
    if (length(empty_context_years) > 0L) {
      add_finding(
        "WARNING",
        "incidence_exposure_by_year_um_uf_ta_de_profile",
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
      "incidence_exposure_by_year_um_uf_ta_de_profile",
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
      "incidence_exposure_by_year_um_uf_ta_de_profile",
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
  stop("Could not create the diagnostics report directory: ", report_dir,
       call. = FALSE)
}
report_dir <- normalizePath(report_dir, winslash = "/", mustWork = TRUE)

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
  report_lines <- c(report_lines, paste0(severity, " (", nrow(subset_findings), ")"))
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
      paste0("  ", row$block, " / ", row$check),
      paste0("    ", row$detail, suffix)
    )
  }
  report_lines <- c(report_lines, "")
}

report_path <- file.path(report_dir, "site_input_diagnostics.txt")
findings_path <- file.path(report_dir, "findings.csv")
report_connection <- file(report_path, open = "wt", encoding = "UTF-8")
writeLines(report_lines, con = report_connection)
close(report_connection)
utils::write.csv(
  all_findings,
  findings_path,
  row.names = FALSE,
  fileEncoding = "UTF-8"
)

written_files <- c(report_path, findings_path)
if (!is.null(label_coverage)) {
  label_path <- file.path(report_dir, "label_coverage.csv")
  utils::write.csv(
    label_coverage,
    label_path,
    row.names = FALSE,
    fileEncoding = "UTF-8"
  )
  written_files <- c(written_files, label_path)
}
if (!is.null(unit_coverage)) {
  unit_path <- file.path(report_dir, "unit_coverage.csv")
  utils::write.csv(
    unit_coverage,
    unit_path,
    row.names = FALSE,
    fileEncoding = "UTF-8"
  )
  written_files <- c(written_files, unit_path)
}
if (!is.null(year_coverage)) {
  year_path <- file.path(report_dir, "year_coverage.csv")
  utils::write.csv(
    year_coverage,
    year_path,
    row.names = FALSE,
    fileEncoding = "UTF-8"
  )
  written_files <- c(written_files, year_path)
}

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
