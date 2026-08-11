---
editor_options:
  markdown:
    wrap: 80
---

# Architecture ORCHIDEE

Ce document s'adresse aux mainteneurs et répond à deux questions : **comment
s'enchaîne le chemin de données ?** et **quel fichier possède la logique à
modifier ?** Les commandes, les gates et le dépannage vivent dans le
[`runbook de maintenance`](maintenance_runbook.md) ; les procédures opérateur et
les schémas de bundle restent autoritaires pour leurs périmètres.

Seul le chemin actuellement ratifié est décrit ici.

## Flux canonique

```text
ROUEN                                  RENNES / AUTRE SITE
export BACT + PMSI redsan              six blocs préparés par le site
        |                                       |
        v                                       |
adaptateur Rouen versionné                      |
        |                                       |
        +---------------+-----------------------+
                        |
                        v
             six blocs de handoff complets
                        |
                        v
               builder partagé ORCHIDEE
                        |
                        +--> bundle v3 complet et conservé
                        |           |
                        |     projection fermée
                        |       spares_current
                        |           |
                        |           v
                        +--> bundle v2 opérationnel
                                    |
                                    v
                         runtime RATB partagé
                                    |
                       périmètre et plausibilité
                       dédoublonnage SPARES
                       indicateurs annuels
                       rapport
```

ORCHIDEE commence après l'acquisition EDSaN et la normalisation PMSI/BIOL.
Rouen et un site externe diffèrent seulement avant les six blocs. Ils utilisent
ensuite le même builder, le même runtime et la même méthode.

## Responsabilités

-   **`redsan`** possède l'accès EDSaN, le batching, la normalisation PMSI/BIOL
    et la politique source PMSI `C > DW`.
-   **L'adaptateur local** possède les décisions dépendantes du site :
    extraction depuis l'entrepôt, screening, mappings, attribution de l'UF
    d'hébergement et construction de l'exposition.
-   **Le builder partagé** valide les six blocs, construit le bundle v3 et
    matérialise sa projection v2.
-   **Le runtime RATB** applique le périmètre, la plausibilité biologique, le
    dédoublonnage et le catalogue d'indicateurs.
-   **Le rapport** restitue les résultats ; il ne redéfinit ni la méthode ni le
    périmètre.

Les tables de QA locales et les détails d'extraction ne font pas partie du
handoff portable.

## Frontière v3 vers v2

`v2` et `v3` ne sont pas deux versions successives d'un protocole, et `v2`
n'est pas un état ancien resté en place. Ce sont deux formes du même bundle,
produites ensemble par le même build.

Le bundle v3 est le contrat de construction complet. Il conserve les quatre
fichiers canoniques et l'exposition profilée au grain année + UM + UF + TA + DE.

Le contexte fermé `spares_current` sélectionne le périmètre TA/DE ratifié et le
profil `midnight_presence`, puis produit un bundle v2 distinct. Le v3 n'est ni
écrasé ni utilisé directement par les notebooks.

Le bundle v2 est l'unique entrée opérationnelle. Il transporte le dénominateur
annuel requis par les indicateurs actuels :

```text
calendar_year + hospital_nights
```

Le détail v3 permet de conserver une exposition plus riche, mais ORCHIDEE ne
publie pas encore de densités stratifiées par UM, UF, TA ou DE. Une telle
publication demanderait aussi les numérateurs, le dédoublonnage contextuel et
les unités correspondantes ; elle ne s'active pas par configuration.

Les schémas exacts des quatre fichiers canoniques sont dans
[`external_bundle/bundle_schemas.md`](external_bundle/bundle_schemas.md).

## Sémantique de l'unité

Dans les deux contrats, `sir_wide$SEJUF` désigne l'UF d'hébergement active au
moment du prélèvement. L'adaptateur doit établir cette attribution avant le
handoff. Une attribution absente ou ambiguë reste auditée et ne retombe pas
silencieusement sur l'UF microbiologique.

Le runtime vérifie également que les codes TA, DE et domaine DE de l'exposition
v3 concordent avec la référence de périmètre des prélèvements avant de produire
le total annuel v2.

## Chemin analytique actif

Le runtime calcule uniquement le chemin brut, sans complétion. La complétion
exploratoire et `chu_native` sont retirés de l'arbre actif ; leur dernière
implémentation cohérente reste consultable au tag
`archive/completion-chu-native-2026-07-22`.

Un rendu complet passe par `scripts/render_orchidee.ps1`, qui construit le cache
brut canonique puis rend le rapport. Il affiche les chemins effectivement
consommés et échoue avant le calcul si le bundle ou l'environnement est
invalide.

## Où vit la logique

### Environnement et bootstrap

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
`r_environment_baseline_2026-07-26.md` ; `renv.lock` reste l'autorité
exécutable.

### Configuration

| Fichier | Responsabilité |
|---|---|
| `config/pipeline.R` | Chemins runtime, cache, affichage et paramètres analytiques/de publication. |
| `config/rouen_raw_handoff.R` | Fenêtre source, screening et références de l'adaptateur Rouen. |

Les chemins cliniques BACT et PMSI sont des paramètres CLI, jamais des
réglages versionnés.

### Adaptateur Rouen

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

### Handoff et contrats de bundle

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

Les schémas et la procédure site sont sous `external_bundle/`. Une modification
du validateur impose une revue des documents de contrat correspondants.

### Coeur RATB

| Fichier | Responsabilité |
|---|---|
| `R/ratb_plausibility_qc_helpers.R` | Contrôles de plausibilité biologique. |
| `R/spares_shared_primitives.R` | Conflits et ordre déterministe partagés. |
| `R/spares_dedup.R` | Classes SPARES et sélection des représentants. |
| `R/ratb_raw_runtime_helpers.R` | Construction et cache du runtime brut canonique. |
| `R/ratb_indicator_helpers.R` | Validation du catalogue et calcul des indicateurs. |
| `R/ratb_report_helpers.R` | Tableaux, graphiques et sorties de restitution. |
| `orchidee_ratb_indicators.qmd` | Rapport produit. |

### Méthode et décisions versionnées

| Emplacement | Responsabilité |
|---|---|
| `documentation/ratb_methodology.qmd` | Méthode analytique publiée et sources. |
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
