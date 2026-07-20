---
editor_options:
  markdown:
    wrap: 80
---

# Orchidee

ORCHIDEE construit les indicateurs RATB/SPARES de l'étape 1 à partir de données
hospitalières.

Ce dépôt a deux publics, dans cet ordre :

1.  Un entrepôt de données hospitalier qui veut brancher ses données sur
    ORCHIDEE.
2.  Les mainteneurs ORCHIDEE qui doivent garder le noyau de l'étape 1 stable.

Le principe pour un site externe est simple : le site ne reproduit pas le chemin
d'extraction CHU. Il fournit des blocs locaux lisibles, puis ORCHIDEE dérive les
fichiers internes utilisés par ORCHIDEE.

Le noyau actuel de l'étape 1 est gelé. Les changements courants doivent donc
préserver les sorties validées, sauf décision explicite de modifier la méthode
ou le périmètre publié.

Les artefacts générés ou locaux (`data/`, `downloads/`, `outputs/`, `archive/`)
ne sont pas versionnés. Un clone frais ne contient donc pas les caches, les
exports ou les rendus locaux.

## Installation R

Les dépendances R sont figées dans `renv.lock`. Après un clone frais, installer
`renv` si nécessaire, puis restaurer l'environnement depuis la racine du dépôt :

```powershell
Rscript -e "if (!requireNamespace('renv', quietly = TRUE)) install.packages('renv'); renv::restore(prompt = FALSE)"
```

Si `Rscript` n'est pas disponible dans le `PATH`, utiliser le chemin complet de
l'installation R locale. La version R attendue est celle indiquée dans
`renv.lock`.

Le recalcul natif CHU du dénominateur PMSI utilise `redsan` 0.2.0 ou plus
récent. Sa politique PMSI par défaut applique explicitement `C > DW` à
l'intérieur d'une même unité sans fusionner les intervalles retenus. Cette
dépendance est enregistrée dans `renv.lock` ; elle ne remplace pas le chemin de
handoff d'un site externe.

## Rennes / autre entrepôt : commencer ici

La page à lire en premier est :

`documentation/external_bundle/site_handoff_inputs_v1.md`

Elle décrit les fichiers élémentaires attendus d'un site externe. C'est la
source de vérité pour l'onboarding Rennes.

En résumé, le site doit préparer :

-   des observations microbiologiques longues ;
-   des dictionnaires de mapping microbiologique ;
-   un mapping unité / structure / TA-DE au niveau `SEJUF` ;
-   un dénominateur annuel d'activité hospitalière, indépendant des lignes
    microbiologiques.

ORCHIDEE dérive ensuite :

-   `sir_wide.rds`
-   `sir_wide_meta.rds`
-   `sample_scope_reference.rds`
-   `denominator_bundle.rds`

Ces quatre fichiers sont construits par ORCHIDEE. Un site externe ne doit pas
les construire à la main.

Le script de construction depuis les blocs site est :

`scripts/build_external_bundle_from_site_inputs.R`

Le détail des colonnes, des valeurs attendues et de la commande complète est
dans `documentation/external_bundle/site_handoff_inputs_v1.md`.

## Rouen : des exports locaux au même handoff

Rouen dispose maintenant d'un adaptateur explicite qui transforme l'export
bactériologique long et l'objet PMSI produit par `redsan` en ces mêmes six
blocs, puis construit le bundle canonique v2. Il applique l'UF d'hébergement
active au prélèvement sans fallback silencieux vers l'UF microbiologique.

Le contrat, les décisions locales et le contenu de l'audit sont décrits dans :

`documentation/external_bundle/rouen_raw_handoff_v1.md`

Le point d'entrée est :

```powershell
Rscript scripts/build_rouen_external_bundle.R `
  <bacteriology_raw.rds> <pmsi.rds> outputs/rouen_bundle_v2 `
  --contract=v2
```

Le profil v1 Rouen couvre par défaut les années 2022 à 2024 ; la même fenêtre
est appliquée à la microbiologie et au dénominateur PMSI.

Les sorties restent locales et ignorées par Git. Le bundle v2 alimente ensuite
le chemin opérationnel par défaut des notebooks sans remplacer ni écraser les
artefacts CHU.

Le contrat v3 est disponible explicitement avec `--contract=v3`. Il conserve
la sémantique d'UF d'hébergement de v2 et remplace le total annuel transporté
par une table d'exposition profilée au grain année + UM + UF + TA + DE. Elle
conserve aussi l'activité mappée hors du périmètre courant. Le runtime applique
le contexte fermé `spares_current_v1` et redérive exactement le total annuel
v2. v3 n'est pas encore la valeur opérationnelle par défaut et n'ajoute pas
encore de panels stratifiés.

## Carte des documents

-   `documentation/operational_flow_v2.md`
    -   vue d'ensemble du chemin Rouen brut vers les indicateurs, responsabilités,
        place de la complétion et évolution attendue du dénominateur ;
-   `documentation/external_bundle/site_handoff_inputs_v1.md`
    -   source de vérité pour ce qu'un site externe doit fournir ;
-   `documentation/external_bundle/canonical_inputs_v1.md`
    -   limite entre adaptation locale et coeur ORCHIDEE ;
-   `documentation/external_bundle/sir_wide_v1.md`
    -   schéma de l'artefact microbiologique canonique ;
-   `documentation/external_bundle/sir_wide_v2.md`
    -   profil successeur où `SEJUF` désigne l'UF d'hébergement au prélèvement ;
-   `documentation/external_bundle/rouen_raw_handoff_v1.md`
    -   chemin Rouen brut bactériologie + PMSI vers les six blocs et le bundle v2 ;
-   `documentation/external_bundle/operational_v2_adoption_2026-07-19.md`
    -   décision et éléments agrégés ayant conduit à adopter v2 par défaut ;
-   `documentation/external_bundle/sample_scope_reference_v1.md`
    -   schéma de la référence de périmètre au niveau prélèvement / `SEJUF` ;
-   `documentation/external_bundle/denominator_bundle_v1.md`
    -   schéma du dénominateur annuel d'incidence ;
-   `documentation/external_bundle/denominator_bundle_v3.md`
    -   exposition profilée, contexte TA/DE courant et évolutions prévues ;
-   `documentation/project_map.md`
    -   carte mainteneur : où se trouve la logique dans le code ;
-   `documentation/maintenance_runbook.md`
    -   commandes de rendu, validation locale et dépannage courant ;
-   `documentation/ratb_implementation_decisions.qmd`
    -   mémo méthodologique du noyau RATB gelé ;
-   `documentation/ratb_indicator_spec.csv`
    -   catalogue des indicateurs publiés.

## Modèle opératoire actuel

Les notebooks ont deux sources d'entrée explicites :

-   `external_bundle_v2`, valeur par défaut, charge strictement les quatre
    fichiers canoniques v2 et constitue le chemin opérationnel canonique ;
-   `chu_native`, mode legacy explicite de comparaison ou de rollback, utilise
    les artefacts internes de `data/` et conserve les audits PMSI/CONSORES
    locaux.

La sélection se fait par `ORCHIDEE_OPERATIONAL_INPUT_SOURCE` et
`ORCHIDEE_EXTERNAL_BUNDLE_V2_DIR`. Les caches et téléchargements externes sont
isolés sous `outputs/external_bundle_v2_runtime/` par défaut. Les tables de QA
propres au producteur CHU ne sont pas simulées dans ce mode ; les QA biologiques,
de dédoublonnage et d'indicateurs restent communes. La complétion est désormais
un diagnostic opt-in séparé ; le chemin canonique reste brut. Il n'existe aucun
autodétecteur ni fallback entre les deux modes : un bundle v2 absent ou invalide
fait échouer explicitement le chemin par défaut.

Le builder générique reste v1 par défaut. Un site ne doit demander
`--contract=v2` qu'après avoir attribué l'UF d'hébergement active au prélèvement
comme décrit dans `documentation/external_bundle/sir_wide_v2.md` ; un bundle v1
reste un artefact de compatibilité et n'est pas accepté par le runtime v2 par
défaut.

Pour comprendre la frontière technique actuelle, lire
`documentation/project_map.md`.
Pour brancher un autre entrepôt, commencer par
`documentation/external_bundle/site_handoff_inputs_v1.md`.

## Répertoires principaux

-   `R/`
    -   helpers R et logique réutilisable ;
-   `scripts/`
    -   points d'entrée CLI : builder externe, validateurs, smoke test et
        wrapper de rendu ;
-   `documentation/external_bundle/`
    -   contrat d'entrée pour Rennes ou un autre entrepôt ;
-   `documentation/`
    -   documentation de maintenance, décisions méthodologiques et specs ;
-   `config/`
    -   chemins, politiques de recompute et paramètres opérationnels ;
-   `dictionaries/`
    -   dictionnaires de normalisation microbiologique ;
-   `ref/`
    -   référentiels institutionnels importés, dont les références TA/DE ;
-   `data/`
    -   artefacts internes générés, ignorés par Git ;
-   `downloads/`
    -   exports de rapport, ignorés par Git ;
-   `outputs/`
    -   brouillons et inspections locales, ignorés par Git.

## Maintenance rapide

-   Ne pas traiter les HTML rendus comme source de vérité.
-   Utiliser `scripts/render_orchidee.ps1` plutôt que lancer `quarto render` à
    la main.
-   Pour un refactor sans changement attendu de résultats, utiliser
    `scripts/characterize_current_outputs.R` avant/après.
-   Pour savoir quel fichier modifier, commencer par
    `documentation/project_map.md`.
-   Pour savoir quoi rerendre, commencer par
    `documentation/maintenance_runbook.md`.
