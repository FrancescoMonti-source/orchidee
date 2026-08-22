---
editor_options:
  markdown:
    wrap: 80
---

# Décisions d'implémentation RATB

Ce document ne réécrit ni la méthode SPARES ni l'expression de besoins : elles
existent hors de ce dépôt et ne sont pas maintenues ici. Il consigne ce que *ce*
code a décidé, et où chaque décision est écrite.

Trois règles le tiennent :

-   une décision, une ligne, un seul renvoi ;
-   aucune valeur n'est recopiée ici si elle vit dans
    [`ratb_indicator_spec.csv`](ratb_indicator_spec.csv), dans un validateur ou
    dans `config/` : ce document pointe, il ne duplique pas ;
-   les renvois nomment un fichier et une fonction, jamais un numéro de ligne.

Une ligne qui aurait besoin de deux renvois signale soit deux décisions à
séparer, soit une duplication dans le code.

## Vocabulaire d'entrée

| Décision | Implémentation | Effet |
|------------------------|------------------------|------------------------|
| `I` et `ZIT` forment une seule classe de valeur | `R/external_handoff_helpers.R` → `orchidee_handoff_normalize_sir()` | Les deux voies d'entrée, Rouen et site |
| `S`, `R`, `ZIT` est le seul alphabet accepté | `R/external_bundle_validation_helpers.R` → `orchidee_external_contract_v2()` | Définition unique ; les autres couches la lisent, la frontière refuse le reste |
| `NC`, `NA`, `N/A` et le vide deviennent absents, et non `ZIT` | `orchidee_handoff_normalize_sir()` | Aucun effet sur les comptes : les deux restent hors dénominateur. La distinction sert l'audit |

## Population analytique

| Décision | Implémentation | Effet |
|------------------------|------------------------|------------------------|
| Le périmètre est défini positivement par les codes TA/DE éligibles | `ref/consores/codes_ta.csv`, `ref/consores/codes_de.csv` ; application `R/ratb_canonical_runtime_helpers.R` | Numérateurs et dénominateurs |
| Pour un site, l'unité d'un prélèvement est le `SEJUF` qu'il fournit sur la ligne de microbiologie | contrat `sample_scope_reference`, `orchidee_external_contract_v2()` | Quels prélèvements entrent au numérateur |
| Pour Rouen, ce `SEJUF` est réécrit : l'unité retenue est l'unité d'hébergement PMSI active à l'heure du prélèvement. Une attribution ambiguë ou absente donne `NA`, donc le prélèvement sort du périmètre au lieu d'être rattaché au hasard | `R/chu_sample_hospitalization_unit_attribution.R` → `build_chu_sample_hospitalization_unit_attribution()`, appliqué par `R/rouen_pmsi_handoff_adapter.R` ; audit `sample_attribution` | Le périmètre Rouen, donc tous les numérateurs |
| Le dépistage est exclu au niveau du document, pas de la ligne de résultat | `config/rouen_raw_handoff.R` → `screening_typeana_codes` ; exclusion dans `R/external_handoff_helpers.R` | Population analytique avant déduplication |
| Une source qui porte `EVTID` doit le porter sur chaque ligne : un trou dans une colonne par ailleurs remplie est une anomalie du système hospitalier et la ligne est écartée. Une colonne absente ou entièrement vide n'est pas une anomalie : la source garde ses lignes sur la clé `PATID` + `ELTID` | `R/external_handoff_helpers.R` → `orchidee_handoff_evtid_anomaly_rows()`, appliqué aux deux frontières d'entrée ; audit Rouen `rows_dropped_without_evtid` | Population analytique. Un marqueur de dépistage porté par une ligne écartée disparaît avec elle, donc le document cesse d'être marqué |
| Une valeur `sir_result` hors vocabulaire arrête le build au lieu d'être lue comme absente ; seul le vide devient absent | `R/external_handoff_helpers.R` → `orchidee_handoff_normalize_sir()` ; refus dans l'adaptateur et à la frontière du bundle | Toutes les voies d'entrée |
| Les couples espèce/antibiotique non plausibles sortent avant la déduplication | `rules/couples_species_atb.csv` ; `R/ratb_plausibility_qc_helpers.R` → `build_ratb_plausibility_qc()`, appelé par `R/ratb_raw_runtime_helpers.R` | Dénominateur des testés ; le résumé et les règles indisponibles restent auditables |

## Déduplication

| Décision | Implémentation | Effet |
|------------------------|------------------------|------------------------|
| Les groupes sont patient × année civile × bactérie normalisée, plus le type de prélèvement pour la vue par type | `R/spares_dedup.R` → `spares_dedup()` | Unité de résultat |
| Deux lignes sont incompatibles s'il existe au moins un conflit `S`↔`R` sur un antibiotique informatif commun | `R/spares_shared_primitives.R` → `.spares_sr_conflict_pair()` | Composition des classes, donc le nombre d'isolats |
| `ZIT` est non informatif : il ne crée jamais de conflit | `R/spares_shared_primitives.R` → `.spares_normalize_noninformative()` | Deux profils divergents uniquement sur `ZIT` fusionnent |
| L'affectation aux classes est gloutonne au premier ajustement ; l'ordre fait donc partie de l'algorithme, pas de l'affichage | `R/spares_dedup.R` → `.spares_class_order_sort()` | Reproductibilité indépendante de l'ordre d'arrivée des lignes |
| Le représentant est choisi par complétude, puis ordre d'événement, date et heure, document, ligne | `R/spares_dedup.R` → `.spares_order_keys()`, `spares_select_representatives()` | Quel antibiogramme représente l'isolat |
| Un signal phénotypique absent est traité comme négatif dans la déduplication | `R/phenotype_flag_helpers.R` → `summarise_class_phenotype_status()` | Regroupement des classes phénotypiques |

## Construction des indicateurs

Le catalogue porte l'organisme, le marqueur, le périmètre et les dénominateurs.
Ce document ne consigne que la mécanique commune.

| Décision | Implémentation | Effet |
|------------------------|------------------------|------------------------|
| Testés = `S` + `R` ; `ZIT` et absent restent hors dénominateur | `R/ratb_indicator_helpers.R` → `compute_ratb_indicator_result()` | Toute proportion publiée |
| Un résultat non testé devient `O`, jamais `R` : rien n'est imputé | `compute_ratb_indicator_result()` | Le numérateur n'est jamais gonflé par l'absence |
| `class_any_r` : un seul `R` suffit ; un molécule directe est une classe à un élément et suit le même code | `compute_ratb_indicator_result()` | Fluoroquinolones, C3G, carbapénèmes, fosfomycine |
| `molecule_priority` : la première molécule *testée* dans l'ordre déclaré au catalogue est retenue, sans comparaison des autres | `compute_ratb_indicator_result()` ; ordre dans `molecule_values` | Méticilline : céfoxitine si testée, sinon oxacilline |
| `phenotype_flag` : chaque isolat éligible compte pour un testé | `compute_ratb_indicator_result()` | Le dénominateur inclut `unknown` et `no_signal`, qui diluent la proportion |
| Les vues publiables sont décidées par `sample_type_mode` | `R/ratb_indicator_helpers.R` → `resolve_ratb_scope_names()` | Vue globale, par type, ou les deux |
| Densité d'incidence = isolats × 1 000 / nuits éligibles de la même année | `R/ratb_indicator_helpers.R` | Incidences publiées |

## Phénotypes

| Décision | Implémentation | Effet |
|------------------------|------------------------|------------------------|
| Quatre états internes : `positive`, `negative`, `unknown`, `no_signal` | `R/phenotype_flag_helpers.R` | Vocabulaire interne |
| Le drapeau public est binaire et vrai seulement pour `positive` | `R/phenotype_flag_helpers.R` | Numérateurs BLSE et carbapénémase |
| Une formulation ambiguë reste `unknown` et n'est pas forcée | `R/phenotype_flag_helpers.R` | `unknown` compte au dénominateur, pas au numérateur |
| Le statut est lu dans les champs structurés puis dans le texte libre | `R/phenotype_flag_helpers.R` | Un changement de vocabulaire local est détectable par les libellés résiduels |

## Dénominateur d'incidence

| Décision | Implémentation | Effet |
|------------------------|------------------------|------------------------|
| Une nuit est une différence de dates : entrée et sortie le même jour valent zéro | `R/ratb_hospital_days_helpers.R` | Séjours courts |
| Un séjour à cheval sur deux années est réparti selon le chevauchement réel | `R/ratb_hospital_days_helpers.R` → `ratb_split_stays_nights_by_year()` | Aucune année ne reçoit un séjour entier qui la dépasse |
| Les nuits sont comptées par unité puis sommées sur les unités éligibles de l'épisode | `R/ratb_hospital_days_helpers.R` | Un transfert entre unités éligibles ne compte pas deux fois |
| Le dénominateur est calculé indépendamment de la microbiologie | `R/ratb_hospital_days_helpers.R` | Un séjour sans prélèvement contribue aux nuits |
| La définition d'exposition est un profil déclaré, pas une convention implicite : `midnight_presence`, en `patient_days`. Le contrat v3 porte l'axe du profil sur chaque ligne, et le registre n'en contient qu'un | `R/external_bundle_validation_helpers.R` → `ratb_denominator_profile_registry()` | Une définition alternative s'ajouterait au registre sans changer le contrat |

## Publication et affichage

| Décision | Implémentation | Effet |
|------------------------|------------------------|------------------------|
| Le rapport publie les années déclarées, et s'arrête si les données en portent une autre. L'incidence n'a pas d'exclusion propre : le dénominateur voit des années de bord parce qu'un séjour à cheval sur la borne de la fenêtre y dépose des nuits, et seules les années déclarées sont publiées | `config/pipeline.R` → `ratb$report_years` ; filtre et contrôle dans `orchidee_ratb_indicators.qmd` | Années publiées, proportions et incidences |
| Les vues par type affichées sont limitées à la liste configurée, intersectée avec les types présents | `config/pipeline.R` → `ratb$indicator_sample_types` | Hémoculture et urines aujourd'hui |
| Le seuil `n` masque des cellules de la carte de chaleur, pas des lignes de tableau | `config/pipeline.R` → `ratb$indicator_min_n` ; `R/ratb_report_helpers.R` → `prepare_ratb_indicator_heatmap()` | À 0, rien n'est masqué |

## Points ouverts

Ces points sont des trous connus, pas des décisions. Les laisser visibles évite
qu'une lecture les prenne pour un choix motivé.

-   **Convention des nuits.** La définition publiée est tranchée et nommée :
    `midnight_presence`, une seule entrée du registre des profils. Ce qui reste
    provisoire est le nom des objets d'audit Rouen, qui portent encore
    `provisional`, et la question ouverte n'est plus « quelle convention »
    mais « faut-il en calculer une seconde en parallèle ». Le contrat v3 le
    permet sans modification : le profil est une dimension de la table
    d'exposition, pas une hypothèse cachée dans le calcul.
-   **Aucun seuil effectif.** `indicator_min_n` vaut 0 : aucune proportion n'est
    masquée, y compris sur très petit dénominateur. Aucun intervalle de
    confiance ni test de tendance n'est publié.
-   **Proportion carbapénémase sur hémoculture.** Le catalogue la marque comme
    indicateur de compatibilité, pour préserver une sortie demandée. La raison
    de fond n'est pas consignée.
-   **Comparabilité.** Rien dans le code ne garantit qu'une année ou un site
    soit comparable à un autre : la normalisation locale, le périmètre et le
    vocabulaire peuvent avoir changé entre deux exécutions.
-   **Vocabulaire source mesuré.** Sur les lignes `LBLRES = SIR` de la fenêtre
    Rouen, `STRRES` ne prend que neuf valeurs : `S`, `R`, `SFP`, vide, `I`,
    `ZIT`, `NC`, `---S`, `---R`. Toute autre valeur arrête le build. Mesurer ce
    vocabulaire demande la source brute : le bloc de handoff ne contient que les
    lignes déjà retenues, et lire celui-ci fait conclure à tort que `NC`
    n'existe pas.
-   **Branches jamais exercées.** Mesuré le 2026-08-13 sur la build
    `outputs/rouen_current`. Deux traitements subsistent sans qu'aucune donnée
    ne les déclenche, et sont conservés pour la même raison : ils rendent une
    dérive visible au lieu de la faire disparaître. Le statut phénotypique
    `unknown` n'est jamais produit aujourd'hui, mais c'est lui qui empêchera
    une formulation locale inconnue d'être comptée `negative` en silence. La
    céfoxitine n'est jamais testée, donc `molecule_priority` retient toujours
    l'oxacilline ; la règle reste écrite parce que la céfoxitine est le
    marqueur correct, et son absence est une lacune des données, pas un choix.
    Le résultat `O`, lui, est massivement présent : ce traitement est justifié.

## Gouvernance

Une modification qui touche une ligne de ce document est une modification
méthodologique : elle exige les tests, un rendu, la porte de comparaison
opérationnelle et la mise à jour de la ligne concernée. Les réglages et ce qu'il
faut refaire après chacun sont dans [`knobs.md`](knobs.md).
