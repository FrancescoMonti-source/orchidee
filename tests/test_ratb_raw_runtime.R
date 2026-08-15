#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(lubridate)
  library(purrr)
  library(tibble)
})

source("R/helpers.R")
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

species_map <- ratb_raw_cache_species_regex_map_path("mappings")
cache_meta <- build_ratb_raw_cache_meta(
  result = result,
  atb_cols = c("cefotaxime", "ceftazidime"),
  runtime_input_signature = list(contract_version = "v2", bundle_files = "abc"),
  species_regex_map_path = species_map
)
other_signature <- list(contract_version = "v2", bundle_files = "def")
stale_code_meta <- cache_meta
stale_code_meta$cache_input_hashes$spares_dedup <- "0000"

# A mapping edit changes the taxonomy the cache was deduplicated against, so
# it has to invalidate the cache exactly like a code edit does.
stale_mapping_meta <- cache_meta
stale_mapping_meta$cache_input_hashes$species_regex_map <- "0000"

# Why: the cache is reusable only while both of its inputs hold. Signing it
# with the bundle alone let an edit to the dedup code publish numbers the
# current code would not produce.
stopifnot(
  length(ratb_raw_cache_staleness_reasons(
    cache_meta,
    cache_meta$runtime_input_signature,
    species_map
  )) == 0L,
  identical(
    ratb_raw_cache_staleness_reasons(
      cache_meta,
      other_signature,
      species_map
    ),
    "the input bundle changed"
  ),
  identical(
    ratb_raw_cache_staleness_reasons(
      stale_code_meta,
      cache_meta$runtime_input_signature,
      species_map
    ),
    "the code or mapping that builds it changed"
  ),
  identical(
    ratb_raw_cache_staleness_reasons(
      stale_mapping_meta,
      cache_meta$runtime_input_signature,
      species_map
    ),
    "the code or mapping that builds it changed"
  ),
  # An unreadable cache must read as stale: the builder maps a failed read to
  # NULL and would otherwise skip its work on a corrupt cache.
  identical(
    ratb_raw_cache_staleness_reasons(
      NULL,
      cache_meta$runtime_input_signature,
      species_map
    ),
    "its metadata is unreadable"
  ),
  # A cache written before the code side was checked carries no hashes at all.
  identical(
    ratb_raw_cache_staleness_reasons(
      cache_meta[setdiff(names(cache_meta), "cache_input_hashes")],
      cache_meta$runtime_input_signature,
      species_map
    ),
    "the code or mapping that builds it changed"
  ),
  # A path that stops resolving hashes to NA, and two NAs compare equal: the
  # check would then pass on any change at all.
  !anyNA(unlist(ratb_raw_cache_input_hashes(species_map)))
)

cat("PASS: canonical raw RATB runtime\n")
