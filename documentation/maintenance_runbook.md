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
& '~\orchidee\scripts\render_orchidee.ps1' -Target <cible>
```

Cibles disponibles :

-   `memo`
-   `meeting`
-   `docs`
-   `indicators`
-   `full`

## Point d'entrée des réglages

Les réglages opérationnels vivent dans `config/pipeline.R` : chemins,
fenêtre d'extraction attendue, flags de recompute et paramètres
d'affichage.

Les règles analytiques maintenues par le projet restent dans `rules/`.
Les dictionnaires biologiques restent dans `dictionaries/` et les
référentiels institutionnels importés restent dans `ref/`, y compris les
référentiels CONSORES TA/DE actifs du périmètre RATB.
Les fichiers de présentation Quarto restent dans `assets/`.

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

Cette vérification compare des signatures agrégées des artefacts
canoniques, des jeux de complétion, des sorties de dédoublonnage et des
panels d'indicateurs recalculés depuis les caches. Elle sert à détecter
un changement non intentionnel ; elle ne remplace pas le rendu Quarto.

## Matrice de rendu

### Si seul le mémo a changé

Commande :

```powershell
& '~\orchidee\scripts\render_orchidee.ps1' -Target memo
```

### Si seule la note de réunion SPF a changé

Commande :

```powershell
& '~\orchidee\scripts\render_orchidee.ps1' -Target meeting
```

### Si les deux documents méthodologiques ont changé

Commande :

```powershell
& '~\orchidee\scripts\render_orchidee.ps1' -Target docs
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
& '~\orchidee\scripts\render_orchidee.ps1' -Target indicators
```

### Si la logique amont a changé

Exemples :

-   complétion
-   dédoublonnage
-   dénominateur / périmètre
-   calcul des indicateurs
-   construction de l'artefact large
-   modification de la spec des indicateurs qui affecte la QA du workflow

Commande :

```powershell
& '~\orchidee\scripts\render_orchidee.ps1' -Target full
```

`full` rend dans cet ordre :

1.  `orchidee_dedup_workflow.qmd`
2.  `orchidee_ratb_indicators.qmd`

## Règles courantes de maintenance

-   Traiter la copie Desktop du dépôt comme la source de vérité de
    travail.
-   Traiter les sorties HTML comme des artefacts dérivés, pas comme la
    source.
-   Garder `data/` pour les artefacts internes générés.
-   Garder `downloads/` pour les artefacts d'export produits par les
    rapports.
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
