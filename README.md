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
versionnés dans le dépôt.

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

ORCHIDEE attend six fichiers. Il en définit le contenu et le format ; votre
équipe décide comment les produire à partir de ses propres systèmes :

1.  les résultats de microbiologie : prélèvement, bactérie, antibiotique,
    résultat S/I/R et indication diagnostic ou dépistage ;
2.  la traduction de vos noms de bactéries vers les noms ORCHIDEE ;
3.  la traduction de vos types de prélèvement ;
4.  la traduction de vos noms d'antibiotiques ;
5.  la correspondance entre vos unités d'hospitalisation et les codes TA/DE ;
6.  les journées d'hospitalisation, par année et par unité.

Ces fichiers peuvent être des CSV ou des objets RDS. 

Avant d'introduire des données locales, vérifier l'installation sur la fixture
synthétique versionnée :

```powershell
& .\scripts\build_site.ps1 -RunSmokeTest
```

Ce smoke test qualifie l'installation, pas vos données. La procédure site donne
le nom et la structure attendue de chaque fichier, les modèles à remplir et les
commandes de vérification puis de calcul :

[documentation/external_bundle/site_handoff_inputs.md](documentation/external_bundle/site_handoff_inputs.md)

## Mainteneurs

`v2` et `v3` ne sont pas deux versions successives d'un protocole. Ce sont deux
formes du même bundle, produites ensemble par le même build : `v3` est le
contrat complet, conservé ; `v2` en est la projection fermée `spares_current`,
seule entrée du runtime et du rapport.

| Question | Document |
|---|---|
| Quelles sont les conventions du dépôt et la collaboration ? | [`AGENTS.md`](AGENTS.md) |
| Comment s'enchaîne la chaîne et quel fichier possède la logique ? | [`architecture.md`](documentation/architecture.md) |
| Quelles décisions d'implémentation ont été prises, et où sont-elles dans le code ? | [`methods.md`](documentation/methods.md) |
| Quels réglages existent, et que faut-il refaire après en avoir changé un ? | [`knobs.md`](documentation/knobs.md) |
| Comment tester, rendre, comparer ou dépanner ? | [`maintenance_runbook.md`](documentation/maintenance_runbook.md) |
| Quelle méthode est publiée ? | [`ratb_methodology.qmd`](documentation/ratb_methodology.qmd) |
| Quels indicateurs sont publiés ? | [`ratb_indicator_spec.csv`](documentation/ratb_indicator_spec.csv) |
| Quels sont les schémas des bundles ? | [`bundle_schemas.md`](documentation/external_bundle/bundle_schemas.md) |

La méthode et le périmètre publiés ne changent qu'après une décision explicite
et la vérification correspondante. Les notes datées conservent des décisions ou
des preuves historiques ; elles ne remplacent pas les documents ci-dessus.
