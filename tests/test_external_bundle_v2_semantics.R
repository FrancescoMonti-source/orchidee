#!/usr/bin/env Rscript

source("R/external_bundle_validation_helpers.R")
source("R/external_handoff_helpers.R")

contract_v1 <- orchidee_external_contract_v1()
contract_v2 <- orchidee_external_contract_v2()

sir_wide <- data.frame(
  PATID = "P1",
  EVTID = "E1",
  ELTID = "L1",
  DATEPRELEV = as.Date("2024-01-15"),
  HEUREPRELEV = as.difftime(9, units = "hours"),
  souche_id = "1",
  naturepvt_norm = "urines",
  bact_norm = "Escherichia coli",
  SEJUF = "UF1",
  stringsAsFactors = FALSE
)
for (atb_col in contract_v1$sir_wide$atb_cols) {
  sir_wide[[atb_col]] <- NA_character_
}
sir_wide$cefotaxime <- "S"
sir_wide$blse_status_row <- "no_signal"
sir_wide$carbapenemase_status_row <- "no_signal"
sir_wide$blse_flag <- FALSE
sir_wide$carbapenemase_flag <- FALSE

meta_v1 <- orchidee_handoff_build_sir_wide_meta(
  sir_wide,
  contract = contract_v1
)
meta_v2 <- orchidee_handoff_build_sir_wide_meta(
  sir_wide,
  contract = contract_v2
)

meta_v2_missing_semantics <- meta_v2[setdiff(
  names(meta_v2),
  c("contract_version", "sejuf_semantics")
)]
meta_v2_wrong_semantics <- meta_v2
meta_v2_wrong_semantics$sejuf_semantics <- "microbiology_sample_unit"

validation_v1 <- external_bundle_validate_sir_wide(
  sir_wide,
  meta_v1,
  contract = contract_v1
)
validation_v2 <- external_bundle_validate_sir_wide(
  sir_wide,
  meta_v2,
  contract = contract_v2
)
validation_v2_missing <- external_bundle_validate_sir_wide(
  sir_wide,
  meta_v2_missing_semantics,
  contract = contract_v2
)
validation_v2_wrong <- external_bundle_validate_sir_wide(
  sir_wide,
  meta_v2_wrong_semantics,
  contract = contract_v2
)
validation_v2_as_v1 <- external_bundle_validate_sir_wide(
  sir_wide,
  meta_v2,
  contract = contract_v1
)
report_version_error <- tryCatch(
  {
    load_validated_external_input_bundle(
      bundle_dir = "unused",
      contract = contract_v2,
      validation_report = list(
        ok = TRUE,
        contract_version = "v1"
      )
    )
    NA_character_
  },
  error = function(condition) conditionMessage(condition)
)

# Why: protects the canonical input contract that v2 explicitly identifies
# SEJUF as the hospitalization unit at sampling while v1 remains unchanged.
stopifnot(
  identical(contract_v2$version, "v2"),
  !any(c("contract_version", "sejuf_semantics") %in% names(meta_v1)),
  identical(meta_v2$contract_version, "v2"),
  identical(meta_v2$sejuf_semantics, "hospitalization_unit_at_sampling"),
  isTRUE(validation_v1$ok),
  isTRUE(validation_v2$ok),
  !isTRUE(validation_v2_missing$ok),
  any(grepl("missing required fields", validation_v2_missing$errors)),
  !isTRUE(validation_v2_wrong$ok),
  any(grepl("sejuf_semantics must equal", validation_v2_wrong$errors)),
  !isTRUE(validation_v2_as_v1$ok),
  any(grepl("contract_version must equal", validation_v2_as_v1$errors)),
  grepl("Validation report contract version", report_version_error)
)

cat("PASS: external bundle v2 SEJUF semantics\n")
