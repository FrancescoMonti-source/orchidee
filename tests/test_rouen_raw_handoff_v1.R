#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(stringr)
  library(tidyr)
  library(tibble)
})

source("R/helpers.R")
source("R/normalisation_bact.R")
source("R/normalisation_atb.R")
source("R/phenotype_flag_helpers.R")
source("R/external_bundle_validation_helpers.R")
source("R/external_handoff_helpers.R")
source("R/ratb_hospital_days_helpers.R")
source("R/chu_sample_hospitalization_unit_attribution.R")
source("R/rouen_microbiology_handoff_adapter.R")
source("R/rouen_pmsi_handoff_adapter.R")

species_rules <- readr::read_delim(
  "dictionaries/species_regex_map.csv",
  delim = ";",
  show_col_types = FALSE
)
antibiotic_rules <- suppressMessages(readr::read_csv(
  "dictionaries/atb_regex_map.csv",
  show_col_types = FALSE
))
antibiotic_expansion <- readr::read_csv(
  "dictionaries/atb_expand_map.csv",
  show_col_types = FALSE
)
supported_pairs <- readr::read_csv(
  "dictionaries/couples_species_atb.csv",
  show_col_types = FALSE
)
sample_type_rules <- readr::read_csv(
  "dictionaries/rouen_naturepvt_regex_v1.csv",
  show_col_types = FALSE
)
sample_type_decisions <- readr::read_csv(
  "dictionaries/rouen_naturepvt_exact_decisions_v1.csv",
  show_col_types = FALSE
)

raw_row <- function(
    PATID,
    EVTID,
    ELTID,
    TYPEANA,
    LBLANA,
    LBLRES,
    STRRES,
    IDENTIFICATION = "Escherichia coli",
    NATUREPVT = "URINE SONDE URETRALE GAUCHE",
    DLVL = "1",
    TRI = 1L
  ) {
  data.frame(
    PATID = PATID,
    EVTID = EVTID,
    ELTID = ELTID,
    DATEPRELEV = as.Date("2024-02-15"),
    HEUREPRELEV = "10:30",
    SEJUM = "UM1",
    SEJUF = "UF_MICRO",
    DLVL = DLVL,
    TYPEANA = TYPEANA,
    LBLANA = LBLANA,
    LBLRES = LBLRES,
    STRRES = STRRES,
    IDENTIFICATION = IDENTIFICATION,
    NATUREPVT = NATUREPVT,
    TRI = TRI,
    stringsAsFactors = FALSE
  )
}

bacteriology_raw <- bind_rows(
  raw_row("P1", "E1", "D1", "ATB", "C3G", "SIR", "---S", TRI = 1L),
  raw_row(
    "P1", "E1", "D1", "ATB", "Cefotaxime", "SIR", "---R", TRI = 2L
  ),
  raw_row(
    "P1", "E1", "D1", "ATB", "Fluoroquinolones", "SIR", "I", TRI = 3L
  ),
  raw_row(
    "P1", "E1", "D1", "PHENO", "RECHERCHE BLSE", "Résultat",
    "Positive", TRI = 4L
  ),
  raw_row(
    "P2", NA_character_, "D2", "BGSAMR_R.BGSAMR_R2", "RECHERCHE SAMR",
    "Résultat", "Positive", TRI = 1L
  ),
  raw_row(
    "P2", "E2", "D2", "ATB", "Cefotaxime", "SIR", "S", TRI = 2L
  ),
  raw_row(
    "P3", NA_character_, "D3", "ATB", "Cefotaxime", "SIR", "S",
    NATUREPVT = "SONDE", TRI = 1L
  ),
  raw_row(
    "P4", "E4", "D4", "ATB", "Cefotaxime", "SIR", "R",
    IDENTIFICATION = "Escherichia coli ou Klebsiella pneumoniae",
    TRI = 1L
  )
)

# Why: protects the Rouen adapter method profile from one raw document
# occurrence through the four canonical microbiology handoff blocks. It fixes
# screening scope, SIR vocabulary, unordered sample mapping, ATB precedence,
# ambiguous-species exclusion and full-raw phenotype attribution.
handoff <- build_rouen_microbiology_handoff_v1(
  bacteriology_raw = bacteriology_raw,
  screening_typeana_codes = c(
    "BGBLSE_R.BGBLSE_R2",
    "BGCARBA_R.BGCARBA_R2",
    "BGABMR_R.BGABMR_R2",
    "BGSAMR_R.BGSAMR_R2"
  ),
  target_start = as.Date("2024-01-01"),
  target_end_exclusive = as.Date("2025-01-01"),
  species_rules = species_rules,
  sample_type_rules = sample_type_rules,
  sample_type_exact_decisions = sample_type_decisions,
  antibiotic_rules = antibiotic_rules,
  antibiotic_expansion = antibiotic_expansion,
  supported_species_antibiotics = supported_pairs
)

observations <- handoff$site_inputs$microbiology_observations
sample_mapping <- handoff$site_inputs$sample_type_mapping
sir_wide <- orchidee_handoff_build_sir_wide_from_microbiology(
  microbiology_observations = observations,
  bacteria_mapping = handoff$site_inputs$bacteria_mapping,
  sample_type_mapping = sample_mapping,
  antibiotic_mapping = handoff$site_inputs$antibiotic_mapping,
  contract = orchidee_external_contract_v2()
)

p1 <- sir_wide[sir_wide$PATID == "P1", , drop = FALSE]
p3 <- sir_wide[sir_wide$PATID == "P3", , drop = FALSE]
screening_row <- observations[observations$PATID == "P2", , drop = FALSE]
audit_value <- function(metric) {
  handoff$audit$summary$value[handoff$audit$summary$metric == metric]
}

stopifnot(
  identical(
    names(handoff$site_inputs),
    c(
      "microbiology_observations",
      "bacteria_mapping",
      "sample_type_mapping",
      "antibiotic_mapping"
    )
  ),
  nrow(screening_row) == 1L,
  identical(screening_row$ratb_diagnostic_scope, FALSE),
  identical(audit_value("screening_document_occurrences_all_raw"), 1L),
  identical(audit_value("screening_document_occurrences_with_sir"), 1L),
  identical(audit_value("screening_rows_all_raw"), 2L),
  identical(audit_value("screening_sir_rows"), 1L),
  identical(audit_value("rows_evtid_filled_from_document"), 1L),
  !"P2" %in% sir_wide$PATID,
  !"P4" %in% observations$PATID,
  nrow(p1) == 1L,
  identical(p1$cefotaxime, "R"),
  identical(p1$ceftriaxone, "S"),
  identical(p1$ceftazidime, "S"),
  identical(p1$ciprofloxacine, "ZIT"),
  identical(p1$naturepvt_norm, "urines"),
  identical(p1$blse_status_row, "positive"),
  isTRUE(p1$blse_flag),
  nrow(p3) == 1L,
  is.na(p3$naturepvt_norm),
  is.na(sample_mapping$naturepvt_norm[
    sample_mapping$sample_type_local == "SONDE"
  ]),
  any(
    handoff$audit$sample_type_rule_hits$sample_type_local ==
      "URINE SONDE URETRALE GAUCHE" &
      grepl("urine", handoff$audit$sample_type_rule_hits$pattern)
  ),
  handoff$audit$phenotype_signal_gate$n_signal_rows == 1L,
  handoff$audit$phenotype_signal_gate$n_signal_rows_without_exact_candidate_key == 0L
)

unit_refs <- load_ratb_unit_references("ref")
ta_de_ref <- load_ratb_consores_ta_de_reference(
  structure_path = "ref/consores_structure_intranet_maj_2025.xlsx",
  codes_ta_path = "ref/consores_codes_ta.csv",
  codes_de_path = "ref/consores_codes_de.csv"
)
pmsi_main <- tibble::tibble(
  PATID = c("P1", "P1", "P5", "P6", "P7", "P8"),
  EVTID = c("E1", "E1", "E5", "E6", "E7", "E8"),
  ELTID = c(
    "PMSI_C", "PMSI_DW_DUPLICATE", "PMSI_DW_ONLY",
    "PMSI_CROSS_START", "PMSI_AFTER_WINDOW", "PMSI_URGENCES"
  ),
  DATENT = as.POSIXct(
    c(
      "2024-02-01 00:00:00",
      "2024-02-01 00:00:00",
      "2024-03-01 00:00:00",
      "2023-12-31 00:00:00",
      "2025-01-01 00:00:00",
      "2024-04-01 00:00:00"
    ),
    tz = "Europe/Paris"
  ),
  DATSORT = as.POSIXct(
    c(
      "2024-03-01 00:00:00",
      "2024-03-01 00:00:00",
      "2024-03-02 00:00:00",
      "2024-01-02 00:00:00",
      "2025-01-02 00:00:00",
      "2024-04-02 00:00:00"
    ),
    tz = "Europe/Paris"
  ),
  SEJUM = c(rep("INTB", 5L), "URGE"),
  SEJUF = c("5130", "5130", "5136", "5136", "5136", "5701"),
  SRC = c("C", "DW", "DW", "DW", "DW", "C"),
  PMSISTATUT = rep("H", 6L),
  SEJDUR = c("29", "29", "1", "2", "1", "1"),
  GHM = rep("SYNTHETIC", 6L)
)

# Why: protects the Rouen adapter integration contract that redsan-normalized
# PMSI produces the two remaining site inputs, clips the denominator window,
# assigns the hospitalization UF without fallback, and composes a valid v2 bundle.
pmsi_handoff <- build_rouen_pmsi_handoff_v1(
  sample_context = handoff$sample_context,
  pmsi_main = pmsi_main,
  unit_refs = unit_refs,
  ta_de_ref = ta_de_ref,
  target_start = as.Date("2024-01-01"),
  target_end_exclusive = as.Date("2025-01-01")
)
composed <- compose_rouen_external_bundle_v2(handoff, pmsi_handoff)
composed_v3 <- compose_rouen_external_bundle_v3(handoff, pmsi_handoff)

bundle_p1 <- composed$bundle$sir_wide[
  composed$bundle$sir_wide$PATID == "P1",
  ,
  drop = FALSE
]
bundle_p3 <- composed$bundle$sir_wide[
  composed$bundle$sir_wide$PATID == "P3",
  ,
  drop = FALSE
]

stopifnot(
  identical(
    names(composed$site_inputs),
    c(
      "microbiology_observations",
      "bacteria_mapping",
      "sample_type_mapping",
      "antibiotic_mapping",
      "unit_mapping",
      "denominator_by_year"
    )
  ),
  identical(composed$bundle$sir_wide_meta$contract_version, "v2"),
  identical(
    composed$bundle$sir_wide_meta$sejuf_semantics,
    "hospitalization_unit_at_sampling"
  ),
  nrow(bundle_p1) == 1L,
  identical(bundle_p1$SEJUF, "5130"),
  nrow(bundle_p3) == 1L,
  is.na(bundle_p3$SEJUF),
  identical(
    pmsi_handoff$site_inputs$denominator_by_year$hospital_nights,
    31L
  ),
  identical(pmsi_handoff$audit$source_policy_summary$value, c(6L, 5L)),
  identical(
    pmsi_handoff$audit$time_window_summary$value,
    c(0L, 0L, 1L, 4L)
  ),
  nrow(pmsi_handoff$audit$hospital_nights_by_year_unit) == 2L,
  all(vapply(composed$validation, function(x) isTRUE(x$ok), logical(1)))
)

incidence_exposure <- composed_v3$bundle$denominator_bundle$
  incidence_exposure_by_year_um_uf_ta_de_profile
current_profile_annual <- incidence_exposure |>
  dplyr::filter(
    .data$denominator_profile_id == "midnight_presence_v1",
    .data$exposure_unit == "patient_days",
    .data$CODE_TA %in% c("03", "20"),
    .data$de_domain_ref %in% ratb_included_ta_de_domains()
  ) |>
  dplyr::group_by(.data$calendar_year) |>
  dplyr::summarise(
    hospital_nights = as.integer(sum(.data$exposure_value)),
    .groups = "drop"
  )

# Why: protects the Rouen v3 handoff contract: the same eligible PMSI unit
# exposure transports mapped TA/DE activity outside today's perimeter while
# the current profile still derives the already-ratified v2 denominator.
stopifnot(
  identical(
    names(composed_v3$site_inputs),
    c(
      "microbiology_observations",
      "bacteria_mapping",
      "sample_type_mapping",
      "antibiotic_mapping",
      "unit_mapping",
      "incidence_exposure_by_year_um_uf_ta_de_profile"
    )
  ),
  identical(composed_v3$bundle$sir_wide_meta$contract_version, "v3"),
  identical(
    names(composed_v3$bundle$denominator_bundle),
    "incidence_exposure_by_year_um_uf_ta_de_profile"
  ),
  identical(
    names(incidence_exposure),
    c(
      "calendar_year", "SEJUM", "SEJUF", "CODE_TA", "CODE_DE",
      "de_domain_ref", "denominator_profile_id", "exposure_value",
      "exposure_unit"
    )
  ),
  !anyNA(incidence_exposure),
  any(
    incidence_exposure$SEJUF == "5701" &
      incidence_exposure$CODE_TA == "10" &
      incidence_exposure$de_domain_ref == "URGENCES" &
      incidence_exposure$exposure_value == 1L
  ),
  sum(incidence_exposure$exposure_value) == 32L,
  identical(
    current_profile_annual$hospital_nights,
    pmsi_handoff$site_inputs$denominator_by_year$hospital_nights
  ),
  all(pmsi_handoff$audit$v3_current_profile_identity$difference == 0L),
  all(c(
    "sample_CODE_TA", "sample_CODE_DE", "sample_de_domain_ref"
  ) %in% names(composed_v3$bundle$sample_scope_reference)),
  all(vapply(composed_v3$validation, function(x) isTRUE(x$ok), logical(1)))
)

# Why: protects the canonical unit-mapping contract before the historical
# CONSORES loader can collapse repeated UF rows with conflicting TA/DE codes.
conflicting_structure <- tibble::tibble(
  UF = c("5130", "5130"),
  CODE_TA = c("03", "20"),
  CODE_DE = c("D03", "D07")
)
mapping_conflict <- tryCatch(
  {
    ratb_assert_unique_consores_unit_mapping(conflicting_structure)
    NULL
  },
  error = identity
)
stopifnot(
  inherits(mapping_conflict, "error"),
  grepl("conflicting TA/DE mappings", conditionMessage(mapping_conflict))
)

cat("PASS: Rouen raw handoff v1\n")
