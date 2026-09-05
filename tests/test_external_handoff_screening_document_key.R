#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(dplyr))

source("R/helpers.R")
source("R/phenotype_flag_helpers.R")
source("R/external_bundle_validation_helpers.R")
source("R/external_handoff_helpers.R")
contract <- orchidee_external_contract_v3()

microbiology_observations <- data.frame(
  PATID = c("P1", "P2", "P3", "P3", "P4", "P4", "P5", "P5", "P6", "P7"),
  EVTID = c(
    "E_SHARED", "E_SHARED", "E_SCREEN", "E_KEEP", "E_MIXED", "E_MIXED",
    NA_character_, "E_LEGACY", "E_CONTROL", "E_OTHER"
  ),
  ELTID = c(
    "REUSED", "REUSED", "SAME_PATIENT", "SAME_PATIENT", "MIXED", "MIXED",
    "LEGACY", "LEGACY", "CONTROL", "LEGACY"
  ),
  DATEPRELEV = rep("2024-01-15", 10L),
  HEUREPRELEV = rep("09:00", 10L),
  SEJUF = rep("UF1", 10L),
  souche_id = rep("1", 10L),
  bacteria_local = rep("E. coli", 10L),
  sample_type_local = rep("Urine", 10L),
  antibiotic_local = rep("Cefotaxime", 10L),
  sir_result = rep("S", 10L),
  ratb_diagnostic_scope = c(
    FALSE, TRUE, FALSE, TRUE, FALSE, TRUE, FALSE, TRUE, TRUE, TRUE
  ),
  blse_status_row = rep(NA_character_, 10L),
  carbapenemase_status_row = rep(NA_character_, 10L),
  stringsAsFactors = FALSE
)

microbiology_observations <- bind_rows(
  microbiology_observations,
  data.frame(
    PATID = rep("P8", 2L),
    EVTID = rep("E_MULTI", 2L),
    ELTID = rep("MULTI_ROW", 2L),
    DATEPRELEV = rep("2024-01-15", 2L),
    HEUREPRELEV = rep("09:00", 2L),
    SEJUF = rep("UF1", 2L),
    souche_id = rep("1", 2L),
    bacteria_local = rep("E. coli", 2L),
    sample_type_local = rep("Urine", 2L),
    antibiotic_local = rep("Cefotaxime", 2L),
    sir_result = c("S", "R"),
    ratb_diagnostic_scope = rep(TRUE, 2L),
    blse_status_row = c("negative", "positive"),
    carbapenemase_status_row = c("unknown", "negative"),
    stringsAsFactors = FALSE
  )
)

bacteria_mapping <- data.frame(
  bacteria_local = "E. coli",
  bact_norm = "Escherichia coli",
  stringsAsFactors = FALSE
)
sample_type_mapping <- data.frame(
  sample_type_local = "Urine",
  naturepvt_norm = "urines",
  stringsAsFactors = FALSE
)
antibiotic_mapping <- data.frame(
  antibiotic_local = "Cefotaxime",
  atb_norm = "cefotaxime",
  stringsAsFactors = FALSE
)

build_fixture <- function(observations) {
  orchidee_handoff_build_sir_wide_from_microbiology(
    microbiology_observations = observations,
    bacteria_mapping = bacteria_mapping,
    sample_type_mapping = sample_type_mapping,
    antibiotic_mapping = antibiotic_mapping
  )
}

# Why: protects the external-handoff engine invariant that screening propagates
# within one source document without allowing reused ELTID values to suppress
# unrelated patients or encounters. P5 covers the anomaly rule: its EVTID-less
# row is dropped, so the screening it carried no longer suppresses its sibling.
# A missing column or a wholly empty EVTID column cannot enable a patient-only
# build. The mixed fixture above still retains the rows with usable stay IDs.
sir_wide <- build_fixture(microbiology_observations)
for (event_ids in list(NULL, rep(NA_character_, nrow(microbiology_observations)),
                       rep(" ", nrow(microbiology_observations)))) {
  without_stays <- microbiology_observations
  without_stays$EVTID <- event_ids
  rejected <- tryCatch(build_fixture(without_stays), error = identity)
  stopifnot(inherits(rejected, "error"), grepl("EVTID", conditionMessage(rejected)))
}

retained_keys <- sir_wide[, c("PATID", "EVTID", "ELTID")]
expected_keys <- data.frame(
  PATID = c("P2", "P3", "P5", "P6", "P7", "P8"),
  EVTID = c("E_SHARED", "E_KEEP", "E_LEGACY", "E_CONTROL", "E_OTHER", "E_MULTI"),
  ELTID = c(
    "REUSED", "SAME_PATIENT", "LEGACY", "CONTROL", "LEGACY", "MULTI_ROW"
  ),
  stringsAsFactors = FALSE
)

multi_row_isolate <- sir_wide[sir_wide$PATID == "P8", , drop = FALSE]

validation <- external_bundle_validate_sir_wide(
  sir_wide,
  orchidee_handoff_build_sir_wide_meta(sir_wide, contract = contract),
  contract = contract
)
# Materialized bundles cannot bypass the input rule by carrying a missing or
# blank stay ID. This boundary also protects externally supplied v2 bundles.
for (event_id in c(NA_character_, " ")) {
  invalid_sir <- sir_wide
  invalid_sir$EVTID[[1L]] <- event_id
  invalid_validation <- external_bundle_validate_sir_wide(
    invalid_sir,
    orchidee_handoff_build_sir_wide_meta(invalid_sir, contract = contract),
    contract = contract
  )
  stopifnot(!isTRUE(invalid_validation$ok), any(grepl("EVTID", invalid_validation$errors)))
}

stopifnot(
  identical(retained_keys, expected_keys),
  nrow(multi_row_isolate) == 1L,
  identical(multi_row_isolate$cefotaxime, "R"),
  identical(multi_row_isolate$nb_resultats, 1),
  identical(multi_row_isolate$blse_status_row, "positive"),
  identical(multi_row_isolate$carbapenemase_status_row, "negative"),
  isTRUE(multi_row_isolate$blse_flag),
  identical(multi_row_isolate$carbapenemase_flag, FALSE),
  isTRUE(validation$ok)
)

cat("PASS: external handoff screening document key\n")
