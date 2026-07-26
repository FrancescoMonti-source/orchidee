#!/usr/bin/env Rscript

required_packages <- c(
  "dplyr",
  "lubridate",
  "purrr",
  "readr",
  "readxl",
  "redsan",
  "stringi",
  "stringr",
  "tibble",
  "tidyr"
)

available <- vapply(
  required_packages,
  requireNamespace,
  logical(1),
  quietly = TRUE
)
missing_packages <- required_packages[!available]
if (length(missing_packages) > 0L) {
  stop(
    "Missing Rouen R packages: ",
    paste(missing_packages, collapse = ", "),
    call. = FALSE
  )
}

if (utils::packageVersion("redsan") < numeric_version("0.2.0")) {
  stop(
    "redsan 0.2.0 or newer is required; found ",
    as.character(utils::packageVersion("redsan")),
    ".",
    call. = FALSE
  )
}
