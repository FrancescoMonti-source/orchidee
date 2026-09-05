# Runtime, cache, report and publication settings for ORCHIDEE.
#
# Routine Rouen onboarding does not require editing this file: BACT, PMSI and
# output paths are CLI parameters. The `ratb` section is part of the analytical
# and publication contract, not a convenience knob. Keep normalization
# transformations in mappings/, external reference extracts in ref/, and
# implementation logic in R/.

# The published period is a declared value, not a per-run convenience. It is
# nevertheless not the same value at every site: Rouen publishes 2022-2024, and
# a site onboarding with its own extract publishes its own consecutive years.
# `python scripts/orchidee.py render --start-year ... --end-year ...` sets these
# two variables for that render process only, so a period travels from the site
# workflow to the report without anyone editing this shared file. Unset -- the
# routine Rouen case -- the declared default below applies unchanged.
orchidee_report_years_from_environment <- function(default_years) {
  start <- Sys.getenv("ORCHIDEE_REPORT_START_YEAR", unset = "")
  end <- Sys.getenv("ORCHIDEE_REPORT_END_YEAR", unset = "")
  if (!nzchar(start) && !nzchar(end)) {
    return(default_years)
  }
  if (!nzchar(start) || !nzchar(end)) {
    stop(
      "ORCHIDEE_REPORT_START_YEAR and ORCHIDEE_REPORT_END_YEAR must be set ",
      "together; a period with one bound is not a period.",
      call. = FALSE
    )
  }
  parse_year <- function(value, name) {
    if (!grepl("^[0-9]{4}$", value)) {
      stop(name, " must be a four-digit calendar year: ", value, call. = FALSE)
    }
    as.integer(value)
  }
  start_year <- parse_year(start, "ORCHIDEE_REPORT_START_YEAR")
  end_year <- parse_year(end, "ORCHIDEE_REPORT_END_YEAR")
  if (end_year < start_year) {
    stop(
      "ORCHIDEE_REPORT_END_YEAR (", end_year, ") precedes ",
      "ORCHIDEE_REPORT_START_YEAR (", start_year, ").",
      call. = FALSE
    )
  }
  seq.int(start_year, end_year)
}

orchidee_config <- list(
  runtime = list(
    # Local/private bundle paths remain outside version control and can be
    # overridden without editing this shared configuration.
    external_bundle_v2_dir = Sys.getenv(
      "ORCHIDEE_EXTERNAL_BUNDLE_V2_DIR",
      unset = file.path("outputs", "rouen_current", "bundle_v2_operational")
    ),
    external_workspace_dir = Sys.getenv(
      "ORCHIDEE_EXTERNAL_WORKSPACE_DIR",
      unset = file.path("outputs", "external_bundle_v2_runtime")
    )
  ),
  paths = list(
    data_dir = "data",
    downloads_dir = "downloads",
    mappings_dir = "mappings",
    ref_dir = "ref",
    documentation_dir = "documentation",
    ratb_indicator_spec_path = file.path(
      "documentation",
      "ratb_indicator_spec.csv"
    )
  ),
  report = list(
    # Display-only settings.
    datatable_digits = 3L,
    datatable_filter_default = "top",
    datatable_initial_zoom = 0.95,
    datatable_zoom_step = 0.05
  ),
  ratb = list(
    # Analytical and publication settings. Changes require the corresponding
    # source tests, full render and operational gate; they are not routine-run
    # overrides.
    indicator_sample_types = c("hemoculture", "urines"),
    indicator_show_full_spec = FALSE,
    indicator_min_n = 0L,
    # The calendar years the report publishes, stated positively.
    # The denominator sees more years than these: a stay crossing the source
    # window boundary contributes nights to the year outside it, so the
    # incidence panel is restricted to the years declared here rather than
    # listing the boundary years to remove. The render stops if the analytical
    # data carries a year that is not declared. A site render overrides the
    # default through the environment; see the function above.
    report_years = orchidee_report_years_from_environment(2022:2024)
  )
)
