library(conflicted)
library(stringr)
library(tidyverse)
library(magrittr)
library(openxlsx)
library(lubridate)
library(DT)
library(purrr)
library(ggplot2)
library(knitr)
conflicts_prefer(dplyr::filter)

source("R/zzz.R")
source("R/bootstrap.R")

orchidee_source_required_config("pipeline.R", "setup config")
orchidee_source_required_script("helpers.R", "setup dependency helpers.R")


options(
  repr.matrix.max.cols = 200,
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
