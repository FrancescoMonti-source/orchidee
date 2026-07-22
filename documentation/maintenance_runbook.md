---
editor_options:
  markdown:
    wrap: 72
---

# Runbook de maintenance

Ce document sert aux opérations de maintenance courante et au rendu.

## Point d'entrée de rendu par défaut

Utiliser le wrapper plutôt que des commandes de rendu ad hoc :

```powershell
& .\scripts\render_orchidee.ps1 -Target <cible>
```

Cibles disponibles :

-   `memo`
-   `docs`
-   `indicators`
-   `full`

## Point d'entrée des réglages

Les réglages opérationnels vivent dans `config/pipeline.R` : chemins,
fenêtre d'extraction attendue, flags de recompute et paramètres
d'affichage.

Les tables de règles analytiques maintenues par le projet doivent rester
dans `rules/` lorsqu'elles existent.
Les dictionnaires biologiques restent dans `dictionaries/`. Les tables de
codes publiables restent dans `ref/`. Les inputs institutionnels privés ne
doivent pas y être ajoutés : le classeur de structure CONSORES reste sous
`data/` ou dans un emplacement protégé désigné par
`ORCHIDEE_CONSORES_STRUCTURE_PATH`.
Un référentiel ou snapshot sans consumer actif doit être archivé hors du dépôt,
pas conservé dans `ref/` par précaution.
Les fichiers de présentation Quarto restent dans `assets/`.

```powershell
$env:ORCHIDEE_CONSORES_STRUCTURE_PATH = "C:\chemin\protege\structure.xlsx"
```

## Dépendances R

Les dépendances sont enregistrées dans `renv.lock`.

Pour restaurer l'environnement d'un clone frais :

```powershell
Rscript -e "if (!requireNamespace('renv', quietly = TRUE)) install.packages('renv'); renv::restore(prompt = FALSE)"
```

Après ajout, suppression ou mise à jour volontaire d'une dépendance, vérifier
l'état puis mettre à jour le lockfile :

```powershell
Rscript -e "renv::status(); renv::snapshot(prompt = FALSE)"
```

Ne pas snapshotter après avoir seulement chargé des artefacts locaux ou rendu un
rapport : `renv.lock` doit représenter les dépendances du code, pas l'état d'une
session de travail.

## Frontière EDSaN / redsan

`redsan` possède l'interrogation EDSaN, le batching et la normalisation des
modules PMSI/BIOL. ORCHIDEE ne duplique plus ces fonctions. Pour le chemin
Rouen, partir de l'export bactériologique long et de l'objet PMSI produit par
`redsan`, puis utiliser `scripts/build_rouen_external_bundle.R`. Toute évolution
du contrat source EDSaN doit donc être réalisée et testée dans `redsan` avant
son adoption par ORCHIDEE.

## Tests R autonomes

Exécuter les tests source depuis la racine du dépôt :

```powershell
Rscript tests/run_tests.R
```

Chaque fichier `tests/test_*.R` est exécuté dans un processus R distinct.

## Construction locale Rouen de bout en bout

Le parcours normal transforme les exports Rouen en six blocs complets, conserve
le bundle v3 durable puis matérialise sa projection v2 opérationnelle :

```powershell
$output = "outputs/rouen_current"
Rscript scripts/build_rouen_external_bundle.R `
  <bacteriology_raw.rds> `
  <pmsi.rds> `
  $output `
  --contract=v3 `
  --operational-v2-output="$output/bundle_v2_operational"
```

La commande écrit les six blocs sous `site_inputs/`, les quatre fichiers v3 sous
`bundle_v3/`, la projection courante sous `bundle_v2_operational/` et l'audit
local dans `adapter_audit.rds`. `build_manifest.txt` donne les chemins, les hash,
le HEAD, le profil de projection et les résultats de validation. L'audit peut
contenir des identifiants patients. Le manifest est le marqueur de fin : son
absence signifie que la construction est incomplète et ne doit pas être
consommée. Conserver tout le répertoire sous
`outputs/` ou dans un autre emplacement protégé et non versionné.

La fenêtre versionnée par défaut est `[2022-01-01, 2025-01-01)` pour les deux
sources. Toute modification se fait dans `config/rouen_raw_handoff.R` et
doit rester visible dans les métadonnées d'audit.

Le script valide strictement v3 et v2 puis exécute le smoke du runtime sur les
deux. La projection applique `spares_current` et doit redériver exactement le
total annuel v2. Le sélecteur opérationnel reste explicitement sur v2 : cette
commande conserve v3 sans l'adopter comme entrée des notebooks. Le build direct
`--contract=v2` reste disponible comme chemin direct explicite.

## Exécution opérationnelle sur un bundle v2

Le bundle v2 strict est le chemin opérationnel par défaut. Sans surcharge,
`config/pipeline.R` cherche le bundle sous
`outputs/rouen_current/bundle_v2_operational`. Après sa construction, lancer un
rendu complet :

```powershell
& .\scripts\render_orchidee.ps1 -Target full
```

`full` construit le cache RATB brut canonique puis rend le rapport
d'indicateurs. La complétion ne fait pas partie de ce chemin.

La complétion exploratoire n'est plus un target de rendu actif. Sa dernière
implémentation cohérente est conservée au tag
`archive/completion-chu-native-2026-07-22`.

Pour utiliser un bundle ou un workspace protégé situé ailleurs :

```powershell
$env:ORCHIDEE_EXTERNAL_BUNDLE_V2_DIR = "C:\chemin\protege\bundle"
$env:ORCHIDEE_EXTERNAL_WORKSPACE_DIR = "C:\chemin\protege\runtime"
& .\scripts\render_orchidee.ps1 -Target full
```

Le loader exige les quatre fichiers préférés du contrat v2 et échoue sans
fallback vers CHU. Cache brut, dédoublonnage et téléchargements sont
écrits sous le workspace externe, pas dans `data/` ni `downloads/`.

Le mode `chu_native` est conservé uniquement comme chemin legacy explicite de
comparaison ou de rollback :

```powershell
$env:ORCHIDEE_OPERATIONAL_INPUT_SOURCE = "chu_native"
& .\scripts\render_orchidee.ps1 -Target full
```

Pour revenir au bundle v2 par défaut dans la même session PowerShell :

```powershell
Remove-Item Env:ORCHIDEE_OPERATIONAL_INPUT_SOURCE
Remove-Item Env:ORCHIDEE_EXTERNAL_BUNDLE_V2_DIR -ErrorAction SilentlyContinue
Remove-Item Env:ORCHIDEE_EXTERNAL_WORKSPACE_DIR -ErrorAction SilentlyContinue
```

## Gate de non-régression du runtime v2

Après un changement qui ne doit pas modifier les résultats opérationnels,
exécuter d'abord un rendu `full`, puis comparer un rendu v2 accepté au rendu
candidat avec le gate read-only :

```powershell
$baseline = "C:\chemin\protege\validation-v2"
$candidate = "C:\chemin\protege\rouen-current"
Rscript scripts/compare_operational_v2_gate.R `
  "$baseline\bundle-v2-projected" `
  "$baseline\runtime" `
  "$candidate\bundle_v2_operational" `
  "$candidate\runtime"
```

Le gate exige l'identité des trois objets canoniques, de `sir_wide_meta` en
ignorant uniquement la valeur de `created_at`, du dédoublonnage brut, de son
audit et des valeurs de toutes les feuilles XLSX publiées. Il ne compare pas
`dedup_cache_meta`, qui
porte des chemins et timestamps de run, ni les PDF/PNG, qui ne constituent pas
le gate numérique. Baseline et candidat restent dans un emplacement privé hors
Git ; le script ne les modifie pas et ne publie aucune valeur clinique.
Une baseline acceptée doit être conservée comme un oracle immuable.

## Matrice de rendu

### Si seul le mémo a changé

Commande :

```powershell
& .\scripts\render_orchidee.ps1 -Target memo
```

### Si les deux documents méthodologiques ont changé

Commande :

```powershell
& .\scripts\render_orchidee.ps1 -Target docs
```

### Si seule la couche d'affichage du rapport d'indicateurs a changé

Exemples :

-   ordre des sections
-   titres
-   notes
-   mise en page des tableaux
-   dimensions des graphiques
-   présentation des phénotypes

Commande :

```powershell
& .\scripts\render_orchidee.ps1 -Target indicators
```

### Si la logique amont a changé

Exemples :

-   dédoublonnage
-   dénominateur / périmètre
-   calcul des indicateurs
-   construction de l'artefact large
-   modification de la spec des indicateurs qui affecte la QA du workflow

Commande :

```powershell
& .\scripts\render_orchidee.ps1 -Target full
```

`full` exécute dans cet ordre :

1.  `scripts/build_ratb_raw_runtime.R`
2.  `orchidee_ratb_indicators.qmd`

## Règles courantes de maintenance

-   Traiter le checkout Git sous `~/Documents/Git/orchidee` comme la
    source de vérité locale de travail ; `main` reflète le travail accepté
    sur GitHub.
-   Créer une branche `task/<slug>` pour les changements significatifs et
    garder `main` propre.
-   Traiter les sorties HTML comme des artefacts dérivés, pas comme la
    source.
-   Garder `data/` pour les artefacts internes générés et les inputs privés
    nécessaires au runtime local.
-   Garder `downloads/` pour les artefacts d'export produits par les
    rapports.
-   Garder `outputs/` comme espace local ignoré par Git pour brouillons,
    inspections et artefacts temporaires.
-   Modifier `config/pipeline.R` pour les réglages de run avant de
    modifier un notebook.
-   Préférer de petits diffs.
-   Éviter de mélanger nettoyage structurel et changements de logique
    scientifique.

## Pièges fréquents

### Le rapport semble faux, mais le pipeline peut être correct

Vérifier si le problème se situe dans :

-   la logique amont ou les données
-   la spec des indicateurs
-   ou seulement la couche de restitution

Une valeur absente du HTML n'implique pas automatiquement qu'elle est
absente du pipeline.

### Les dénominateurs de résistance et d'incidence sont des objets différents

Ne pas supposer qu'un changement de l'un explique automatiquement
l'autre.

### Les sorties phénotypiques sont particulières

Les indicateurs phénotypiques sont des sorties dérivées, pas de simples
lignes molécule. Le rapport d'indicateurs comporte désormais une section
dédiée aux phénotypes en plus du catalogue.

### Les comparaisons CONSORES ne sont pas automatiquement comparables

Des pourcentages qui se ressemblent peuvent malgré tout reposer sur des
dénominateurs, des filtres ou des prétraitements différents.

## Premières étapes de dépannage

1.  Vérifier le répertoire de travail.
2.  Confirmer quel fichier porte réellement la logique que l'on veut
    modifier.
3.  Confirmer si le changement porte sur la logique, la spec ou
    l'affichage seulement.
4.  Utiliser le wrapper avec la plus petite cible valide.
5.  Si la sortie reste incorrecte, inspecter les artefacts dans `data/`
    avant de modifier davantage de code.
