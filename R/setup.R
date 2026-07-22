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
