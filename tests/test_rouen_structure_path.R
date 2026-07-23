#!/usr/bin/env Rscript

run_rouen_structure_path_test <- function() {
  current_variable <- "ORCHIDEE_ROUEN_STRUCTURE_PATH"
  legacy_variable <- "ORCHIDEE_CONSORES_STRUCTURE_PATH"
  variables <- c(current_variable, legacy_variable)
  previous_values <- Sys.getenv(variables, unset = NA_character_)
  on.exit({
    for (variable in variables) {
      previous_value <- previous_values[[variable]]
      if (is.na(previous_value)) {
        Sys.unsetenv(variable)
      } else {
        do.call(
          Sys.setenv,
          stats::setNames(list(previous_value), variable)
        )
      }
    }
  })

  default_structure_path <- file.path(
    "ref",
    "rouen",
    "establishment_structure_2025.xlsx"
  )

  Sys.unsetenv(variables)
  default_rouen <- new.env(parent = globalenv())
  sys.source("config/rouen_raw_handoff.R", envir = default_rouen)

  legacy_structure_path <- tempfile(fileext = ".xlsx")
  Sys.setenv(ORCHIDEE_CONSORES_STRUCTURE_PATH = legacy_structure_path)
  legacy_warning <- NULL
  legacy_rouen <- new.env(parent = globalenv())
  withCallingHandlers(
    sys.source("config/rouen_raw_handoff.R", envir = legacy_rouen),
    warning = function(condition) {
      legacy_warning <<- conditionMessage(condition)
      invokeRestart("muffleWarning")
    }
  )

  helper_env <- new.env(parent = globalenv())
  sys.source("R/ratb_hospital_days_helpers.R", envir = helper_env)
  helper_warning <- NULL
  helper_legacy_path <- withCallingHandlers(
    helper_env$ratb_default_rouen_structure_path(),
    warning = function(condition) {
      helper_warning <<- conditionMessage(condition)
      invokeRestart("muffleWarning")
    }
  )

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
    identical(
      legacy_rouen$rouen_raw_handoff_config$references$establishment_structure,
      legacy_structure_path
    ),
    grepl("deprecated", legacy_warning, fixed = TRUE),
    identical(helper_legacy_path, legacy_structure_path),
    grepl("deprecated", helper_warning, fixed = TRUE),
    identical(
      override_rouen$rouen_raw_handoff_config$references$establishment_structure,
      override_structure_path
    )
  )
}

run_rouen_structure_path_test()

cat("PASS: Rouen establishment structure path\n")
