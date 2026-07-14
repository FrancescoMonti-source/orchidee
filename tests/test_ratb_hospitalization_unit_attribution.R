#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(dplyr))

source("R/ratb_hospital_days_helpers.R")
source("R/chu_sample_hospitalization_unit_attribution.R")

at_time <- function(x) {
  as.POSIXct(x, tz = "Europe/Paris")
}

samples <- data.frame(
  PATID = c(paste0("P", seq_len(9L)), "", "P11", "P12"),
  EVTID = c(
    "E_UNIQUE", "E_BOUNDARY", "E_TIE", "E_AMBIGUOUS", "E_UNASSIGNED",
    "E_DST_VALID", "E_DST_GAP", "E_DST_FOLD", "E_INCOMPLETE", "E_BLANK",
    "E_GAP", "E_ONLY_INCOMPLETE"
  ),
  ELTID = c(
    "M_UNIQUE", "M_BOUNDARY", "M_TIE", "M_AMBIGUOUS", "M_UNASSIGNED",
    "M_DST_VALID", "M_DST_GAP", "M_DST_FOLD", "M_INCOMPLETE", "M_BLANK",
    "M_GAP", "M_ONLY_INCOMPLETE"
  ),
  DATEPRELEV = as.Date(c(
    rep("2024-01-15", 5L), "2024-03-31", "2024-03-31", "2024-10-27",
    "2024-01-15", "2024-01-15", "2024-01-15", "2024-01-15"
  )),
  HEUREPRELEV = as.difftime(
    c(10, 12, 11, 11, 15, 3.5, 2.5, 2.5, 11, 11, 12, 11),
    units = "hours"
  ),
  SEJUM = c(
    "UM_X", "UM_A", "UM_D", "UM_X", "UM_G", "UM_H", "UM_I", "UM_J",
    "UM_K", "UM_L", "UM_M", "UM_N"
  ),
  SEJUF = c(
    "UF_X", "UF_A", "UF_D", "UF_X", "UF_G", "UF_H", "UF_I", "UF_J",
    "UF_K", "UF_L", "UF_M", "UF_N"
  ),
  stringsAsFactors = FALSE
)

pmsi_main <- data.frame(
  PATID = c(
    "P1", "P2", "P2", "P3", "P3", "P4", "P4", "P5", "P6", "P7", "P8",
    "P9", "P9", "", "P11", "P11", "P12"
  ),
  EVTID = c(
    "E_UNIQUE", "E_BOUNDARY", "E_BOUNDARY", "E_TIE", "E_TIE",
    "E_AMBIGUOUS", "E_AMBIGUOUS", "E_UNASSIGNED", "E_DST_VALID",
    "E_DST_GAP", "E_DST_FOLD", "E_INCOMPLETE", "E_INCOMPLETE", "E_BLANK",
    "E_GAP", "E_GAP", "E_ONLY_INCOMPLETE"
  ),
  DATENT = at_time(c(
    "2024-01-15 08:00:00", "2024-01-15 08:00:00",
    "2024-01-15 12:00:00", "2024-01-15 09:00:00",
    "2024-01-15 10:00:00", "2024-01-15 09:00:00",
    "2024-01-15 10:00:00", "2024-01-15 09:00:00",
    "2024-03-31 03:00:00", "2024-03-31 01:00:00",
    "2024-10-27 01:00:00", "2024-01-15 09:00:00",
    "2024-01-15 10:00:00", "2024-01-15 09:00:00",
    "2024-01-15 08:00:00", "2024-01-15 14:00:00",
    "2024-01-15 09:00:00"
  )),
  DATSORT = at_time(c(
    "2024-01-15 12:00:00", "2024-01-15 12:00:00",
    "2024-01-15 16:00:00", "2024-01-15 13:00:00",
    "2024-01-15 14:00:00", "2024-01-15 13:00:00",
    "2024-01-15 14:00:00", "2024-01-15 13:00:00",
    "2024-03-31 04:00:00", "2024-03-31 04:00:00",
    "2024-10-27 04:00:00", "2024-01-15 13:00:00",
    "2024-01-15 14:00:00", "2024-01-15 13:00:00",
    "2024-01-15 10:00:00", "2024-01-15 16:00:00",
    "2024-01-15 13:00:00"
  )),
  SEJUM = c(
    "UM_A", "UM_A", "UM_B", "UM_C", "UM_D", "UM_E", "UM_F", "UM_G",
    "UM_H", "UM_I", "UM_J", "UM_K", NA_character_, "UM_L", "UM_M", "UM_M",
    "UM_N"
  ),
  SEJUF = c(
    "UF_A", "UF_A", "UF_B", "UF_C", "UF_D", "UF_E", "UF_F", "UF_G",
    "UF_H", "UF_I", "UF_J", "UF_K", "UF_UNKNOWN", "UF_L", "UF_M", "UF_M",
    NA_character_
  ),
  stringsAsFactors = FALSE
)

# Why: protects the ratified upstream sample-attribution contract: use the
# hospitalization unit at sampling, with half-open PMSI time bounds, a
# microbiology UM+UF tie-break only for overlapping candidates, and no silent
# fallback for ambiguous or unmatched samples. It also protects wall-clock
# interpretation across daylight-saving transitions and keeps disjoint PMSI
# rows separate instead of replacing them with min/max unit bounds.
audit <- build_chu_sample_hospitalization_unit_attribution(samples, pmsi_main)

sample_result <- function(eltid) {
  result <- audit[audit$ELTID == eltid, , drop = FALSE]
  stopifnot(nrow(result) == 1L)
  result
}

unique_result <- sample_result("M_UNIQUE")
boundary_result <- sample_result("M_BOUNDARY")
tie_result <- sample_result("M_TIE")
ambiguous_result <- sample_result("M_AMBIGUOUS")
unassigned_result <- sample_result("M_UNASSIGNED")
dst_valid_result <- sample_result("M_DST_VALID")
dst_gap_result <- sample_result("M_DST_GAP")
dst_fold_result <- sample_result("M_DST_FOLD")
incomplete_result <- sample_result("M_INCOMPLETE")
blank_result <- sample_result("M_BLANK")
gap_result <- sample_result("M_GAP")
only_incomplete_result <- sample_result("M_ONLY_INCOMPLETE")

stopifnot(
  nrow(audit) == 12L,
  identical(audit$ELTID, samples$ELTID),
  identical(audit$microbiology_SEJUF, samples$SEJUF),
  identical(unique_result$hospitalization_SEJUM_at_sampling, "UM_A"),
  identical(unique_result$hospitalization_SEJUF_at_sampling, "UF_A"),
  identical(unique_result$attribution_method, "single_active_unit_pair"),
  identical(
    unique_result$microbiology_unit_pair_matches_attributed_unit_pair,
    FALSE
  ),
  identical(boundary_result$hospitalization_SEJUM_at_sampling, "UM_B"),
  identical(boundary_result$hospitalization_SEJUF_at_sampling, "UF_B"),
  identical(boundary_result$microbiology_uf_matches_attributed_uf, FALSE),
  tie_result$n_active_unit_pairs == 2L,
  identical(tie_result$hospitalization_SEJUM_at_sampling, "UM_D"),
  identical(tie_result$hospitalization_SEJUF_at_sampling, "UF_D"),
  identical(
    tie_result$attribution_method,
    "microbiology_unit_pair_breaks_tie"
  ),
  identical(
    tie_result$microbiology_unit_pair_matches_attributed_unit_pair,
    TRUE
  ),
  identical(ambiguous_result$attribution_status, "ambiguous_hebergement"),
  ambiguous_result$n_active_unit_pairs == 2L,
  is.na(ambiguous_result$hospitalization_SEJUF_at_sampling),
  identical(unassigned_result$attribution_status, "unassigned_hebergement"),
  unassigned_result$n_active_interval_records == 0L,
  identical(dst_valid_result$sample_datetime_status, "valid"),
  identical(dst_valid_result$hospitalization_SEJUF_at_sampling, "UF_H"),
  identical(dst_gap_result$sample_datetime_status, "nonexistent_local_time"),
  identical(
    dst_gap_result$attribution_reason,
    "nonexistent_local_sample_datetime"
  ),
  identical(dst_fold_result$sample_datetime_status, "ambiguous_local_time"),
  identical(
    dst_fold_result$attribution_reason,
    "ambiguous_local_sample_datetime"
  ),
  incomplete_result$n_active_interval_records == 2L,
  incomplete_result$n_active_incomplete_unit_records == 1L,
  identical(incomplete_result$hospitalization_SEJUM_at_sampling, "UM_K"),
  identical(incomplete_result$hospitalization_SEJUF_at_sampling, "UF_K"),
  identical(incomplete_result$attribution_status, "assigned_hebergement"),
  identical(incomplete_result$attribution_reason, "single_active_unit_pair"),
  identical(incomplete_result$hospitalization_unit_attribution_resolved, TRUE),
  is.na(blank_result$PATID),
  identical(blank_result$attribution_reason, "missing_patient_or_event_key"),
  gap_result$n_active_interval_records == 0L,
  identical(gap_result$attribution_reason, "no_active_interval"),
  only_incomplete_result$n_active_interval_records == 1L,
  only_incomplete_result$n_active_incomplete_unit_records == 1L,
  only_incomplete_result$n_active_unit_pairs == 0L,
  identical(
    only_incomplete_result$attribution_status,
    "unassigned_hebergement"
  ),
  identical(
    only_incomplete_result$attribution_reason,
    "active_interval_missing_complete_unit_pair"
  ),
  is.na(only_incomplete_result$hospitalization_SEJUF_at_sampling)
)

cat("PASS: upstream hospitalization-unit attribution contract\n")
