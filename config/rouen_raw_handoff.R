# Versioned settings for the packaged Rouen raw-data adapter.
#
# Keep raw input paths out of this file. The CLI receives them explicitly so
# this configuration remains public, portable and free of patient data.

rouen_structure_path_from_env <- function() {
  current <- Sys.getenv("ORCHIDEE_ROUEN_STRUCTURE_PATH", unset = "")
  legacy <- Sys.getenv("ORCHIDEE_CONSORES_STRUCTURE_PATH", unset = "")

  if (nzchar(current)) {
    return(current)
  }
  if (nzchar(legacy)) {
    warning(
      "ORCHIDEE_CONSORES_STRUCTURE_PATH is deprecated; ",
      "use ORCHIDEE_ROUEN_STRUCTURE_PATH.",
      call. = FALSE
    )
    return(legacy)
  }
  file.path("ref", "rouen", "establishment_structure_2025.xlsx")
}

rouen_raw_handoff_config <- list(
  adapter_id = "rouen_raw_handoff",
  target_start = as.Date("2022-01-01"),
  target_end_exclusive = as.Date("2025-01-01"),
  screening_typeana_codes = c(
    "BGBLSE_R.BGBLSE_R2",
    "BGCARBA_R.BGCARBA_R2",
    "BGABMR_R.BGABMR_R2",
    "BGSAMR_R.BGSAMR_R2"
  ),
  references = list(
    unit_ref_dir = file.path("ref", "rouen"),
    establishment_structure = rouen_structure_path_from_env(),
    codes_ta = file.path("ref", "consores", "codes_ta.csv"),
    codes_de = file.path("ref", "consores", "codes_de.csv")
  ),
  dictionaries = list(
    species = file.path("dictionaries", "species_regex_map.csv"),
    sample_type_rules = file.path(
      "dictionaries",
      "rouen_naturepvt_regex.csv"
    ),
    sample_type_decisions = file.path(
      "dictionaries",
      "rouen_naturepvt_exact_decisions.csv"
    ),
    antibiotic = file.path("dictionaries", "atb_regex_map.csv"),
    antibiotic_expansion = file.path("dictionaries", "atb_expand_map.csv"),
    supported_species_antibiotics = file.path(
      "dictionaries",
      "couples_species_atb.csv"
    )
  )
)
