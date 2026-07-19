# Site-owned knobs for the first versioned Rouen raw-data adapter.
#
# Keep raw input paths out of this file. The CLI receives them explicitly so
# this configuration remains public, portable and free of patient data.

rouen_raw_handoff_v1_config <- list(
  adapter_version = "rouen_raw_handoff_v1",
  target_start = as.Date("2022-01-01"),
  target_end_exclusive = as.Date("2025-01-01"),
  screening_typeana_codes = c(
    "BGBLSE_R.BGBLSE_R2",
    "BGCARBA_R.BGCARBA_R2",
    "BGABMR_R.BGABMR_R2",
    "BGSAMR_R.BGSAMR_R2"
  ),
  dictionaries = list(
    species = file.path("dictionaries", "species_regex_map.csv"),
    sample_type_rules = file.path(
      "dictionaries",
      "rouen_naturepvt_regex_v1.csv"
    ),
    sample_type_decisions = file.path(
      "dictionaries",
      "rouen_naturepvt_exact_decisions_v1.csv"
    ),
    antibiotic = file.path("dictionaries", "atb_regex_map.csv"),
    antibiotic_expansion = file.path("dictionaries", "atb_expand_map.csv"),
    supported_species_antibiotics = file.path(
      "dictionaries",
      "couples_species_atb.csv"
    )
  )
)
