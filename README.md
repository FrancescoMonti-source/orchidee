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

## Choisir le bon point d'entrée

-   **Rennes ou un autre entrepôt** : préparer les six blocs attendus par
    `scripts/build_site.ps1`. Commencer par la
    [procédure opérateur site](documentation/external_bundle/site_handoff_inputs.md).
-   **Rouen** : fournir seulement les chemins BACT et PMSI à
    `scripts/build_rouen.ps1`. Commencer par la
    [procédure opérateur Rouen](documentation/external_bundle/rouen_raw_handoff.md).

## Rennes / autre entrepôt : commencer ici

Cette section sert uniquement d'orientation. La procédure opérateur maintenue,
avec les colonnes, commandes et erreurs possibles, est
[`documentation/external_bundle/site_handoff_inputs.md`](documentation/external_bundle/site_handoff_inputs.md).

Après l'[installation R](#installation-r), vérifier d'abord l'installation en
faisant tourner le parcours complet sur la fixture synthétique versionnée :

```powershell
& .\scripts\build_site.ps1 -RunSmokeTest
```

Un `PASS` prouve que l'environnement et le builder fonctionnent sans introduire
de données cliniques : tout problème ultérieur appartient donc à l'extraction
ou au mapping local. Ce n'est pas du matériel d'onboarding et cela n'apprend
rien sur les données du site. La sortie reste sous `outputs/site_smoke_test/`.

Si les six fichiers locaux n'existent pas encore, générer ensuite leurs
en-têtes et le kit de références pour les valeurs cibles ORCHIDEE :

```powershell
$handoff = "data/site_handoff"
& .\scripts\build_site.ps1 -EmitTemplates $handoff
```

Le site remplit les six fichiers de premier niveau. `mapping_reference/`
indique vers quelles valeurs ORCHIDEE mapper les libellés locaux ; ce
sous-répertoire est un kit d'aide, pas un septième bloc à fournir.

Suivre ensuite dans la procédure opérateur la commande nommée avec `-DryRun`,
qui vérifie seulement les chemins et les colonnes. Après ce `PASS`, relancer la
même commande avec `-Diagnose` : elle lit les six blocs une seule fois et
rapporte en un seul passage tous les problèmes de contrat, classés `BLOCKING`,
`WARNING` et `INFO`, avec le nombre de lignes et d'occurrences documentaires
concernées par libellé local. C'est l'étape qui évite d'enchaîner un rebuild
par classe d'erreur. Retirer enfin `-DryRun` et `-Diagnose` pour construire.

Toutes les options du point d'entrée sont visibles avec :

```powershell
Get-Help .\scripts\build_site.ps1 -Full
```

Après validation, ORCHIDEE conserve le bundle v3 complet, matérialise le bundle
v2 opérationnel et affiche la commande de rendu liée à ce même build. Les
fichiers RDS internes sont générés par ORCHIDEE, pas préparés par le site.

## Rouen : démarrage rapide

L'opérateur Rouen fournit exactement deux fichiers cliniques :

1.  l'export BACT automatique récupéré localement ;
2.  l'objet PMSI RDS produit par `redsan`.

ORCHIDEE ne télécharge ni ne produit ces deux entrées. Si l'une manque, il faut
d'abord suivre la procédure institutionnelle Rouen correspondante ; aucun
mapping ou artefact intermédiaire ORCHIDEE ne peut la remplacer.

Depuis la racine d'un clone frais, restaurer une fois l'environnement R :

```powershell
& .\scripts\setup.ps1
```

Vérifier ensuite les deux chemins, R et les paquets nécessaires sans lire les
objets cliniques ni lancer le build :

```powershell
& .\scripts\build_rouen.ps1 `
  -Bact "C:\protected\bact22_24" `
  -Pmsi "C:\protected\pmsi" `
  -DryRun
```

Après le `PASS`, relancer exactement la même commande sans `-DryRun`. Un run
ordinaire ne demande de modifier aucun fichier sous `config/`, `mappings/`,
`ref/` ou `rules/`.

La procédure opérateur de référence décrit les sorties, le manifest de fin et
le rendu à partir du même build :

[`documentation/external_bundle/rouen_raw_handoff.md`](documentation/external_bundle/rouen_raw_handoff.md)

Toutes les options du point d'entrée sont visibles avec :

```powershell
Get-Help .\scripts\build_rouen.ps1 -Full
```

## Installation R

Les dépendances et la version de R sont figées dans `renv.lock`.
`scripts/setup.ps1` trouve la version R attendue sans exiger `Rscript` dans le
`PATH`, restaure la bibliothèque locale `renv/` et vérifie les versions
installées :

```powershell
& .\scripts\setup.ps1
```

Le resolver examine d'abord `ORCHIDEE_R`, qui doit lui aussi pointer vers la
version exacte déclarée dans `renv.lock`, puis l'installation standard de cette
version et les autres candidats connus. `-DryRun` vérifie R et le lockfile sans
installer ni modifier de paquet. Relancer le setup après une modification
volontaire de `renv.lock`.

Le patch R est volontairement exact pour ce pipeline clinique gelé : le lock
courant demande R 4.5.3. Sous Windows, cette version reste disponible dans
[les archives officielles CRAN](https://cran.r-project.org/bin/windows/base/old/4.5.3/).
Une mise à jour de R ou du lock n'est acceptée qu'avec une restauration depuis
un cache vide, les tests source et le gate opérationnel complet décrits dans le
runbook.

Sur le poste Windows qualifié, le setup annonce explicitement l'usage de
Schannel avec révocation TLS en mode `best-effort` lorsque le service de
révocation est indisponible. Cette exception est limitée à la restauration,
conserve la validation de la chaîne de certificats et est documentée dans
`documentation/r_environment_baseline_2026-07-26.md`.

Pour les commandes R de maintenance, utiliser le même resolver et la même
bibliothèque de projet :

```powershell
& .\scripts\run_r.ps1 tests/run_tests.R
& .\scripts\run_r.ps1 -Expression "renv::status()"
```

L'adaptateur PMSI Rouen utilise `redsan` 0.2.0 ou plus récent. Sa politique
PMSI par défaut applique explicitement `C > DW` à
l'intérieur d'une même unité sans fusionner les intervalles retenus. Cette
dépendance est enregistrée dans `renv.lock` ; elle ne remplace pas le chemin de
handoff d'un site externe.

L'opérateur ORCHIDEE ne doit donc pas installer `redsan` séparément. Il doit en
revanche disposer de l'objet PMSI que le pipeline `redsan` a produit en amont.

## Repères du dépôt

Le principe pour un site externe est simple : le site ne reproduit pas le chemin
d'extraction CHU. Il fournit des blocs locaux lisibles, puis ORCHIDEE dérive les
fichiers internes utilisés par ORCHIDEE.

Le noyau actuel de l'étape 1 est gelé. Les changements courants doivent donc
préserver les sorties validées, sauf décision explicite de modifier la méthode
ou le périmètre publié.

Les données locales d'exécution (`data/`) et les artefacts générés
(`downloads/`, `outputs/`, `archive/`) ne sont pas versionnés. Un clone frais
ne contient donc ni données patient, ni caches, ni exports, ni rendus locaux.

Les références non sensibles propres à l'adaptateur Rouen sont en revanche
versionnées sous `ref/rouen/`, y compris la structure interne de
l'établissement. Les sources méthodologiques et les références consommées sont
recensées dans `documentation/reference_sources.md`.

L'interrogation EDSaN, le découpage en lots et la normalisation des modules
PMSI/BIOL appartiennent désormais à `redsan`. ORCHIDEE ne maintient plus de
second client EDSaN : il consomme l'export bactériologique local et l'objet PMSI
produit par `redsan`, puis les transforme par son adaptateur Rouen ou reçoit les
six blocs de handoff d'un autre site.

## Carte des documents

-   `documentation/operational_flow.md`
    -   vue d'ensemble du chemin Rouen brut vers les indicateurs, responsabilités,
        place de la complétion et évolution attendue du dénominateur ;
-   `documentation/external_bundle/site_handoff_inputs.md`
    -   source de vérité pour ce qu'un site externe doit fournir ;
-   `documentation/external_bundle/sir_wide.md`
    -   schéma de l'artefact microbiologique canonique et sémantique où
        `SEJUF` désigne l'UF d'hébergement au prélèvement ;
-   `documentation/external_bundle/rouen_raw_handoff.md`
    -   chemin Rouen brut bactériologie + PMSI vers les six blocs et le bundle
        v2 ou v3 ;
-   `documentation/external_bundle/operational_v2_adoption_2026-07-19.md`
    -   décision et éléments agrégés ayant conduit à adopter v2 par défaut ;
-   `documentation/external_bundle/sample_scope_reference.md`
    -   schéma de la référence de périmètre au niveau prélèvement / `SEJUF` ;
-   `documentation/external_bundle/denominator_bundle_v2.md`
    -   schéma du dénominateur annuel d'incidence ;
-   `documentation/external_bundle/denominator_bundle_v3.md`
    -   exposition profilée, contexte TA/DE courant et évolutions prévues ;
-   `documentation/project_map.md`
    -   carte mainteneur : où se trouve la logique dans le code ;
-   `documentation/maintenance_runbook.md`
    -   commandes de rendu, validation locale et dépannage courant ;
-   `documentation/r_environment_baseline_2026-07-26.md`
    -   qualification du bootstrap froid et du gate fonctionnel du lock R ;
-   `documentation/ratb_implementation_decisions.qmd`
    -   mémo méthodologique du noyau RATB gelé ;
-   `documentation/reference_sources.md`
    -   sources publiques et frontière avec les documents locaux privés ;
-   `documentation/ratb_indicator_spec.csv`
    -   catalogue des indicateurs publiés.

## Modèle opératoire actuel

Les notebooks chargent strictement les quatre fichiers canoniques d'un
`external_bundle_v2`. Il s'agit de leur unique source opérationnelle.

Le chemin du bundle se configure avec `ORCHIDEE_EXTERNAL_BUNDLE_V2_DIR`. Les
caches et téléchargements sont isolés sous
`outputs/external_bundle_v2_runtime/` par défaut, ou sous le workspace désigné
par `ORCHIDEE_EXTERNAL_WORKSPACE_DIR`. Un bundle absent ou invalide fait échouer
explicitement le runtime : il n'existe aucun autodétecteur ni fallback.
Pour un rendu ponctuel, préférer les paramètres explicites `-Bundle` et
`-Workspace` du wrapper : ils rendent la provenance visible et ne modifient les
variables que pendant cette invocation.

Le chemin canonique reste brut et n'applique aucune complétion. Les dernières
implémentations cohérentes de la complétion exploratoire et du runtime
`chu_native` sont conservées au tag
`archive/completion-chu-native-2026-07-22`.

Les CLI qui acceptent plusieurs contrats demandent explicitement
`--contract=v2|v3`. Le parcours d'onboarding préféré construit v3 à partir des
six blocs complets et demande `--operational-v2-output` pour produire l'entrée
du runtime actuel. Un site ne doit déclarer ni v2 ni v3 avant d'avoir attribué
l'UF d'hébergement active au prélèvement comme décrit dans
`documentation/external_bundle/sir_wide.md`.

Pour comprendre la frontière technique actuelle, lire
`documentation/project_map.md`.
Pour brancher un autre entrepôt, commencer par
`documentation/external_bundle/site_handoff_inputs.md`.

## Répertoires principaux

-   `R/`
    -   helpers R et logique réutilisable ;
-   `scripts/`
    -   setup R et points d'entrée CLI : runner R commun, builders,
        validateurs, smoke test et wrapper de rendu ;
-   `examples/`
    -   jeux de données entièrement synthétiques et versionnés pour vérifier
        les parcours opérateur avant d'introduire des données locales ;
-   `renv/`
    -   infrastructure d'activation versionnée ; la bibliothèque restaurée sous
        `renv/library/` reste locale et ignorée par Git ;
-   `documentation/external_bundle/`
    -   contrat d'entrée pour Rennes ou un autre entrepôt ;
-   `documentation/`
    -   documentation de maintenance, décisions méthodologiques et specs ;
-   `config/`
    -   chemins, politiques de recompute et paramètres opérationnels ;
-   `mappings/`
    -   mappings versionnés qui traduisent les valeurs microbiologiques locales
        vers les valeurs canoniques ORCHIDEE ;
-   `ref/`
    -   faits de référence versionnés effectivement consommés : catalogues
        TA/DE partagés sous `ref/consores/` et références propres à Rouen sous
        `ref/rouen/` ;
-   `rules/`
    -   décisions analytiques maintenues par ORCHIDEE ;
-   `data/`
    -   zone locale facultative pour les inputs d'une exécution, ignorés par
        Git ; les scripts acceptent aussi des chemins protégés externes ;
-   `downloads/`
    -   exports de rapport, ignorés par Git ;
-   `outputs/`
    -   bundles, caches, audits, brouillons et inspections générés localement,
        ignorés par Git.

## Maintenance rapide

-   Ne pas traiter les HTML rendus comme source de vérité.
-   Utiliser `scripts/render_orchidee.ps1` plutôt que lancer `quarto render` à
    la main.
-   Pour un refactor sans changement attendu de résultats, utiliser le gate v2
    documenté dans `documentation/maintenance_runbook.md`.
-   Pour savoir quel fichier modifier, commencer par
    `documentation/project_map.md`.
-   Pour savoir quoi rerendre, commencer par
    `documentation/maintenance_runbook.md`.
