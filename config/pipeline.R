# Runtime, cache, report and publication settings for ORCHIDEE.
#
# Routine Rouen onboarding does not require editing this file: BACT, PMSI and
# output paths are CLI parameters. The `ratb` section is part of the analytical
# and publication contract, not a convenience knob. Keep normalization
# transformations in mappings/, external reference extracts in ref/, and
# implementation logic in R/.

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
  cache = list(
    # Maintainer controls for an intentional cache refresh.
    # Force rebuild of dedup outputs.
    # Turn on after dedup logic/scope changes, render once, then set back to FALSE.
    recompute_dedup = FALSE,
    # Force rebuild of incidence outputs in the product-facing indicator report.
    # Turn on after incidence denominator/numerator changes, then set back to FALSE.
    recompute_incidence_pipeline = FALSE
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
    incidence_excluded_years = c(2021L, 2025L)
    # Downstream incidence publication guard.
    # This is separate from the sir_wide DATEPRELEV window because incidence
    # also depends on hospital-stay/year splitting and may see boundary years.
  )
)
