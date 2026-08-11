---
editor_options:
  markdown:
    wrap: 72
---

# Runbook de maintenance

Ce document possède les commandes de maintenance, les gates et le dépannage.
Les procédures opérateur et les schémas de données vivent dans
`documentation/external_bundle/`.

## Séquence normale

1.  Vérifier la branche et les changements déjà présents.
2.  Identifier le propriétaire de la logique dans
    [`architecture.md`](architecture.md).
3.  Exécuter les tests source.
4.  Utiliser la plus petite cible de rendu valide.
5.  Pour un changement sans effet attendu sur les résultats, exécuter le gate
    v2.
6.  Relire le diff et les artefacts concernés avant intégration.

## Environnement R

Restaurer un clone frais avec la version R et les dépendances de `renv.lock` :

```powershell
& .\scripts\setup.ps1
```

Vérifier la résolution sans installer :

```powershell
& .\scripts\setup.ps1 -DryRun
```

Lancer les commandes R par le runner du dépôt :

```powershell
& .\scripts\run_r.ps1 -Expression "renv::status()"
```

`ORCHIDEE_R` peut désigner un autre exécutable de la version exacte demandée
par le lockfile. La qualification datée de l'environnement courant est dans
`documentation/r_environment_baseline_2026-07-26.md`.

Après une modification volontaire des dépendances :

```powershell
& .\scripts\run_r.ps1 -Expression `
  "renv::status(); renv::snapshot(prompt = FALSE)"
```

Ne pas snapshotter l'état accidentel d'une session ou d'un rendu.

## Tests source

```powershell
& .\scripts\run_r.ps1 tests/run_tests.R
```

Les fichiers `tests/test_*.R` sont exécutés dans des processus R distincts et
le runner s'arrête au premier échec.

## Rendu

Utiliser exclusivement le wrapper :

```powershell
& .\scripts\render_orchidee.ps1 -Target <cible>
```

| Cible | Quand l'utiliser |
|---|---|
| `memo` | Wording ou présentation de la méthodologie seulement. |
| `indicators` | Affichage du rapport sans changement de logique amont. |
| `full` | Périmètre, dénominateur, dédoublonnage, indicateurs, mappings ou autre logique amont. |

Pour les cibles qui consomment les données, lier explicitement le bundle et le
workspace au build voulu :

```powershell
& .\scripts\render_orchidee.ps1 -Target indicators `
  -Bundle "outputs/rouen_current/bundle_v2_operational" `
  -Workspace "outputs/rouen_current/runtime"
```

Remplacer `indicators` par `full` lorsque la logique amont a changé. `full`
construit d'abord le cache brut canonique, puis rend le rapport.

Le wrapper résout R et Quarto, vérifie les paquets et le bundle, affiche les
chemins consommés et échoue sur toute étape invalide. `ORCHIDEE_QUARTO` reste
disponible pour une installation Quarto non standard.

## Site externe sans adaptateur

La procédure maintenue est
[`external_bundle/site_handoff_inputs.md`](external_bundle/site_handoff_inputs.md).
Ne pas recopier ses commandes ici.

Invariants de maintenance :

-   `scripts/build_site.ps1` est l'unique point d'entrée opérateur ;
-   l'ordre est smoke d'installation, templates si nécessaires, `-DryRun`,
    `-Diagnose`, puis build ;
-   un `PASS` de `-Diagnose` promet que v3, sa projection v2 et leurs
    validations aboutissent sur les mêmes blocs ;
-   le build conserve v3 et matérialise un v2 séparé ;
-   les deux manifests sont écrits en dernier et portent le même `build_id` ;
-   `-Force` n'appartient pas à la première commande de build.

La CLI positionnelle `scripts/build_external_bundle_from_site_inputs.R` est
réservée aux comparaisons explicites de contrats par un maintainer.

## Construction Rouen

Vérifier les chemins sans lire les objets :

```powershell
& .\scripts\build_rouen.ps1 `
  -Bact "C:\protected\bact22_24" `
  -Pmsi "C:\protected\pmsi" `
  -DryRun
```

Après le `PASS`, relancer sans `-DryRun`. Le parcours normal demande seulement
BACT, PMSI et éventuellement `-Output`. Il écrit par défaut :

```text
outputs/rouen_current/
  site_inputs/
  bundle_v3/
  bundle_v2_operational/
  adapter_audit.rds
```

Le manifest marque la fin du build. Son absence signifie que la sortie est
incomplète. `adapter_audit.rds` peut contenir des identifiants patients : tout
le répertoire reste sous `outputs/` ou dans un emplacement protégé hors Git.

La fenêtre, le screening et les références versionnées de l'adaptateur vivent
dans `config/rouen_raw_handoff.R`. Les chemins cliniques restent des paramètres
CLI.

La procédure détaillée est
[`external_bundle/rouen_raw_handoff.md`](external_bundle/rouen_raw_handoff.md).

## Exécution sur le bundle v2

Le runtime consomme uniquement le bundle v2 projeté :

```powershell
& .\scripts\render_orchidee.ps1 -Target full `
  -Bundle "outputs/rouen_current/bundle_v2_operational" `
  -Workspace "outputs/rouen_current/runtime"
```

Les variables `ORCHIDEE_EXTERNAL_BUNDLE_V2_DIR` et
`ORCHIDEE_EXTERNAL_WORKSPACE_DIR` restent disponibles pour une session
répétée, mais les paramètres explicites rendent mieux la provenance d'un run.

## Gate de non-régression v2

Après le rendu `full` d'un changement qui ne doit pas modifier les résultats :

```powershell
$baseline = "C:\protected\validation-v2"
$candidate = "C:\protected\rouen-current"
& .\scripts\run_r.ps1 scripts/compare_operational_v2_gate.R `
  "$baseline\bundle-v2-projected" `
  "$baseline\runtime" `
  "$candidate\bundle_v2_operational" `
  "$candidate\runtime"
```

Le gate compare les objets canoniques, les résultats de dédoublonnage, leur
audit et les cellules XLSX publiées. Il ignore seulement les métadonnées de run
explicitement non déterministes. La baseline reste privée, immuable et hors
Git.

## Configuration et emplacements

-   `config/pipeline.R` : chemins runtime, cache, affichage et contrat de
    publication ;
-   `config/rouen_raw_handoff.R` : réglages versionnés propres à l'adaptateur ;
-   `data/` : entrées locales facultatives ;
-   `outputs/` : bundles, caches, audits et inspections ;
-   `downloads/` : exports destinés au lecteur ;
-   `mappings/`, `ref/`, `rules/` : transformations, faits et décisions.

Un run ordinaire ne modifie aucun fichier de configuration. Changer un réglage
analytique, une fenêtre ou une règle de screening exige la vérification
correspondante.

## Dépannage

### Un rapport semble faux

Déterminer d'abord si le problème appartient aux données ou à la logique amont,
au catalogue des indicateurs, ou uniquement à la restitution. Une valeur
absente du HTML n'est pas nécessairement absente du pipeline.

### Un build est refusé sur une sortie existante

Lire le manifest et le message du wrapper. Utiliser un autre `-Output`, ou
`-Force` seulement après avoir confirmé que la sortie complète vient du même
workflow et qu'aucun build n'est actif.

### Un diagnostic trouve un verrou résiduel

Ne supprimer `.orchidee_diagnostics.lock` qu'après avoir établi qu'aucun
diagnostic n'utilise encore ce répertoire.

### Le runtime charge la mauvaise donnée

Relancer avec `-Bundle` et `-Workspace` explicites et vérifier les chemins
affichés par le wrapper.

### Une comparaison externe semble différente

Vérifier le périmètre, le grain, le dénominateur et le prétraitement avant de
comparer des pourcentages ou des densités.

## Hygiène du dépôt

-   Les HTML et fichiers intermédiaires Quarto sont dérivés.
-   Les données patient, bundles, audits et caches ne sont jamais versionnés.
-   Les snapshots sans consumer actif sont archivés hors du dépôt.
-   Les changements scientifiques restent séparés des nettoyages structurels.
-   Avant de finir, relire `git status`, le diff et la vérification exécutée.
