---
editor_options:
  markdown:
    wrap: 80
---

# Orchidee

Aucune donnée patient, aucun bundle et aucun audit n'est versionné. Les scripts
acceptent des chemins protégés hors du checkout et écrivent leurs sorties sous
`outputs/`.

Deux parcours d'entrée mènent au même rapport. Suivre uniquement le sien.

## Prérequis et installation

Windows avec PowerShell, Git et Quarto. La version de R et les dépendances sont
imposées par `renv.lock`. Depuis la racine d'un clone frais :

```powershell
& .\scripts\setup.ps1
```

Pour exécuter un script R dans cet environnement verrouillé :

```powershell
& .\scripts\run_r.ps1 tests/run_tests.R
```

Les détails de restauration et de qualification sont dans le
[runbook de maintenance](documentation/maintenance_runbook.md).

## Rouen

Vous fournissez deux chemins : l'export BACT et l'objet PMSI produit par
`redsan`. L'adaptateur Rouen, ses mappings et ses références sont déjà
versionnés dans le dépôt et génèrent eux-mêmes les six blocs de handoff ; vous
ne préparez aucun autre fichier. Dans ce parcours, `redsan` possède l'accès
EDSaN, le batching et la normalisation PMSI/BIOL.

Après l'installation, contrôler les deux chemins sans lire les objets
cliniques :

```powershell
& .\scripts\build_rouen.ps1 `
  -Bact "C:\protected\bact22_24" `
  -Pmsi "C:\protected\pmsi" `
  -DryRun
```

Après le `PASS`, la procédure Rouen mène du build aux sorties, puis au rendu du
rapport :

[documentation/external_bundle/rouen_raw_handoff.md](documentation/external_bundle/rouen_raw_handoff.md)

## Autre établissement

Vous fournissez les six blocs de handoff. Votre équipe possède l'extraction
depuis son entrepôt, l'identification du périmètre de dépistage et les mappings
locaux.

Avant d'introduire des données locales, vérifier l'installation sur la fixture
synthétique versionnée :

```powershell
& .\scripts\build_site.ps1 -RunSmokeTest
```

Ce smoke test qualifie l'installation, pas vos données. La procédure site décrit
les six blocs, les templates, le diagnostic, le build et le rendu :

[documentation/external_bundle/site_handoff_inputs.md](documentation/external_bundle/site_handoff_inputs.md)

## Mainteneurs

`v2` et `v3` ne sont pas deux versions successives d'un protocole. Ce sont deux
formes du même bundle, produites ensemble par le même build : `v3` est le
contrat complet, conservé ; `v2` en est la projection fermée `spares_current`,
seule entrée du runtime et du rapport.

| Question | Document |
|---|---|
| Quelles sont les conventions du dépôt et la collaboration ? | [`AGENTS.md`](AGENTS.md) |
| Comment s'enchaînent adaptateurs, v3, v2 et indicateurs ? | [`operational_flow.md`](documentation/operational_flow.md) |
| Quel fichier possède la logique à modifier ? | [`project_map.md`](documentation/project_map.md) |
| Comment tester, rendre, comparer ou dépanner ? | [`maintenance_runbook.md`](documentation/maintenance_runbook.md) |
| Quelle méthode est publiée ? | [`ratb_methodology.qmd`](documentation/ratb_methodology.qmd) |
| Quels indicateurs sont publiés ? | [`ratb_indicator_spec.csv`](documentation/ratb_indicator_spec.csv) |
| Quels sont les schémas des bundles ? | [`external_bundle/`](documentation/external_bundle/README.md) |

La méthode et le périmètre publiés ne changent qu'après une décision explicite
et la vérification correspondante. Les notes datées conservent des décisions ou
des preuves historiques ; elles ne remplacent pas les documents ci-dessus.
