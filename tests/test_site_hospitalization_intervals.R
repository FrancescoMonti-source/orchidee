#!/usr/bin/env Rscript

# Why: the generic site path now receives hospitalization intervals and derives
# the denominator and each sample's hosting unit itself. Those derivations are
# the analytical decisions ORCHIDEE took over from the site, so each one is
# pinned here by the case that would have been decided differently:
#   - a return to a unit after another unit is two visits, not one;
#   - duplicate or overlapping rows for one unit are one occupied interval;
#   - a transfer whose exit instant is the next entry instant is adjacent, and
#     the patient is counted once;
#   - a stay crossing the declared period keeps only the nights inside it;
#   - a hospitalization with no microbiology still contributes nights;
#   - a real double occupancy, a reversed interval, a malformed timestamp and a
#     clock reading a zone makes ambiguous all stop the workflow;
#   - a sample that cannot be placed loses its perimeter, not the build.

suppressPackageStartupMessages(library(dplyr))

source("R/external_bundle_validation_helpers.R")
source("R/ratb_hospital_days_helpers.R")
source("R/external_handoff_helpers.R")
source("R/chu_sample_hospitalization_unit_attribution.R")
source("R/site_handoff_preparation_helpers.R")

unit_mapping <- data.frame(
  SEJUF = c("UF_A", "UF_B"),
  CODE_TA = c("03", "03"),
  CODE_DE = c("102", "102"),
  de_domain_ref = c("MÉDECINE", "MÉDECINE"),
  stringsAsFactors = FALSE
)

observation <- function(
    PATID = "P1",
    EVTID = "E1",
    ELTID = "L1",
    DATEPRELEV = "2024-01-04",
    HEUREPRELEV = "09:00"
  ) {
  data.frame(
    PATID = PATID,
    EVTID = EVTID,
    ELTID = ELTID,
    DATEPRELEV = DATEPRELEV,
    HEUREPRELEV = HEUREPRELEV,
    bacteria_local = "E. coli",
    sample_type_local = "Urine",
    antibiotic_local = "Cefotaxime",
    sir_result = "S",
    ratb_diagnostic_scope = TRUE,
    stringsAsFactors = FALSE
  )
}

intervals <- function(DATENT, DATSORT, SEJUM, SEJUF, PATID = "P1", EVTID = "E1") {
  data.frame(
    PATID = PATID,
    EVTID = EVTID,
    DATENT = DATENT,
    DATSORT = DATSORT,
    SEJUM = SEJUM,
    SEJUF = SEJUF,
    stringsAsFactors = FALSE
  )
}

prepare <- function(
    hospitalization_intervals,
    microbiology_observations = observation(),
    start_year = 2024L,
    end_year = 2024L,
    timezone = orchidee_site_default_timezone()
  ) {
  orchidee_site_prepare_handoff(
    microbiology_observations = microbiology_observations,
    bacteria_mapping = data.frame(
      bacteria_local = "E. coli",
      bact_norm = "escherichia_coli",
      stringsAsFactors = FALSE
    ),
    sample_type_mapping = data.frame(
      sample_type_local = "Urine",
      naturepvt_norm = "urines",
      stringsAsFactors = FALSE
    ),
    antibiotic_mapping = data.frame(
      antibiotic_local = "Cefotaxime",
      atb_norm = "cefotaxime",
      stringsAsFactors = FALSE
    ),
    unit_mapping = unit_mapping,
    hospitalization_intervals = hospitalization_intervals,
    period = orchidee_site_resolve_period(start_year, end_year),
    timezone = timezone
  )
}

blocking_checks <- function(result) {
  sort(unique(vapply(
    Filter(
      function(finding) identical(finding$severity, "BLOCKING"),
      result$findings
    ),
    function(finding) paste0(finding$block, "/", finding$check),
    character(1)
  )))
}

has_check <- function(result, severity, check) {
  any(vapply(
    result$findings,
    function(finding) {
      identical(finding$severity, severity) && identical(finding$check, check)
    },
    logical(1)
  ))
}

nights_by_unit <- function(result) {
  exposure <- result$site_inputs$incidence_exposure_by_year_um_uf_ta_de_profile
  stats::setNames(
    as.integer(exposure$exposure_value),
    paste(exposure$calendar_year, exposure$SEJUF, sep = "/")
  )
}

## A -> B -> A ---------------------------------------------------------------
##
## The two visits to UF_A are separated by time spent in UF_B. Merging them
## would count the UF_B nights twice; treating each row independently would be
## right here but wrong for the duplicate case below. Both must hold at once.

return_visit <- prepare(intervals(
  c("2024-01-01 08:00", "2024-01-03 08:00", "2024-01-05 08:00"),
  c("2024-01-03 08:00", "2024-01-05 08:00", "2024-01-07 08:00"),
  c("UM_A", "UM_B", "UM_A"),
  c("UF_A", "UF_B", "UF_A")
))

## Duplicate and overlapping rows for one unit --------------------------------

duplicate_rows <- prepare(intervals(
  c("2024-01-01 08:00", "2024-01-02 08:00", "2024-01-01 08:00"),
  c("2024-01-04 08:00", "2024-01-05 08:00", "2024-01-04 08:00"),
  rep("UM_A", 3L),
  rep("UF_A", 3L)
))

## Cross-year clipping --------------------------------------------------------
##
## Declared period 2024 only. The stay starts in 2023 and ends in 2024, so the
## 2023 nights are clipped out and said to be clipped.

cross_year <- prepare(
  intervals(
    "2023-12-29 08:00",
    "2024-01-03 08:00",
    "UM_A",
    "UF_A"
  ),
  microbiology_observations = observation(DATEPRELEV = "2024-01-02")
)

## A hospitalization with no microbiology -------------------------------------
##
## The denominator is computed independently of the microbiology: an episode
## with no sample still contributes its nights.

no_sample <- prepare(
  rbind(
    intervals("2024-01-01 08:00", "2024-01-03 08:00", "UM_A", "UF_A"),
    intervals(
      "2024-02-01 08:00",
      "2024-02-11 08:00",
      "UM_B",
      "UF_B",
      PATID = "P9",
      EVTID = "E9"
    )
  )
)

## Blocking classes -----------------------------------------------------------

# The overlapping row is the one that starts *second*, and it names the unit
# that sorts first alphabetically. The scan reorders the stays by entry instant,
# so a finding that read its units from the unmerged frame would name UF_B here
# instead of UF_A, and send the site after the wrong row.
overlapping_units <- prepare(intervals(
  c("2024-01-01 08:00", "2024-01-02 08:00"),
  c("2024-01-05 08:00", "2024-01-06 08:00"),
  c("UM_B", "UM_A"),
  c("UF_B", "UF_A")
))
overlapping_units_finding <- Filter(
  function(finding) identical(finding$check, "overlapping_units_in_episode"),
  overlapping_units$findings
)[[1L]]

reversed <- prepare(intervals(
  "2024-01-05 08:00",
  "2024-01-01 08:00",
  "UM_A",
  "UF_A"
))

malformed <- prepare(intervals(
  "05/01/2024",
  "2024-01-07 08:00",
  "UM_A",
  "UF_A"
))

missing_unit_key <- prepare(intervals(
  "2024-01-01 08:00",
  "2024-01-05 08:00",
  "UM_A",
  NA_character_
))

# Europe/Paris moves the clock forward on 31 March 2024 at 02:00 and back on
# 27 October 2024 at 03:00, so 02:30 does not exist on the first date and
# happens twice on the second. Neither is a value ORCHIDEE may resolve on a
# site's behalf.
nonexistent_clock <- prepare(intervals(
  "2024-03-31 02:30",
  "2024-04-02 08:00",
  "UM_A",
  "UF_A"
))

ambiguous_clock <- prepare(intervals(
  "2024-10-25 08:00",
  "2024-10-27 02:30",
  "UM_A",
  "UF_A"
))

## Attribution ----------------------------------------------------------------

# The sample is drawn while the patient is in UF_B; ORCHIDEE places it there
# without the site naming a unit.
transfer_attribution <- prepare(
  intervals(
    c("2024-01-01 08:00", "2024-01-03 08:00"),
    c("2024-01-03 08:00", "2024-01-07 08:00"),
    c("UM_A", "UM_B"),
    c("UF_A", "UF_B")
  ),
  microbiology_observations = observation(
    DATEPRELEV = "2024-01-04",
    HEUREPRELEV = "09:00"
  )
)

# A same-day interval counts zero nights and still hosts its sample: the two
# roles of an interval are independent.
same_day <- prepare(
  rbind(
    intervals("2024-01-01 08:00", "2024-01-11 08:00", "UM_A", "UF_A"),
    intervals(
      "2024-02-02 08:00",
      "2024-02-02 18:00",
      "UM_B",
      "UF_B",
      PATID = "P2",
      EVTID = "E2"
    )
  ),
  microbiology_observations = rbind(
    observation(),
    observation(
      PATID = "P2",
      EVTID = "E2",
      ELTID = "L2",
      DATEPRELEV = "2024-02-02",
      HEUREPRELEV = "10:00"
    )
  )
)

# No interval for the sample's episode, and a sample with no sampling time.
# Both lose their perimeter; neither stops the build.
unplaceable <- prepare(
  intervals("2024-01-01 08:00", "2024-01-11 08:00", "UM_A", "UF_A"),
  microbiology_observations = rbind(
    observation(),
    observation(PATID = "P404", EVTID = "E404", ELTID = "L404"),
    observation(ELTID = "L2", HEUREPRELEV = NA_character_)
  )
)

## Period selection of microbiology -------------------------------------------

outside_period <- prepare(
  intervals("2024-01-01 08:00", "2024-01-11 08:00", "UM_A", "UF_A"),
  microbiology_observations = rbind(
    observation(),
    observation(ELTID = "L2", DATEPRELEV = "2022-01-04")
  )
)

## The period reaches the render ----------------------------------------------
##
## The site period travels to the report as two process-scoped variables, so
## the same numbers select the microbiology and declare the published years.
## An edit of config/pipeline.R would leave the next Rouen render publishing
## somebody else's period, which is why the default has to survive untouched.
read_report_years <- function(start = NA_character_, end = NA_character_) {
  previous <- Sys.getenv(
    c("ORCHIDEE_REPORT_START_YEAR", "ORCHIDEE_REPORT_END_YEAR"),
    unset = NA_character_
  )
  on.exit({
    for (name in names(previous)) {
      if (is.na(previous[[name]])) {
        Sys.unsetenv(name)
      } else {
        do.call(Sys.setenv, stats::setNames(list(previous[[name]]), name))
      }
    }
  }, add = TRUE)
  Sys.unsetenv(c("ORCHIDEE_REPORT_START_YEAR", "ORCHIDEE_REPORT_END_YEAR"))
  if (!is.na(start)) Sys.setenv(ORCHIDEE_REPORT_START_YEAR = start)
  if (!is.na(end)) Sys.setenv(ORCHIDEE_REPORT_END_YEAR = end)
  config_environment <- new.env(parent = globalenv())
  sys.source("config/pipeline.R", envir = config_environment)
  as.integer(get("orchidee_config", envir = config_environment)$ratb$report_years)
}

default_report_years <- read_report_years()
overridden_report_years <- read_report_years("2025", "2026")
report_years_after_override <- read_report_years()
half_period_error <- tryCatch(
  {
    read_report_years("2025")
    NA_character_
  },
  error = function(condition) conditionMessage(condition)
)

## A blocking finding is a refusal, not a warning the builder may ignore -------

rscript_path <- file.path(
  R.home("bin"),
  if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
)
build_root <- tempfile("orchidee-site-intervals-")
dir.create(build_root, recursive = TRUE)
on.exit(unlink(build_root, recursive = TRUE, force = TRUE), add = TRUE)
overlap_blocks <- list(
  microbiology_observations = observation(),
  bacteria_mapping = data.frame(
    bacteria_local = "E. coli",
    bact_norm = "escherichia_coli",
    stringsAsFactors = FALSE
  ),
  sample_type_mapping = data.frame(
    sample_type_local = "Urine",
    naturepvt_norm = "urines",
    stringsAsFactors = FALSE
  ),
  antibiotic_mapping = data.frame(
    antibiotic_local = "Cefotaxime",
    atb_norm = "cefotaxime",
    stringsAsFactors = FALSE
  ),
  unit_mapping = unit_mapping,
  hospitalization_intervals = intervals(
    c("2024-01-01 08:00", "2024-01-02 08:00"),
    c("2024-01-05 08:00", "2024-01-06 08:00"),
    c("UM_A", "UM_B"),
    c("UF_A", "UF_B")
  )
)
overlap_paths <- file.path(build_root, paste0(names(overlap_blocks), ".rds"))
invisible(Map(saveRDS, overlap_blocks, overlap_paths))
overlap_build <- suppressWarnings(system2(
  rscript_path,
  c(
    "--no-save",
    "--no-restore",
    shQuote("scripts/build_external_bundle_from_site_inputs.R"),
    shQuote(overlap_paths),
    shQuote(file.path(build_root, "bundle_v3")),
    "--start-year=2024",
    "--end-year=2024",
    "--no-next-steps"
  ),
  stdout = TRUE,
  stderr = TRUE
))
overlap_build_status <- attr(overlap_build, "status")
if (is.null(overlap_build_status)) overlap_build_status <- 0L

## Assertions -----------------------------------------------------------------

stopifnot(
  # A -> B -> A: six nights in total, four of them in UF_A. Merging the two
  # UF_A visits would report four and six; treating the union as one interval
  # across units would report six for UF_A alone.
  length(blocking_checks(return_visit)) == 0L,
  identical(
    nights_by_unit(return_visit),
    c("2024/UF_A" = 4L, "2024/UF_B" = 2L)
  ),

  # Three rows, one occupied interval from 1 to 5 January: four nights, not the
  # ten a naive sum of the rows would give.
  length(blocking_checks(duplicate_rows)) == 0L,
  identical(nights_by_unit(duplicate_rows), c("2024/UF_A" = 4L)),
  has_check(duplicate_rows, "INFO", "merged_unit_rows"),

  # A stay crossing the period bound keeps only the nights inside it, and the
  # ones it loses are counted in the report rather than disappearing.
  length(blocking_checks(cross_year)) == 0L,
  identical(nights_by_unit(cross_year), c("2024/UF_A" = 2L)),
  has_check(cross_year, "INFO", "nights_outside_period"),

  # An episode with no microbiology contributes its nights.
  length(blocking_checks(no_sample)) == 0L,
  identical(
    nights_by_unit(no_sample),
    c("2024/UF_A" = 2L, "2024/UF_B" = 10L)
  ),

  # A patient in two different units at once has no defensible night split.
  identical(
    blocking_checks(overlapping_units),
    "hospitalization_intervals/overlapping_units_in_episode"
  ),
  is.null(overlapping_units$site_inputs),
  # The unit named is the one whose stay overlaps an earlier one, read in the
  # scan's own row order.
  identical(overlapping_units_finding$values, "UF_A"),

  # Malformed rows stop the workflow instead of being read as something else.
  # Each fixture holds a single interval, so removing it also leaves the block
  # with nothing to derive an exposure from; both findings are reported, and
  # the named cause comes first in the report.
  identical(
    blocking_checks(reversed),
    sort(c(
      "hospitalization_intervals/reversed_interval",
      "hospitalization_intervals/no_usable_interval"
    ))
  ),
  identical(
    blocking_checks(malformed),
    sort(c(
      "hospitalization_intervals/timestamp_malformed",
      "hospitalization_intervals/no_usable_interval"
    ))
  ),
  identical(
    blocking_checks(missing_unit_key),
    sort(c(
      "hospitalization_intervals/missing_key_value",
      "hospitalization_intervals/no_usable_interval"
    ))
  ),
  identical(
    blocking_checks(nonexistent_clock),
    sort(c(
      "hospitalization_intervals/timestamp_nonexistent_local_time",
      "hospitalization_intervals/no_usable_interval"
    ))
  ),
  identical(
    blocking_checks(ambiguous_clock),
    sort(c(
      "hospitalization_intervals/timestamp_ambiguous_local_time",
      "hospitalization_intervals/no_usable_interval"
    ))
  ),

  # ORCHIDEE places the sample in the unit hosting the patient at sampling
  # time; the site never names a unit on a microbiology row.
  length(blocking_checks(transfer_attribution)) == 0L,
  identical(
    transfer_attribution$site_inputs$microbiology_observations$SEJUF,
    "UF_B"
  ),

  # A same-day interval counts no night and still hosts its sample.
  length(blocking_checks(same_day)) == 0L,
  identical(nights_by_unit(same_day), c("2024/UF_A" = 10L)),
  identical(
    same_day$site_inputs$microbiology_observations$SEJUF,
    c("UF_A", "UF_B")
  ),
  has_check(same_day, "INFO", "same_day_intervals"),

  # A sample that cannot be placed keeps its row and loses its perimeter.
  length(blocking_checks(unplaceable)) == 0L,
  identical(
    unplaceable$site_inputs$microbiology_observations$SEJUF,
    c("UF_A", NA_character_, NA_character_)
  ),
  has_check(unplaceable, "WARNING", "samples_without_hosting_unit"),

  # Microbiology outside the declared period is excluded, and said to be.
  length(blocking_checks(outside_period)) == 0L,
  identical(nrow(outside_period$site_inputs$microbiology_observations), 1L),
  has_check(outside_period, "INFO", "rows_outside_period"),

  # The render period: the declared default survives an unset environment, an
  # explicit pair overrides it for that process only, and one bound alone is
  # refused rather than completed with a guess.
  identical(report_years_after_override, default_report_years),
  identical(overridden_report_years, 2025:2026),
  !is.na(half_period_error),
  grepl("must be set together", half_period_error, fixed = TRUE),

  # What --diagnose calls blocking, the builder refuses to build.
  !identical(overlap_build_status, 0L),
  any(grepl(
    "two different hosting units at the same time",
    overlap_build,
    fixed = TRUE
  )),
  !dir.exists(file.path(build_root, "bundle_v3"))
)

cat("PASS: site hospitalization intervals, attribution and analysis period\n")
