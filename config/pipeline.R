# Operational knobs for routine Orchidee runs.
#
# Edit this file when changing how the pipeline runs. Keep normalization maps in
# dictionaries/, external reference extracts in ref/, and implementation logic in R/.

orchidee_config <- list(
  paths = list(
    data_dir = "data",
    downloads_dir = "downloads",
    dictionaries_dir = "dictionaries",
    ref_dir = "ref",
    documentation_dir = "documentation",
    consores_structure_path = file.path(
      "ref",
      "consores_structure_intranet_maj_2025.xlsx"
    ),
    consores_codes_ta_path = file.path("ref", "consores_codes_ta.csv"),
    consores_codes_de_path = file.path("ref", "consores_codes_de.csv"),
    ratb_indicator_spec_path = file.path(
      "documentation",
      "ratb_indicator_spec.csv"
    )
  ),
  build = list(
    sir_wide = list(
      # DATEPRELEV window for the canonical microbiology artifact.
      # Rows outside this range are dropped before sir_wide is built.
      expected_bact_date_start = as.Date("2022-01-01"),
      expected_bact_date_end = as.Date("2024-12-31"),
      # If TRUE, any row dropped by the DATEPRELEV guard aborts the build.
      # If FALSE, dropped rows are allowed and counted in sir_wide_meta.
      fail_on_dropped_dateprelev_rows = FALSE
    )
  ),
  cache = list(
    # Force rebuild of RATB hospitalization scope and hospital-night caches.
    # Turn on after perimeter/ref changes, render once, then set back to FALSE.
    recompute_ratb_scope = FALSE,
    # Force rebuild of completion datasets/logs.
    # Turn on after completion logic changes, render once, then set back to FALSE.
    recompute_completion = FALSE,
    # Force rebuild of dedup outputs.
    # Turn on after dedup logic/scope changes, render once, then set back to FALSE.
    recompute_dedup = FALSE,
    # Force rebuild of incidence outputs in the product-facing indicator report.
    # Turn on after incidence denominator/numerator changes, then set back to FALSE.
    recompute_incidence_pipeline = FALSE
  ),
  report = list(
    datatable_digits = 3L,
    datatable_filter_default = "top",
    datatable_initial_zoom = 0.95,
    datatable_zoom_step = 0.05
  ),
  ratb = list(
    microbiology_scope_policy = "sample_uf_ta_de",
    incidence_denominator_policy = "pmsi_source_preferred_unit_stays_ta_de",
    indicator_sample_types = c("hemoculture", "urines"),
    indicator_show_full_spec = FALSE,
    indicator_min_n = 0L,
    incidence_excluded_years = c(2021L, 2025L)
    # Downstream incidence publication guard.
    # This is separate from the sir_wide DATEPRELEV window because incidence
    # also depends on hospital-stay/year splitting and may see boundary years.
  )
)
