#!/usr/bin/env Rscript

run_rouen_structure_path_test <- function() {
  current_variable <- "ORCHIDEE_ROUEN_STRUCTURE_PATH"
  previous_value <- Sys.getenv(current_variable, unset = NA_character_)
  on.exit({
    if (is.na(previous_value)) {
      Sys.unsetenv(current_variable)
    } else {
      Sys.setenv(ORCHIDEE_ROUEN_STRUCTURE_PATH = previous_value)
    }
  })

  default_structure_path <- file.path(
    "ref",
    "rouen",
    "establishment_structure_2025.xlsx"
  )

  Sys.unsetenv(current_variable)
  default_rouen <- new.env(parent = globalenv())
  sys.source("config/rouen_raw_handoff.R", envir = default_rouen)

  helper_env <- new.env(parent = globalenv())
  sys.source("R/ratb_hospital_days_helpers.R", envir = helper_env)
  helper_default_path <- helper_env$ratb_default_rouen_structure_path()

  override_structure_path <- tempfile(fileext = ".xlsx")
  Sys.setenv(ORCHIDEE_ROUEN_STRUCTURE_PATH = override_structure_path)
  override_rouen <- new.env(parent = globalenv())
  sys.source("config/rouen_raw_handoff.R", envir = override_rouen)

  # Why: protects the Rouen reference contract: the versioned structure has a
  # stable default while deployments may inject an explicitly selected update.
  stopifnot(
    identical(
      default_rouen$rouen_raw_handoff_config$references$establishment_structure,
      default_structure_path
    ),
    identical(helper_default_path, default_structure_path),
    identical(helper_env$ratb_default_rouen_structure_path(), override_structure_path),
    identical(
      override_rouen$rouen_raw_handoff_config$references$establishment_structure,
      override_structure_path
    )
  )
}

run_rouen_structure_path_test()

cat("PASS: Rouen establishment structure path\n")
