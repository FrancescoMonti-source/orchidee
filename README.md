---
editor_options:
  markdown:
    wrap: 80
---

# Orchidee

Orchidee est le dépôt de travail pour le workflow de résistance SPARES/RATB.

Le dépôt canonique est versionné sur GitHub :
`https://github.com/FrancescoMonti-source/orchidee`.

La copie de travail locale recommandée est `~/Documents/Git/orchidee`.
Les artefacts générés ou locaux (`data/`, `downloads/`, `outputs/`,
`archive/`) ne sont pas versionnés ; un clone frais ne contient donc pas les
caches, les exports ou les rendus locaux.

Ce dépôt a actuellement 3 publics principaux :

-   maintenance du pipeline
-   production des rapports et livrables
-   discussion méthodologique avec SPF

## Modèle opératoire actuel

Aujourd'hui, le dépôt fonctionne à partir d'artefacts internes canoniques stockés dans `data/`.

En pratique, le workflow actuel est le suivant :

1.  construire ou réutiliser l'artefact microbiologique canonique,
2.  construire ou réutiliser les artefacts de périmètre
    d'hospitalisation et de dénominateur,
3.  calculer les jeux comparés et les indicateurs,
4.  rendre les sorties destinées au lecteur.

Le rendu est donc une étape aval. Un nouveau mainteneur doit d'abord comprendre à partir de quels artefacts le workflow démarre et quels documents expliquent la structure du projet.

Concrètement, le point d'entrée microbiologique canonique est `data/sir_wide.rds`, accompagné de son fichier de métadonnées `data/sir_wide_meta.rds`.

Autour de cet artefact, le workflow produit ensuite des artefacts intermédiaires de périmètre hospitalier, de complétion et de dédoublonnage, qui servent à calculer les indicateurs puis à alimenter le rapport.

Pour le détail de ces artefacts et de leur rôle exact, se reporter à `documentation/project_map.md`.

Pour une réutilisation future par d'autres établissements, un contrat
externe d'entrée est documenté dans `documentation/external_bundle/`. Le
chemin CHU actuel produit les objets canoniques de périmètre et de
dénominateur, puis le notebook les applique via la frontière canonique
partagée, sans être encore un mode d'exécution externe complet.

## Premiers documents à lire pour la reprise

1.  `documentation/project_map.md`
2.  `documentation/maintenance_runbook.md`
3.  `documentation/external_bundle/README.md`
4.  `documentation/ratb_implementation_decisions.qmd`

## Points d'entrée principaux

-   `orchidee_dedup_workflow.qmd`
    -   notebook socle
    -   stratégies de complétion, dédoublonnage, dénominateur en nuits
        d'hospitalisation, tables de QA
-   `orchidee_ratb_indicators.qmd`
    -   rapport RATB orienté produit
    -   tableaux finaux, heatmaps, section phénotypes
-   `documentation/ratb_implementation_decisions.qmd`
    -   source méthodologique de référence pour les choix
        d'implémentation
-   `documentation/ratb_meeting_prep_spf.qmd`
    -   note de support pour les échanges avec SPF

## Répertoires clés

-   `R/`
    -   helpers R réutilisables, sourcés par les notebooks ou d'autres
        scripts R
-   `scripts/`
    -   points d'entrée en ligne de commande, exécutés directement depuis
        le shell
    -   par exemple le wrapper de rendu et le validateur autonome du
        bundle externe
-   `config/`
    -   réglages opérationnels du pipeline : chemins, fenêtres de dates,
        politiques de recompute et paramètres d'affichage
-   `assets/`
    -   fichiers de présentation utilisés par les rendus Quarto
-   `rules/`
    -   emplacement réservé aux tables de règles analytiques maintenues
        par le projet ; aucune table active n'y est actuellement requise
-   `dictionaries/`
    -   dictionnaires de normalisation et de taxonomie / antibiotiques
-   `ref/`
    -   référentiels institutionnels importés, par exemple UF/UM et
        référentiels CONSORES TA/DE utilisés pour le périmètre RATB
-   `data/`
    -   artefacts internes canoniques et caches utilisés par le workflow
        et le rapport
-   `downloads/`
    -   tableaux et figures exportés par le rapport d'indicateurs
-   `outputs/`
    -   espace local ignoré par Git pour brouillons, inspections et
        artefacts temporaires ; ne pas l'utiliser comme source canonique
-   `documentation/`
    -   mémo, note de réunion, documentation du contrat externe,
        documents d'entrée et de référence
-   `archive/backups/`
    -   sauvegardes manuelles mises en quarantaine

## Contrat du bundle externe

La documentation de l'externalisation future se trouve dans `documentation/external_bundle/` :

-   `documentation/external_bundle/README.md`
-   `documentation/external_bundle/site_handoff_inputs_v1.md`
-   `documentation/external_bundle/canonical_inputs_v1.md`
-   `documentation/external_bundle/sir_wide_v1.md`
-   `documentation/external_bundle/sample_scope_reference_v1.md`
-   `documentation/external_bundle/denominator_bundle_v1.md`
-   validateur : `scripts/validate_external_bundle.R`

Cette couche documente le futur contrat d'entrée pour un autre établissement.
Elle sert déjà de frontière interne pour le périmètre et le dénominateur : le
chemin CHU produit les objets canoniques et le notebook les consomme pour
construire les entrées RATB aval. Le notebook principal ne propose toutefois
pas encore un mode d'exécution externe complet.

Pour un échange avec un autre établissement, le point d'entrée le plus lisible
est `site_handoff_inputs_v1.md` : il décrit les blocs élémentaires à fournir
avant que ORCHIDEE ne dérive le bundle canonique utilisé par le runtime. Le
script `scripts/build_external_bundle_from_site_inputs.R` construit ce bundle
depuis les observations microbiologiques longues, les dictionnaires locaux, le
mapping UF/TA-DE et le dénominateur annuel.

## Conseils immédiats de maintenance

-   Préférer le wrapper de rendu aux commandes `quarto render` lancées à la main.
-   Ne pas traiter les HTML rendus comme source de vérité.
-   Quand un rapport semble incorrect, commencer par déterminer si le problème vient :
    -   de la logique amont ou des données
    -   de la spec des indicateurs
    -   ou seulement de la couche de restitution
-   Pour les rendus, la matrice de rerender et le dépannage courant, se reporter à `documentation/maintenance_runbook.md`.

