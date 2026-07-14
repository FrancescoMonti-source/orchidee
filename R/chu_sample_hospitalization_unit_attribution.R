# CHU sample-to-hospitalization-unit attribution.
#
# This helper implements the upstream attribution contract without wiring it
# into the current v1 cache, canonical bundle, or indicator runtime. Source
# R/ratb_hospital_days_helpers.R first for the shared local time and trimming
# primitives used below. Pass the uncollapsed `pmsi$main` returned by `redsan`
# with `source_policy = "c_over_dw"`.

build_chu_sample_hospitalization_unit_attribution <- function(
    sir_wide,
    pmsi_main
  ) {
  stopifnot(
    is.data.frame(sir_wide),
    is.data.frame(pmsi_main)
  )

  sample_cols <- c(
    "PATID", "EVTID", "ELTID", "DATEPRELEV", "HEUREPRELEV",
    "SEJUM", "SEJUF"
  )
  interval_cols <- c(
    "PATID", "EVTID", "DATENT", "DATSORT", "SEJUM", "SEJUF"
  )
  missing_sample_cols <- setdiff(sample_cols, names(sir_wide))
  missing_interval_cols <- setdiff(
    interval_cols,
    names(pmsi_main)
  )
  if (length(missing_sample_cols) > 0L) {
    stop(
      "sir_wide is missing sample-attribution columns: ",
      paste(missing_sample_cols, collapse = ", "),
      call. = FALSE
    )
  }
  if (length(missing_interval_cols) > 0L) {
    stop(
      "PMSI main is missing sample-attribution columns: ",
      paste(missing_interval_cols, collapse = ", "),
      call. = FALSE
    )
  }
  if (!inherits(sir_wide$DATEPRELEV, "Date") ||
      !inherits(sir_wide$HEUREPRELEV, "difftime") ||
      !inherits(pmsi_main$DATENT, "POSIXt") ||
      !inherits(pmsi_main$DATSORT, "POSIXt")) {
    stop(
      "Sample attribution requires DATEPRELEV Date, HEUREPRELEV difftime, ",
      "and PMSI DATENT/DATSORT POSIXt columns.",
      call. = FALSE
    )
  }

  sample_variants <- sir_wide %>%
    transmute(
      PATID = ratb_trim_or_na_local(PATID),
      EVTID = ratb_trim_or_na_local(EVTID),
      ELTID = ratb_trim_or_na_local(ELTID),
      DATEPRELEV = DATEPRELEV,
      HEUREPRELEV = HEUREPRELEV,
      microbiology_SEJUM = ratb_trim_or_na_local(SEJUM),
      microbiology_SEJUF = ratb_trim_or_na_local(SEJUF)
    ) %>%
    distinct()

  inconsistent_samples <- sample_variants %>%
    count(PATID, EVTID, ELTID, name = "n_sample_variants") %>%
    filter(n_sample_variants > 1L)
  if (nrow(inconsistent_samples) > 0L) {
    stop(
      "Sample attribution requires one datetime and microbiology UM/UF pair ",
      "per PATID + EVTID + ELTID.",
      call. = FALSE
    )
  }

  interval_tz <- ratb_resolve_posix_tz(pmsi_main$DATENT)
  sample_seconds <- as.integer(round(as.numeric(
    sample_variants$HEUREPRELEV,
    units = "secs"
  )))
  sample_datetime_missing <-
    is.na(sample_variants$DATEPRELEV) | is.na(sample_seconds)
  sample_time_of_day_valid <-
    !sample_datetime_missing & sample_seconds >= 0L & sample_seconds < 86400L
  sample_wall_clock <- rep(NA_character_, nrow(sample_variants))
  sample_wall_clock[sample_time_of_day_valid] <- paste(
    as.character(sample_variants$DATEPRELEV[sample_time_of_day_valid]),
    sprintf(
      "%02d:%02d:%02d",
      sample_seconds[sample_time_of_day_valid] %/% 3600L,
      (sample_seconds[sample_time_of_day_valid] %% 3600L) %/% 60L,
      sample_seconds[sample_time_of_day_valid] %% 60L
    )
  )
  sample_datetime <- as.POSIXct(
    sample_wall_clock,
    format = "%Y-%m-%d %H:%M:%S",
    tz = interval_tz
  )
  sample_clock_roundtrip <- format(
    sample_datetime,
    format = "%Y-%m-%d %H:%M:%S",
    tz = interval_tz
  )
  sample_datetime_normalized <-
    sample_time_of_day_valid &
    !is.na(sample_datetime) &
    sample_clock_roundtrip != sample_wall_clock
  sample_datetime_normalized[is.na(sample_datetime_normalized)] <- FALSE
  same_clock_one_hour_before <-
    !is.na(sample_datetime) &
    format(
      sample_datetime - 3600,
      format = "%Y-%m-%d %H:%M:%S",
      tz = interval_tz
    ) == sample_wall_clock
  same_clock_one_hour_after <-
    !is.na(sample_datetime) &
    format(
      sample_datetime + 3600,
      format = "%Y-%m-%d %H:%M:%S",
      tz = interval_tz
    ) == sample_wall_clock
  same_clock_one_hour_before[is.na(same_clock_one_hour_before)] <- FALSE
  same_clock_one_hour_after[is.na(same_clock_one_hour_after)] <- FALSE
  sample_datetime_ambiguous <-
    same_clock_one_hour_before | same_clock_one_hour_after

  sample_datetime_status <- rep("valid", nrow(sample_variants))
  sample_datetime_status[sample_datetime_missing] <- "missing_date_or_time"
  sample_datetime_status[
    !sample_datetime_missing & !sample_time_of_day_valid
  ] <- "invalid_time_of_day"
  sample_datetime_status[
    sample_time_of_day_valid &
      (is.na(sample_datetime) | sample_datetime_normalized)
  ] <- "nonexistent_local_time"
  sample_datetime_status[sample_datetime_ambiguous] <- "ambiguous_local_time"
  sample_datetime[sample_datetime_status != "valid"] <- NA

  samples <- sample_variants %>%
    mutate(
      .sample_id = row_number(),
      sample_datetime = sample_datetime,
      sample_datetime_status = sample_datetime_status
    )

  intervals <- pmsi_main %>%
    transmute(
      PATID = ratb_trim_or_na_local(PATID),
      EVTID = ratb_trim_or_na_local(EVTID),
      DATENT = DATENT,
      DATSORT = DATSORT,
      hospitalization_SEJUM_at_sampling = ratb_trim_or_na_local(SEJUM),
      hospitalization_SEJUF_at_sampling = ratb_trim_or_na_local(SEJUF)
    ) %>%
    filter(
      !is.na(PATID),
      !is.na(EVTID),
      !is.na(DATENT),
      !is.na(DATSORT)
    )

  active_intervals <- samples %>%
    filter(
      !is.na(PATID),
      !is.na(EVTID),
      !is.na(sample_datetime)
    ) %>%
    inner_join(
      intervals,
      by = c("PATID", "EVTID"),
      relationship = "many-to-many",
      na_matches = "never"
    ) %>%
    filter(DATENT <= sample_datetime, sample_datetime < DATSORT)

  active_interval_counts <- active_intervals %>%
    group_by(.sample_id) %>%
    summarise(
      n_active_interval_records = n(),
      n_active_incomplete_unit_records = sum(
        is.na(hospitalization_SEJUM_at_sampling) |
          is.na(hospitalization_SEJUF_at_sampling)
      ),
      .groups = "drop"
    )

  active_unit_pairs <- active_intervals %>%
    filter(
      !is.na(hospitalization_SEJUM_at_sampling),
      !is.na(hospitalization_SEJUF_at_sampling)
    ) %>%
    transmute(
      .sample_id,
      microbiology_SEJUM,
      microbiology_SEJUF,
      hospitalization_SEJUM_at_sampling,
      hospitalization_SEJUF_at_sampling,
      .microbiology_unit_pair_match =
        !is.na(microbiology_SEJUM) &
        !is.na(microbiology_SEJUF) &
        microbiology_SEJUM == hospitalization_SEJUM_at_sampling &
        microbiology_SEJUF == hospitalization_SEJUF_at_sampling
    ) %>%
    distinct(
      .sample_id,
      hospitalization_SEJUM_at_sampling,
      hospitalization_SEJUF_at_sampling,
      .keep_all = TRUE
    )

  candidate_counts <- active_unit_pairs %>%
    group_by(.sample_id) %>%
    summarise(
      n_active_unit_pairs = n(),
      n_microbiology_unit_pair_matches = sum(
        .microbiology_unit_pair_match,
        na.rm = TRUE
      ),
      .groups = "drop"
    )

  selected_units <- active_unit_pairs %>%
    left_join(candidate_counts, by = ".sample_id") %>%
    filter(
      n_active_unit_pairs == 1L |
        (n_active_unit_pairs > 1L &
          n_microbiology_unit_pair_matches == 1L &
          .microbiology_unit_pair_match)
    ) %>%
    transmute(
      .sample_id,
      hospitalization_SEJUM_at_sampling,
      hospitalization_SEJUF_at_sampling,
      attribution_method = if_else(
        n_active_unit_pairs == 1L,
        "single_active_unit_pair",
        "microbiology_unit_pair_breaks_tie"
      )
    )

  samples %>%
    left_join(active_interval_counts, by = ".sample_id") %>%
    left_join(candidate_counts, by = ".sample_id") %>%
    left_join(selected_units, by = ".sample_id") %>%
    mutate(
      n_active_interval_records = dplyr::coalesce(
        n_active_interval_records,
        0L
      ),
      n_active_incomplete_unit_records = dplyr::coalesce(
        n_active_incomplete_unit_records,
        0L
      ),
      n_active_unit_pairs = dplyr::coalesce(n_active_unit_pairs, 0L),
      n_microbiology_unit_pair_matches = dplyr::coalesce(
        n_microbiology_unit_pair_matches,
        0L
      ),
      attribution_status = case_when(
        !is.na(attribution_method) ~ "assigned_hebergement",
        n_active_unit_pairs > 1L ~ "ambiguous_hebergement",
        TRUE ~ "unassigned_hebergement"
      ),
      attribution_reason = case_when(
        is.na(PATID) | is.na(EVTID) ~ "missing_patient_or_event_key",
        sample_datetime_status == "missing_date_or_time" ~
          "missing_sample_datetime",
        sample_datetime_status == "invalid_time_of_day" ~
          "invalid_sample_time_of_day",
        sample_datetime_status == "nonexistent_local_time" ~
          "nonexistent_local_sample_datetime",
        sample_datetime_status == "ambiguous_local_time" ~
          "ambiguous_local_sample_datetime",
        attribution_method == "single_active_unit_pair" ~
          "single_active_unit_pair",
        attribution_method == "microbiology_unit_pair_breaks_tie" ~
          "microbiology_unit_pair_breaks_tie",
        n_active_unit_pairs > 1L ~ "multiple_active_unit_pairs",
        n_active_incomplete_unit_records > 0L ~
          "active_interval_missing_complete_unit_pair",
        TRUE ~ "no_active_interval"
      ),
      microbiology_um_matches_attributed_um = case_when(
        attribution_status != "assigned_hebergement" ~ NA,
        is.na(microbiology_SEJUM) ~ NA,
        TRUE ~ microbiology_SEJUM == hospitalization_SEJUM_at_sampling
      ),
      microbiology_uf_matches_attributed_uf = case_when(
        attribution_status != "assigned_hebergement" ~ NA,
        is.na(microbiology_SEJUF) ~ NA,
        TRUE ~ microbiology_SEJUF == hospitalization_SEJUF_at_sampling
      ),
      microbiology_unit_pair_matches_attributed_unit_pair = case_when(
        attribution_status != "assigned_hebergement" ~ NA,
        is.na(microbiology_SEJUM) | is.na(microbiology_SEJUF) ~ NA,
        TRUE ~ microbiology_um_matches_attributed_um &
          microbiology_uf_matches_attributed_uf
      ),
      hospitalization_unit_attribution_resolved =
        attribution_status == "assigned_hebergement"
    ) %>%
    arrange(.sample_id) %>%
    select(-.sample_id)
}
