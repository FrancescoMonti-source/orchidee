#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(lubridate)
  library(purrr)
  library(tibble)
})

source("R/spares_shared_primitives.R")
source("R/phenotype_flag_helpers.R")
source("R/spares_dedup.R")
source("R/ratb_raw_runtime_helpers.R")

sir <- data.frame(
  PATID = c("P1", "P1", "P2"),
  EVTID = c("E1", "E2", "E3"),
  ELTID = c("L1", "L2", "L3"),
  DATEPRELEV = as.Date(c("2024-01-10", "2024-02-10", "2024-03-10")),
  HEUREPRELEV = as.difftime(c(8, 9, 10), units = "hours"),
  souche_id = c("1", "1", "1"),
  naturepvt_norm = c("urines", "hemoculture", "urines"),
  bact_norm = c("escherichia_coli", "escherichia_coli", "escherichia_coli"),
  nb_resultats = c(1L, 2L, 1L),
  cefotaxime = c("S", "S", "R"),
  ceftazidime = c(NA, "S", NA),
  stringsAsFactors = FALSE
)

result <- build_ratb_raw_dedup_results(
  sir_df = sir,
  atb_cols = c("cefotaxime", "ceftazidime")
)
validation <- validate_ratb_raw_dedup_results(result)
global_representatives <- result$dedup_results$sir_wide_raw$global$dedup
by_type_representatives <- result$dedup_results$sir_wide_raw$by_type$dedup

# Why: protects the canonical raw-engine invariant that no completion is
# applied and global versus by-type patient-year dedup differ only by the
# declared sample-type key.
stopifnot(
  isTRUE(validation$ok),
  identical(names(result$dedup_results), "sir_wide_raw"),
  all(result$raw_dataset$completion_strategy == "raw"),
  all(result$raw_dataset$n_cells_filled == 0L),
  identical(result$raw_dataset$cefotaxime, sir$cefotaxime),
  identical(result$raw_dataset$ceftazidime, sir$ceftazidime),
  setequal(global_representatives$ELTID, c("L2", "L3")),
  setequal(by_type_representatives$ELTID, c("L1", "L2", "L3"))
)

cat("PASS: canonical raw RATB runtime\n")
