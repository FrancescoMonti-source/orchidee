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
-   `completion`
-   `full`

## Point d'entrée des réglages

Les réglages opérationnels vivent dans `config/pipeline.R` : chemins,
fenêtre d'extraction attendue, flags de recompute et paramètres
d'affichage.

Les tables de règles analytiques maintenues par le projet doivent rester
dans `rules/` lorsqu'elles existent.
Les dictionnaires biologiques restent dans `dictionaries/` et les
référentiels institutionnels importés restent dans `ref/`, y compris les
référentiels CONSORES TA/DE actifs du périmètre RATB.
Les fichiers de présentation Quarto restent dans `assets/`.

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

## Tests R autonomes

Exécuter les tests source depuis la racine du dépôt :

```powershell
Rscript tests/run_tests.R
```

Chaque fichier `tests/test_*.R` est exécuté dans un processus R distinct.

## Construction locale du handoff Rouen v2

Pour transformer les exports locaux Rouen en bundle canonique v2 :

```powershell
Rscript scripts/build_rouen_external_bundle.R `
  <bacteriology_raw.rds> `
  <pmsi.rds> `
  outputs/rouen_bundle_v2 `
  --contract=v2
```

La commande écrit les six blocs sous `site_inputs/`, les quatre fichiers
canoniques sous `bundle/` et l'audit local dans `adapter_audit.rds`. Cet audit
peut contenir des identifiants patients : conserver tout le répertoire sous
`outputs/` ou dans un autre emplacement protégé et non versionné.

La fenêtre versionnée par défaut est `[2022-01-01, 2025-01-01)` pour les deux
sources. Toute modification se fait dans `config/rouen_raw_handoff_v1.R` et
doit rester visible dans les métadonnées d'audit.

Le script valide strictement le contrat v2 puis exécute le smoke du runtime
canonique. Un changement limité à cet adaptateur se valide avec les tests
source et un gate local sur les exports privés.

Pour construire sans l'adopter un candidat v3 au dénominateur fin, utiliser un
répertoire distinct et `--contract=v3`. Le bundle v3 transporte la table année
+ UM + UF + TA + DE et le smoke en dérive le total annuel actuel. Le sélecteur
opérationnel reste explicitement sur v2 tant qu'une décision d'adoption séparée
n'a pas été prise.

## Exécution opérationnelle sur un bundle v2

Le bundle v2 strict est le chemin opérationnel par défaut. Sans surcharge,
`config/pipeline.R` cherche le bundle sous
`outputs/rouen_bundle_v2/bundle`. Après sa construction, lancer un rendu
complet :

```powershell
& .\scripts\render_orchidee.ps1 -Target full
```

`full` construit le cache RATB brut canonique puis rend le rapport
d'indicateurs. La complétion ne fait pas partie de ce chemin.

Pour exécuter explicitement le diagnostic de complétion :

```powershell
& .\scripts\render_orchidee.ps1 -Target completion
```

Ses caches et téléchargements sont isolés dans un sous-dossier
`completion_diagnostic/` du workspace sélectionné.

Pour utiliser un bundle ou un workspace protégé situé ailleurs :

```powershell
$env:ORCHIDEE_EXTERNAL_BUNDLE_V2_DIR = "C:\chemin\protege\bundle"
$env:ORCHIDEE_EXTERNAL_WORKSPACE_DIR = "C:\chemin\protege\runtime"
& .\scripts\render_orchidee.ps1 -Target full
```

Le loader exige les quatre fichiers préférés du contrat v2 et échoue sans
fallback vers CHU ou v1. Cache brut, dédoublonnage et téléchargements sont
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

## Snapshot de caractérisation avant refactor

Avant un nettoyage structurel censé ne pas changer les résultats, créer un
snapshot local des artefacts et panels courants :

```powershell
Rscript scripts/characterize_current_outputs.R write
```

Le snapshot est écrit dans `data/characterization_baseline.rds`, donc il
reste local et n'est pas versionné. Après le refactor et le rendu adapté,
vérifier que les signatures n'ont pas changé :

```powershell
Rscript scripts/characterize_current_outputs.R check
```

Si `Rscript` n'est pas disponible dans le `PATH`, utiliser le chemin complet
de l'installation R locale.

Cet ancien helper caractérise les artefacts locaux `chu_native`, y compris les
jeux de complétion historiques. Il ne constitue pas le gate du runtime v2.
Pour v2, comparer le cache brut isolé et les panels produits sur le même bundle.

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

### Si seule la complétion exploratoire a changé

Commande :

```powershell
& .\scripts\render_orchidee.ps1 -Target completion
```

Ce rendu reste diagnostique et n'écrit pas dans le cache opérationnel brut.

## Règles courantes de maintenance

-   Traiter le checkout Git sous `~/Documents/Git/orchidee` comme la
    source de vérité locale de travail ; `main` reflète le travail accepté
    sur GitHub.
-   Créer une branche `task/<slug>` pour les changements significatifs et
    garder `main` propre.
-   Traiter les sorties HTML comme des artefacts dérivés, pas comme la
    source.
-   Garder `data/` pour les artefacts internes générés.
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

### Complétion et dédoublonnage sont deux étapes différentes

Une règle de complétion peut utiliser une fenêtre de 30 jours sans que
le dédoublonnage lui-même devienne un dédoublonnage à 30 jours.

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
