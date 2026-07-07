---
editor_options:
  markdown:
    wrap: 80
---

# Orchidee

ORCHIDEE construit les indicateurs RATB/SPARES de l'étape 1 à partir de données
hospitalières.

Ce README est d'abord le point d'entrée pour Rennes ou pour tout autre entrepôt
de données hospitalier qui veut brancher ses données sur ORCHIDEE. Il résume les
blocs locaux à fournir, les objets qu'ORCHIDEE dérive ensuite, et les documents
où lire le contrat détaillé.

Il sert aussi aux mainteneurs du dépôt : le noyau actuel de l'étape 1 est gelé,
et les changements courants doivent préserver les sorties validées sauf décision
explicite de modifier la méthode ou le périmètre publié.

Le dépôt canonique est versionné sur GitHub :
`https://github.com/FrancescoMonti-source/orchidee`.

La copie de travail locale recommandée est `~/Documents/Git/orchidee`.
Les artefacts générés ou locaux (`data/`, `downloads/`, `outputs/`,
`archive/`) ne sont pas versionnés ; un clone frais ne contient donc pas les
caches, les exports ou les rendus locaux.

## À qui s'adresse ce dépôt ?

Le premier public est une équipe entrepôt de données hospitalier. Pour ce public,
l'idée principale est la suivante : il ne faut pas reproduire le chemin
d'extraction CHU. Le site fournit des blocs locaux simples et compréhensibles,
puis ORCHIDEE dérive le bundle canonique utilisé par le runtime RATB.

Les mainteneurs ORCHIDEE sont le deuxième public. Ils utilisent ce dépôt pour
préserver le noyau gelé de l'étape 1, faire évoluer la documentation, contrôler
les rendus et préparer les extensions futures sans casser les sorties validées.

## Ce qu'un site externe doit fournir

Le point d'entrée pour Rennes ou un autre entrepôt est :
`documentation/external_bundle/site_handoff_inputs_v1.md`.

Le site doit préparer quatre familles de données :

1.  des observations microbiologiques longues, avec le statut
    diagnostic/non-dépistage explicite ;
2.  des dictionnaires de mapping microbiologique : bactéries, types de
    prélèvements et antibiotiques locaux vers les valeurs ORCHIDEE ;
3.  un mapping unité / structure / TA-DE, au niveau `SEJUF` ;
4.  un dénominateur annuel d'activité hospitalière (`calendar_year`,
    `hospital_nights`), calculé indépendamment des lignes microbiologiques.

ORCHIDEE construit ensuite les quatre fichiers canoniques internes :

-   `sir_wide.rds`
-   `sir_wide_meta.rds`
-   `sample_scope_reference.rds`
-   `denominator_bundle.rds`

Ces quatre fichiers constituent le contrat machine/runtime. Ils ne doivent pas
être construits à la main par le site externe.

## Commande de construction du bundle externe

Depuis la racine du dépôt :

```powershell
& 'C:\Program Files\R\R-4.5.2\bin\Rscript.exe' `
  scripts/build_external_bundle_from_site_inputs.R `
  <microbiology_observations.rds|csv|tsv> `
  <bacteria_mapping.rds|csv|tsv> `
  <sample_type_mapping.rds|csv|tsv> `
  <antibiotic_mapping.rds|csv|tsv> `
  <unit_mapping.rds|csv|tsv> `
  <denominator_by_year.rds|csv|tsv> `
  <output_bundle_dir> `
  [de_reference.rds|csv|tsv] `
  [--force]
```

Le script écrit le bundle canonique et lance la validation stricte. Pour le
détail exact des colonnes, consulter `documentation/external_bundle/`.

## Modèle opératoire actuel

Aujourd'hui, le chemin CHU fonctionne à partir d'artefacts internes canoniques
stockés dans `data/`.

En pratique, le workflow actuel est le suivant :

1.  construire ou réutiliser l'artefact microbiologique canonique ;
2.  construire ou réutiliser les artefacts de périmètre d'hospitalisation et
    de dénominateur ;
3.  calculer les jeux comparés et les indicateurs ;
4.  rendre les sorties destinées au lecteur.

Le point d'entrée microbiologique canonique est `data/sir_wide.rds`, accompagné
de son fichier de métadonnées `data/sir_wide_meta.rds`.

Autour de cet artefact, le workflow produit ensuite des artefacts intermédiaires
de périmètre hospitalier, de complétion et de dédoublonnage, qui servent à
calculer les indicateurs puis à alimenter le rapport.

Pour le détail de ces artefacts et de leur rôle exact, se reporter à
`documentation/project_map.md`.

Le notebook principal ne propose pas encore un mode d'exécution externe complet.
Le contrat externe est déjà exécutable jusqu'au bundle validé, et sert de
frontière stable pour brancher un autre établissement sans importer les détails
CHU dans le coeur partagé.

## Premiers documents à lire

Pour Rennes ou un autre site externe :

1.  `documentation/external_bundle/README.md`
2.  `documentation/external_bundle/site_handoff_inputs_v1.md`
3.  `documentation/external_bundle/canonical_inputs_v1.md`
4.  `documentation/external_bundle/sir_wide_v1.md`
5.  `documentation/external_bundle/sample_scope_reference_v1.md`
6.  `documentation/external_bundle/denominator_bundle_v1.md`

Pour la maintenance ORCHIDEE :

1.  `documentation/project_map.md`
2.  `documentation/maintenance_runbook.md`
3.  `documentation/ratb_implementation_decisions.qmd`
4.  `documentation/ratb_indicator_spec.csv`

## Points d'entrée principaux

-   `scripts/build_external_bundle_from_site_inputs.R`
    -   point d'entrée privilégié pour construire un bundle externe depuis les
        blocs fournis par un site ;
-   `scripts/validate_external_bundle.R`
    -   validateur autonome du bundle canonique ;
-   `scripts/smoke_external_runtime_inputs.R`
    -   vérifie qu'un bundle validé peut alimenter la frontière runtime
        ORCHIDEE ;
-   `orchidee_dedup_workflow.qmd`
    -   notebook socle du chemin CHU et des audits internes ;
-   `orchidee_ratb_indicators.qmd`
    -   rapport RATB orienté produit ;
-   `documentation/ratb_implementation_decisions.qmd`
    -   mémo méthodologique de référence pour le noyau gelé de l'étape 1.

## Répertoires clés

-   `R/`
    -   helpers R réutilisables, sourcés par les notebooks ou d'autres
        scripts R ;
-   `scripts/`
    -   points d'entrée en ligne de commande, dont le builder de bundle
        externe, les validateurs et le wrapper de rendu ;
-   `documentation/external_bundle/`
    -   contrat d'entrée pour Rennes ou un autre entrepôt ;
-   `config/`
    -   réglages opérationnels du pipeline : chemins, fenêtres de dates,
        politiques de recompute et paramètres d'affichage ;
-   `assets/`
    -   fichiers de présentation utilisés par les rendus Quarto ;
-   `rules/`
    -   emplacement réservé aux tables de règles analytiques maintenues par le
        projet ; aucune table active n'y est actuellement requise ;
-   `dictionaries/`
    -   dictionnaires de normalisation et de taxonomie / antibiotiques ;
-   `ref/`
    -   référentiels institutionnels importés, par exemple UF/UM et
        référentiels CONSORES TA/DE utilisés pour le périmètre RATB ;
-   `data/`
    -   artefacts internes canoniques et caches utilisés par le workflow CHU et
        le rapport ;
-   `downloads/`
    -   tableaux et figures exportés par le rapport d'indicateurs ;
-   `outputs/`
    -   espace local ignoré par Git pour brouillons, inspections et artefacts
        temporaires ; ne pas l'utiliser comme source canonique ;
-   `documentation/`
    -   mémo méthodologique, documentation du contrat externe, documents
        d'entrée et de référence ;
-   `archive/backups/`
    -   sauvegardes manuelles mises en quarantaine.

## Conseils immédiats de maintenance

-   Préférer le wrapper de rendu aux commandes `quarto render` lancées à la
    main.
-   Ne pas traiter les HTML rendus comme source de vérité.
-   Quand un rapport semble incorrect, commencer par déterminer si le problème
    vient :
    -   de la logique amont ou des données ;
    -   de la spec des indicateurs ;
    -   ou seulement de la couche de restitution.
-   Pour les rendus, la matrice de rerender et le dépannage courant, se reporter
    à `documentation/maintenance_runbook.md`.
