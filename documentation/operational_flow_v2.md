---
editor_options:
  markdown:
    wrap: 80
---

# Flux opérationnel ORCHIDEE v2

## Pourquoi cette page existe

Cette page donne une seule vue du chemin actuellement ratifié, depuis les
exports locaux jusqu'aux indicateurs. Elle distingue le flux opérationnel, les
diagnostics et les extensions qui nécessitent encore un nouveau contrat.

Les contrats détaillés restent autoritaires pour leurs schémas respectifs. Cette
page explique comment ils s'enchaînent.

## Flux canonique

```text
Export bactériologique local, format long
        |
        v
Adaptateur microbiologique du site
        |
        +--> microbiology_observations
        +--> bacteria_mapping
        +--> sample_type_mapping
        +--> antibiotic_mapping

Export PMSI normalisé par redsan
        |
        v
Adaptateur PMSI du site
        |
        +--> unit_mapping
        +--> denominator_by_year

Six blocs de handoff
        |
        v
Builder partagé ORCHIDEE
        |
        +--> sir_wide.rds
        +--> sir_wide_meta.rds
        +--> sample_scope_reference.rds
        +--> denominator_bundle.rds
        |
        v
Runtime canonique
        |
        +--> périmètre TA/DE
        +--> plausibilité biologique RATB
        +--> dédoublonnage SPARES brut, global et par type de prélèvement
        +--> catalogue fermé de 140 indicateurs
        +--> proportions et densités d'incidence annuelles
        +--> rapport
```

Le chemin analytique canonique utilise les données brutes, sans complétion. Les
stratégies de complétion ne définissent ni l'entrée du bundle ni la méthode RATB
ratifiée.

## Responsabilités

`redsan` possède l'accès à EDSaN, la normalisation des tables sources et la
politique PMSI `C > DW`. Il conserve les intervalles PMSI retenus ; il ne décide
pas du périmètre scientifique RATB.

L'adaptateur local possède les décisions qui dépendent du site : screening,
mappings microbiologiques, attribution de l'unité d'hébergement et construction
du dénominateur. À Rouen, un prélèvement est attribué à l'intervalle PMSI actif
selon `DATENT <= prélèvement < DATSORT`. Une attribution non résolue ne retombe
pas silencieusement sur l'UF microbiologique.

Le builder partagé transforme les six blocs lisibles du site en quatre fichiers
canoniques. Le runtime partagé applique ensuite le périmètre, le contrôle de
plausibilité, le dédoublonnage et le catalogue d'indicateurs.

`orchideecore` n'est pas une dépendance d'exécution. Il reste un oracle
indépendant et gelé qui a démontré, sur le même bundle v2 et sans complétion,
l'identité des représentants, partitions SPARES, résultats par isolat et panels
annuels.

## Sémantique v2 de l'unité

Dans un bundle v2, `sir_wide$SEJUF` désigne l'UF d'hébergement active au moment
du prélèvement. Cette UF reçoit ensuite ses codes TA et DE via la référence
d'unité. Les unités non attribuées ou ambiguës restent auditables mais sont hors
du périmètre analytique fondé sur l'hébergement.

Cette décision explique les différences ratifiées entre `external_bundle_v2` et
le chemin historique `chu_native`. Elle ne modifie pas le catalogue biologique
ni les règles de dédoublonnage.

## Dénominateur : contrat actuel et extension nécessaire

Le contrat portable actuel transporte uniquement :

```text
calendar_year + hospital_nights
```

Ce grain suffit pour publier une densité d'incidence annuelle globale. Il ne
permet pas de calculer correctement une densité par UM, UF, TA ou DE.

L'adaptateur Rouen calcule déjà, pour son audit, une table plus fine à partir des
séjours PMSI. Le futur contrat devra promouvoir une table au grain :

```text
calendar_year + SEJUM + SEJUF + CODE_TA + CODE_DE + hospital_nights
```

Une seule table à ce grain est préférable à plusieurs dénominateurs calculés
séparément. Elle permet d'agréger ensuite par année, UM, UF, TA, DE ou combinaison
de ces dimensions, tout en vérifiant que la somme des unités reproduit le total
annuel.

Cette promotion n'appartient pas au contrat v2 actuel. Elle devra être introduite
comme une évolution explicite du handoff et du `denominator_bundle`, avec ses
propres validations. Le dénominateur fin ne doit jamais être reconstruit à partir
du total annuel.

## Place de la complétion

La complétion a servi à comparer quatre stratégies exploratoires aux données
brutes. Le notebook historique calcule encore ces stratégies avec leur
dédoublonnage et les affiche dans son propre rapport diagnostique.

La séparation opérationnelle est désormais :

- le rendu opérationnel ordinaire exécute et publie le chemin brut uniquement ;
- la complétion devient un diagnostic opt-in séparé ;
- ce diagnostic compare ses résultats au même baseline brut, sans modifier les
  artefacts canoniques ni les sorties opérationnelles.

`scripts/render_orchidee.ps1 -Target full` construit le cache brut puis rend le
rapport d'indicateurs. `-Target completion` exécute explicitement le notebook
historique dans des sous-dossiers `completion_diagnostic/` isolés. Les caches du
diagnostic ne peuvent donc pas alimenter le rapport opérationnel.

Le gate Rouen réel du 2026-07-20 a confirmé que le nouveau chemin brut reproduit
exactement les objets ratifiés : `dedup`, `class_map`, `episode_summary` et
`audit`, pour les scopes global et par type. Les 36 classeurs du rapport brut
étaient également identiques cellule par cellule aux lignes `brut` du runtime
précédent.

## Trois comparaisons à ne pas confondre

1. Un nouveau rendu v2 comparé au gate v2 précédent doit être identique.
2. ORCHIDEE et `orchideecore`, exécutés sur le même bundle v2 brut, doivent être
   identiques à tolérance zéro.
3. `external_bundle_v2` et `chu_native` ne sont pas attendus identiques : v2
   applique l'UF d'hébergement sans fallback et modifie donc intentionnellement
   une partie du périmètre et des numérateurs.

Les écarts agrégés ayant justifié cette adoption sont consignés dans
`documentation/external_bundle/operational_v2_adoption_2026-07-19.md`.
