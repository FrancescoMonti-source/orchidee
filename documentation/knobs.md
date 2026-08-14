---
editor_options:
  markdown:
    wrap: 80
---

# Réglages

Tout ce qui est modifiable sans écrire de code, classé par conséquence et non
par fichier. Les commentaires de `config/pipeline.R` et
`config/rouen_raw_handoff.R` restent la description détaillée de chaque réglage ;
ce document dit où ils sont, ce qu'ils cassent et ce qu'il faut refaire.

La classe est la règle :

-   **A — affichage.** Aucun chiffre ne change.
-   **B — exécution.** Change ce qui tourne, pas ce que les chiffres signifient.
-   **C — analytique.** Change les chiffres publiés.

Les chemins d'entrée cliniques ne sont pas des réglages : ils sont passés en
paramètres de ligne de commande et ne sont pas versionnés.

## A — affichage

| Réglage | Où | À refaire |
|--------------------|--------------------|-----------------------------|
| `report$datatable_digits`, `datatable_filter_default`, `datatable_initial_zoom`, `datatable_zoom_step` | `config/pipeline.R` | Rendu `indicators` |
| `ratb$indicator_show_full_spec` | `config/pipeline.R` | Rendu `indicators` |

## B — exécution

| Réglage | Où | À refaire |
|--------------------|--------------------|-----------------------------|
| `runtime$external_bundle_v2_dir`, `runtime$external_workspace_dir` | `config/pipeline.R`, ou `ORCHIDEE_EXTERNAL_BUNDLE_V2_DIR` et `ORCHIDEE_EXTERNAL_WORKSPACE_DIR` | Rendu concerné |
| `ORCHIDEE_ROUEN_STRUCTURE_PATH` | environnement ; défaut dans `config/rouen_raw_handoff.R`. `ORCHIDEE_CONSORES_STRUCTURE_PATH` est déprécié et avertit | Build Rouen |
| `cache$recompute_dedup`, `cache$recompute_incidence_pipeline` | `config/pipeline.R` | Rendu `full`, puis remettre à `FALSE` |
| `paths$*` | `config/pipeline.R` | Rendu concerné |

`cache$recompute_*` est un drapeau d'état qu'il faut penser à remettre à `FALSE`
après le rendu. Tant qu'il n'est pas converti en paramètre de
`scripts/render_orchidee.ps1`, c'est le réglage le plus facile à oublier dans
une position qui fait recalculer, ou pire ne pas recalculer, sans le dire.

## C — analytique

Toute modification ici change des chiffres publiés. Elle exige, à chaque fois :
`tests/run_tests.R`, un rendu `full`, la porte
`scripts/compare_operational_v2_gate.R`, et la mise à jour de la ligne
correspondante de [`methods.md`](methods.md).

| Réglage | Où | Ce qu'il déplace |
|--------------------|--------------------|-----------------------------|
| `ratb$report_years` | `config/pipeline.R` | Les années publiées. Une année présente dans les données mais non déclarée arrête le rendu |
| `ratb$indicator_sample_types` | `config/pipeline.R` | Quelles vues par type sont publiées |
| `ratb$indicator_min_n` | `config/pipeline.R` | Le masquage des cellules de carte de chaleur |
| `target_start`, `target_end_exclusive` | `config/rouen_raw_handoff.R` | La fenêtre source Rouen, donc la population |
| `screening_typeana_codes` | `config/rouen_raw_handoff.R` | Ce qui est écarté comme dépistage |
| Catalogue des indicateurs | `documentation/ratb_indicator_spec.csv` | Les indicateurs, leurs périmètres, leurs dénominateurs |
| Correspondances locales | `mappings/*.csv` | La normalisation des bactéries, prélèvements et antibiotiques |
| Couples espèce/antibiotique | `rules/couples_species_atb.csv` | Ce que le contrôle de plausibilité écarte |
| Références TA/DE | `ref/consores/codes_ta.csv`, `ref/consores/codes_de.csv` | Le périmètre hospitalier |
| Références d'unités Rouen | `ref/rouen/` | Le périmètre, pour Rouen uniquement |

## Ce qui n'est pas un réglage

Le contrat de bundle, l'alphabet `S`/`R`/`ZIT`, la logique de déduplication, la
convention des nuits et la mécanique des indicateurs sont du code. Les changer
est une modification méthodologique, pas un réglage : voir
[`methods.md`](methods.md).
