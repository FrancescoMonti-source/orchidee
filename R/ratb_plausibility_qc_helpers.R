build_ratb_plausibility_qc <- function(sir_df, species_regex_map_path) {
  stopifnot(is.data.frame(sir_df))
  stopifnot(exists("build_species_taxonomy_map", mode = "function"))

  required_key_cols <- c("PATID", "ELTID", "bact_norm")
  missing_key_cols <- setdiff(required_key_cols, names(sir_df))
  if (length(missing_key_cols) > 0L) {
    stop(
      "Missing required columns for RATB plausibility QC: ",
      paste(missing_key_cols, collapse = ", "),
      call. = FALSE
    )
  }

  col_chr <- function(col) {
    if (col %in% names(sir_df)) {
      return(as.character(sir_df[[col]]))
    }
    rep(NA_character_, nrow(sir_df))
  }

  any_r <- function(cols) {
    cols <- intersect(cols, names(sir_df))
    if (length(cols) == 0L) {
      return(rep(FALSE, nrow(sir_df)))
    }
    rowSums(sir_df[cols] == "R", na.rm = TRUE) > 0L
  }

  species_taxonomy <- build_species_taxonomy_map(species_regex_map_path)

  c3g_cols <- c("cefotaxime", "ceftazidime", "ceftriaxone")
  fq_cols <- c("ofloxacine", "levofloxacine", "moxifloxacine", "ciprofloxacine")

  sir_qc <- sir_df %>%
    left_join(species_taxonomy, by = "bact_norm") %>%
    mutate(
      qc_saureus_oxa_cefox_discordance = coalesce(
        bact_norm == "staphylococcus_aureus" &
          !is.na(col_chr("oxacilline")) &
          !is.na(col_chr("cefoxitine")) &
          col_chr("oxacilline") != col_chr("cefoxitine"),
        FALSE
      ),
      qc_enterobacterales_amoxampi_s_c3g_r = coalesce(
        bact_order == "Enterobacterales" &
          col_chr("amoxicilline_ampicilline") == "S" &
          any_r(c3g_cols),
        FALSE
      ),
      qc_enterobacterales_nalidixic_s_fq_r = coalesce(
        bact_order == "Enterobacterales" &
          col_chr("acide_nalidixique") == "S" &
          any_r(fq_cols),
        FALSE
      ),
      qc_klebsiella_enterobacter_amoxampi_s = coalesce(
        bact_norm %in% c("klebsiella_pneumoniae", "enterobacter_cloacae_complex") &
          col_chr("amoxicilline_ampicilline") == "S",
        FALSE
      ),
      qc_any_plausibility_exclusion = if_any(starts_with("qc_"), ~ .x)
    )

  summary <- sir_qc %>%
    summarise(
      n_rows = n(),
      n_excluded = sum(qc_any_plausibility_exclusion, na.rm = TRUE),
      pct_excluded = if_else(n_rows > 0L, 100 * n_excluded / n_rows, NA_real_),
      across(starts_with("qc_"), ~ sum(.x, na.rm = TRUE))
    )

  list(
    data = sir_qc %>%
      filter(!qc_any_plausibility_exclusion) %>%
      select(-bact_order, -starts_with("qc_")),
    excluded = sir_qc %>%
      filter(qc_any_plausibility_exclusion),
    summary = summary,
    unavailable_rules = tibble(
      rule_id = "qc_enterobacterales_nalidixic_s_fq_r",
      reason = if ("acide_nalidixique" %in% names(sir_df)) {
        NA_character_
      } else {
        "acide_nalidixique is not present in the current sir_wide artifact"
      }
    ) %>%
      filter(!is.na(reason))
  )
}
