---
editor_options:
  markdown:
    wrap: 80
---

# Flux opérationnel ORCHIDEE

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
        +--> incidence_exposure_by_year_um_uf_ta_de_profile

Six blocs de handoff complets, non versionnés
        |
        v
Builder partagé ORCHIDEE
        |
        +--> bundle v3 durable et validé
        |       (quatre fichiers canoniques)
        |
        v
Projection fermée spares_current
        |
        +--> bundle v2 opérationnel et validé
        |       (quatre fichiers canoniques dans un répertoire distinct)
        |
        v
Runtime canonique v2
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

Le builder partagé transforme les six blocs lisibles du site en un bundle v3
complet, puis en dérive séparément le bundle v2 accepté par le runtime actuel.
Le runtime partagé applique ensuite le périmètre, le contrôle de plausibilité,
le dédoublonnage et le catalogue d'indicateurs.

`orchideecore` n'est pas une dépendance d'exécution. Il reste un oracle
indépendant et gelé qui a démontré, sur le même bundle v2 et sans complétion,
l'identité des représentants, partitions SPARES, résultats par isolat et panels
annuels.

## Sémantique v2 de l'unité

Dans un bundle v2, `sir_wide$SEJUF` désigne l'UF d'hébergement active au moment
du prélèvement. Cette UF reçoit ensuite ses codes TA et DE via la référence
d'unité. Les unités non attribuées ou ambiguës restent auditables mais sont hors
du périmètre analytique fondé sur l'hébergement.

Cette décision explique les différences ratifiées avec l'ancien chemin
`chu_native`. Elle ne modifie pas le catalogue biologique ni les règles de
dédoublonnage. Le chemin historique reste consultable au tag
`archive/completion-chu-native-2026-07-22`.

## Dénominateur : contrat opérationnel et extension v3

Le bundle v2 opérationnel transporte uniquement :

```text
calendar_year + hospital_nights
```

Ce grain suffit pour publier une densité d'incidence annuelle globale. Il ne
permet pas de calculer correctement une densité par UM, UF, TA ou DE.

Le contrat externe v3 transporte désormais l'exposition profilée calculée par
l'adaptateur Rouen au grain :

```text
calendar_year + SEJUM + SEJUF + CODE_TA + CODE_DE + de_domain_ref +
denominator_profile_id + exposure_value + exposure_unit
```

La table conserve toute contribution d'exposition positive issue d'une
activité valide dont TA/DE sont mappés, même hors du périmètre actuel. Le
runtime applique le contexte fermé `spares_current`
(TA 03/20, domaines DE ratifiés, `midnight_presence`) et en dérive le total
annuel v2. Il vérifie aussi la concordance TA/DE avec la référence de périmètre
des prélèvements.

Cette promotion ne modifie pas v2 et v3 n'est pas encore la valeur
opérationnelle par défaut. Elle prépare le contrat et le runtime ; les panels
stratifiés, leurs numérateurs, leur dédoublonnage contextuel et leurs unités de
publication restent une étape séparée. Les comptages à midi, par durée exacte
ou par dates civiles touchées restent des options conceptuelles sans
identificateur réservé ni implémentation exécutable.

## Chemin analytique brut

La complétion a servi à comparer quatre stratégies exploratoires aux données
brutes, mais elle n'a pas été retenue dans la méthode active. Le runtime exécute
et publie uniquement le chemin brut. Sa dernière implémentation cohérente,
notebook et helpers compris, est conservée au tag
`archive/completion-chu-native-2026-07-22`.

`scripts/render_orchidee.ps1 -Target full` construit le cache brut puis rend le
rapport d'indicateurs.

Le gate Rouen réel du 2026-07-20 a confirmé que le nouveau chemin brut reproduit
exactement les objets ratifiés : `dedup`, `class_map`, `episode_summary` et
`audit`, pour les scopes global et par type. Les 36 classeurs du rapport brut
étaient également identiques cellule par cellule aux lignes `brut` du runtime
précédent.

## Comparaisons à ne pas confondre

1. Un nouveau rendu v2 comparé au gate v2 précédent doit être identique.
2. ORCHIDEE et `orchideecore`, exécutés sur le même bundle v2 brut, doivent être
   identiques à tolérance zéro.

La comparaison historique entre `external_bundle_v2` et `chu_native` n'était
pas attendue identique : v2 applique l'UF d'hébergement sans fallback et
modifie donc intentionnellement une partie du périmètre et des numérateurs. Les
écarts agrégés ayant justifié cette adoption sont consignés dans
`documentation/external_bundle/operational_v2_adoption_2026-07-19.md` ; ce
troisième chemin n'est plus un mode exécutable de `main`.
