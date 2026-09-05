## Preparation of the six site-owned blocks for a site without an ORCHIDEE
## adapter (Rennes and any comparable establishment).
##
## The public handoff asks a site for what it holds: microbiology results, four
## mappings, and its hospitalization intervals. ORCHIDEE owns everything derived
## from them -- which unit a sample belongs to, how many calendar nights a unit
## was occupied, and the analysis period. This file is that derivation, and it
## is the single place where it happens: `scripts/diagnose_site_inputs.R` and
## `scripts/build_external_bundle_from_site_inputs.R` both call
## `orchidee_site_prepare_handoff()`, so the diagnostics describe the build that
## will actually run rather than a parallel reading of the same files.
##
## Nothing below re-implements analytical behavior that already exists. The
## interval union is `ratb_assign_unit_stay_intervals()`, the year split is
## `ratb_split_stays_nights_by_year()`, and the sample-to-unit attribution is
## `build_chu_sample_hospitalization_unit_attribution()`, all shared with the
## Rouen path unchanged.
##
## Source order: R/ratb_hospital_days_helpers.R,
## R/chu_sample_hospitalization_unit_attribution.R and
## R/external_handoff_helpers.R first.

# The instant a local timestamp denotes depends on a zone, and a site handoff
# that leaves it implicit reads differently on a Paris laptop and on a UTC
# server. It is stated, not guessed, and it is not a per-run knob.
orchidee_site_default_timezone <- function() {
  "Europe/Paris"
}

## The public six blocks -------------------------------------------------------
##
## Blocks 1 to 5 are the ones the site already owned. Block 6 is no longer a
## precomputed exposure table: a site is asked for its hospitalization
## intervals, which it holds, rather than for a denominator, which it would have
## to derive by guessing ORCHIDEE's night convention.
##
## This is deliberately *not* `orchidee_handoff_site_input_spec()`. That one is
## the internal construction contract, shared with the Rouen adapter, and it
## keeps the profiled exposure block because that is what the bundle builder
## consumes. The two specs meet in `orchidee_site_prepare_handoff()`.
orchidee_site_public_input_spec <- function() {
  internal <- orchidee_handoff_site_input_spec()

  microbiology <- internal$microbiology_observations
  # SEJUF leaves the public microbiology block: in this path ORCHIDEE decides
  # which unit hosted the patient at sampling time, from block 6. A site that
  # sends the column anyway is told it is ignored rather than having it used.
  #
  # EVTID and HEUREPRELEV become expected columns because attribution needs
  # both. Their *values* may be missing: an absent value costs the sample its
  # unit, which is a diagnostic and an exclusion, not a reason to refuse a
  # transmission that is otherwise usable.
  microbiology$required_columns <- c(
    "PATID",
    "EVTID",
    "ELTID",
    "DATEPRELEV",
    "HEUREPRELEV",
    "bacteria_local",
    "sample_type_local",
    "antibiotic_local",
    "sir_result"
  )
  microbiology$template_columns <- setdiff(
    microbiology$template_columns,
    "SEJUF"
  )

  interval_columns <- c(
    "PATID",
    "EVTID",
    "DATENT",
    "DATSORT",
    "SEJUM",
    "SEJUF"
  )

  list(
    microbiology_observations = microbiology,
    bacteria_mapping = internal$bacteria_mapping,
    sample_type_mapping = internal$sample_type_mapping,
    antibiotic_mapping = internal$antibiotic_mapping,
    unit_mapping = internal$unit_mapping,
    hospitalization_intervals = list(
      required_columns = interval_columns,
      required_one_of = list(),
      template_columns = interval_columns
    )
  )
}

## Analysis period -------------------------------------------------------------

# Two consecutive calendar years, stated by the operator. The period is not a
# filter applied late: it selects the microbiology rows and clips the exposure,
# so a number entered here and a number entered at render time have to be the
# same number. Both come from `orchidee_site_resolve_period()`.
orchidee_site_resolve_period <- function(start_year, end_year) {
  as_year <- function(value, label) {
    if (length(value) != 1L || is.na(value)) {
      stop(label, " must be a single calendar year.", call. = FALSE)
    }
    numeric_value <- suppressWarnings(as.numeric(value))
    if (is.na(numeric_value) ||
        !is.finite(numeric_value) ||
        abs(numeric_value - round(numeric_value)) > 0) {
      stop(label, " must be a whole calendar year: ", value, call. = FALSE)
    }
    year <- as.integer(round(numeric_value))
    if (year < 1900L || year > 2999L) {
      stop(label, " is outside the supported range: ", year, call. = FALSE)
    }
    year
  }

  start <- as_year(start_year, "start_year")
  end <- as_year(end_year, "end_year")
  if (end < start) {
    stop(
      "end_year (", end, ") precedes start_year (", start, ").",
      call. = FALSE
    )
  }

  list(
    start_year = start,
    end_year = end,
    years = seq.int(start, end),
    label = if (start == end) as.character(start) else paste0(start, "-", end)
  )
}

## Findings --------------------------------------------------------------------
##
## The same record shape `scripts/diagnose_site_inputs.R` accumulates, so a
## finding raised here is reported there without translation, and the build can
## refuse on the same records.

orchidee_site_finding <- function(
    severity,
    block,
    check,
    detail,
    n_rows = NA_integer_,
    n_document_occurrences = NA_integer_,
    values = character()
  ) {
  list(
    severity = severity,
    block = block,
    check = check,
    detail = detail,
    n_rows = as.integer(n_rows),
    n_document_occurrences = as.integer(n_document_occurrences),
    values = sort(unique(as.character(values)))
  )
}

orchidee_site_has_blocking <- function(findings) {
  any(vapply(findings, function(f) identical(f$severity, "BLOCKING"), logical(1)))
}

# Same truncation and same trailer as the diagnostics report: a finding raised
# here and one raised there must point a site at the same place for the full
# list, or the correct-and-rerun loop comes back with the same problem.
orchidee_site_format_values <- function(x, limit = 10L) {
  x <- sort(unique(as.character(x)))
  shown <- utils::head(x, limit)
  paste0(
    paste(shown, collapse = ", "),
    if (length(x) > limit) {
      paste0(
        " (+",
        length(x) - limit,
        " more; the complete list is in finding_values.csv)"
      )
    } else {
      ""
    }
  )
}

## Interval timestamps ---------------------------------------------------------

# Hospitalization bounds carry a time of day and decide both a night count and a
# sample's unit, so their representation is strict where `DATEPRELEV` is
# permissive. `12/03/2024` is refused here rather than read as one of the two
# days it could mean; the accepted written forms are ISO, with an optional time.
#
# The two failures a zone creates are refused by name rather than resolved: a
# clock reading that does not exist on the day it claims (spring forward) and
# one that happens twice (autumn back) are ambiguity, and ORCHIDEE does not pick
# one of the two instants on a site's behalf.
orchidee_site_parse_interval_datetimes <- function(
    x,
    timezone = orchidee_site_default_timezone()
  ) {
  n <- length(x)
  status <- rep("ok", n)
  values <- as.POSIXct(rep(NA_real_, n), tz = timezone, origin = "1970-01-01")

  raw_text <- function(v) {
    if (is.factor(v)) v <- as.character(v)
    if (is.character(v)) return(orchidee_handoff_trim_or_na(v))
    if (inherits(v, "POSIXt")) return(format(v, "%Y-%m-%d %H:%M:%S", tz = timezone))
    if (inherits(v, "Date")) return(as.character(v))
    as.character(v)
  }
  raw <- raw_text(x)

  if (inherits(x, "POSIXt")) {
    # An instant needs no interpretation; only its presence and finiteness are
    # in question.
    finite <- is.finite(as.numeric(x))
    values[finite] <- as.POSIXct(
      as.numeric(x)[finite],
      tz = timezone,
      origin = "1970-01-01"
    )
    status[!finite] <- "missing"
    return(list(values = values, status = status, raw = raw))
  }

  if (inherits(x, "Date")) {
    days <- unclass(x)
    usable <- is.finite(days) & !orchidee_handoff_non_whole_days(days)
    values[usable] <- as.POSIXct(
      paste0(as.character(x[usable]), " 00:00:00"),
      format = "%Y-%m-%d %H:%M:%S",
      tz = timezone
    )
    status[!usable] <- ifelse(is.na(days[!usable]), "missing", "malformed")
    return(list(values = values, status = status, raw = raw))
  }

  if (is.factor(x)) x <- as.character(x)
  if (!is.character(x)) {
    # A numeric column is neither a day number nor a second count without a
    # convention this contract never stated. Refusing it is the honest answer.
    status <- ifelse(is.na(x), "missing", "malformed")
    return(list(values = values, status = status, raw = raw))
  }

  text <- orchidee_handoff_trim_or_na(x)
  status[is.na(text)] <- "missing"

  iso <- "^[0-9]{4}-[0-9]{2}-[0-9]{2}([ T][0-9]{2}:[0-9]{2}(:[0-9]{2})?)?$"
  shaped <- !is.na(text) & grepl(iso, text)
  status[!is.na(text) & !shaped] <- "malformed"

  padded <- rep(NA_character_, n)
  date_only <- shaped & nchar(text) == 10L
  padded[date_only] <- paste0(text[date_only], " 00:00:00")
  with_minutes <- shaped & nchar(text) == 16L
  padded[with_minutes] <- paste0(
    sub("T", " ", text[with_minutes], fixed = TRUE),
    ":00"
  )
  with_seconds <- shaped & nchar(text) == 19L
  padded[with_seconds] <- sub("T", " ", text[with_seconds], fixed = TRUE)

  parsed <- suppressWarnings(as.POSIXct(
    padded,
    format = "%Y-%m-%d %H:%M:%S",
    tz = timezone
  ))
  # A shape that parses to nothing is either a calendar or clock that exists
  # nowhere -- 2024-02-30, 25:00 -- or one the declared zone skips at a spring
  # change. Re-reading it in UTC, which has no such gap, separates the two: a
  # value that parses there is well formed and refused for the zone, and telling
  # a site to fix its date format would send it after the wrong correction.
  unreadable <- shaped & is.na(parsed)
  if (any(unreadable)) {
    zoneless <- suppressWarnings(as.POSIXct(
      padded[unreadable],
      format = "%Y-%m-%d %H:%M:%S",
      tz = "UTC"
    ))
    status[unreadable] <- ifelse(
      is.na(zoneless),
      "malformed",
      "nonexistent_local_time"
    )
  }

  readable <- shaped & !is.na(parsed)
  roundtrip <- rep(NA_character_, n)
  roundtrip[readable] <- format(
    parsed[readable],
    format = "%Y-%m-%d %H:%M:%S",
    tz = timezone
  )
  # `as.POSIXct()` silently shifts a nonexistent local clock reading onto the
  # next valid instant. The round trip is what makes that visible.
  status[readable & roundtrip != padded] <- "nonexistent_local_time"

  ambiguous <- rep(FALSE, n)
  check <- readable & status == "ok"
  if (any(check)) {
    before <- format(
      parsed[check] - 3600,
      format = "%Y-%m-%d %H:%M:%S",
      tz = timezone
    )
    after <- format(
      parsed[check] + 3600,
      format = "%Y-%m-%d %H:%M:%S",
      tz = timezone
    )
    ambiguous[check] <- (before == padded[check]) | (after == padded[check])
  }
  status[ambiguous] <- "ambiguous_local_time"

  values[status == "ok"] <- parsed[status == "ok"]
  list(values = values, status = status, raw = raw)
}

## Hospitalization intervals ---------------------------------------------------

# One uninterrupted visit to one hosting unit per row, read as [entry, exit):
# a transfer whose exit instant equals the next entry instant is adjacent, not
# overlapping, and the patient is counted once.
#
# Returns the merged unit stays, the profiled exposure ORCHIDEE builds from
# them, and the findings. `unit_stays` is NULL when a blocking finding makes the
# derivation meaningless.
orchidee_site_prepare_hospitalization_intervals <- function(
    hospitalization_intervals,
    unit_mapping,
    period,
    timezone = orchidee_site_default_timezone()
  ) {
  orchidee_handoff_require_functions(c(
    "ratb_assign_unit_stay_intervals",
    "ratb_split_stays_nights_by_year",
    "ratb_normalize_code_ta",
    "ratb_normalize_code_de"
  ))
  block <- "hospitalization_intervals"
  findings <- list()
  add <- function(...) {
    findings[[length(findings) + 1L]] <<- orchidee_site_finding(...)
    invisible(NULL)
  }

  intervals <- data.frame(
    PATID = orchidee_handoff_trim_or_na(hospitalization_intervals$PATID),
    EVTID = orchidee_handoff_trim_or_na(hospitalization_intervals$EVTID),
    SEJUM = orchidee_handoff_trim_or_na(hospitalization_intervals$SEJUM),
    SEJUF = orchidee_handoff_trim_or_na(hospitalization_intervals$SEJUF),
    stringsAsFactors = FALSE
  )

  # The row and column counts are already reported by the block-reading pass;
  # what this adds is the shape that matters downstream.
  add(
    "INFO",
    block,
    "hosting_units",
    paste0(
      length(unique(intervals$SEJUF[!is.na(intervals$SEJUF)])),
      " distinct hosting units appear across ",
      length(unique(paste(intervals$PATID, intervals$EVTID, sep = "\r"))),
      " hospitalization episodes."
    ),
    n_rows = nrow(intervals)
  )

  if (nrow(intervals) == 0L) {
    add(
      "BLOCKING",
      block,
      "no_rows",
      paste0(
        "The block contains no interval. There is no exposure to compute and ",
        "no sample can be attributed to a unit."
      )
    )
    return(list(unit_stays = NULL, exposure = NULL, findings = findings))
  }

  usable <- rep(TRUE, nrow(intervals))
  for (column in c("PATID", "EVTID", "SEJUM", "SEJUF")) {
    missing_values <- is.na(intervals[[column]])
    if (any(missing_values)) {
      usable <- usable & !missing_values
      add(
        "BLOCKING",
        block,
        "missing_key_value",
        paste0(
          sum(missing_values),
          " rows have no ",
          column,
          ". Every interval needs a patient, an episode and a hosting unit; ",
          "ORCHIDEE does not guess any of the three."
        ),
        n_rows = sum(missing_values)
      )
    }
  }

  parsed_entry <- orchidee_site_parse_interval_datetimes(
    hospitalization_intervals$DATENT,
    timezone = timezone
  )
  parsed_exit <- orchidee_site_parse_interval_datetimes(
    hospitalization_intervals$DATSORT,
    timezone = timezone
  )
  timestamp_details <- c(
    missing = "are empty",
    malformed = paste0(
      "cannot be read. Use YYYY-MM-DD, YYYY-MM-DD HH:MM or ",
      "YYYY-MM-DD HH:MM:SS"
    ),
    nonexistent_local_time = paste0(
      "name a clock reading that does not exist on that day in ",
      timezone,
      " (the hour the spring change skips)"
    ),
    ambiguous_local_time = paste0(
      "name a clock reading that occurs twice on that day in ",
      timezone,
      " (the hour the autumn change repeats); ORCHIDEE does not choose one ",
      "of the two instants"
    )
  )
  for (column in c("DATENT", "DATSORT")) {
    parsed <- if (identical(column, "DATENT")) parsed_entry else parsed_exit
    usable <- usable & parsed$status == "ok"
    for (state in names(timestamp_details)) {
      affected <- parsed$status == state
      if (!any(affected)) {
        next
      }
      add(
        "BLOCKING",
        block,
        paste0("timestamp_", state),
        paste0(
          sum(affected),
          " ",
          column,
          " values ",
          timestamp_details[[state]],
          ": ",
          orchidee_site_format_values(parsed$raw[affected]),
          "."
        ),
        n_rows = sum(affected),
        values = parsed$raw[affected]
      )
    }
  }

  intervals$DATENT <- parsed_entry$values
  intervals$DATSORT <- parsed_exit$values

  reversed <- usable & (intervals$DATSORT < intervals$DATENT)
  if (any(reversed)) {
    usable <- usable & !reversed
    add(
      "BLOCKING",
      block,
      "reversed_interval",
      paste0(
        sum(reversed),
        " rows end before they start. An exit that precedes its entry is a ",
        "source error, not a zero-length stay."
      ),
      n_rows = sum(reversed)
    )
  }

  if (!any(usable)) {
    add(
      "BLOCKING",
      block,
      "no_usable_interval",
      "No interval row survives the checks above; no exposure can be derived."
    )
    return(list(unit_stays = NULL, exposure = NULL, findings = findings))
  }

  same_day <- usable &
    format(intervals$DATENT, "%Y-%m-%d", tz = timezone) ==
      format(intervals$DATSORT, "%Y-%m-%d", tz = timezone)
  if (any(same_day)) {
    add(
      "INFO",
      block,
      "same_day_intervals",
      paste0(
        sum(same_day),
        " intervals start and end on the same calendar day. They are kept: ",
        "they host samples, and they contribute zero nights because a night ",
        "is a change of date."
      ),
      n_rows = sum(same_day)
    )
  }

  # Duplicate and overlapping rows for the same unit are one occupied interval;
  # a gap between two visits to that unit keeps them separate. This is the
  # shared union, not a second implementation of it.
  merged <- ratb_assign_unit_stay_intervals(
    intervals[usable, , drop = FALSE]
  )
  unit_stays <- merged %>%
    group_by(PATID, EVTID, SEJUM, SEJUF, .unit_stay_id) %>%
    summarise(
      n_source_rows = dplyr::n(),
      DATENT = min(DATENT),
      DATSORT = max(DATSORT),
      .groups = "drop"
    ) %>%
    select(-.unit_stay_id)

  collapsed <- sum(unit_stays$n_source_rows) - nrow(unit_stays)
  if (collapsed > 0L) {
    add(
      "INFO",
      block,
      "merged_unit_rows",
      paste0(
        collapsed,
        " rows repeat or overlap another row for the same episode and unit ",
        "and were merged into a single occupied interval. A later return to ",
        "the same unit stays a separate visit."
      ),
      n_rows = collapsed
    )
  }

  # After the merge, two stays of one episode can only overlap if they name
  # different hosting units: merged same-unit stays are disjoint by
  # construction. A patient in two units at once is a contradiction in the
  # source, and ORCHIDEE has no rule for splitting the night between them, so
  # the workflow stops instead of choosing.
  overlap_scan <- unit_stays %>%
    arrange(PATID, EVTID, DATENT, DATSORT) %>%
    group_by(PATID, EVTID) %>%
    mutate(
      .previous_max_exit = lag(cummax(as.numeric(DATSORT)), default = -Inf),
      .overlaps_earlier = as.numeric(DATENT) < .previous_max_exit &
        as.numeric(DATENT) < as.numeric(DATSORT)
    ) %>%
    ungroup()
  # Every read below is from `overlap_scan`, not from `unit_stays`: the scan is
  # sorted by entry instant and the two frames no longer share a row order, so
  # a mask from one applied to the other would name the wrong units.
  overlapping <- overlap_scan$.overlaps_earlier %in% TRUE
  if (any(overlapping)) {
    overlapping_episodes <- unique(paste(
      overlap_scan$PATID[overlapping],
      overlap_scan$EVTID[overlapping]
    ))
    add(
      "BLOCKING",
      block,
      "overlapping_units_in_episode",
      paste0(
        length(overlapping_episodes),
        " episodes place the patient in two different hosting units at the ",
        "same time, for a strictly positive duration. Adjacent transfers are ",
        "valid -- an exit instant equal to the next entry instant does not ",
        "overlap -- but a real double occupancy has no defensible night ",
        "split. Correct the source intervals. Units involved: ",
        orchidee_site_format_values(overlap_scan$SEJUF[overlapping]),
        "."
      ),
      n_rows = sum(overlapping),
      values = overlap_scan$SEJUF[overlapping]
    )
  }

  ## Unit mapping coverage -----------------------------------------------------

  unit_lookup <- data.frame(
    SEJUF = orchidee_handoff_trim_or_na(unit_mapping$SEJUF),
    CODE_TA = ratb_normalize_code_ta(unit_mapping$CODE_TA),
    CODE_DE = ratb_normalize_code_de(unit_mapping$CODE_DE),
    de_domain_ref = orchidee_handoff_normalize_included_de_domain(
      orchidee_handoff_trim_or_na(unit_mapping$de_domain_ref)
    ),
    stringsAsFactors = FALSE
  )
  unit_lookup <- unit_lookup[
    !is.na(unit_lookup$SEJUF) & !duplicated(unit_lookup$SEJUF), ,
    drop = FALSE
  ]

  matched <- match(unit_stays$SEJUF, unit_lookup$SEJUF)
  uncovered <- unique(unit_stays$SEJUF[is.na(matched)])
  if (length(uncovered) > 0L) {
    add(
      "BLOCKING",
      "unit_mapping",
      "interval_uf_not_covered",
      paste0(
        length(uncovered),
        " hosting units used by hospitalization_intervals have no ",
        "unit_mapping row: ",
        orchidee_site_format_values(uncovered),
        ". unit_mapping must cover every unit that hosts a patient."
      ),
      n_rows = sum(is.na(matched)),
      values = uncovered
    )
  }
  incomplete <- !is.na(matched) & (
    is.na(unit_lookup$CODE_TA[matched]) |
      is.na(unit_lookup$CODE_DE[matched]) |
      is.na(unit_lookup$de_domain_ref[matched])
  )
  if (any(incomplete)) {
    add(
      "BLOCKING",
      "unit_mapping",
      "incomplete_ta_de_mapping",
      paste0(
        length(unique(unit_stays$SEJUF[incomplete])),
        " hosting units have an empty CODE_TA, CODE_DE or de_domain_ref: ",
        orchidee_site_format_values(unit_stays$SEJUF[incomplete]),
        ". Strict validation rejects an incomplete perimeter mapping."
      ),
      n_rows = sum(incomplete),
      values = unit_stays$SEJUF[incomplete]
    )
  }

  if (orchidee_site_has_blocking(findings)) {
    return(list(unit_stays = unit_stays, exposure = NULL, findings = findings))
  }

  ## Nights, split by calendar year and clipped to the period -------------------
  ##
  ## The bounds handed to the shared splitter are local calendar dates, computed
  ## in the declared zone. Letting it convert the instants itself would read a
  ## Paris admission at 00:30 on 1 January as the previous year.
  stays_for_split <- unit_stays %>%
    mutate(
      CODE_TA = unit_lookup$CODE_TA[matched],
      CODE_DE = unit_lookup$CODE_DE[matched],
      de_domain_ref = unit_lookup$de_domain_ref[matched],
      datent_min = as.Date(format(DATENT, "%Y-%m-%d", tz = timezone)),
      datsort_max = as.Date(format(DATSORT, "%Y-%m-%d", tz = timezone))
    ) %>%
    mutate(
      cross_year = as.integer(format(datent_min, "%Y")) !=
        as.integer(format(datsort_max, "%Y"))
    ) %>%
    select(
      PATID, EVTID, SEJUM, SEJUF, CODE_TA, CODE_DE, de_domain_ref,
      datent_min, datsort_max, cross_year
    )

  year_split <- ratb_split_stays_nights_by_year(
    stays_for_split,
    id_cols = c(
      "PATID", "EVTID", "SEJUM", "SEJUF", "CODE_TA", "CODE_DE", "de_domain_ref"
    )
  )

  in_period <- year_split$calendar_year %in% period$years
  nights_outside <- sum(year_split$overlap_nights[!in_period])
  if (nights_outside > 0L) {
    add(
      "INFO",
      block,
      "nights_outside_period",
      paste0(
        nights_outside,
        " nights fall in calendar years outside ",
        period$label,
        " (",
        paste(
          sort(unique(year_split$calendar_year[!in_period])),
          collapse = ", "
        ),
        ") and are clipped out of the denominator. A stay crossing a period ",
        "bound keeps only the nights inside it."
      ),
      n_rows = sum(!in_period)
    )
  }
  year_split <- year_split[in_period, , drop = FALSE]

  if (nrow(year_split) == 0L) {
    add(
      "BLOCKING",
      block,
      "no_exposure_in_period",
      paste0(
        "No hospitalization night falls inside ",
        period$label,
        ". Either the period or the intervals are wrong; an empty denominator ",
        "publishes no incidence."
      )
    )
    return(list(unit_stays = unit_stays, exposure = NULL, findings = findings))
  }

  exposure <- year_split %>%
    group_by(
      calendar_year, SEJUM, SEJUF, CODE_TA, CODE_DE, de_domain_ref
    ) %>%
    summarise(
      exposure_value = as.integer(sum(overlap_nights, na.rm = TRUE)),
      .groups = "drop"
    ) %>%
    mutate(
      denominator_profile_id = "midnight_presence",
      exposure_unit = "patient_days"
    ) %>%
    select(
      calendar_year, SEJUM, SEJUF, CODE_TA, CODE_DE, de_domain_ref,
      denominator_profile_id, exposure_value, exposure_unit
    ) %>%
    arrange(calendar_year, SEJUM, SEJUF, CODE_TA, CODE_DE, de_domain_ref) %>%
    as.data.frame()

  add(
    "INFO",
    block,
    "derived_exposure",
    paste0(
      nrow(exposure),
      " exposure rows derived for ",
      period$label,
      ", totalling ",
      format(sum(exposure$exposure_value), scientific = FALSE),
      " patient-days over ",
      nrow(unit_stays),
      " unit stays. ORCHIDEE derives this table; the site does not supply it."
    ),
    n_rows = nrow(exposure)
  )

  list(unit_stays = unit_stays, exposure = exposure, findings = findings)
}

## Whole preparation -----------------------------------------------------------

orchidee_site_prepare_handoff <- function(
    microbiology_observations,
    bacteria_mapping,
    sample_type_mapping,
    antibiotic_mapping,
    unit_mapping,
    hospitalization_intervals,
    period,
    timezone = orchidee_site_default_timezone()
  ) {
  orchidee_handoff_require_functions(
    "build_chu_sample_hospitalization_unit_attribution"
  )
  findings <- list()
  add <- function(...) {
    findings[[length(findings) + 1L]] <<- orchidee_site_finding(...)
    invisible(NULL)
  }
  collect <- function(new_findings) {
    findings <<- c(findings, new_findings)
    invisible(NULL)
  }

  add(
    "INFO",
    "period",
    "analysis_period",
    paste0(
      "Analysis period ",
      period$label,
      ", timestamps read in ",
      timezone,
      ". Microbiology outside this period is excluded and exposure is clipped ",
      "to it."
    )
  )

  intervals_result <- orchidee_site_prepare_hospitalization_intervals(
    hospitalization_intervals = hospitalization_intervals,
    unit_mapping = unit_mapping,
    period = period,
    timezone = timezone
  )
  collect(intervals_result$findings)

  ## Microbiology: period filter ----------------------------------------------

  obs <- microbiology_observations
  if ("SEJUF" %in% names(obs)) {
    add(
      "WARNING",
      "microbiology_observations",
      "sejuf_column_ignored",
      paste0(
        "The block carries a SEJUF column. In this path ORCHIDEE decides the ",
        "unit of each sample from hospitalization_intervals, so the column is ",
        "ignored. Remove it to avoid suggesting it is used."
      ),
      n_rows = nrow(obs)
    )
    obs <- obs[, setdiff(names(obs), "SEJUF"), drop = FALSE]
  }

  parsed_dates <- orchidee_handoff_parse_date_values(obs$DATEPRELEV)
  sample_year <- rep(NA_integer_, nrow(obs))
  readable <- !parsed_dates$bad
  sample_year[readable] <- as.integer(format(
    parsed_dates$values[readable],
    "%Y"
  ))
  # An unreadable date is reported by the microbiology checks that follow, not
  # silently dropped here as "outside the period".
  outside_period <- readable & !(sample_year %in% period$years)
  if (any(outside_period)) {
    add(
      "INFO",
      "microbiology_observations",
      "rows_outside_period",
      paste0(
        sum(outside_period),
        " microbiology rows are dated outside ",
        period$label,
        " (",
        paste(sort(unique(sample_year[outside_period])), collapse = ", "),
        ") and are excluded before any other check."
      ),
      n_rows = sum(outside_period)
    )
    obs <- obs[!outside_period, , drop = FALSE]
    parsed_dates$values <- parsed_dates$values[!outside_period]
    parsed_dates$bad <- parsed_dates$bad[!outside_period]
  }

  if (nrow(obs) == 0L) {
    add(
      "BLOCKING",
      "microbiology_observations",
      "no_rows_in_period",
      paste0(
        "No microbiology row is dated inside ",
        period$label,
        ". Check the period, or the dates the export carries."
      )
    )
  }

  ## Attribution ---------------------------------------------------------------

  attribution <- NULL
  attributed_sejuf <- rep(NA_character_, nrow(obs))
  attributed_sejum <- rep(NA_character_, nrow(obs))

  if (nrow(obs) > 0L && !is.null(intervals_result$unit_stays) &&
      !orchidee_site_has_blocking(findings)) {
    parsed_times <- orchidee_handoff_parse_time_values(obs$HEUREPRELEV)
    samples <- data.frame(
      PATID = orchidee_handoff_trim_or_na(obs$PATID),
      EVTID = orchidee_handoff_trim_or_na(obs$EVTID),
      ELTID = orchidee_handoff_trim_or_na(obs$ELTID),
      stringsAsFactors = FALSE
    )
    samples$DATEPRELEV <- parsed_dates$values
    samples$HEUREPRELEV <- parsed_times$values
    # The shared attribution reads the microbiology unit pair only to break a
    # tie between two units active at once. This path blocks on that situation
    # upstream, so the tie-break is unreachable and the columns are held empty
    # rather than fed a value that could quietly decide anything.
    samples$SEJUM <- NA_character_
    samples$SEJUF <- NA_character_

    occurrence <- paste(samples$PATID, samples$EVTID, samples$ELTID, sep = "\r")
    variants <- !duplicated(data.frame(
      occurrence,
      as.character(samples$DATEPRELEV),
      as.numeric(samples$HEUREPRELEV),
      stringsAsFactors = FALSE
    ))
    conflicting <- unique(occurrence[variants][
      duplicated(occurrence[variants])
    ])
    if (length(conflicting) > 0L) {
      add(
        "BLOCKING",
        "microbiology_observations",
        "conflicting_sample_datetime",
        paste0(
          length(conflicting),
          " sample occurrences carry more than one DATEPRELEV or HEUREPRELEV ",
          "value. One sample is drawn once; ORCHIDEE cannot attribute it to a ",
          "unit from two different instants."
        ),
        n_rows = sum(occurrence %in% conflicting)
      )
    } else if (!any(parsed_dates$bad) && !any(parsed_times$bad)) {
      attribution <- build_chu_sample_hospitalization_unit_attribution(
        sir_wide = samples,
        pmsi_main = intervals_result$unit_stays %>%
          select(PATID, EVTID, DATENT, DATSORT, SEJUM, SEJUF) %>%
          as.data.frame()
      )
      key <- paste(
        attribution$PATID,
        attribution$EVTID,
        attribution$ELTID,
        sep = "\r"
      )
      index <- match(occurrence, key)
      attributed_sejuf <- attribution$hospitalization_SEJUF_at_sampling[index]
      attributed_sejum <- attribution$hospitalization_SEJUM_at_sampling[index]

      unresolved <- attribution$attribution_status != "assigned_hebergement"
      if (any(unresolved)) {
        reasons <- table(attribution$attribution_reason[unresolved])
        add(
          "WARNING",
          "microbiology_observations",
          "samples_without_hosting_unit",
          paste0(
            sum(unresolved),
            " of ",
            nrow(attribution),
            " sample occurrences could not be placed in a hosting unit and ",
            "stay outside the analytic perimeter. Reasons: ",
            paste(
              paste0(names(reasons), " (", as.integer(reasons), ")"),
              collapse = ", "
            ),
            ". A missing EVTID or sampling time is the usual cause, and both ",
            "are recoverable at the source."
          ),
          n_rows = sum(occurrence %in% key[unresolved]),
          n_document_occurrences = sum(unresolved),
          values = names(reasons)
        )
      }
      add(
        "INFO",
        "microbiology_observations",
        "attributed_samples",
        paste0(
          sum(!unresolved),
          " sample occurrences were placed in the hosting unit active at ",
          "sampling time. ORCHIDEE owns this attribution; the site does not ",
          "supply a unit."
        ),
        n_document_occurrences = sum(!unresolved)
      )
    }
  }

  obs$SEJUF <- attributed_sejuf
  obs$SEJUM <- attributed_sejum

  site_inputs <- if (is.null(intervals_result$exposure)) {
    NULL
  } else {
    list(
      microbiology_observations = obs,
      bacteria_mapping = bacteria_mapping,
      sample_type_mapping = sample_type_mapping,
      antibiotic_mapping = antibiotic_mapping,
      unit_mapping = unit_mapping,
      incidence_exposure_by_year_um_uf_ta_de_profile =
        intervals_result$exposure
    )
  }

  list(
    findings = findings,
    site_inputs = site_inputs,
    # Also returned on its own: when the interval block blocks, there is no
    # bundle to build, but the microbiology findings are still worth reporting
    # in the same pass rather than in a second round after the intervals are
    # fixed.
    microbiology_observations = obs,
    unit_stays = intervals_result$unit_stays,
    attribution = attribution,
    period = period,
    timezone = timezone
  )
}
