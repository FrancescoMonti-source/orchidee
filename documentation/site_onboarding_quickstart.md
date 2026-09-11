# Guide de démarrage rapide : intégration d'un site partenaire

Ce guide décrit en 5 étapes simples la mise en place et l'exécution du pipeline
ORCHIDEE pour un établissement hospitalier partenaire (sans adaptateur local
prédéfini).

Pour les détails exhaustifs sur chaque colonne, les formats de date et la
matrice de responsabilités, consulter le document de référence :
[Contrat technique d'intégration (site_contract.md)](site_contract.md).

---

## 1. Principe général

ORCHIDEE standardise la chaîne de production des indicateurs de résistance aux
antibiotiques (RATB / SPARES) en séparant strictement les responsabilités :

1. **L'établissement** fournit exactement **6 blocs de transmission** (fichiers
   CSV ou RDS) : 2 extractions de données sources (microbiologie, mouvements
   d'hospitalisation) et 4 tables de correspondance locales.
2. **ORCHIDEE** prend en charge tous les traitements complexes : attribution
   automatique des prélèvements à l'unité hébergeant le patient à l'heure du
   prélèvement, découpage des nuits par unité et année civile, exclusion du
   dépistage, filtrage selon le périmètre officiel (TA 03/20), et calcul des
   taux d'incidence.

---

## 2. Prérequis & Installation

### A. Python et R

* **Python 3.8+** doit être installé.
* **R 4.3+** doit être installé (R 4.5.3 recommandé).
  * *Note compatibilité :* Si votre environnement dispose d'une version de R
    différente de celle verrouillée dans `renv.lock` (ex. R 4.3.x ou 4.4.x),
    définissez la variable d'environnement :
    ```bash
    # Windows (PowerShell) :
    $env:ORCHIDEE_ALLOW_R_MISMATCH = "1"
    # Linux / macOS :
    export ORCHIDEE_ALLOW_R_MISMATCH=1
    ```
    Si `Rscript` n'est pas dans votre `PATH`, vous pouvez également spécifier son
    chemin complet :
    ```bash
    $env:ORCHIDEE_R = "C:\Program Files\R\R-4.4.2\bin\Rscript.exe"
    ```

### B. Initialisation et test d'installation

Depuis la racine du dépôt :

```bash
# Restauration des dépendances R (renv)
python scripts/orchidee.py setup

# Qualification de l'installation (smoke test synthétique)
python scripts/orchidee.py site --run-smoke-test
```
Le message `PASS: site handoff build...` confirme que l'environnement est
opérationnel.

---

## 3. Étape par étape

### Étape 1 — Générer les modèles vierges

Créez un dossier propre pour votre établissement et émettez les modèles :

```bash
python scripts/orchidee.py site --emit-templates "data/mon_etablissement"
```

Cette commande crée :
- Les 6 fichiers CSV d'entrée avec leurs en-têtes officiels ;
- Le sous-dossier `mapping_reference/` contenant les dictionnaires de référence
  (bactéries cibles, antibiotiques supportés, codes TA et DE autorisés).

### Étape 2 — Remplir les 6 blocs

Renseignez les fichiers dans votre dossier `data/mon_etablissement/` :

| Bloc | Fichier | Contenu |
|---|---|---|
| **1. Microbiologie** | `microbiology_observations.csv` | Résultats d'antibiogrammes (unitaire par bactérie, prélèvement et antibiotique). *Important : ne transmettre que les antibiotiques listés dans `mapping_reference/supported_atb_norm.csv` ; filtrer les autres molécules en amont.* |
| **2. Correspondance bactéries** | `bacteria_mapping.csv` | Mappe vos libellés de germes locaux vers les taxons `bact_norm`. |
| **3. Correspondance prélèvements** | `sample_type_mapping.csv` | Mappe vos types de prélèvements vers `hemoculture`, `urines` ou vide. |
| **4. Correspondance antibiotiques** | `antibiotic_mapping.csv` | Mappe vos libellés de molécules vers `atb_norm`. |
| **5. Correspondance unités** | `unit_mapping.csv` | Associe vos unités fonctionnelles (`SEJUF`) aux codes PMSI `CODE_TA` (03, 20...), `CODE_DE` et domaines (`MÉDECINE`, `CHIRURGIE`, etc.). |
| **6. Mouvements d'hospitalisation** | `hospitalization_intervals.csv` | Intervalles de présence continue en unité `[DATENT, DATSORT)`. |

> [!TIP]
> Un exemple clinique complet et documenté est disponible dans
> [`examples/site_handoff_worked/`](../examples/site_handoff_worked/README.md).

> [!NOTE]
> **Recommandations pratiques pour l'extraction :** Pour les solutions concrètes aux
> situations fréquentes en entrepôt hospitalier (filtrage des molécules hors catalogue
> pour préserver la déduplication SPARES, heure de prélèvement au laboratoire,
> micro-chevauchements de transferts), consultez les
> [Recommandations pratiques pour l'ETL hospitalier](site_contract.md#recommandations-pratiques-pour-letl-hospitalier).

### Étape 3 — Configurer le lanceur

Copiez le script modèle `examples/run_site_handoff.py` :

```bash
cp examples/run_site_handoff.py mon_etablissement_runner.py
```

Dans `mon_etablissement_runner.py`, ajustez les réglages :
- `INPUT_DIR = r"data/mon_etablissement"` (ou spécifiez les fichiers dans `SITE_INPUTS`) ;
- `OUTPUT_DIR = r"outputs/mon_etablissement"` ;
- `START_YEAR = 2024` et `END_YEAR = 2024`.

---

## 4. Les 3 Stades d'Exécution

Le script s'exécute en 3 stades progressifs à l'aide de l'argument `--stage` :

### Stade 1 : Diagnostics (`--stage diagnostics`)

```bash
python mon_etablissement_runner.py --stage diagnostics
```
* **Ce qu'il fait :** Contrôle la présence des fichiers, la validité des colonnes,
  l'absence de valeurs non mappées, la cohérence des identifiants et l'absence de
  conflits de souches.
* **Sécurité :** Aucun calcul lourd, aucune écriture dans les répertoires de build.
* **Résultat :** Un rapport détaillé est produit dans `outputs/mon_etablissement/diagnostics/`.
  Si des constats `BLOCKING` apparaissent, corrigez vos fichiers sources et
  relancez jusqu'à obtenir `0 BLOCKING`.

### Stade 2 : Construction des bundles (`--stage build`)

```bash
python mon_etablissement_runner.py --stage build
```
* **Ce qu'il fait :** Relance automatiquement le diagnostic de sécurité, attribue
  chaque prélèvement à son unité d'hébergement, découpe les nuits par année,
  puis assemble deux bundles standardisés :
  - `bundle_v3/` : Archive complète et durable de toutes les activités déclarées.
  - `bundle_v2_operational/` : Projection stricte sur le périmètre publié (TA 03 et 20).
* **Validation :** Valide la conformité structurelle des bundles avant de conclure.

### Stade 3 : Calcul des indicateurs et rapport (`--stage report`)

```bash
python mon_etablissement_runner.py --stage report
```
* **Ce qu'il fait :** Compile le rapport Quarto complet à partir du bundle opérationnel.
* **Livrable :** Le rapport HTML autonome est généré directement dans votre dossier :
  `outputs/mon_etablissement/orchidee_ratb_indicators.html`.

---

## 5. Inspection des Livrables

Après achèvement des trois stades, votre dossier de sortie contient :

```text
outputs/mon_etablissement/
├── diagnostics/
│   ├── site_input_diagnostics.txt   # Synthèse textuelle de conformité
│   ├── findings.csv                 # Liste détaillée des constats (BLOCKING, WARNING, INFO)
│   ├── label_coverage.csv           # Taux de couverture des correspondances locales
│   └── unit_coverage.csv            # Répartition des unités dans le périmètre
├── bundle_v3/                       # Données complètes transmises (format RDS)
│   └── build_manifest.txt
├── bundle_v2_operational/           # Données prêtes pour le moteur de calcul RATB
│   └── build_manifest.txt
├── runtime/                         # Caches et calculs intermédiaires
└── orchidee_ratb_indicators.html    # Rapport final interactif pour l'équipe clinique
```

Pour approfondir les règles de gestion (identifiants, chevauchements, fuseaux
horaires, RACI), consultez [`documentation/site_contract.md`](site_contract.md).
