#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(dplyr))

source("R/helpers.R")
source("R/external_bundle_validation_helpers.R")
source("R/external_handoff_helpers.R")
source("R/ratb_canonical_runtime_helpers.R")
source("R/ratb_operational_input_helpers.R")

operational_input_source_override <- Sys.getenv(
  "ORCHIDEE_OPERATIONAL_INPUT_SOURCE",
  unset = NA_character_
)
Sys.unsetenv("ORCHIDEE_OPERATIONAL_INPUT_SOURCE")
pipeline_config_env <- new.env(parent = globalenv())
sys.source("config/pipeline.R", envir = pipeline_config_env)
default_operational_input_source <-
  pipeline_config_env$orchidee_config$runtime$input_source
if (is.na(operational_input_source_override)) {
  Sys.unsetenv("ORCHIDEE_OPERATIONAL_INPUT_SOURCE")
} else {
  Sys.setenv(
    ORCHIDEE_OPERATIONAL_INPUT_SOURCE = operational_input_source_override
  )
}

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

compat_bundle_dir <- tempfile("orchidee_external_bundle_v2_compat_")
dir.create(compat_bundle_dir)
on.exit(unlink(compat_bundle_dir, recursive = TRUE), add = TRUE)
invisible(file.copy(
  file.path(bundle_dir, c("sir_wide.rds", "sir_wide_meta.rds")),
  compat_bundle_dir
))
saveRDS(
  list(
    sample_scope_reference = readRDS(
      file.path(bundle_dir, "sample_scope_reference.rds")
    ),
    incidence_denominator_by_year = readRDS(
      file.path(bundle_dir, "denominator_bundle.rds")
    )$incidence_denominator_by_year
  ),
  file.path(compat_bundle_dir, "ratb_scope_cache")
)

config <- list(
  runtime = list(
    input_source = "external_bundle_v2",
    external_bundle_v2_dir = bundle_dir,
    external_workspace_dir = tempfile("orchidee_external_workspace_")
  ),
  paths = list(data_dir = tempfile("missing_chu_data_"), downloads_dir = "unused")
)

legacy_config <- config
legacy_config$runtime$input_source <- "chu_native"
legacy_context <- resolve_ratb_operational_context(legacy_config)

runtime <- load_ratb_operational_runtime(
  config = config,
  chu_cache_policy = "load_existing"
)
bundle_validation <- validate_external_input_bundle(
  bundle_dir = bundle_dir,
  contract = contract,
  strict_preferred = TRUE
)

invalid_mode_error <- tryCatch(
  {
    invalid_config <- config
    invalid_config$runtime$input_source <- "external"
    load_ratb_operational_runtime(invalid_config)
    NA_character_
  },
  error = function(condition) conditionMessage(condition)
)

v1_error <- tryCatch(
  {
    v1_config <- config
    v1_bundle_dir <- tempfile("orchidee_external_bundle_v1_")
    dir.create(v1_bundle_dir)
    on.exit(unlink(v1_bundle_dir, recursive = TRUE), add = TRUE)
    invisible(file.copy(list.files(bundle_dir, full.names = TRUE), v1_bundle_dir))
    saveRDS(
      orchidee_handoff_build_sir_wide_meta(
        sir_wide,
        contract = orchidee_external_contract_v1()
      ),
      file.path(v1_bundle_dir, "sir_wide_meta.rds")
    )
    v1_config$runtime$external_bundle_v2_dir <- v1_bundle_dir
    load_ratb_operational_runtime(v1_config)
    NA_character_
  },
  error = function(condition) conditionMessage(condition)
)

compatibility_error <- tryCatch(
  {
    compatibility_config <- config
    compatibility_config$runtime$external_bundle_v2_dir <- compat_bundle_dir
    load_ratb_operational_runtime(compatibility_config)
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

stale_cache_dir <- tempfile("orchidee_stale_chu_scope_cache_")
dir.create(stale_cache_dir)
on.exit(unlink(stale_cache_dir, recursive = TRUE), add = TRUE)
saveRDS(list(), file.path(stale_cache_dir, "ratb_scope_cache"))
saveRDS(
  list(
    fingerprint = "old_scope",
    sir_wide_artifact_signature = list(artifact = "old")
  ),
  file.path(stale_cache_dir, "ratb_scope_cache_meta")
)
stale_cache_error <- tryCatch(
  {
    load_existing_chu_ratb_scope_cache(
      sir_wide = sir_wide,
      sir_wide_artifact_signature = list(artifact = "current"),
      data_dir = stale_cache_dir
    )
    NA_character_
  },
  error = function(condition) conditionMessage(condition)
)

# Why: protects the ratified operational policy: v2 is the default while CHU
# native remains an explicit legacy comparison/rollback selection.
stopifnot(
  identical(default_operational_input_source, "external_bundle_v2"),
  identical(legacy_context$input_source, "chu_native"),
  isTRUE(legacy_context$is_chu_native)
)

# Why: protects the operational input/cache boundary: external_bundle_v2 uses
# only strict v2 inputs, external paths cannot overlap CHU paths, and a
# read-only CHU cache must match the current sir_wide artifact.
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
  is.null(runtime$chu_native_qa),
  isTRUE(bundle_validation$ok),
  any(grepl("contains extra columns outside the v2 contract", bundle_validation$warnings)),
  identical(runtime$provenance$contract_version, "v2"),
  identical(
    runtime$provenance$sejuf_semantics,
    "hospitalization_unit_at_sampling"
  ),
  nrow(runtime$runtime_inputs$sir_wide_ratb_analytic_scope) == 1L,
  grepl("must be exactly one of", invalid_mode_error),
  grepl("missing required fields", v1_error),
  grepl("Strict preferred mode requires", compatibility_error),
  grepl("must keep external cache and downloads separate", workspace_collision_error),
  grepl("Existing RATB scope cache is not usable", stale_cache_error)
)

cat("PASS: RATB operational input selector\n")
