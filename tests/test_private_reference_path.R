#!/usr/bin/env Rscript

run_private_reference_path_test <- function() {
  variable <- "ORCHIDEE_CONSORES_STRUCTURE_PATH"
  previous_value <- Sys.getenv(variable, unset = NA_character_)
  on.exit({
    if (is.na(previous_value)) {
      Sys.unsetenv(variable)
    } else {
      Sys.setenv(ORCHIDEE_CONSORES_STRUCTURE_PATH = previous_value)
    }
  })

  default_structure_path <- file.path(
    "data",
    "consores_structure_intranet_maj_2025.xlsx"
  )

  Sys.unsetenv(variable)
  default_rouen <- new.env(parent = globalenv())
  sys.source("config/rouen_raw_handoff.R", envir = default_rouen)

  override_structure_path <- tempfile(fileext = ".xlsx")
  Sys.setenv(ORCHIDEE_CONSORES_STRUCTURE_PATH = override_structure_path)
  override_rouen <- new.env(parent = globalenv())
  sys.source("config/rouen_raw_handoff.R", envir = override_rouen)

  # Why: protects the canonical private-input contract: local execution has a
  # stable ignored default while deployments can inject the structure workbook.
  stopifnot(
    identical(
      default_rouen$rouen_raw_handoff_config$references$consores_structure,
      default_structure_path
    ),
    identical(
      override_rouen$rouen_raw_handoff_config$references$consores_structure,
      override_structure_path
    )
  )
}

run_private_reference_path_test()

cat("PASS: private CONSORES reference path\n")
