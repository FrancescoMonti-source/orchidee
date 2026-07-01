ratb_trim_or_na <- function(x) {
  x <- trimws(as.character(x))
  x[!nzchar(x)] <- NA_character_
  x
}

ratb_split_values <- function(x) {
  x <- ratb_trim_or_na(x)
  if (length(x) == 0L || is.na(x)) {
    return(character(0))
  }
  vals <- trimws(unlist(strsplit(x, "\\|", perl = TRUE), use.names = FALSE))
  vals <- vals[!is.na(vals) & nzchar(vals)]
  unique(vals)
}

ratb_parse_logical_flag <- function(x) {
  tolower(trimws(as.character(x))) %in% c("true", "t", "1", "yes", "y")
}

ratb_parse_publication_flag <- function(x, default = TRUE) {
  x <- ratb_trim_or_na(x)
  if_else(is.na(x), default, ratb_parse_logical_flag(x))
}

ratb_detect_delimiter <- function(spec_path) {
  header <- readLines(spec_path, n = 1L, warn = FALSE, encoding = "UTF-8")
  if (length(header) == 0L) {
    stop("Empty RATB indicator spec: ", spec_path, call. = FALSE)
  }

  header <- sub("^\ufeff", "", header[[1]], useBytes = TRUE)
  semicolon_pos <- gregexpr(";", header, fixed = TRUE)[[1]]
  comma_pos <- gregexpr(",", header, fixed = TRUE)[[1]]
  n_semicolon <- sum(semicolon_pos > 0L)
  n_comma <- sum(comma_pos > 0L)

  if (n_semicolon > n_comma) ";" else ","
}

load_ratb_indicator_spec <- function(spec_path) {
  required_cols <- c(
    "indicator_id",
    "wave",
    "enabled",
    "display_order",
    "organism_section",
    "organism_label",
    "organism_filter_type",
    "organism_filter_values",
    "report_taxon_label",
    "indicator_label",
    "indicator_kind",
    "molecule_values",
    "phenotype_flag",
    "scope_mode",
    "sample_type_mode",
    "sample_type_values",
    "analysis_period",
    "numerator_kind",
    "denominator_kind",
    "notes"
  )
  optional_cols <- c("publish_proportion", "publish_incidence")

  if (!file.exists(spec_path)) {
    stop("Missing RATB indicator spec: ", spec_path, call. = FALSE)
  }

  delimiter <- ratb_detect_delimiter(spec_path)

  spec <- utils::read.table(
    file = spec_path,
    header = TRUE,
    sep = delimiter,
    quote = "\"",
    comment.char = "",
    stringsAsFactors = FALSE,
    check.names = FALSE,
    fill = TRUE
  ) %>%
    tibble::as_tibble()

  if (length(names(spec)) > 0L) {
    names(spec)[1] <- sub("^﻿", "", names(spec)[1], useBytes = TRUE)
  }

  missing_cols <- setdiff(required_cols, names(spec))
  if (length(missing_cols) > 0L) {
    stop(
      "RATB indicator spec is missing required columns: ",
      paste(missing_cols, collapse = ", "),
      call. = FALSE
    )
  }

  for (col in setdiff(optional_cols, names(spec))) {
    spec[[col]] <- NA_character_
  }

  char_cols <- setdiff(c(required_cols, optional_cols), c("wave", "enabled", "display_order", "publish_proportion", "publish_incidence"))

  spec %>%
    mutate(
      across(all_of(char_cols), ratb_trim_or_na),
      wave = suppressWarnings(as.integer(wave)),
      enabled = ratb_parse_logical_flag(enabled),
      display_order = suppressWarnings(as.integer(display_order)),
      publish_proportion = ratb_parse_publication_flag(publish_proportion),
      publish_incidence = ratb_parse_publication_flag(publish_incidence)
    ) %>%
    mutate(
      organism_filter_values_list = purrr::map(organism_filter_values, ratb_split_values),
      molecule_values_list = purrr::map(molecule_values, ratb_split_values),
      sample_type_values_list = purrr::map(sample_type_values, ratb_split_values)
    ) %>%
    arrange(display_order, indicator_id)
}


build_species_taxonomy_map <- function(species_regex_map_path) {
  species_taxonomy <- utils::read.csv(
    species_regex_map_path,
    stringsAsFactors = FALSE
  ) %>%
    transmute(
      bact_norm = trimws(as.character(bact_norm)),
      bact_order = trimws(as.character(bact_order))
    ) %>%
    filter(
      !is.na(bact_norm), nzchar(bact_norm),
      !is.na(bact_order), nzchar(bact_order)
    ) %>%
    distinct()

  order_diag <- species_taxonomy %>%
    group_by(bact_norm) %>%
    summarise(n_orders = n_distinct(bact_order), .groups = "drop")

  if (any(order_diag$n_orders != 1L)) {
    bad <- order_diag %>%
      filter(n_orders != 1L) %>%
      pull(bact_norm)
    stop(
      "Non-unique bact_order mapping for bact_norm values: ",
      paste(bad, collapse = ", "),
      call. = FALSE
    )
  }

  species_taxonomy %>%
    distinct(bact_norm, bact_order)
}

validate_ratb_indicator_spec <- function(
    spec,
    atb_cols,
    supported_atb_cols = atb_cols,
    phenotype_cols = character(),
    available_sample_types = character()
  ) {
  allowed_indicator_kinds <- c("class_any_r", "molecule_direct", "molecule_priority", "phenotype_flag")
  allowed_sample_type_modes <- c("global_only", "by_type_only", "global_and_by_type")
  allowed_numerator_kinds <- c("resistant_isolates", "phenotype_positive_isolates")
  allowed_denominator_kinds <- c("tested_isolates", "all_isolates", "hospital_days")

  duplicated_ids <- duplicated(spec$indicator_id) | duplicated(spec$indicator_id, fromLast = TRUE)
  n_requested_molecules <- purrr::map_int(spec$molecule_values_list, length)
  n_supported_molecules <- purrr::map_int(
    spec$molecule_values_list,
    ~ sum(.x %in% supported_atb_cols)
  )
  molecules_unsupported <- purrr::map_chr(
    spec$molecule_values_list,
    ~ paste(setdiff(.x, supported_atb_cols), collapse = " | ")
  )
  n_observed_molecules <- purrr::map_int(
    spec$molecule_values_list,
    ~ sum(.x %in% atb_cols)
  )
  molecules_supported_but_unobserved <- purrr::map_chr(
    spec$molecule_values_list,
    ~ paste(setdiff(intersect(.x, supported_atb_cols), atb_cols), collapse = " | ")
  )
  n_requested_sample_types <- purrr::map_int(spec$sample_type_values_list, length)
  missing_sample_types <- purrr::map_chr(
    spec$sample_type_values_list,
    ~ paste(setdiff(.x, available_sample_types), collapse = " | ")
  )

  tibble(
    indicator_id = spec$indicator_id,
    publish_proportion = spec$publish_proportion,
    publish_incidence = spec$publish_incidence,
    duplicated_indicator_id = duplicated_ids,
    supported_indicator_kind = spec$indicator_kind %in% allowed_indicator_kinds,
    supported_sample_type_mode = spec$sample_type_mode %in% allowed_sample_type_modes,
    supported_numerator_kind = spec$numerator_kind %in% allowed_numerator_kinds,
    supported_denominator_kind = spec$denominator_kind %in% allowed_denominator_kinds,
    has_scope_mode = !is.na(spec$scope_mode) & nzchar(spec$scope_mode),
    has_filter_values = purrr::map_int(spec$organism_filter_values_list, length) > 0L,
    n_requested_molecules = n_requested_molecules,
    n_available_molecules = n_supported_molecules,
    any_molecule_available = n_supported_molecules > 0L,
    all_required_molecules_available = n_supported_molecules == n_requested_molecules,
    molecules_missing = molecules_unsupported,
    n_observed_molecules = n_observed_molecules,
    all_required_molecules_observed = n_observed_molecules == n_requested_molecules,
    molecules_supported_but_unobserved = molecules_supported_but_unobserved,
    has_valid_indicator_payload = case_when(
      spec$indicator_kind %in% c("class_any_r", "molecule_direct", "molecule_priority") ~ n_requested_molecules > 0L,
      spec$indicator_kind == "phenotype_flag" ~ !is.na(spec$phenotype_flag) & nzchar(spec$phenotype_flag),
      TRUE ~ FALSE
    ),
    phenotype_col_present = case_when(
      spec$indicator_kind == "phenotype_flag" ~ spec$phenotype_flag %in% phenotype_cols,
      TRUE ~ NA
    ),
    n_requested_sample_types = n_requested_sample_types,
    all_requested_sample_types_present = case_when(
      n_requested_sample_types == 0L ~ TRUE,
      TRUE ~ purrr::map_lgl(
        spec$sample_type_values_list,
        ~ all(.x %in% available_sample_types)
      )
    ),
    missing_sample_types = missing_sample_types
  ) %>%
    mutate(
      hard_validation_ok =
        !duplicated_indicator_id &
        supported_indicator_kind &
        supported_sample_type_mode &
        supported_numerator_kind &
        supported_denominator_kind &
        has_scope_mode &
        has_filter_values &
        has_valid_indicator_payload
    )
}

build_ratb_indicator_coverage_audit <- function(spec, validation) {
  stopifnot(nrow(spec) == nrow(validation))

  bind_cols(spec, validation %>% select(-indicator_id, -any_of(c("publish_proportion", "publish_incidence")))) %>%
    mutate(
      publication_mode = case_when(
        publish_proportion & publish_incidence ~ "proportion_and_incidence",
        publish_proportion & !publish_incidence ~ "proportion_only",
        !publish_proportion & publish_incidence ~ "incidence_only",
        TRUE ~ "not_published"
      ),
      proportion_execution_status = case_when(
        !publish_proportion ~ "not_requested_proportion",
        !enabled ~ "disabled",
        wave != 1L ~ "not_wave1",
        analysis_period != "annual" ~ "deferred_period",
        !hard_validation_ok ~ "invalid_spec",
        indicator_kind == "phenotype_flag" & !dplyr::coalesce(phenotype_col_present, FALSE) ~ "pending_phenotype_flag",
        indicator_kind != "phenotype_flag" & !any_molecule_available ~ "missing_molecule_support",
        !all_requested_sample_types_present ~ "missing_sample_type_mapping",
        TRUE ~ "published_proportion"
      ),
      incidence_execution_status = case_when(
        !publish_incidence ~ "not_requested_incidence",
        !enabled ~ "disabled",
        wave != 1L ~ "not_wave1",
        analysis_period != "annual" ~ "deferred_period",
        !hard_validation_ok ~ "invalid_spec",
        indicator_kind == "phenotype_flag" & !dplyr::coalesce(phenotype_col_present, FALSE) ~ "pending_phenotype_flag",
        indicator_kind != "phenotype_flag" & !any_molecule_available ~ "missing_molecule_support",
        TRUE ~ "published_incidence"
      ),
      proportion_executable = proportion_execution_status == "published_proportion",
      incidence_executable = incidence_execution_status == "published_incidence",
      execution_status = proportion_execution_status,
      executable_wave1 = proportion_executable,
      coverage_note = case_when(
        proportion_execution_status == "invalid_spec" | incidence_execution_status == "invalid_spec" ~ "Spec row failed hard validation.",
        indicator_kind == "phenotype_flag" & !dplyr::coalesce(phenotype_col_present, FALSE) ~ paste0(
          "Missing phenotype column in artifact: ",
          phenotype_flag
        ),
        indicator_kind != "phenotype_flag" & !any_molecule_available ~ paste0(
          "None of the requested molecules are present in the supported molecule universe: ",
          molecules_missing
        ),
        proportion_execution_status == "missing_sample_type_mapping" ~ paste0(
          "Unknown sample_type_values: ",
          missing_sample_types
        ),
        indicator_kind != "phenotype_flag" &
          any_molecule_available &
          !all_required_molecules_available ~ paste0(
            "Partial molecule coverage against the supported molecule universe. Unsupported: ",
            molecules_missing
          ),
        publication_mode == "incidence_only" ~ "Published in incidence only.",
        publication_mode == "proportion_only" ~ "Published in proportion only.",
        TRUE ~ notes
      )
    )
}


apply_ratb_organism_filter <- function(df, spec_row, bact_order_map) {
  filter_type <- spec_row$organism_filter_type[[1]]
  filter_values <- spec_row$organism_filter_values_list[[1]]

  if (!"bact_order" %in% names(df)) {
    df <- df %>% left_join(bact_order_map, by = "bact_norm")
  }

  if (is.na(filter_type) || !nzchar(filter_type) || length(filter_values) == 0L) {
    return(df)
  }

  if (identical(filter_type, "bact_norm")) {
    return(df %>% filter(bact_norm %in% filter_values))
  }

  if (identical(filter_type, "bact_order")) {
    return(df %>% filter(bact_order %in% filter_values))
  }

  if (identical(filter_type, "enterobacterales_other")) {
    return(
      df %>%
        filter(
          bact_order == "Enterobacterales",
          !(bact_norm %in% filter_values)
        )
    )
  }

  stop("Unsupported organism_filter_type: ", filter_type, call. = FALSE)
}

resolve_ratb_scope_names <- function(sample_type_mode) {
  if (identical(sample_type_mode, "global_only")) {
    return("global")
  }
  if (identical(sample_type_mode, "by_type_only")) {
    return("by_type")
  }
  if (identical(sample_type_mode, "global_and_by_type")) {
    return(c("global", "by_type"))
  }
  stop("Unsupported sample_type_mode: ", sample_type_mode, call. = FALSE)
}

compute_ratb_indicator_result <- function(df, spec_row, atb_cols, supported_atb_cols = atb_cols) {
  kind <- spec_row$indicator_kind[[1]]

  if (identical(kind, "phenotype_flag")) {
    phenotype_col <- spec_row$phenotype_flag[[1]]
    if (!(phenotype_col %in% names(df))) {
      return(NULL)
    }

    result <- if_else(
      as.logical(df[[phenotype_col]]),
      "R",
      "S"
    )

    return(list(
      indicator_result = result,
      n_tested_cells = rep.int(1L, nrow(df)),
      n_resistant_cells = as.integer(result == "R")
    ))
  }

  molecule_cols <- Filter(
    function(col) col %in% supported_atb_cols && col %in% names(df),
    spec_row$molecule_values_list[[1]]
  )
  if (length(molecule_cols) == 0L) {
    return(NULL)
  }

  if (identical(kind, "molecule_priority")) {
    val_mat <- as.matrix(df[, molecule_cols, drop = FALSE])
    tested_idx <- apply(
      val_mat,
      1,
      function(row_vals) {
        match(TRUE, row_vals %in% c("S", "R"), nomatch = 0L)
      }
    )
    has_tested <- tested_idx > 0L
    chosen_vals <- rep(NA_character_, nrow(df))
    if (any(has_tested)) {
      chosen_vals[has_tested] <- val_mat[cbind(which(has_tested), tested_idx[has_tested])]
    }

    indicator_result <- if_else(
      has_tested,
      if_else(chosen_vals == "R", "R", "S"),
      "O"
    )

    return(list(
      indicator_result = indicator_result,
      n_tested_cells = as.integer(has_tested),
      n_resistant_cells = as.integer(has_tested & chosen_vals == "R")
    ))
  }

  val_mat <- as.matrix(df[, molecule_cols, drop = FALSE])
  n_tested_cells <- rowSums((val_mat == "S") | (val_mat == "R"), na.rm = TRUE)
  n_resistant_cells <- rowSums(val_mat == "R", na.rm = TRUE)
  indicator_result <- case_when(
    n_resistant_cells > 0L ~ "R",
    n_tested_cells == 0L ~ "O",
    TRUE ~ "S"
  )

  list(
    indicator_result = indicator_result,
    n_tested_cells = n_tested_cells,
    n_resistant_cells = n_resistant_cells
  )
}

build_ratb_indicator_panel_annual <- function(
    dedup_results,
    spec,
    atb_cols,
    supported_atb_cols = atb_cols,
    bact_order_map
  ) {
  if (nrow(spec) == 0L) {
    return(tibble())
  }

  panels <- purrr::imap_dfr(
    dedup_results,
    function(dataset_res, dataset_name) {
      purrr::map_dfr(
        seq_len(nrow(spec)),
        function(idx) {
          spec_row <- spec[idx, , drop = FALSE]
          scope_names <- resolve_ratb_scope_names(spec_row$sample_type_mode[[1]])

          purrr::map_dfr(
            scope_names,
            function(scope_name) {
              if (!(scope_name %in% names(dataset_res))) {
                return(tibble())
              }

              ds <- dataset_res[[scope_name]]$dedup
              if (!("dedup_year" %in% names(ds))) {
                ds <- ds %>% mutate(dedup_year = lubridate::year(as.Date(DATEPRELEV)))
              }

              ds <- if (identical(scope_name, "global")) {
                ds %>% mutate(sample_type = "all_types")
              } else {
                ds %>% mutate(sample_type = naturepvt_norm)
              }

              requested_types <- spec_row$sample_type_values_list[[1]]
              if (identical(scope_name, "by_type") && length(requested_types) > 0L) {
                ds <- ds %>% filter(sample_type %in% requested_types)
              }

              ds <- apply_ratb_organism_filter(
                df = ds,
                spec_row = spec_row,
                bact_order_map = bact_order_map
              )

              if (nrow(ds) == 0L) {
                return(tibble())
              }

              result <- compute_ratb_indicator_result(
                df = ds,
                spec_row = spec_row,
                atb_cols = atb_cols,
                supported_atb_cols = supported_atb_cols
              )

              if (is.null(result)) {
                return(tibble())
              }

              ds %>%
                mutate(indicator_result = result$indicator_result) %>%
                group_by(dedup_year, sample_type) %>%
                summarise(
                  n_isolates = n(),
                  n_r = sum(indicator_result == "R", na.rm = TRUE),
                  n_s = sum(indicator_result == "S", na.rm = TRUE),
                  n_o = sum(indicator_result == "O", na.rm = TRUE),
                  n_tested = n_r + n_s,
                  n_resistant = n_r,
                  pct_resistant = if_else(
                    n_tested > 0L,
                    100 * n_resistant / n_tested,
                    NA_real_
                  ),
                  .groups = "drop"
                ) %>%
                mutate(
                  dataset = dataset_name,
                  scope = scope_name,
                  organism_section = spec_row$organism_section[[1]],
                  organism_label = spec_row$organism_label[[1]],
                  report_taxon_label = spec_row$report_taxon_label[[1]],
                  indicator_id = spec_row$indicator_id[[1]],
                  indicator_label = spec_row$indicator_label[[1]],
                  indicator_kind = spec_row$indicator_kind[[1]],
                  numerator_kind = spec_row$numerator_kind[[1]],
                  denominator_kind = spec_row$denominator_kind[[1]],
                  display_order = spec_row$display_order[[1]],
                  .before = 1
                )
            }
          )
        }
      )
    }
  )

  panels %>%
    arrange(
      display_order, report_taxon_label, indicator_label,
      dataset, scope, sample_type, dedup_year
    )
}

normalise_ratb_incidence_denominator <- function(
    incidence_denominator_by_year
  ) {
  denominator <- incidence_denominator_by_year
  if (!is.data.frame(denominator)) {
    stop(
      "Incidence denominator must be a data frame.",
      call. = FALSE
    )
  }

  if (all(c("calendar_year", "hospital_nights") %in% names(denominator))) {
    return(
      denominator %>%
        transmute(
          dedup_year = as.integer(calendar_year),
          hospital_nights = as.numeric(hospital_nights),
          denominator_source = "hospital_nights_provisional"
        ) %>%
        arrange(dedup_year)
    )
  }

  stop(
    "Incidence denominator must contain calendar_year and hospital_nights.",
    call. = FALSE
  )
}

build_ratb_indicator_panel_incidence_annual <- function(
    dedup_results,
    spec,
    atb_cols,
    supported_atb_cols = atb_cols,
    bact_order_map,
    incidence_denominator_by_year
  ) {
  if (nrow(spec) == 0L) {
    return(tibble())
  }

  stopifnot(is.list(dedup_results))
  denominator_years <- normalise_ratb_incidence_denominator(
    incidence_denominator_by_year = incidence_denominator_by_year
  )

  panels <- purrr::imap_dfr(
    dedup_results,
    function(dataset_res, dataset_name) {
      if (!("global" %in% names(dataset_res))) {
        return(tibble())
      }

      ds <- dataset_res$global$dedup
      if (!is.data.frame(ds)) {
        return(tibble())
      }

      if (!("dedup_year" %in% names(ds))) {
        ds <- ds %>% mutate(dedup_year = lubridate::year(as.Date(DATEPRELEV)))
      }

      purrr::map_dfr(
        seq_len(nrow(spec)),
        function(idx) {
          spec_row <- spec[idx, , drop = FALSE]
          ds_filtered <- apply_ratb_organism_filter(
            df = ds,
            spec_row = spec_row,
            bact_order_map = bact_order_map
          )

          if (nrow(ds_filtered) == 0L) {
            yearly_counts <- denominator_years %>%
              transmute(
                dedup_year,
                n_isolates = 0L,
                n_r = 0L,
                n_s = 0L,
                n_o = 0L,
                n_tested = 0L,
                n_resistant = 0L
              )
          } else {
            result <- compute_ratb_indicator_result(
              df = ds_filtered,
              spec_row = spec_row,
              atb_cols = atb_cols,
              supported_atb_cols = supported_atb_cols
            )

            if (is.null(result)) {
              stop(
                "Incidence builder received a non-computable indicator payload for: ",
                spec_row$indicator_id[[1]],
                call. = FALSE
              )
            }

            yearly_counts <- ds_filtered %>%
              mutate(indicator_result = result$indicator_result) %>%
              group_by(dedup_year) %>%
              summarise(
                n_isolates = n(),
                n_r = sum(indicator_result == "R", na.rm = TRUE),
                n_s = sum(indicator_result == "S", na.rm = TRUE),
                n_o = sum(indicator_result == "O", na.rm = TRUE),
                n_tested = n_r + n_s,
                n_resistant = n_r,
                .groups = "drop"
              )

            yearly_counts <- denominator_years %>%
              select(dedup_year) %>%
              left_join(yearly_counts, by = "dedup_year") %>%
              mutate(
                across(
                  c(n_isolates, n_r, n_s, n_o, n_tested, n_resistant),
                  ~ dplyr::coalesce(as.integer(.x), 0L)
                )
              )
          }

          yearly_counts %>%
            left_join(denominator_years, by = "dedup_year") %>%
            mutate(
              incidence_density_per_1000 = if_else(
                !is.na(hospital_nights) & hospital_nights > 0,
                1000 * n_resistant / hospital_nights,
                NA_real_
              ),
              dataset = dataset_name,
              scope = "global",
              sample_type = "all_types",
              organism_section = spec_row$organism_section[[1]],
              organism_label = spec_row$organism_label[[1]],
              report_taxon_label = spec_row$report_taxon_label[[1]],
              indicator_id = spec_row$indicator_id[[1]],
              indicator_label = spec_row$indicator_label[[1]],
              indicator_kind = spec_row$indicator_kind[[1]],
              numerator_kind = spec_row$numerator_kind[[1]],
              denominator_kind = "hospital_days",
              display_order = spec_row$display_order[[1]],
              metric_name = "incidence_density_per_1000",
              .before = 1
            )
        }
      )
    }
  )

  panels %>%
    arrange(
      display_order, report_taxon_label, indicator_label,
      dataset, dedup_year
    )
}

