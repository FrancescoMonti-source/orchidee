#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(dplyr))

source("R/ratb_hospital_days_helpers.R")

make_inputs <- function(datent, datsort, sejum, sejuf) {
  pmsi_main <- tibble(
    PATID = rep("P", length(datent)),
    EVTID = rep("E", length(datent)),
    DATENT = as.POSIXct(datent, tz = "UTC"),
    DATSORT = as.POSIXct(datsort, tz = "UTC"),
    SEJUM = sejum,
    SEJUF = sejuf,
    GHM = rep("G", length(datent))
  )
  pmsi_event_bounds <- tibble(
    PATID = "P",
    EVTID = "E",
    datent_min = min(pmsi_main$DATENT),
    datsort_max = max(pmsi_main$DATSORT)
  )
  status_lookup <- tibble(
    PATID = "P",
    EVTID = "E",
    ratb_scope_status = "included",
    pmsi_status_values = "H",
    n_status_non_missing = 1L,
    n_distinct_status = 1L,
    n_pmsi_rows = nrow(pmsi_main),
    evtid_multi_pat = FALSE,
    n_patid_for_evtid = 1L
  )
  refs <- list(
    uf_ref = tibble(SEJUF = c("UF_A", "UF_B"), uf_label = c("A", "B")),
    uf2um_ref = tibble(
      SEJUF = c("UF_A", "UF_B"),
      SEJUM_from_ref = c("UM_A", "UM_B")
    ),
    um_ref = tibble(SEJUM = c("UM_A", "UM_B"), um_label = c("A", "B"))
  )
  ta_de_ref <- tibble(
    SEJUF = c("UF_A", "UF_B"),
    CODE_TA = "03",
    CODE_DE = "D",
    de_domain_ref = "MED",
    uf_ta_eligible = TRUE,
    uf_de_mapped = TRUE,
    uf_de_eligible = TRUE,
    uf_is_eligible_by_ta_de = TRUE,
    uf_ta_de_status = "included",
    uf_ta_de_reason = "eligible"
  )
  list(
    pmsi_main = pmsi_main,
    pmsi_event_bounds = pmsi_event_bounds,
    status_lookup = status_lookup,
    refs = refs,
    ta_de_ref = ta_de_ref
  )
}

run_case <- function(...) {
  x <- make_inputs(...)
  build_ratb_pmsi_ta_de_denominator(
    x$pmsi_main,
    x$pmsi_event_bounds,
    x$status_lookup,
    x$refs,
    x$ta_de_ref
  )
}

# A -> B -> A: the two A visits are separated by time spent in B.
separate_visits <- run_case(
  c("2024-01-01", "2024-01-03", "2024-01-05"),
  c("2024-01-03", "2024-01-05", "2024-01-07"),
  c("UM_A", "UM_B", "UM_A"),
  c("UF_A", "UF_B", "UF_A")
)
stopifnot(
  identical(
    separate_visits$hospital_days_year_summary_provisional$
      hospital_nights_provisional,
    6L
  )
)

# Overlapping rows for one unit are still one occupied interval.
overlapping_rows <- run_case(
  c("2024-01-01", "2024-01-02"),
  c("2024-01-04", "2024-01-05"),
  c("UM_A", "UM_A"),
  c("UF_A", "UF_A")
)
stopifnot(
  identical(
    overlapping_rows$hospital_days_year_summary_provisional$
      hospital_nights_provisional,
    4L
  )
)

cat("PASS: denominator interval union preserves separate visits and merges overlaps\n")
