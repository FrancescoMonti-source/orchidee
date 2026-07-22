#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(dplyr))

source("R/external_bundle_validation_helpers.R")
source("R/ratb_hospital_days_helpers.R")
source("R/external_handoff_helpers.R")
source("R/ratb_canonical_runtime_helpers.R")

capture_error <- function(expr) {
  tryCatch(
    {
      force(expr)
      NA_character_
    },
    error = function(e) conditionMessage(e)
  )
}

contract_v3 <- orchidee_external_contract_v3()
exposure <- data.frame(
  calendar_year = c(2024L, 2024L, 2025L),
  SEJUM = c("UM1", "UM2", "UM1"),
  SEJUF = c("UF1", "UF2", "UF1"),
  CODE_TA = c("03", "10", "03"),
  CODE_DE = c("D03", "D07", "D03"),
  de_domain_ref = c("MÉDECINE", "URGENCES", "MÉDECINE"),
  denominator_profile_id = rep("midnight_presence", 3L),
  exposure_value = c(100L, 20L, 75L),
  exposure_unit = rep("patient_days", 3L),
  stringsAsFactors = FALSE
)

denominator_bundle <- orchidee_handoff_build_denominator_bundle(
  incidence_exposure_by_year_um_uf_ta_de_profile = exposure,
  contract = contract_v3
)
denominator_validation <- external_bundle_validate_denominator_bundle(
  denominator_bundle,
  contract = contract_v3
)

duplicate_bundle <- denominator_bundle
duplicate_bundle$incidence_exposure_by_year_um_uf_ta_de_profile <- rbind(
  duplicate_bundle$incidence_exposure_by_year_um_uf_ta_de_profile,
  duplicate_bundle$incidence_exposure_by_year_um_uf_ta_de_profile[1L, ]
)
duplicate_validation <- external_bundle_validate_denominator_bundle(
  duplicate_bundle,
  contract = contract_v3
)

unknown_profile_bundle <- denominator_bundle
unknown_profile_bundle$incidence_exposure_by_year_um_uf_ta_de_profile$
  denominator_profile_id[1L] <- "unknown_profile"
unknown_profile_validation <- external_bundle_validate_denominator_bundle(
  unknown_profile_bundle,
  contract = contract_v3
)

wrong_unit_bundle <- denominator_bundle
wrong_unit_bundle$incidence_exposure_by_year_um_uf_ta_de_profile$
  exposure_unit[1L] <- "patient_minutes"
wrong_unit_validation <- external_bundle_validate_denominator_bundle(
  wrong_unit_bundle,
  contract = contract_v3
)

nonfinite_bundle <- denominator_bundle
nonfinite_bundle$incidence_exposure_by_year_um_uf_ta_de_profile$
  exposure_value[1L] <- Inf
nonfinite_validation <- external_bundle_validate_denominator_bundle(
  nonfinite_bundle,
  contract = contract_v3
)

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
for (atb_col in contract_v3$sir_wide$atb_cols) {
  sir_wide[[atb_col]] <- NA_character_
}
sir_wide$cefotaxime <- "S"
sir_wide$blse_status_row <- "no_signal"
sir_wide$carbapenemase_status_row <- "no_signal"
sir_wide$blse_flag <- FALSE
sir_wide$carbapenemase_flag <- FALSE
sample_scope_reference <- data.frame(
  SEJUF = c("UF1", "UF2"),
  sample_CODE_TA = c("03", "10"),
  sample_CODE_DE = c("D03", "D07"),
  sample_de_domain_ref = c("MÉDECINE", "URGENCES"),
  sample_uf_is_eligible_by_ta_de = c(TRUE, FALSE),
  sample_uf_ta_de_status = c("eligible_ta_de", "excluded_ta"),
  sample_uf_ta_de_reason = c("eligible_ta_de", "ta_not_03_20"),
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

external_bundle_v3 <- list(
  sir_wide = sir_wide,
  sir_wide_meta = orchidee_handoff_build_sir_wide_meta(
    sir_wide,
    contract = contract_v3
  ),
  sample_scope_reference = sample_scope_reference,
  denominator_bundle = denominator_bundle
)
operational_v2_bundle <- project_external_bundle_v3_to_operational_v2(
  external_bundle_v3
)

mismatched_scope <- sample_scope_reference
mismatched_scope$sample_CODE_DE[mismatched_scope$SEJUF == "UF1"] <- "D07"
mismatch_error <- capture_error(
  build_ratb_downstream_scope_from_canonical_inputs(
    sir_wide = sir_wide,
    sample_scope_reference = mismatched_scope,
    denominator_bundle = denominator_bundle
  )
)
unknown_context_error <- capture_error(
  build_ratb_downstream_scope_from_canonical_inputs(
    sir_wide = sir_wide,
    sample_scope_reference = sample_scope_reference,
    denominator_bundle = denominator_bundle,
    analysis_context_id = "emergency_future"
  )
)

bundle_dir <- tempfile("orchidee-v3-cross-artifact-")
dir.create(bundle_dir)
saveRDS(sir_wide, file.path(bundle_dir, "sir_wide.rds"))
saveRDS(
  orchidee_handoff_build_sir_wide_meta(sir_wide, contract = contract_v3),
  file.path(bundle_dir, "sir_wide_meta.rds")
)
saveRDS(
  sample_scope_reference,
  file.path(bundle_dir, "sample_scope_reference.rds")
)
saveRDS(denominator_bundle, file.path(bundle_dir, "denominator_bundle.rds"))
valid_bundle_report <- validate_external_input_bundle(
  bundle_dir,
  contract = contract_v3,
  strict_preferred = TRUE
)
saveRDS(
  sample_scope_reference[sample_scope_reference$SEJUF != "UF2", ],
  file.path(bundle_dir, "sample_scope_reference.rds")
)
missing_exposure_scope_report <- validate_external_input_bundle(
  bundle_dir,
  contract = contract_v3,
  strict_preferred = TRUE
)
operational_v2_dir <- tempfile("orchidee-v3-projected-v2-")
dir.create(operational_v2_dir)
invisible(Map(
  saveRDS,
  operational_v2_bundle,
  file.path(
    operational_v2_dir,
    paste0(names(operational_v2_bundle), ".rds")
  )
))
operational_v2_report <- validate_external_input_bundle(
  operational_v2_dir,
  contract = orchidee_external_contract_v2(),
  strict_preferred = TRUE
)
unlink(operational_v2_dir, recursive = TRUE)
unlink(bundle_dir, recursive = TRUE)
missing_v3_code_de_error <- capture_error(
  orchidee_handoff_build_sample_scope_reference(
    unit_mapping = data.frame(
      SEJUF = "UF1",
      CODE_TA = "03",
      de_domain_ref = "MÉDECINE",
      stringsAsFactors = FALSE
    ),
    contract = contract_v3
  )
)
missing_v3_direct_domain_error <- capture_error(
  orchidee_handoff_build_sample_scope_reference(
    unit_mapping = data.frame(
      SEJUF = "UF1",
      CODE_TA = "03",
      CODE_DE = "D03",
      stringsAsFactors = FALSE
    ),
    contract = contract_v3
  )
)

cli_root <- tempfile("orchidee-six-block-cli-")
cli_input_dir <- file.path(cli_root, "inputs")
cli_v3_dir <- file.path(cli_root, "bundle_v3")
cli_v2_dir <- file.path(cli_root, "bundle_v2")
dir.create(cli_input_dir, recursive = TRUE)
cli_blocks <- list(
  microbiology_observations = data.frame(
    PATID = "P1",
    EVTID = "E1",
    ELTID = "L1",
    DATEPRELEV = as.Date("2024-01-15"),
    HEUREPRELEV = "09:00",
    SEJUF = "UF1",
    bacteria_local = "E. coli local",
    sample_type_local = "Urine local",
    antibiotic_local = "Cefotaxime local",
    sir_result = "S",
    ratb_diagnostic_scope = TRUE,
    stringsAsFactors = FALSE
  ),
  bacteria_mapping = data.frame(
    bacteria_local = "E. coli local",
    bact_norm = "Escherichia coli",
    stringsAsFactors = FALSE
  ),
  sample_type_mapping = data.frame(
    sample_type_local = "Urine local",
    naturepvt_norm = "urines",
    stringsAsFactors = FALSE
  ),
  antibiotic_mapping = data.frame(
    antibiotic_local = "Cefotaxime local",
    atb_norm = "cefotaxime",
    stringsAsFactors = FALSE
  ),
  unit_mapping = data.frame(
    SEJUF = c("UF1", "UF2"),
    CODE_TA = c("03", "10"),
    CODE_DE = c("D03", "D07"),
    de_domain_ref = c("MÉDECINE", "URGENCES"),
    stringsAsFactors = FALSE
  ),
  incidence_exposure_by_year_um_uf_ta_de_profile = exposure
)
cli_block_paths <- file.path(
  cli_input_dir,
  paste0(names(cli_blocks), ".rds")
)
invisible(Map(saveRDS, cli_blocks, cli_block_paths))
rscript <- file.path(
  R.home("bin"),
  if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
)
cli_output <- system2(
  rscript,
  c(
    "--vanilla",
    shQuote("scripts/build_external_bundle_from_site_inputs.R"),
    shQuote(unname(cli_block_paths)),
    shQuote(cli_v3_dir),
    "--contract=v3",
    shQuote(paste0("--operational-v2-output=", cli_v2_dir))
  ),
  stdout = TRUE,
  stderr = TRUE
)
cli_status <- attr(cli_output, "status")
if (is.null(cli_status)) cli_status <- 0L
cli_v3_report <- validate_external_input_bundle(
  cli_v3_dir,
  contract = contract_v3,
  strict_preferred = TRUE
)
cli_v2_report <- validate_external_input_bundle(
  cli_v2_dir,
  contract = orchidee_external_contract_v2(),
  strict_preferred = TRUE
)
cli_v3_sir_wide <- readRDS(file.path(cli_v3_dir, "sir_wide.rds"))
cli_v2_sir_wide <- readRDS(file.path(cli_v2_dir, "sir_wide.rds"))
cli_v2_denominator <- readRDS(file.path(cli_v2_dir, "denominator_bundle.rds"))
cli_de_reference_path <- file.path(cli_input_dir, "de_reference.rds")
saveRDS(
  data.frame(
    CODE_DE = c("D03", "D07"),
    de_domain_ref = c("MÉDECINE", "URGENCES"),
    stringsAsFactors = FALSE
  ),
  cli_de_reference_path
)
cli_seventh_block_output <- suppressWarnings(
  system2(
    rscript,
    c(
      "--vanilla",
      shQuote("scripts/build_external_bundle_from_site_inputs.R"),
      shQuote(unname(cli_block_paths)),
      shQuote(file.path(cli_root, "invalid_v3")),
      shQuote(cli_de_reference_path),
      "--contract=v3"
    ),
    stdout = TRUE,
    stderr = TRUE
  )
)
cli_seventh_block_status <- attr(cli_seventh_block_output, "status")
if (is.null(cli_seventh_block_status)) cli_seventh_block_status <- 0L
cli_colliding_v2_dir <- if (identical(.Platform$OS.type, "windows")) {
  tolower(cli_v3_dir)
} else {
  cli_v3_dir
}
cli_colliding_output <- suppressWarnings(
  system2(
    rscript,
    c(
      "--vanilla",
      shQuote("scripts/build_external_bundle_from_site_inputs.R"),
      shQuote(unname(cli_block_paths)),
      shQuote(cli_v3_dir),
      "--contract=v3",
      shQuote(paste0("--operational-v2-output=", cli_colliding_v2_dir)),
      "--force"
    ),
    stdout = TRUE,
    stderr = TRUE
  )
)
cli_colliding_status <- attr(cli_colliding_output, "status")
if (is.null(cli_colliding_status)) cli_colliding_status <- 0L
unlink(cli_root, recursive = TRUE)

# Why: protects the v3 canonical input contract: the exposure table is long by
# closed denominator profile, retains mapped activity outside today's scope,
# and rejects duplicate grain, unknown profiles and incoherent units.
stopifnot(
  identical(contract_v3$version, "v3"),
  identical(
    contract_v3$sir_wide$required_meta_values$contract_version,
    "v3"
  ),
  identical(
    names(denominator_bundle),
    "incidence_exposure_by_year_um_uf_ta_de_profile"
  ),
  isTRUE(denominator_validation$ok),
  nrow(denominator_bundle$incidence_exposure_by_year_um_uf_ta_de_profile) == 3L,
  any(
    denominator_bundle$incidence_exposure_by_year_um_uf_ta_de_profile$
      CODE_TA == "10"
  ),
  !isTRUE(duplicate_validation$ok),
  any(grepl("duplicate rows at grain", duplicate_validation$errors)),
  !isTRUE(unknown_profile_validation$ok),
  any(grepl("unsupported values", unknown_profile_validation$errors)),
  !isTRUE(wrong_unit_validation$ok),
  any(grepl("unsupported values", wrong_unit_validation$errors)),
  !isTRUE(nonfinite_validation$ok),
  any(grepl("integer-like", nonfinite_validation$errors))
)

# Why: protects the current analysis-context invariant: v3 applies the same
# TA/DE scope as v2 before annual aggregation, while retaining the full exposure
# table and failing closed when sample and denominator mappings disagree.
stopifnot(
  isTRUE(runtime_validation$ok),
  identical(ratb_included_ta_de_domains(), ratb_spares_current_de_domains()),
  identical(
    names(runtime_inputs),
    c(
      "sir_wide_ratb_scope",
      "sir_wide_ratb_analytic_scope",
      "incidence_denominator_by_year",
      "incidence_exposure_by_year_um_uf_ta_de_profile"
    )
  ),
  identical(
    runtime_inputs$incidence_denominator_by_year,
    tibble::tibble(
      calendar_year = c(2024L, 2025L),
      hospital_nights = c(100L, 75L)
    )
  ),
  identical(
    runtime_inputs$incidence_exposure_by_year_um_uf_ta_de_profile,
    denominator_bundle$incidence_exposure_by_year_um_uf_ta_de_profile
  ),
  grepl("disagrees with sample scope TA/DE mapping", mismatch_error),
  grepl("Unsupported RATB analysis context", unknown_context_error)
)

# Why: protects the v3-to-v2 projection contract: the durable profiled bundle
# keeps its exact microbiology rows while the operational artifact declares v2,
# carries only the v2 scope shape and derives the closed current annual total.
stopifnot(
  identical(operational_v2_bundle$sir_wide, external_bundle_v3$sir_wide),
  identical(operational_v2_bundle$sir_wide_meta$contract_version, "v2"),
  identical(
    operational_v2_bundle$sir_wide_meta$sejuf_semantics,
    "hospitalization_unit_at_sampling"
  ),
  identical(
    names(operational_v2_bundle$sample_scope_reference),
    orchidee_external_contract_v2()$sample_scope_reference$required_columns
  ),
  identical(
    operational_v2_bundle$denominator_bundle$incidence_denominator_by_year,
    runtime_inputs$incidence_denominator_by_year
  ),
  isTRUE(operational_v2_report$ok),
  grepl("missing required columns: CODE_DE", missing_v3_code_de_error),
  grepl("missing required columns: de_domain_ref", missing_v3_direct_domain_error)
)

# Why: protects the preferred six-block onboarding contract: one CLI run must
# validate and retain v3, then materialize an independently validated v2
# projection without changing microbiology rows, accepting a seventh block or
# allowing two aliases of the same output directory.
stopifnot(
  identical(cli_status, 0L),
  isTRUE(cli_v3_report$ok),
  isTRUE(cli_v2_report$ok),
  identical(cli_v3_sir_wide, cli_v2_sir_wide),
  !identical(cli_seventh_block_status, 0L),
  any(grepl(
    "do not pass a seventh de_reference block",
    cli_seventh_block_output
  )),
  !identical(cli_colliding_status, 0L),
  any(grepl(
    "must differ from output_bundle_dir",
    cli_colliding_output
  )),
  identical(
    cli_v2_denominator$incidence_denominator_by_year,
    tibble::tibble(
      calendar_year = c(2024L, 2025L),
      hospital_nights = c(100L, 75L)
    )
  )
)

# Why: protects the canonical cross-artifact contract: strict v3 validation
# must reject an exposure UF that the sample-scope mapping cannot interpret,
# rather than deferring the contradiction to the downstream runtime smoke.
stopifnot(
  isTRUE(valid_bundle_report$ok),
  !isTRUE(missing_exposure_scope_report$ok),
  any(grepl(
    "SEJUF absent from sample_scope_reference",
    missing_exposure_scope_report$errors
  )),
  grepl("missing required columns: CODE_DE", missing_v3_code_de_error)
)

cat("PASS: external bundle v3 profiled incidence exposure\n")
