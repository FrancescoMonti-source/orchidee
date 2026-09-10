---
editor_options:
  markdown:
    wrap: 80
---

# Parcours Rouen : adaptateur BACT / PMSI et mécanique interne des bundles

Ce document détaille l'adaptateur historique de Rouen, la structure des sorties
produites par la commande `orchidee.py rouen`, et les relations entre les formats
de bundles `v3` et `v2`.

Pour une prise en main rapide ou pour les autres établissements, voir :
- Le [README](../README.md) principal pour une vue d'ensemble des deux parcours ;
- Le [contrat d'entrée standard (site_contract.md)](site_contract.md) pour les
  établissements sans adaptateur dédié (Rennes et partenaires).

---

## 1. Rôle de l'adaptateur Rouen

L'adaptateur Rouen est versionné directement dans le dépôt
(notamment `R/rouen_microbiology_handoff_adapter.R`,
`R/rouen_pmsi_handoff_adapter.R`, `ref/rouen/` et `mappings/`).
Ses règles de mapping et ses tables de référence locales sont intégrées :
un run ordinaire ne demande de préparer ni fichier de configuration ni
correspondance manuelle.

L'adaptateur prend en entrée deux chemins :
1. L'export bactériologie (`--bact`), issu des systèmes microbiologiques locaux ;
2. L'export PMSI (`--pmsi`), produit par `redsan`.

Le build traduit ces deux exports dans les **six blocs de construction communs**
d'ORCHIDEE (microbiologie, correspondances et séjours d'hospitalisation), puis
construit les bundles validés.

---

## 2. Commandes d'exécution

### Étape 1 : Contrôle préalable

```console
python scripts/orchidee.py rouen --bact "C:\protected\bact22_24" --pmsi "C:\protected\pmsi" --dry-run
```

`--dry-run` vérifie la présence des fichiers, l'environnement R verrouillé et
les paquets requis sans charger l'intégralité des données cliniques. Attendre
le verdict `PASS`.

### Étape 2 : Lancement du build

```console
python scripts/orchidee.py rouen --bact "C:\protected\bact22_24" --pmsi "C:\protected\pmsi" > build.log 2>&1
```

Le traitement peut durer une vingtaine de minutes selon le volume de séjours.
La redirection vers `build.log` permet de conserver la trace complète des
contrôles, le `PASS` final et la commande de rendu suggérée.

Une exécution réussie écrit un fichier de complétion `build_manifest.txt` dans
chaque bundle : sans ce marqueur valide, la sortie ne doit pas être exploitée.

La sortie par défaut est `outputs/rouen_current`. Pour préserver un historique
ou isoler les données protégées hors du dépôt, spécifier un dossier avec
`--output` :

```console
python scripts/orchidee.py rouen --bact "C:\protected\bact22_24" --pmsi "C:\protected\pmsi" --output "D:\ORCHIDEE\rouen_2024"
```

Le build refuse d'écraser une sortie complète existante. Pour remplacer une
sortie précédente après révision, ajouter `--force`.

### Étape 3 : Calcul des indicateurs et rendu du rapport

Le build affiche en dernière ligne la commande exacte de rendu à exécuter :

```console
python scripts/orchidee.py render --rebuild --bundle "outputs/rouen_current/bundle_v2_operational" --workspace "outputs/rouen_current/runtime"
```

- `--bundle` pointe vers le bundle opérationnel `v2` issu du build ;
- `--workspace` reçoit le cache de calcul et les tableaux exportables dans
  `downloads/` ;
- Le rapport HTML final autonome `orchidee_ratb_indicators.html` est écrit à la
  racine du dépôt.

---

## 3. Structure détaillée du répertoire de sortie

Un build Rouen réussi produit l'arborescence suivante :

| Répertoire ou fichier | Rôle et contenu |
|---|---|
| `site_inputs/` | Les six blocs de construction internes : les deux exports BACT et PMSI traduits dans le format canonique commun d'ORCHIDEE, exactement identique aux six blocs transmis par les sites partenaires. |
| `bundle_v3/` | Archive durable de référence. Conserve l'exposition hospitalière au grain fin (année, UM, UF, TA, DE) pour l'ensemble de l'activité, y compris hors périmètre RATB. |
| `bundle_v2_operational/` | Projection fermée `spares_current`. Le dénominateur est réduit au total annuel de journées pour le seul périmètre RATB publié. C'est l'unique entrée requise par le moteur de rapport Quarto. |
| `adapter_audit.rds` | Audit interne du build Rouen, traçant les résolutions et exclusions d'enregistrements. Usage diagnostique interne ; aucune action requise de l'opérateur. |
| `build_manifest.txt` | Marqueur d'intégrité et de complétion contenant l'identifiant unique du build (`build_id`), la date et le hash de validation. |

---

## 4. Mécanique interne : Bundle v3 vs Bundle v2 opérationnel

`bundle_v3` et `bundle_v2_operational` ne sont **pas deux versions successives**
d'un format obsolète et d'un nouveau format : **le même build produit les deux
simultanément à partir des mêmes blocs**.

### Similitudes
- Les données de microbiologie (`microbiology.rds` ou CSV équivalent) et leurs
  dictionnaires descriptifs sont **strictement identiques** dans les deux
  bundles.
- Tous les libellés locaux ont été résolus vers les cibles canoniques d'ORCHIDEE.

### Différences (Le dénominateur)
- **`bundle_v3` (archive durable)** :
  Conserve l'exposition hospitalière avec toutes ses dimensions fines :
  année, UM (Unité Médicale), UF (Unité Fonctionnelle), code TA (Discipline),
  code DE (Domaine d'Activité). Il documente explicitement pourquoi chaque
  unité entre ou non dans le périmètre RATB national (`included_in_spares_current`).
- **`bundle_v2_operational` (entrée du rapport)** :
  Applique la projection fermée `spares_current` : il agrège les journées
  d'hospitalisation par année pour les seules unités répondant aux critères du
  périmètre RATB publié aujourd'hui. C'est ce dénominateur consolidé qui
  alimente le rapport.

### Règle de dérivation
On peut toujours recalculer un `v2` à partir d'un `v3` si les règles du
périmètre national évoluent, mais **jamais l'inverse**. Pour cette raison,
`bundle_v3` constitue l'archive de référence à conserver précieusement pour
chaque millésime.
