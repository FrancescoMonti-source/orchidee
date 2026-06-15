normalise_atb <- function(bact, atb_regex_map) {

  map_u <- atb_regex_map %>%
    distinct(atb_norm, atb_family, atb_subfamily) %>%
    filter(!is.na(atb_norm)) %>%                 # <-- chiave
    distinct(atb_norm, .keep_all = TRUE)         # opzionale ma consigliato

  normalize_atb_label <- function(x) {
    strip_accents <- function(y) {
      y <- as.character(y)
      if (exists("rm_accent", mode = "function")) {
        return(rm_accent(y))
      }
      iconv(y, from = "", to = "ASCII//TRANSLIT")
    }

    x %>%
      as.character() %>%
      strip_accents() %>%
      stringr::str_to_lower() %>%
      stringr::str_replace_all("\\p{Pd}+", "-") %>%
      stringr::str_squish()
  }

  bact %>%
    mutate(
      LBLANA_norm = normalize_atb_label(LBLANA),
      atb_norm = dplyr::if_else(
        LBLRES == "SIR",
        {
          idx <- purrr::map_int(LBLANA_norm, ~{
            w <- stringr::str_which(.x, atb_regex_map$pattern)
            if (length(w) == 0) NA_integer_ else w[1]
          })
          atb_regex_map$atb_norm[idx]
        },
        NA_character_
      ),
      atb_matched = (LBLRES == "SIR") & !is.na(atb_norm),
      atb_match_origin = dplyr::if_else(
        (LBLRES == "SIR") & !is.na(atb_norm),
        "explicit",
        NA_character_
      )
    ) %>%
    select(-LBLANA_norm) %>%
    left_join(map_u, by = "atb_norm", relationship = "many-to-one")
}
