#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(dplyr))

source("R/helpers.R")
source("R/external_bundle_validation_helpers.R")
source("R/external_handoff_helpers.R")
source("R/ratb_canonical_runtime_helpers.R")
source("R/ratb_operational_input_helpers.R")

pipeline_config_env <- new.env(parent = globalenv())
sys.source("config/pipeline.R", envir = pipeline_config_env)

contract <- orchidee_external_contract_v2()
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
for (atb_col in contract$sir_wide$atb_cols) {
  sir_wide[[atb_col]] <- NA_character_
}
sir_wide$cefotaxime <- "S"
sir_wide$blse_status_row <- "no_signal"
sir_wide$carbapenemase_status_row <- "no_signal"
sir_wide$blse_flag <- FALSE
sir_wide$carbapenemase_flag <- FALSE

bundle_dir <- tempfile("orchidee_external_bundle_v2_")
dir.create(bundle_dir)
on.exit(unlink(bundle_dir, recursive = TRUE), add = TRUE)

saveRDS(sir_wide, file.path(bundle_dir, "sir_wide.rds"))
saveRDS(
  orchidee_handoff_build_sir_wide_meta(sir_wide, contract = contract),
  file.path(bundle_dir, "sir_wide_meta.rds")
)
saveRDS(
  data.frame(
    SEJUF = "UF1",
    sample_uf_is_eligible_by_ta_de = TRUE,
    sample_uf_ta_de_status = "eligible_ta_de",
    sample_uf_ta_de_reason = "eligible_ta_de",
    stringsAsFactors = FALSE
  ),
  file.path(bundle_dir, "sample_scope_reference.rds")
)
saveRDS(
  list(
    incidence_denominator_by_year = data.frame(
      calendar_year = 2024L,
      hospital_nights = 365L,
      n_episodes = 1L
    )
  ),
  file.path(bundle_dir, "denominator_bundle.rds")
)

config <- list(
  runtime = list(
    external_bundle_v2_dir = bundle_dir,
    external_workspace_dir = tempfile("orchidee_external_workspace_")
  ),
  paths = list(data_dir = tempfile("protected_data_"), downloads_dir = "unused")
)

context <- resolve_ratb_operational_context(config)
runtime <- load_ratb_operational_runtime(config = config)
bundle_validation <- validate_external_input_bundle(
  bundle_dir = bundle_dir,
  contract = contract
)

missing_v2_metadata_error <- tryCatch(
  {
    incomplete_config <- config
    incomplete_bundle_dir <- tempfile("orchidee_external_bundle_missing_meta_")
    dir.create(incomplete_bundle_dir)
    on.exit(unlink(incomplete_bundle_dir, recursive = TRUE), add = TRUE)
    invisible(file.copy(
      list.files(bundle_dir, full.names = TRUE),
      incomplete_bundle_dir
    ))
    incomplete_meta <- readRDS(
      file.path(incomplete_bundle_dir, "sir_wide_meta.rds")
    )
    incomplete_meta$contract_version <- NULL
    incomplete_meta$sejuf_semantics <- NULL
    saveRDS(
      incomplete_meta,
      file.path(incomplete_bundle_dir, "sir_wide_meta.rds")
    )
    incomplete_config$runtime$external_bundle_v2_dir <- incomplete_bundle_dir
    load_ratb_operational_runtime(incomplete_config)
    NA_character_
  },
  error = function(condition) conditionMessage(condition)
)

workspace_collision_error <- tryCatch(
  {
    collision_config <- config
    collision_config$runtime$external_workspace_dir <- "."
    collision_config$paths$downloads_dir <- "downloads"
    resolve_ratb_operational_context(collision_config)
    NA_character_
  },
  error = function(condition) conditionMessage(condition)
)

# Why: the collision guard compares configured paths, and the directories it
# protects are routinely absent on a fresh install. Its comparison key must
# therefore be canonical without consulting the filesystem: normalizePath()
# returns a non-existent path unchanged on Unix, which silently disarmed the
# guard there while it kept working on Windows.
stopifnot(
  identical(
    ratb_comparison_path("downloads"),
    ratb_comparison_path("./downloads")
  ),
  identical(
    ratb_comparison_path("downloads"),
    ratb_comparison_path("downloads/")
  ),
  identical(
    ratb_comparison_path("outputs/../downloads"),
    ratb_comparison_path("downloads")
  ),
  identical(
    ratb_comparison_path(file.path(getwd(), "downloads")),
    ratb_comparison_path("downloads")
  ),
  identical(
    ratb_comparison_path("/orchidee-absent/./x/"),
    ratb_comparison_path("/orchidee-absent/x")
  ),
  !identical(
    ratb_comparison_path("downloads"),
    ratb_comparison_path("outputs")
  ),
  grepl("^(/|[A-Za-z]:/)", ratb_comparison_path("downloads"))
)

# Why: protects the canonical operational policy: strict external bundle v2 is
# the only runtime input, with no selector or CHU-native fallback surface.
stopifnot(
  !"input_source" %in% names(pipeline_config_env$orchidee_config$runtime),
  identical(context$input_source, "external_bundle_v2"),
  !"is_chu_native" %in% names(context),
  !"chu_native_qa" %in% names(runtime)
)

# Why: protects the external-v2 input/cache contract: four canonical artifacts
# feed the canonical objects and runtime outputs stay outside protected paths.
stopifnot(
  identical(runtime$input_source, "external_bundle_v2"),
  identical(
    names(runtime$runtime_inputs),
    c(
      "sir_wide_ratb_scope",
      "sir_wide_ratb_analytic_scope",
      "incidence_denominator_by_year"
    )
  ),
  isTRUE(bundle_validation$ok),
  any(grepl("contains extra columns outside the v2 contract", bundle_validation$warnings)),
  identical(runtime$provenance$contract_version, "v2"),
  identical(
    runtime$provenance$sejuf_semantics,
    "hospitalization_unit_at_sampling"
  ),
  nrow(runtime$runtime_inputs$sir_wide_ratb_analytic_scope) == 1L,
  grepl("missing required fields", missing_v2_metadata_error),
  grepl("must keep external cache and downloads separate", workspace_collision_error)
)

cat("PASS: RATB operational external-v2 runtime\n")
