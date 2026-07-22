# Helpers for BLSE / carbapenemase phenotype parsing and propagation.
#
# Public-facing design:
# - internal statuses keep four states: positive / negative / unknown / no_signal
# - public flags are binary and TRUE only for positive
# - dedup treats absent phenotype signal as phenotype-negative

normalize_phenotype_text <- function(x) {
  x_chr <- as.character(x)
  if (exists("rm_accent", mode = "function")) {
    x_chr <- rm_accent(x_chr)
  } else {
    x_chr <- iconv(x_chr, from = "", to = "ASCII//TRANSLIT")
  }
  x_chr <- stringr::str_squish(tolower(x_chr))
  x_chr[x_chr %in% c("", "na", "n/a")] <- NA_character_
  x_chr
}

normalize_phenotype_status <- function(x) {
  x_chr <- normalize_phenotype_text(x)
  dplyr::case_when(
    x_chr %in% c("positive", "negative", "unknown", "no_signal") ~ x_chr,
    TRUE ~ NA_character_
  )
}

classify_blse_row <- function(lblana, lblres, strres) {
  lblana <- normalize_phenotype_text(lblana)
  lblres <- normalize_phenotype_text(lblres)
  strres <- normalize_phenotype_text(strres)

  out <- dplyr::case_when(
    lblana == "recherche blse" &
      lblres == "resultat" &
      strres == "positive" ~ "positive",
    lblana == "recherche blse" &
      lblres == "resultat" &
      strres == "negative" ~ "negative",
    lblana == "recherche blse" &
      lblres == "resultat" &
      strres == "non effectuee" ~ "unknown",

    lblana == "commentaire blse" &
      lblres == "resultat blse" &
      strres == "r" ~ "positive",
    lblana == "commentaire blse" &
      lblres == "resultat blse" &
      strres == "s" ~ "negative",

    lblres == "blse" & strres == "presence de blse" ~ "positive",
    lblres == "blse" &
      strres == "presence de blse+presence de carba" ~ "positive",
    lblres == "blse" & strres == "absence de blse" ~ "negative",

    lblres == "isolat et commentaire germe" &
      strres == "producteur de blse" ~ "positive",
    lblres == "isolat et commentaire germe" &
      strres == "non producteur de blse" ~ "negative",

    TRUE ~ NA_character_
  )

  fallback_pos <- is.na(out) &
    (stringr::str_detect(strres, "^presence de blse") |
      stringr::str_detect(strres, "^presence blse$") |
      (stringr::str_detect(strres, "(^|\\b)producteur de blse\\b") &
        !stringr::str_detect(strres, "\\bnon producteur de blse\\b")) |
      stringr::str_detect(strres, "souche egalement productrice de blse") |
      stringr::str_detect(strres, "egalement producteur de blse") |
      strres %in% c("blse+", "producteur de blse."))

  fallback_neg <- is.na(out) &
    (stringr::str_detect(strres, "^absence de blse") |
      stringr::str_detect(strres, "\\bnon producteur de blse\\b") |
      strres == "blse-")

  fallback_unknown <- is.na(out) &
    (stringr::str_detect(strres, "\\bcote blse\\b") |
      stringr::str_detect(strres, "cote blse et carba|cote carba et blse") |
      stringr::str_detect(strres, "\\bblse uniquement\\b") |
      (stringr::str_detect(strres, "\\bblse\\b") &
        stringr::str_detect(
          strres,
          "e\\.coli|kleb|enterobacter|hormaechei|aerogenes|baumanii|baumannii|pseudomonas|citrobacter|serratia|morganella|proteus"
        )))

  out[fallback_pos] <- "positive"
  out[fallback_neg] <- "negative"
  out[fallback_unknown] <- "unknown"
  out
}

classify_carbapenemase_row <- function(lblana, lblres, strres) {
  lblana <- normalize_phenotype_text(lblana)
  lblres <- normalize_phenotype_text(lblres)
  strres <- normalize_phenotype_text(strres)

  out <- dplyr::case_when(
    lblana == "recherche carba" &
      lblres == "resultat" &
      strres == "positive" ~ "positive",
    lblana == "recherche carba" &
      lblres == "resultat" &
      strres == "negative" ~ "negative",
    lblana == "recherche carba" &
      lblres == "resultat" &
      strres == "non effectuee" ~ "unknown",

    lblana == "commentaire carba" &
      lblres == "resultat carba" &
      strres == "r" ~ "positive",
    lblana == "commentaire carba" &
      lblres == "resultat carba" &
      strres == "s" ~ "negative",

    lblres == "carba" & strres == "presence de carba" ~ "positive",
    lblres == "carba" & strres == "absence de carba" ~ "negative",

    lblres == "isolat et commentaire germe" &
      strres == "producteur de carbapenemase" ~ "positive",

    lblana == "resultat carba par methode enzymatique" &
      lblres == "resultat" &
      strres == "positive" ~ "positive",
    lblana == "resultat carba par methode enzymatique" &
      lblres == "resultat" &
      strres == "negative" ~ "negative",

    lblana == "resultat carba par methode immunologique" &
      lblres %in% c("neg/pos", "resultat") &
      strres == "positive" ~ "positive",
    lblana == "resultat carba par methode immunologique" &
      lblres %in% c("neg/pos", "resultat") &
      strres == "negative" ~ "negative",

    TRUE ~ NA_character_
  )

  fallback_pos <- is.na(out) &
    ((stringr::str_detect(strres, "producteur de carbapen") &
      !stringr::str_detect(strres, "non producteur de carbapen")) |
      stringr::str_detect(strres, "production de carbapen") |
      stringr::str_detect(strres, "^presence de carba") |
      strres %in% c("oxa-48", "vim", "ndm", "oxa-23") |
      stringr::str_detect(strres, "^souche productrice de carbapen"))

  fallback_neg <- is.na(out) &
    (stringr::str_detect(strres, "^absence de carba") |
      stringr::str_detect(strres, "\\bcarba neg\\b") |
      strres == "carba-" |
      stringr::str_detect(strres, "non producteur de carbapen"))

  fallback_unknown <- is.na(out) &
    (stringr::str_detect(strres, "\\bcote carba\\b") |
      stringr::str_detect(strres, "cote blse et carba|cote carba et blse") |
      stringr::str_detect(strres, "sur le cote") |
      (stringr::str_detect(strres, "carba|carbapen") &
        stringr::str_detect(
          strres,
          "e\\.coli|kleb|enterobacter|hormaechei|aerogenes|baumanii|baumannii|pseudomonas"
        )))

  out[fallback_pos] <- "positive"
  out[fallback_neg] <- "negative"
  out[fallback_unknown] <- "unknown"
  out
}

collapse_phenotype_status <- function(x, absence_as_negative = FALSE) {
  x_norm <- normalize_phenotype_status(x)
  x_norm <- x_norm[!is.na(x_norm)]

  if (isTRUE(absence_as_negative)) {
    return(dplyr::case_when(
      any(x_norm == "positive") ~ "positive",
      TRUE ~ "negative"
    ))
  }

  dplyr::case_when(
    any(x_norm == "positive") ~ "positive",
    any(x_norm == "negative") ~ "negative",
    any(x_norm == "unknown") ~ "unknown",
    TRUE ~ "no_signal"
  )
}

phenotype_status_to_flag <- function(x) {
  normalize_phenotype_status(x) == "positive"
}

phenotype_status_to_sr_proxy <- function(x) {
  x_norm <- normalize_phenotype_status(x)
  dplyr::case_when(
    x_norm == "positive" ~ "R",
    TRUE ~ "S"
  )
}

resolve_phenotype_status_sources <- function(df, prefer_final = TRUE) {
  blse_candidates <- if (isTRUE(prefer_final)) {
    c("blse_status_final", "blse_status_row")
  } else {
    c("blse_status_row", "blse_status_final")
  }
  carb_candidates <- if (isTRUE(prefer_final)) {
    c("carbapenemase_status_final", "carbapenemase_status_row")
  } else {
    c("carbapenemase_status_row", "carbapenemase_status_final")
  }

  list(
    blse = blse_candidates[blse_candidates %in% names(df)][1],
    carbapenemase = carb_candidates[carb_candidates %in% names(df)][1]
  )
}

prepare_phenotype_sr_columns <- function(
  df,
  prefer_final = TRUE,
  sr_col_names = c(
    blse = ".pheno_blse_sr",
    carbapenemase = ".pheno_carba_sr"
  )
) {
  stopifnot(is.data.frame(df))

  out <- df
  status_sources <- resolve_phenotype_status_sources(
    out,
    prefer_final = prefer_final
  )
  sr_cols <- character(0)

  if (!is.na(status_sources$blse) && !sr_col_names[["blse"]] %in% names(out)) {
    out[[sr_col_names[["blse"]]]] <- phenotype_status_to_sr_proxy(out[[
      status_sources$blse
    ]])
    sr_cols <- c(sr_cols, sr_col_names[["blse"]])
  } else if (sr_col_names[["blse"]] %in% names(out)) {
    sr_cols <- c(sr_cols, sr_col_names[["blse"]])
  }

  if (
    !is.na(status_sources$carbapenemase) &&
      !sr_col_names[["carbapenemase"]] %in% names(out)
  ) {
    out[[sr_col_names[["carbapenemase"]]]] <- phenotype_status_to_sr_proxy(out[[
      status_sources$carbapenemase
    ]])
    sr_cols <- c(sr_cols, sr_col_names[["carbapenemase"]])
  } else if (sr_col_names[["carbapenemase"]] %in% names(out)) {
    sr_cols <- c(sr_cols, sr_col_names[["carbapenemase"]])
  }

  list(
    data = out,
    sr_cols = unique(sr_cols),
    status_sources = status_sources,
    sr_col_names = sr_col_names
  )
}

build_phenotype_status_lookup <- function(df, key_cols) {
  required_cols <- c(key_cols, "LBLANA", "LBLRES", "STRRES")
  missing_cols <- setdiff(required_cols, names(df))
  if (length(missing_cols) > 0L) {
    stop(
      "Cannot build phenotype status lookup. Missing columns: ",
      paste(missing_cols, collapse = ", "),
      call. = FALSE
    )
  }

  df %>%
    dplyr::mutate(
      blse_status_line = classify_blse_row(LBLANA, LBLRES, STRRES),
      carbapenemase_status_line = classify_carbapenemase_row(
        LBLANA,
        LBLRES,
        STRRES
      )
    ) %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(key_cols))) %>%
    dplyr::summarise(
      blse_status_row = collapse_phenotype_status(blse_status_line),
      carbapenemase_status_row = collapse_phenotype_status(
        carbapenemase_status_line
      ),
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      blse_flag = phenotype_status_to_flag(blse_status_row),
      carbapenemase_flag = phenotype_status_to_flag(carbapenemase_status_row)
    )
}

summarise_class_phenotype_status <- function(
  df,
  class_cols,
  prefer_final = TRUE
) {
  stopifnot(is.data.frame(df))
  status_sources <- resolve_phenotype_status_sources(
    df,
    prefer_final = prefer_final
  )
  if (all(vapply(status_sources, function(x) is.na(x), logical(1)))) {
    return(NULL)
  }

  out <- df %>%
    dplyr::distinct(dplyr::across(dplyr::all_of(class_cols)))

  if (!is.na(status_sources$blse)) {
    blse_summary <- df %>%
      dplyr::group_by(dplyr::across(dplyr::all_of(class_cols))) %>%
      dplyr::summarise(
        blse_status_final = collapse_phenotype_status(.data[[
          status_sources$blse
        ]], absence_as_negative = TRUE),
        .groups = "drop"
      )
    out <- dplyr::left_join(out, blse_summary, by = class_cols)
    out$blse_flag <- phenotype_status_to_flag(out$blse_status_final)
  }

  if (!is.na(status_sources$carbapenemase)) {
    carb_summary <- df %>%
      dplyr::group_by(dplyr::across(dplyr::all_of(class_cols))) %>%
      dplyr::summarise(
        carbapenemase_status_final = collapse_phenotype_status(.data[[
          status_sources$carbapenemase
        ]], absence_as_negative = TRUE),
        .groups = "drop"
      )
    out <- dplyr::left_join(out, carb_summary, by = class_cols)
    out$carbapenemase_flag <- phenotype_status_to_flag(
      out$carbapenemase_status_final
    )
  }

  out
}
