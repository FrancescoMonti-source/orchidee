#bact = readRDS("data/bact22_24")

################################################
# Species identification and taxonomy mapping
################################################

# This script standardizes microbiology identification fields
# into structured taxonomic variables using a rule-based approach.

# All microbiological decisions are centralized in a single dictionary file
# (species_regex_map.csv). Each row contains a regular expression and the
# corresponding taxonomic interpretation.

# Rules are evaluated sequentially. The first matching rule is applied and
# no further rules are evaluated. For this reason, rule order is critical.

# The dictionary includes:
# - Explicit species or group definitions (e.g. Escherichia coli,
#   Enterobacter cloacae complex)
# - Higher-level group definitions required for surveillance (e.g.
#   Enterobacterales)
# - Exclusion rules for non-informative laboratory text (e.g. "antibiogramme",
#   "en cours")
# - Ambiguity rules for unresolved identifications (e.g. "X or Y")

# If no rule matches and the identification string follows a clean biological
# pattern (Genus [species]), the genus and species are inferred automatically.
# Status terms, conjunctions, and non-taxonomic words are explicitly excluded
# from species inference.

# Taxonomic ranks (order and family) are only populated when explicitly
# defined in the dictionary. This ensures consistency with SPARES definitions
# and avoids implicit or unstable taxonomic assumptions.

# As a result, the system is:
# - Transparent: all rules are readable in a single file
# - Auditable: changes in classification only occur through dictionary edits
# - Robust to laboratory free-text variability


library(dplyr)
library(stringr)
library(purrr)

apply_species_regex_map <- function(x, rules) {
  if (is.na(x) || is.null(x) || !nzchar(x)) return(NULL)

  # scarta pattern vuoti/NA per evitare warning di stringi su regex vuote
  if ("pattern" %in% names(rules)) {
    rules <- rules %>%
      mutate(pattern = str_squish(as.character(pattern))) %>%
      filter(!is.na(pattern), nzchar(pattern))
  }
  if (nrow(rules) == 0L) return(NULL)

  # usa regex precompilate se presenti; altrimenti le crea al volo
  if (!".re" %in% names(rules)) {
    rules <- rules %>% mutate(.re = regex(pattern, ignore_case = TRUE))
  }

  idx <- which(str_detect(x, rules$.re))[1]
  if (is.na(idx)) return(NULL)

  rules[idx, , drop = FALSE]
}

infer_genus_from_bact_norm <- function(bact_norm) {
  if_else(is.na(bact_norm), NA_character_, str_to_title(word(bact_norm, 1, sep = "_")))
}

extract_genus <- function(x) {
  str_match(str_squish(x), "(?i)^([A-Z][a-z]+)\\b")[, 2]
}

extract_epithet <- function(x) {
  x  <- str_squish(x)
  ep <- str_match(x, "^[A-Z][a-z]+\\s+([A-Za-z][A-Za-z\\-\\.]*)\\b")[, 2]
  ep <- str_replace(ep, "\\.$", "")
  ep <- str_to_lower(ep)

  stop2 <- c("ou","et","en","a","à","de","du","des","d","sur","avec","sans",
             "cours","presence","présence","absence","colonisation","contamination","non")

  ep <- if_else(is.na(ep), NA_character_, ep)
  ep <- if_else(ep %in% stop2, NA_character_, ep)
  ep <- if_else(str_detect(ep, "^(spp?|sp)\\.?$"), NA_character_, ep)
  ep
}

make_bact_norm <- function(genus, epithet) {
  if_else(!is.na(epithet),
          paste0(str_to_lower(genus), "_", str_to_lower(epithet)),
          paste0(str_to_lower(genus), "_spp"))
}

normalize_bact <- function(bact, species_regex_map) {

  # garantisci character + precompila regex (1 volta sola)
  species_regex_map <- species_regex_map %>%
    mutate(across(everything(), ~ if (is.factor(.x)) as.character(.x) else .x)) %>%
    mutate(pattern = str_squish(as.character(pattern))) %>%
    filter(!is.na(pattern), nzchar(pattern)) %>%
    mutate(.re = regex(pattern, ignore_case = TRUE))

  bact %>%
    mutate(
      IDENTIFICATION = str_squish(IDENTIFICATION),

      .rule = map(IDENTIFICATION, ~ apply_species_regex_map(.x, species_regex_map)),

      taxon_type = map_chr(.rule, ~ if (is.null(.x)) NA_character_ else .x$taxon_type),
      bact_norm = map_chr(.rule, ~ if (is.null(.x)) NA_character_ else .x$bact_norm),
      bact_genus      = map_chr(.rule, ~ if (is.null(.x)) NA_character_ else .x$bact_genus),
      bact_family     = map_chr(.rule, ~ if (is.null(.x)) NA_character_ else .x$bact_family),
      bact_order      = map_chr(.rule, ~ if (is.null(.x)) NA_character_ else .x$bact_order),

      taxon_type = if_else(is.na(taxon_type), "bacterium", taxon_type),

     bact_genus = if_else(
        is.na(bact_genus) & !is.na(bact_norm) & taxon_type == "bacterium",
        infer_genus_from_bact_norm(bact_norm),
       bact_genus
      ),

      genus_fallback = if_else(
        taxon_type == "bacterium" & is.na(bact_genus),
        extract_genus(IDENTIFICATION),
        NA_character_
      ),
      epithet_fallback = if_else(
        taxon_type == "bacterium" & is.na(bact_norm),
        extract_epithet(IDENTIFICATION),
        NA_character_
      ),

      bact_genus = if_else(is.na(bact_genus), genus_fallback, bact_genus),

      bact_norm = if_else(
        taxon_type == "bacterium" & is.na(bact_norm) & !is.na(bact_genus),
        make_bact_norm(bact_genus, epithet_fallback),
        bact_norm
      ),

      bact_matched = (taxon_type != "noise") & !is.na(bact_genus)
    ) %>%
    select(-.rule, -genus_fallback, -epithet_fallback)
}
