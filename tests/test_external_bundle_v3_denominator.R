#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(dplyr))

source("R/external_bundle_validation_helpers.R")
source("R/ratb_hospital_days_helpers.R")
source("R/external_handoff_helpers.R")
source("R/ratb_canonical_runtime_helpers.R")

contract_v3 <- orchidee_external_contract_v3()
fine_denominator <- data.frame(
  calendar_year = c(2024L, 2024L, 2025L),
  SEJUM = c("UM1", "UM2", "UM1"),
  SEJUF = c("UF1", "UF2", "UF1"),
  CODE_TA = c("03", "20", "03"),
  CODE_DE = c("D03", "D07", "D03"),
  hospital_nights = c(100L, 50L, 75L),
  stringsAsFactors = FALSE
)

denominator_bundle <- orchidee_handoff_build_denominator_bundle(
  denominator_by_year_um_uf_ta_de = fine_denominator,
  contract = contract_v3
)
denominator_validation <- external_bundle_validate_denominator_bundle(
  denominator_bundle,
  contract = contract_v3
)

duplicate_bundle <- denominator_bundle
duplicate_bundle$incidence_denominator_by_year_um_uf_ta_de <- rbind(
  duplicate_bundle$incidence_denominator_by_year_um_uf_ta_de,
  duplicate_bundle$incidence_denominator_by_year_um_uf_ta_de[1L, ]
)
duplicate_validation <- external_bundle_validate_denominator_bundle(
  duplicate_bundle,
  contract = contract_v3
)

missing_code_bundle <- denominator_bundle
missing_code_bundle$incidence_denominator_by_year_um_uf_ta_de$CODE_DE[1L] <- NA_character_
missing_code_validation <- external_bundle_validate_denominator_bundle(
  missing_code_bundle,
  contract = contract_v3
)

sir_wide <- data.frame(
  PATID = "P1",
  EVTID = "E1",
  ELTID = "L1",
  SEJUF = "UF1",
  stringsAsFactors = FALSE
)
sample_scope_reference <- data.frame(
  SEJUF = "UF1",
  sample_uf_is_eligible_by_ta_de = TRUE,
  sample_uf_ta_de_status = "eligible_ta_de",
  sample_uf_ta_de_reason = "eligible_ta_de",
  stringsAsFactors = FALSE
)
runtime_inputs <- build_ratb_downstream_scope_from_canonical_inputs(
  sir_wide = sir_wide,
  sample_scope_reference = sample_scope_reference,
  denominator_bundle = denominator_bundle
)
runtime_validation <- validate_ratb_canonical_runtime_inputs(
  runtime_inputs,
  sir_wide = sir_wide
)

# Why: protects the v3 canonical input contract: one non-ambiguous table at
# year + UM + UF + TA + DE grain is required, with complete dimensions.
stopifnot(
  identical(contract_v3$version, "v3"),
  identical(
    contract_v3$sir_wide$required_meta_values$contract_version,
    "v3"
  ),
  identical(
    names(denominator_bundle),
    "incidence_denominator_by_year_um_uf_ta_de"
  ),
  isTRUE(denominator_validation$ok),
  !isTRUE(duplicate_validation$ok),
  any(grepl("duplicate rows at grain", duplicate_validation$errors)),
  !isTRUE(missing_code_validation$ok),
  any(grepl("must not contain NA values", missing_code_validation$errors))
)

# Why: protects the runtime bridge that derives the unchanged global annual
# denominator from the single fine v3 table while preserving that table for
# future stratified incidence.
stopifnot(
  isTRUE(runtime_validation$ok),
  identical(
    names(runtime_inputs),
    c(
      "sir_wide_ratb_scope",
      "sir_wide_ratb_analytic_scope",
      "incidence_denominator_by_year",
      "incidence_denominator_by_year_um_uf_ta_de"
    )
  ),
  identical(
    runtime_inputs$incidence_denominator_by_year,
    tibble::tibble(
      calendar_year = c(2024L, 2025L),
      hospital_nights = c(150L, 75L)
    )
  ),
  identical(
    runtime_inputs$incidence_denominator_by_year_um_uf_ta_de,
    denominator_bundle$incidence_denominator_by_year_um_uf_ta_de
  )
)

cat("PASS: external bundle v3 fine denominator\n")
