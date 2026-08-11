---
editor_options:
  markdown:
    wrap: 72
---

# Où vit la logique

Cet index de fichiers répond à une seule question : **quel fichier possède la
logique à modifier ?** Le chemin de données est décrit dans
[`operational_flow.md`](operational_flow.md) et les commandes dans
[`maintenance_runbook.md`](maintenance_runbook.md).

## Environnement et bootstrap

| Fichier | Responsabilité |
|---|---|
| `.Rprofile`, `renv/activate.R` | Activation standard de la bibliothèque du projet. |
| `scripts/setup.ps1` | Résolution de la version R du lockfile et restauration de `renv`. |
| `scripts/run_r.ps1` | Exécution d'un script ou d'une expression dans l'environnement verrouillé. |
| `scripts/orchidee_environment.ps1` | Résolution PowerShell commune utilisée par les wrappers. |
| `R/setup.R` | Bootstrap des notebooks, bibliothèques et configuration. |
| `R/bootstrap.R` | Résolution légère des chemins et sourcing partagé. |
| `R/helpers.R` | Utilitaires R généraux encore partagés. |

La qualification datée du lock courant est conservée dans
`documentation/r_environment_baseline_2026-07-26.md` ; `renv.lock` reste
l'autorité exécutable.

## Configuration

| Fichier | Responsabilité |
|---|---|
| `config/pipeline.R` | Chemins runtime, cache, affichage et paramètres analytiques/de publication. |
| `config/rouen_raw_handoff.R` | Fenêtre source, screening et références de l'adaptateur Rouen. |

Les chemins cliniques BACT et PMSI sont des paramètres CLI, jamais des
réglages versionnés.

## Adaptateur Rouen

| Fichier | Responsabilité |
|---|---|
| `R/normalisation_atb.R` | Normalisation des antibiotiques. |
| `R/normalisation_bact.R` | Normalisation des bactéries. |
| `R/phenotype_flag_helpers.R` | Interprétation et propagation des phénotypes. |
| `R/rouen_microbiology_handoff_adapter.R` | Export BACT vers les quatre blocs microbiologiques. |
| `R/rouen_pmsi_handoff_adapter.R` | PMSI vers attribution d'UF, mapping TA/DE et exposition. |
| `R/chu_sample_hospitalization_unit_attribution.R` | Attribution temporelle de l'UF d'hébergement au prélèvement. |
| `scripts/build_rouen.ps1` | Point d'entrée opérateur à deux chemins. |
| `scripts/build_rouen_external_bundle.R` | CLI R avancée utilisée par le wrapper. |

Les décisions locales consommées par cet adaptateur vivent dans
`mappings/`, `ref/rouen/` et `config/rouen_raw_handoff.R`.

## Handoff et contrats de bundle

| Fichier | Responsabilité |
|---|---|
| `R/external_handoff_helpers.R` | Six blocs vers les quatre artefacts canoniques v3. |
| `R/external_bundle_validation_helpers.R` | Contrats exécutables et validation stricte v2/v3. |
| `R/ratb_canonical_runtime_helpers.R` | Périmètre canonique et projection fermée v3 vers v2. |
| `R/ratb_operational_input_helpers.R` | Chargement strict du bundle v2 opérationnel. |
| `R/ratb_hospital_days_helpers.R` | Primitives temporelles, exposition et dénominateur Rouen. |
| `scripts/build_site.ps1` | Point d'entrée opérateur pour les six blocs. |
| `scripts/build_external_bundle_from_site_inputs.R` | CLI R avancée du builder partagé. |
| `scripts/diagnose_site_inputs.R` | Diagnostic agrégé du contrat des six blocs. |
| `scripts/validate_external_bundle.R` | Validation autonome d'un bundle construit. |
| `scripts/smoke_external_runtime_inputs.R` | Vérification du passage bundle vers runtime. |

Les schémas et la procédure site sont sous
`documentation/external_bundle/`. Une modification du validateur impose une
revue des documents de contrat correspondants.

## Coeur RATB

| Fichier | Responsabilité |
|---|---|
| `R/ratb_plausibility_qc_helpers.R` | Contrôles de plausibilité biologique. |
| `R/spares_shared_primitives.R` | Conflits et ordre déterministe partagés. |
| `R/spares_dedup.R` | Classes SPARES et sélection des représentants. |
| `R/ratb_raw_runtime_helpers.R` | Construction et cache du runtime brut canonique. |
| `R/ratb_indicator_helpers.R` | Validation du catalogue et calcul des indicateurs. |
| `R/ratb_report_helpers.R` | Tableaux, graphiques et sorties de restitution. |
| `orchidee_ratb_indicators.qmd` | Rapport produit. |

## Méthode et décisions versionnées

| Emplacement | Responsabilité |
|---|---|
| `documentation/ratb_methodology.qmd` | Méthode analytique publiée. |
| `documentation/ratb_indicator_spec.csv` | Catalogue et règles de publication. |
| `mappings/` | Transformations source vers valeurs canoniques. |
| `ref/consores/` | Catalogues TA/DE importés. |
| `ref/rouen/` | Références non sensibles propres à Rouen. |
| `rules/` | Décisions analytiques produites par ORCHIDEE. |
| `assets/` | Présentation des rendus Quarto. |

Un mapping, un fait de référence et une règle analytique ne sont pas
interchangeables. Les README de ces répertoires précisent leur frontière.

## Si vous devez changer X

| Changement | Commencer par | Vérification |
|---|---|---|
| Méthode ou indicateur publié | `ratb_methodology.qmd`, `ratb_indicator_spec.csv` | `full` et revue des sorties |
| Normalisation antibiotique/bactérie | `mappings/`, `R/normalisation_*.R` | tests puis `full` |
| Contrat des six blocs ou bundle | `external_handoff_helpers.R`, `external_bundle_validation_helpers.R` | tests onboarding et contrats |
| Adaptateur Rouen | `config/rouen_raw_handoff.R`, adaptateurs Rouen | nouveau build Rouen et gate v2 |
| Dédoublonnage | `spares_shared_primitives.R`, `spares_dedup.R` | `full` et gate v2 |
| Périmètre ou dénominateur | `ratb_canonical_runtime_helpers.R`, `ratb_hospital_days_helpers.R` | `full` et gate v2 |
| Calcul des indicateurs | `ratb_indicator_helpers.R`, catalogue | `full` |
| Affichage seulement | `ratb_report_helpers.R`, rapport QMD | `indicators` |
| Wording méthodologique seulement | `ratb_methodology.qmd` | `memo` |
| Environnement R | `renv.lock`, scripts de setup | restauration propre, tests et gate pertinent |

Les commandes exactes et la matrice de rendu vivent uniquement dans le
[`runbook de maintenance`](maintenance_runbook.md).
