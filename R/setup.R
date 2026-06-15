library(conflicted)
library(fuzzyjoin)
library(stringr)
library(tidyverse)
library(magrittr)
library(glue)
library(openxlsx)
library(corpustools)
library(stringdist)
library(lubridate)
library(progressr)
library(ggtext)
library(DT)
library(purrr)
library(ggplot2)
library(DT)
library(psych)
library(stopwords)
library(knitr)
library(fmckage)
library(arrow)
conflicts_prefer(dplyr::filter)

source("R/biol.R")
source("R/get_edsan.R")
source("R/pmsi.R")
source("R/zzz.R")
setup_source <- function(script_name) {
  candidates <- c(script_name, file.path("R", script_name))
  path <- candidates[file.exists(candidates)][1]
  if (is.na(path)) {
    stop(
      "Missing setup dependency: ", script_name, ". Checked: ",
      paste(candidates, collapse = ", "),
      call. = FALSE
    )
  }
  source(path)
}

setup_source_config <- function(config_name) {
  candidates <- c(file.path("config", config_name), config_name)
  path <- candidates[file.exists(candidates)][1]
  if (is.na(path)) {
    stop(
      "Missing setup config: ", config_name, ". Checked: ",
      paste(candidates, collapse = ", "),
      call. = FALSE
    )
  }
  source(path)
}

setup_source_config("pipeline.R")
setup_source("helpers.R")


options(
  repr.matrix.max.cols = 200,   # ou plus si tu es fou
  repr.matrix.max.rows = 200
)

make_periods <- function(start_date, end_date,
                         sep = ",", by = "6 months",
                         prefix = "", suffix = "") {
    s <- lubridate::as_date(start_date)
    e <- lubridate::as_date(end_date)
    if (is.na(s) || is.na(e)) stop("start_date/end_date must be coercible to Date")
    if (s > e) {
        return(tibble::tibble(
            start = as.Date(character()),
            end   = as.Date(character()),
            period = character()
        ))
    }

    starts <- seq(from = s, to = e, by = by)
    ends <- c(starts[-1] - 1, e)

    tibble::tibble(
        start  = starts,
        end    = ends,
        period = paste0(prefix,
                        format(starts, "%Y-%m-%d"),
                        sep,
                        format(ends, "%Y-%m-%d"),
                        suffix)
    )
}
