---
editor_options:
  markdown:
    wrap: 80
---

# Cartographie du projet

Ce document s'adresse aux mainteneurs. Il répond à deux questions :

1.  où se trouve chaque partie du workflow Orchidee ?
2.  où faut-il modifier le code ou la documentation quand on veut changer quelque chose ?

## Chaîne de traitement de haut niveau

1.  Normaliser les champs microbiologiques sources et construire
    l'artefact S/I/R large.
2.  Construire le périmètre analytique d'hospitalisation et les objets
    annuels de dénominateur en nuits d'hospitalisation.
3.  Construire les jeux de données de complétion selon plusieurs
    stratégies.
4.  Exécuter un dédoublonnage de type SPARES sur chaque jeu comparé.
5.  Calculer les panels annuels d'indicateurs RATB.
6.  Rendre le rapport produit et les documents méthodologiques de
    support.

## Frontière opérationnelle vers le coeur ORCHIDEE

Les notebooks sélectionnent explicitement soit le producteur natif CHU, soit
un bundle externe v2 strict. Les deux chemins convergent vers les mêmes trois
objets runtime avant la complétion, le dédoublonnage et les indicateurs. Il n'y
a aucun autodétecteur ni fallback entre les deux sources.

`external_bundle_v2` est le chemin opérationnel canonique et la valeur par
défaut. `chu_native` reste disponible comme mode legacy explicite de comparaison
ou de rollback ; il ne constitue plus la cible des évolutions du workflow.
La décision et ses éléments agrégés sont consignés dans
`documentation/external_bundle/operational_v2_adoption_2026-07-19.md`.

La règle d'architecture est donc : plusieurs entrées locales peuvent exister
(adaptateur natif CHU/Rouen, blocs de handoff pour Rennes ou un autre site),
mais elles doivent converger vers les mêmes objets internes avant le coeur
RATB partagé.

```text
Données CHU / EDSaN / PMSI / référentiels TA-DE
        |
        v
Adaptateur CHU
R/chu_ratb_scope_adapter.R
R/chu_ratb_scope_cache_helpers.R
        |
        | ou, pour le handoff Rouen brut vers le profil v2
        v
R/rouen_microbiology_handoff_adapter.R
R/rouen_pmsi_handoff_adapter.R
        |
        | produit les objets canoniques et le contexte de QA local
        v
Objets canoniques de frontière
- sir_wide (et ses métadonnées sir_wide_meta)
- sample_scope_reference
- denominator_bundle
        |
        v
Sélecteur opérationnel fail-closed
R/ratb_operational_input_helpers.R
        |
        v
Coeur runtime indépendant de l'entrepôt
R/ratb_canonical_runtime_helpers.R
        |
        v
Objets consommés par les notebooks
- sir_wide_ratb_scope
- sir_wide_ratb_analytic_scope
- incidence_denominator_by_year
```

Les tables comme `ratb_scope_join_audit`, `hospital_stays_validated`,
`hospital_days_year_summary` ou `incidence_denominator_pmsi_ta_de_audit`
restent du contexte de QA natif CHU. Elles aident à comprendre le workflow
actuel, mais elles ne font pas partie du contrat portable minimal.

Pour brancher Rennes ou un autre entrepôt, ne pas utiliser cette carte comme
contrat d'onboarding. La source de vérité est
`documentation/external_bundle/site_handoff_inputs_v1.md`.

## Notebooks principaux

### `orchidee_dedup_workflow.qmd`

Rôle :

-   notebook socle du workflow
-   comparaison des stratégies de complétion
-   exécution du dédoublonnage et QA
-   QA du périmètre d'hospitalisation et du dénominateur

À utiliser quand on veut comprendre :

-   comment les jeux de complétion sont produits
-   comment le dédoublonnage est appliqué
-   comment les artefacts de dénominateur sont construits et contrôlés

### `orchidee_ratb_indicators.qmd`

Rôle :

-   rapport RATB orienté produit
-   catalogue des indicateurs
-   restitutions annuelles de proportions et d'incidence
-   section de restitution des phénotypes

À utiliser quand on veut modifier :

-   la structure du rapport
-   l'ordre des sections
-   les réglages d'affichage
-   la présentation des phénotypes

### `documentation/ratb_implementation_decisions.qmd`

Rôle :

-   mémo méthodologique
-   justification des choix d'implémentation

## Fichiers R principaux

Les notebooks chargent ces fichiers en deux temps : `R/setup.R` est sourcé
en tête (librairies, bootstrap portable, lecture de `config/pipeline.R`),
puis chaque notebook source explicitement les scripts de logique dont il a
besoin via `orchidee_source_required_script()`.

Quelques helpers R autonomes sourcent aussi `R/bootstrap.R` directement
pour accéder aux mêmes fonctions de résolution de chemins lorsqu'ils sont
chargés hors notebook.

### Bootstrap

-   `R/setup.R`
    -   bootstrap portable : chargement des librairies, sourcing de
        `R/bootstrap.R`, lecture de la config et helpers communs ; sourcé
        en tête des notebooks
-   `R/bootstrap.R`
    -   helpers légers de résolution de chemins et de sourcing partagés
        entre notebooks, scripts CLI et helpers R
-   `R/helpers.R`
    -   utilitaires généraux partagés
-   `R/zzz.R`
    -   déclarations `globalVariables`
-   `R/setup_chu_adapter.R`
    -   bootstrap de l'adaptateur CHU / EDSaN ; source `R/setup.R` puis
        les helpers d'extraction amont locaux

### Adaptateur CHU / extraction amont

-   `R/get_edsan.R`
    -   récupération des données EDSaN (batch par fenêtre temporelle ou
        par liste d'ID)
-   `R/biol.R`
    -   traitement des examens microbiologiques bruts (BIOL)
-   `R/pmsi.R`
    -   traitement des séjours PMSI (parsing des dates d'entrée/sortie et
        des heures)
-   `R/chu_ratb_scope_adapter.R`
    -   chemin natif actuel de recompute du cache RATB à partir de
        l'artefact local `data/pmsi`
    -   normalise aussi les anciens artefacts locaux avec
        `redsan::prefer_pmsi_src_c_over_dw()`, conformément à la politique PMSI
        par défaut de `redsan` 0.2.0, sans fusionner les intervalles retenus
    -   produit les objets canoniques `sample_scope_reference` et
        `denominator_bundle`, ainsi que le contexte de QA natif CHU
    -   laisse le notebook appliquer ces objets via le helper aval partagé
    -   conserve les tables natives de QA nécessaires au notebook socle
-   `R/chu_ratb_scope_cache_helpers.R`
    -   chargement, fraîcheur, rafraîchissement et recompute du cache de
        périmètre RATB natif CHU
    -   garde la mécanique de cache hors du notebook socle tout en
        séparant cette mécanique du producteur CHU lui-même
    -   reconstruit le payload runtime enrichi du notebook à partir des
        objets canoniques et du contexte de QA natif CHU

### Normalisation et artefact amont

-   `R/normalisation_atb.R`
    -   normalisation des antibiotiques
-   `R/normalisation_bact.R`
    -   normalisation des bactéries
-   `R/build_sir_wide_artifact.R`
    -   artefact microbiologique large (construit un artefact
        microbiologique au format large à partir des données brutes de
        l'entrepôt)
    -   porte les flags phénotypiques en amont
-   `R/phenotype_flag_helpers.R`
    -   parsing et propagation des phénotypes BLSE / carbapénèmase
    -   statuts internes à quatre états, flags publics binaires (positif
        uniquement)
-   `R/rouen_microbiology_handoff_adapter.R`
    -   transforme l'export bactériologique long Rouen en quatre blocs de
        handoff : observations, mappings bactéries, prélèvements et antibiotiques
    -   porte les décisions locales versionnées de screening, mapping unordered,
        expansion des classes ATB et attribution exacte des phénotypes
-   `R/rouen_pmsi_handoff_adapter.R`
    -   applique la politique PMSI `C > DW` via `redsan`, attribue l'UF
        d'hébergement au prélèvement et construit mapping TA/DE et dénominateur
    -   compose les six blocs avec le builder partagé sous contrat v2, sans
        fallback vers l'UF microbiologique

### Complétion et dédoublonnage

-   `R/completion_helpers.R`
    -   logique de complétion et exécution des stratégies
-   `R/completion_workflow_helpers.R`
    -   plumbing d'orchestration, de validation et de journalisation de
        la complétion/dédoublonnage, sorti du notebook socle
-   `R/spares_shared_primitives.R`
    -   primitives de conflit et d'ordonnancement
-   `R/spares_dedup.R`
    -   classes de compatibilité de type SPARES et sélection du
        représentant

### Contrôle qualité

-   `R/ratb_plausibility_qc_helpers.R`
    -   construction des flags de plausibilité (QC) sur l'artefact S/I/R
    -   utilisés dans la QA du notebook socle

### Dénominateur / périmètre

-   `R/ratb_canonical_runtime_helpers.R`
    -   coeur aval indépendant de l'entrepôt : applique
        `sample_scope_reference` à `sir_wide`
    -   construit le périmètre microbiologique analytique et expose la
        table annuelle de dénominateur du `denominator_bundle` au
        workflow RATB
    -   valide les invariants minimaux des entrées runtime canoniques
-   `R/ratb_hospital_days_helpers.R`
    -   helpers natifs PMSI / CHU pour les audits de séjour et le
        dénominateur local
    -   produit les nuits éligibles par année et unité de séjour avant
        leur agrégation annuelle globale
    -   transformation des références CONSORES TA/DE locales vers la
        `sample_scope_reference` canonique
    -   découpage inter-annuel
-   `R/external_handoff_helpers.R`
    -   helpers de handoff pour un site externe : dérive les métadonnées
        de `sir_wide`, construit `sir_wide` depuis des observations
        microbiologiques longues et des dictionnaires locaux, construit la
        `sample_scope_reference` depuis un mapping simple UF/TA-DE et
        enveloppe le dénominateur annuel en `denominator_bundle`
    -   ne constitue pas un connecteur universel d'entrepôt ; il attend
        des blocs locaux déjà compréhensibles et mappés par le site

### Indicateurs et couche rapport

-   `R/ratb_indicator_helpers.R`
    -   parsing et validation de la spec des indicateurs
    -   calcul des panels annuels
    -   exécution des indicateurs phénotypiques
-   `R/ratb_report_helpers.R`
    -   helpers d'affichage partagés par le notebook socle et le rapport
        d'indicateurs
    -   wrappers de tableaux et graphiques
    -   builders de sorties par taxon
    -   builders de la section phénotypes

## Dictionnaires et contrat de publication

-   `assets/`
    -   feuilles de style et fragments HTML utilisés par les rendus
        Quarto
-   `config/pipeline.R`
    -   point d'entrée des réglages opérationnels : chemins, fenêtres de
        dates, flags de recompute et paramètres d'affichage
-   `ref/consores_structure_intranet_maj_2025.xlsx`,
    `ref/consores_codes_ta.csv`, `ref/consores_codes_de.csv`
    -   référentiels CONSORES actifs pour l'éligibilité TA/DE du
        périmètre RATB d'hospitalisation
-   `rules/`
    -   emplacement réservé aux tables de règles analytiques maintenues
        par le projet
    -   ne contient plus de table active pour le périmètre RATB ; ce
        périmètre repose sur les référentiels CONSORES TA/DE dans `ref/`
        et sur `R/ratb_hospital_days_helpers.R`
-   `documentation/ratb_indicator_spec.csv`
    -   contrat de publication des indicateurs
    -   premier endroit à vérifier quand on ajoute ou retire des sorties
-   `dictionaries/couples_species_atb.csv`
    -   univers espèces/antibiotiques supporté
-   `dictionaries/atb_regex_map.csv`
    -   table de normalisation regex des antibiotiques
-   `dictionaries/rouen_naturepvt_regex_v1.csv`
    -   règles Rouen évaluées sans utiliser leur ordre pour départager les cibles
-   `dictionaries/rouen_naturepvt_exact_decisions_v1.csv`
    -   décisions humaines exactes, motivées, pour les conflits ou reports connus
-   `dictionaries/family.csv`
    -   labels de familles et métadonnées de regroupement

### Contrat externe et validation

-   `R/external_bundle_validation_helpers.R`
    -   helpers de validation réutilisables pour le contrat d'entrée
        externe
    -   porte les profils exécutables v1 et v2 via
        `orchidee_external_contract_v1()` et `orchidee_external_contract_v2()`
    -   charge aussi un bundle validé via
        `load_validated_external_input_bundle()`
-   `R/ratb_hospital_days_helpers.R`
    -   contient les helpers natifs PMSI / CHU qui produisent la
        référence de périmètre et les tables de dénominateur locales
-   `R/ratb_canonical_runtime_helpers.R`
    -   contient le helper de frontière
        `build_ratb_downstream_scope_from_canonical_inputs()` qui applique
        une référence de périmètre canonique à `sir_wide`
-   `R/ratb_operational_input_helpers.R`
    -   sélectionne exactement `chu_native` ou `external_bundle_v2`
    -   garde les caches externes séparés et expose seulement les trois
        objets runtime partagés aux notebooks
-   `scripts/validate_external_bundle.R`
    -   validateur CLI autonome pour les bundles externes
-   `scripts/materialize_external_bundle.R`
    -   écrit un bundle externe préféré à partir d'artefacts compatibles
        puis revalide strictement le résultat
-   `scripts/build_external_bundle_from_handoff_inputs.R`
    -   construit un bundle externe préféré depuis les blocs élémentaires
        de handoff d'un site externe qui fournit déjà un `sir_wide.rds`
    -   dérive `sir_wide_meta.rds`, `sample_scope_reference.rds` et
        `denominator_bundle.rds`, puis lance la validation stricte
-   `scripts/build_external_bundle_from_site_inputs.R`
    -   construit un bundle externe préféré depuis les blocs élémentaires
        complets d'un site externe
    -   dérive `sir_wide.rds`, `sir_wide_meta.rds`,
        `sample_scope_reference.rds` et `denominator_bundle.rds`, puis
        lance la validation stricte
-   `scripts/build_rouen_external_bundle_v2.R`
    -   point d'entrée Rouen bactériologie brute + objet PMSI `redsan`
    -   écrit séparément les six blocs, le bundle canonique v2 et l'audit local,
        puis exécute validation stricte et smoke runtime
-   `scripts/audit_chu_site_handoff.R`
    -   diagnostic mainteneur : dérive des blocs élémentaires depuis les
        artefacts CHU courants (observations et mappings depuis
        `sir_wide.rds` ; `unit_mapping` et `denominator_by_year` depuis
        `ratb_scope_cache`), tente de les reconstruire avec la logique de
        handoff site externe et écrit un rapport local sans modifier le
        workflow de production CHU
-   `scripts/smoke_external_runtime_inputs.R`
    -   smoke test CLI vérifiant qu'un bundle validé peut construire les
        entrées aval minimales du coeur RATB
-   `documentation/external_bundle/`
    -   documentation du handoff site externe, du contrat pour les
        entrées canoniques, de `sir_wide`, de la référence de périmètre au
        prélèvement et du bundle de dénominateur
    -   à maintenir en cohérence avec
        `R/external_bundle_validation_helpers.R` quand le schéma v1
        change
    -   `rouen_raw_handoff_v1.md` documente le chemin local A vers B sans en
        faire le contrat d'onboarding d'un autre établissement
-   `R/build_sir_wide_artifact.R`
    -   producteur interne de l'artefact CHU actuel
    -   sert d'exemple de construction de l'artefact canonique, mais ne
        constitue pas le contrat d'adaptation externe pour un autre
        établissement

### Scripts de contrôle local

-   `scripts/characterize_current_outputs.R`
    -   crée ou vérifie un snapshot local de signatures agrégées des
        artefacts et panels courants avant un refactor sans changement
        attendu de résultats

## Artefacts générés

Les artefacts internes de travail vivent dans `data/`. Ils ne jouent pas
tous le même rôle dans la chaîne de traitement ; les principaux sont les
suivants.

-   `sir_wide.rds`, `sir_wide_meta.rds`
    -   artefact microbiologique canonique normalisé, utilisé comme point
        de départ amont du workflow aval
    -   le fichier `meta` porte les métadonnées de validation,
        d'empreinte et de reproductibilité de cet artefact

-   `ratb_scope_cache`, `ratb_scope_cache_meta`
    -   payload du périmètre analytique d'hospitalisation et des objets
        annuels de journées / nuits d'hospitalisation utilisés ensuite
        dans le workflow et le rapport
    -   le fichier `meta` permet de savoir si ce cache peut être rechargé
        tel quel ou doit être recalculé

-   `completion_datasets`, `completion_logs`, `raw_row_log`, `completion_cache_meta`
    -   sortie de la phase de complétion : jeux de données comparés,
        journaux de groupe et de ligne, et trace brute de référence
    -   le fichier `meta` sert à vérifier la fraîcheur du cache de
        complétion avant de le réutiliser

-   `dedup_results`, `dedup_cache_meta`
    -   sortie de la phase de dédoublonnage, structurée par jeu comparé
        puis par scope (`global`, `by_type`)
    -   le fichier `meta` sert à vérifier que ces résultats restent
        cohérents avec les entrées amont et les scripts actifs

-   `ratb_incidence_cache`, `ratb_incidence_cache_meta`
    -   cache auxiliaire encore présent pour certains scripts annexes et
        vérifications manuelles liées à l'incidence
    -   ce n'est plus l'artefact central le mieux documenté dans le
        chemin principal, contrairement à `sir_wide`, au scope, à la
        complétion et au dédoublonnage

Les artefacts d'export destinés au lecteur et générés par le rapport
vivent dans `downloads/`.

Les brouillons, inspections et artefacts temporaires locaux vivent dans
`outputs/`, ignoré par Git. Ne pas l'utiliser comme source canonique.

## Si vous devez changer X, commencez ici

### Changer la définition d'un indicateur publié

Commencer par :

-   `documentation/ratb_indicator_spec.csv`
-   puis vérifier si l'univers de molécules porté doit aussi changer
    dans `dictionaries/couples_species_atb.csv`

### Changer une composition de famille ou une règle de normalisation antibiotique

Commencer par :

-   `dictionaries/atb_regex_map.csv`
-   `dictionaries/family.csv`
-   `dictionaries/couples_species_atb.csv`
-   puis vérifier la spec des indicateurs

### Changer un réglage opérationnel du pipeline

Commencer par :

-   `config/pipeline.R`

Exemples : chemins, fenêtre d'extraction attendue, flags de recompute,
paramètres d'affichage et seuils de publication non biologiques.

### Changer le comportement de dédoublonnage

Commencer par :

-   `R/spares_dedup.R`
-   `R/spares_shared_primitives.R`
-   puis rerendre `full`

### Changer le comportement de complétion

Commencer par :

-   `R/completion_helpers.R`
-   puis rerendre `full`

### Changer la logique de périmètre d'hospitalisation ou de dénominateur d'incidence

Commencer par :

-   `R/ratb_hospital_days_helpers.R`
-   puis rerendre `full`
-   puis vérifier si le wording du mémo d'implémentation doit aussi être
    mis à jour

### Changer uniquement l'affichage du rapport

Commencer par :

-   `R/ratb_report_helpers.R`
-   `orchidee_ratb_indicators.qmd`
-   en général, rerendre `indicators`

### Changer uniquement le wording méthodologique

Commencer par :

-   `documentation/ratb_implementation_decisions.qmd`
-   rerendre `memo`
