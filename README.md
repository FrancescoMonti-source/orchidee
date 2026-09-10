---
editor_options:
  markdown:
    wrap: 80
---

# Orchidee

Deux parcours d'entrée (standard vs Rouen) mènent au même rapport. Suivre uniquement le sien.

## Prérequis et installation

Windows ou Linux, avec Git, Python 3.8 ou plus récent et Quarto. La version de
R et les dépendances sont imposées par `renv.lock`. R 4.5.3 est la version de
référence déclarée dans le verrou. Pour les environnements disposant déjà d'une
version R récente (R 4.3.x ou 4.4.x), positionner la variable d'environnement
`ORCHIDEE_ALLOW_R_MISMATCH=1` (ou spécifier directement le binaire via
`ORCHIDEE_R=/chemin/vers/Rscript`) permet d'exécuter le projet sans blocage.
PowerShell n'est pas requis.
Dans les commandes ci-dessous, remplacer `python` par `python3` si le système
expose ainsi son interpréteur Python 3. Depuis la racine d'un clone frais :

```console
python scripts/orchidee.py setup
```

Pour vérifier une installation sur la fixture synthétique versionnée :

```console
python scripts/orchidee.py site --run-smoke-test
```

Ce smoke test qualifie l'installation en validant la chaîne complète, sans
ouvrir vos données. Pour exécuter la suite de tests unitaires :

```console
python scripts/orchidee.py run-r tests/run_tests.R
```

## Parcours standard (Rennes et sites partenaires sans adaptateur dédié)

**Votre guide complet est ici :
[documentation/site_contract.md](documentation/site_contract.md).** Il donne le
nom et la structure attendue de chaque fichier, les modèles à remplir et les
commandes de vérification puis de calcul.

Vous fournissez les résultats de microbiologie, les mouvements hospitaliers
et les correspondances entre votre vocabulaire local et celui d'ORCHIDEE.
Votre équipe les extrait de ses propres systèmes et enregistre six blocs
distincts (fichiers CSV ou RDS) :

1. `microbiology_observations` : résultats de microbiologie (prélèvement, bactérie,
   antibiotique, résultat S/I/R et indication diagnostic ou dépistage) ;
2. `bacteria_mapping` : traduction de vos noms de bactéries vers les noms ORCHIDEE ;
3. `sample_type_mapping` : traduction de vos types de prélèvement ;
4. `antibiotic_mapping` : traduction de vos noms d'antibiotiques ;
5. `unit_mapping` : correspondance entre vos unités d'hospitalisation et les codes TA/DE ;
6. `hospitalization_intervals` : séjours d'hospitalisation (une ligne par passage
   ininterrompu dans une unité, y compris les séjours sans microbiologie).

Vous transmettez ce que vous détenez : des résultats, des correspondances et
des séjours. Vous ne calculez pas de dénominateur et n'indiquez pas l'unité
d'un prélèvement. ORCHIDEE possède l'attribution des prélèvements aux unités,
le comptage des nuits et le périmètre, pour que ces décisions soient les mêmes
d'un établissement à l'autre. Vous déclarez en revanche la période analysée,
de la première à la dernière année incluse, la même à chaque étape.

### Documents de référence

| Pour | Lire |
|---|---|
| Le contrat : chaque fichier, chaque colonne, chaque commande | [`site_contract.md`](documentation/site_contract.md) |
| Un exemple travaillé : quatre séjours inventés, les chiffres attendus | [`examples/site_handoff_worked/`](examples/site_handoff_worked/README.md) |
| Un fichier de lancement à copier et remplir | [`examples/run_site_handoff.py`](examples/run_site_handoff.py) |

### Déroulement en 3 stades

Le traitement s'exécute en 3 stades successifs via [`examples/run_site_handoff.py`](examples/run_site_handoff.py)
(ou directement avec la commande `orchidee.py site`) :

1. **Diagnostics (`diagnostics`)** : contrôle la conformité des six fichiers avec
   le contrat d'entrée, sans rien construire. Corriger les éventuels constats
   `BLOCKING` signalés dans le rapport avant de continuer.
2. **Build (`build`)** : relance les contrôles, réconcilie les séjours, effectue
   l'attribution des prélèvements et construit les bundles d'entrée internes.
3. **Rapport (`report`)** : calcule les indicateurs RATB à partir du build validé
   et produit le rapport HTML autonome `orchidee_ratb_indicators.html`.

Pour générer des modèles CSV vierges et le dictionnaire des cibles reconnues
dans un dossier dédié :

```console
python scripts/orchidee.py site --emit-templates "data/mon_etablissement"
```

Pour lancer les étapes : copier [`examples/run_site_handoff.py`](examples/run_site_handoff.py)
dans votre dossier de travail, configurer vos chemins et vos années d'analyse, puis exécuter :

```console
python run_site_handoff.py --stage diagnostics
python run_site_handoff.py --stage build
python run_site_handoff.py --stage report
```
*(ou renseigner la variable `STAGE` dans le script et lancer `python run_site_handoff.py`).*

## Parcours Rouen (Adaptateur BACT / PMSI)

L'adaptateur Rouen, ses mappings et ses références sont intégrés au dépôt
(notamment `R/rouen_microbiology_handoff_adapter.R`,
`R/rouen_pmsi_handoff_adapter.R`, `ref/rouen/` et `mappings/`) : un run
ordinaire ne demande de préparer ni configuration ni correspondance.

Il requiert deux chemins : l'export bactériologie (`--bact`) et l'export PMSI
(`--pmsi`) produit par `redsan`.

Le build traduit ces deux exports dans les six blocs de construction internes,
puis en dérive les bundles. Pour le détail d'architecture, la structure des
sorties et la mécanique interne des bundles (`v3` vs `v2`), consulter
[`documentation/rouen_handoff.md`](documentation/rouen_handoff.md).

### 1. Contrôler les deux chemins

```console
python scripts/orchidee.py rouen --bact "C:\protected\bact22_24" --pmsi "C:\protected\pmsi" --dry-run
```

`--dry-run` vérifie les chemins, l'environnement R verrouillé et les paquets
requis sans ouvrir les objets cliniques. Attendre le `PASS`.

### 2. Lancer le build

```console
python scripts/orchidee.py rouen --bact "C:\protected\bact22_24" --pmsi "C:\protected\pmsi" > build.log 2>&1
```

Il peut durer une vingtaine de minutes et rester silencieux. La redirection
vers `build.log` conserve le déroulé complet, le `PASS` final et la commande de
rendu.

Une exécution réussie finit par `PASS` et écrit `build_manifest.txt` : sans ce
fichier, ne pas utiliser la sortie.

La sortie par défaut est `outputs/rouen_current` ; `--output` accepte un autre
répertoire dédié. Le build refuse d'écrire par-dessus une sortie existante sans `--force`.

### 3. Calculer les indicateurs

Le build affiche en dernière ligne la commande de rendu, avec les chemins de ce
build déjà résolus :

```console
python scripts/orchidee.py render --rebuild --bundle "outputs/rouen_current/bundle_v2_operational" --workspace "outputs/rouen_current/runtime"
```

Le rapport lui-même est écrit à la racine du dépôt,
`orchidee_ratb_indicators.html` ; c'est un fichier autonome, qui s'ouvre dans
un navigateur et se transmet tel quel.

Pour les détails d'architecture et l'archive `v3`, voir
[`documentation/rouen_handoff.md`](documentation/rouen_handoff.md).

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
| Quel contrat chaque test protège-t-il, et pour quel établissement ? | [`test_inventory.md`](documentation/test_inventory.md) |

La méthode et le périmètre publiés ne changent qu'après une décision explicite
et la vérification correspondante.
