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

Puis retirer `-DryRun` pour construire les artefacts :

```powershell
& .\scripts\build_rouen.ps1 `
  -Bact "C:\protected\bact22_24" `
  -Pmsi "C:\protected\pmsi"
```

Un run ordinaire ne demande de modifier aucun fichier sous `config/`,
`mappings/`, `ref/` ou `rules/`. Pour afficher l'aide complète du point
d'entrée :

```powershell
Get-Help .\scripts\build_rouen.ps1 -Full
```

La procédure opérateur de référence, y compris les règles de destination et le
contenu des sorties, est
[`documentation/external_bundle/rouen_raw_handoff.md`](documentation/external_bundle/rouen_raw_handoff.md).

La destination par défaut est `outputs/rouen_current`. La présence de
`outputs/rouen_current/build_manifest.txt` marque un build terminé. Les
mappings, références et règles Rouen sont déjà dans le checkout ; les six blocs
de handoff et les bundles sont générés. Quarto n'est pas nécessaire pour cette
construction ; il intervient seulement lors du rendu ultérieur des rapports.
Le traitement réel prend des minutes, pas des secondes, et peut rester
silencieux pendant une partie du calcul : ne consommer la sortie qu'après
l'apparition du manifest.

À ce stade :

-   `site_inputs/` contient les six blocs intermédiaires générés ;
-   `bundle_v3/` est le bundle complet à conserver ;
-   `bundle_v2_operational/` est l'entrée du runtime actuel ;
-   `build_manifest.txt` prouve que la construction et ses validations sont
    terminées.

Si l'objectif était seulement de produire le handoff, s'arrêter ici. Pour
calculer ensuite les indicateurs à partir de ce même build, lier explicitement
le bundle et son workspace au rendu :

```powershell
& .\scripts\render_orchidee.ps1 -Target full `
  -Bundle "outputs/rouen_current/bundle_v2_operational" `
  -Workspace "outputs/rouen_current/runtime"
```

Si `-Output` a été changé pendant le build, remplacer
`outputs/rouen_current` dans ces deux chemins. Le wrapper affiche toujours le
bundle, le workspace et l'origine de leur sélection avant de calculer.

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

## Choisir le bon point d'entrée

-   **Rouen** : fournir seulement les deux chemins d'entrée BACT et PMSI à
    `scripts/build_rouen.ps1`. Le wrapper trouve R et l'adaptateur génère les
    six blocs ; commencer par
    `documentation/external_bundle/rouen_raw_handoff.md`.
-   **Rennes ou un autre entrepôt** : fournir directement les six blocs décrits
    dans `documentation/external_bundle/site_handoff_inputs.md` à
    `scripts/build_site.ps1`.

## Rennes / autre entrepôt : commencer ici

Si les six fichiers n'existent pas encore, générer leurs en-têtes et le kit de
références pour les valeurs cibles ORCHIDEE :

```powershell
$handoff = "data/site_handoff"
& .\scripts\build_site.ps1 -EmitTemplates $handoff
```

Le sous-répertoire `mapping_reference/` indique notamment les valeurs
`atb_norm` supportées, la taxonomie bactérienne reconnue, les types de
prélèvement utilisés par les indicateurs actuels, les catalogues nationaux
TA/DE et le profil de dénominateur accepté. Il ne réalise aucun mapping local :
le site reste responsable d'associer ses propres libellés à ces cibles.

Une fois les fichiers remplis, commencer par le préflight ci-dessous. Il
contrôle les chemins, R, les paquets et les colonnes sans construire de bundle :

```powershell
$handoff = "data/site_handoff"
& .\scripts\build_site.ps1 `
  -MicrobiologyObservations `
    (Join-Path $handoff "microbiology_observations.csv") `
  -BacteriaMapping (Join-Path $handoff "bacteria_mapping.csv") `
  -SampleTypeMapping (Join-Path $handoff "sample_type_mapping.csv") `
  -AntibioticMapping (Join-Path $handoff "antibiotic_mapping.csv") `
  -UnitMapping (Join-Path $handoff "unit_mapping.csv") `
  -IncidenceExposure `
    (Join-Path $handoff `
      "incidence_exposure_by_year_um_uf_ta_de_profile.csv") `
  -DryRun
```

Pour une première construction, après `PASS`, relancer exactement la même
commande sans `-DryRun`. Si le préflight signale un output complet existant,
suivre son message : choisir un autre `-Output` ou, après revue, ajouter
`-Force`.

`documentation/external_bundle/site_handoff_inputs.md` décrit les colonnes et
les erreurs possibles ; c'est la source de vérité pour les six entrées.

Pour placer les résultats dans un espace protégé externe, ajouter
`-Output "D:\ORCHIDEE\site_current"`. Toutes les options sont visibles avec :

```powershell
Get-Help .\scripts\build_site.ps1 -Full
```

En résumé, le site prépare exactement six blocs de handoff non versionnés :

-   `microbiology_observations` ;
-   `bacteria_mapping` ;
-   `sample_type_mapping` ;
-   `antibiotic_mapping` ;
-   `unit_mapping`, avec `CODE_TA`, `CODE_DE` et `de_domain_ref` ;
-   `incidence_exposure_by_year_um_uf_ta_de_profile`.

Ces blocs conservent les informations nécessaires au bundle v3, même si le
runtime opérationnel consomme encore v2. Le builder peut valider et conserver
v3 puis en matérialiser la projection v2 `spares_current` conforme au contrat
d'entrée du runtime.

ORCHIDEE dérive ensuite :

-   `sir_wide.rds`
-   `sir_wide_meta.rds`
-   `sample_scope_reference.rds`
-   `denominator_bundle.rds`

Ces quatre fichiers sont construits par ORCHIDEE. Un site externe ne doit pas
les construire à la main.

Le wrapper écrit par défaut le bundle v3 conservé sous
`outputs/site_current/bundle_v3` et le bundle v2 opérationnel sous
`outputs/site_current/bundle_v2_operational`. Chaque répertoire n'est utilisable
qu'après apparition de son `build_manifest.txt`, avec le même `build_id` dans
les deux manifests. Le wrapper affiche ensuite la commande de rendu avec ces
chemins explicites.

## Rouen : des exports locaux au même handoff

Rouen dispose maintenant d'un adaptateur explicite qui transforme l'export
bactériologique long et l'objet PMSI produit par `redsan` en ces mêmes familles
de blocs, puis construit dans une seule exécution le bundle v3 durable et sa
projection v2 opérationnelle. Il applique l'UF
d'hébergement active au prélèvement sans fallback silencieux vers l'UF
microbiologique.

Le contrat, les décisions locales et le contenu de l'audit sont décrits dans :

`documentation/external_bundle/rouen_raw_handoff.md`

Le démarrage rapide ci-dessus résume la procédure opérateur de référence liée
plus haut. Le reste de cette section décrit le contrat sans ajouter d'étape au
parcours ordinaire.

Le profil Rouen couvre par défaut les années 2022 à 2024 ; la même fenêtre
est appliquée à la microbiologie et au dénominateur PMSI.

Dans un checkout Rouen prêt à l'emploi, l'opérateur renseigne seulement les
deux chemins d'entrée BACT et PMSI. La destination par défaut est
`outputs/rouen_current` ; `-Output` permet d'en choisir une autre et `-DryRun`
vérifie les chemins, la version R verrouillée et les paquets nécessaires sans
lancer le build. Un output compatible existant est signalé pendant ce préflight
sans le bloquer ; le build réel exige ensuite `-Force` ou un autre `-Output`.
Un ancien layout incompatible fait échouer le préflight et impose un autre
`-Output`. Les mappings versionnés et les références sous `ref/rouen/` et
`ref/consores/` sont déjà fournis et chargés automatiquement. Les six blocs de
handoff et les bundles sont générés par la commande. Les fichiers d'entrée
peuvent ne pas avoir d'extension, comme dans l'exemple. Dans le checkout, le
wrapper refuse une destination hors de `outputs/` ; un répertoire dédié dans un
emplacement protégé externe reste accepté, mais pas la racine d'un disque ni un
dossier parent du checkout.

Les sorties restent locales et ignorées par Git. `site_inputs/` conserve les
six blocs, `bundle_v3/` le contrat complet et `bundle_v2_operational/` l'entrée
du runtime actuel. `build_manifest.txt` indique leurs chemins, empreintes et
statuts de validation sans devoir ouvrir les objets RDS.

Le contrat v3 conserve la sémantique d'UF d'hébergement de v2 et remplace le
total annuel transporté
par une table d'exposition profilée au grain année + UM + UF + TA + DE. Elle
conserve aussi l'activité mappée hors du périmètre courant. Le runtime applique
le contexte fermé `spares_current` et redérive exactement le total annuel
v2. v3 n'est pas consommé directement par les notebooks et n'ajoute pas encore
de panels stratifiés. Le build direct `--contract=v2` reste disponible comme
chemin de compatibilité explicite, mais ce n'est plus la commande d'onboarding
Rouen recommandée.

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
