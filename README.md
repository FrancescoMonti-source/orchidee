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

Pour vérifier une installation :

```powershell
& .\scripts\run_r.ps1 tests/run_tests.R
```

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

Après le `PASS`, retirer `-DryRun` pour lancer le build. Il peut durer une
vingtaine de minutes et rester silencieux. La sortie par défaut est
`outputs/rouen_current` ; `-Output` accepte un autre répertoire dédié, y compris
protégé hors du dépôt. Une exécution réussie finit par `PASS` et écrit
`build_manifest.txt` : sans ce fichier, ne pas utiliser la sortie.

Le build produit `site_inputs/` (les six blocs), `bundle_v3/` (le bundle
complet, à conserver), `bundle_v2_operational/` (l'entrée du runtime) et
`adapter_audit.rds`. Si l'objectif est le handoff, s'arrêter ici. Pour produire
les indicateurs à partir du même build :

```powershell
& .\scripts\render_orchidee.ps1 -Target full `
  -Bundle "outputs/rouen_current/bundle_v2_operational" `
  -Workspace "outputs/rouen_current/runtime"
```

Adapter les deux chemins si le build utilisait `-Output`. Aucun fichier de
configuration ou de mapping ne doit être préparé ou modifié pour un run
ordinaire.

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
| Quelles décisions ont été prises, et où sont-elles dans le code ? | [`methods.md`](documentation/methods.md) |
| Qu'est-ce qui est réglable, et que faut-il refaire après ? | [`knobs.md`](documentation/knobs.md) |
| Quels indicateurs sont publiés ? | [`ratb_indicator_spec.csv`](documentation/ratb_indicator_spec.csv) |

La méthode et le périmètre publiés ne changent qu'après une décision explicite
et la vérification correspondante.
