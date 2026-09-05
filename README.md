---
editor_options:
  markdown:
    wrap: 80
---

# Orchidee

Deux parcours d'entrée (Rouen vs "autres") mènent au même rapport. Suivre uniquement le sien.

## Prérequis et installation

Windows ou Linux, avec Git, Python 3.8 ou plus récent et Quarto. La version de
R et les dépendances sont imposées par `renv.lock`. Installer R 4.5.3
avant de lancer `setup`, qui installe les paquets R du projet. PowerShell n'est pas requis.
Dans les commandes ci-dessous, remplacer `python` par `python3` si le système
expose ainsi son interpréteur Python 3. Depuis la racine d'un clone frais :

```console
python scripts/orchidee.py setup
```

Pour vérifier une installation :

```console
python scripts/orchidee.py run-r tests/run_tests.R
```

## Rouen

L'adaptateur Rouen, ses mappings et ses références sont versionnés dans le
dépôt : un run ordinaire ne demande de préparer ni configuration ni
correspondance. Il y a deux chemins à fournir, l'export bactériologie et
l'export PMSI produit par `redsan`, et trois commandes à lancer.

Le build traduit ces deux exports dans les six blocs de construction internes,
puis en dérive les bundles. Un bundle est un répertoire de quatre fichiers
validés : la microbiologie, sa description, le périmètre des unités et le
dénominateur. Ces quatre fichiers sont tout ce que le calcul des indicateurs a
besoin de savoir de l'établissement ; le vocabulaire local n'y apparaît plus.

Les deux parcours produisent les mêmes six blocs internes, par des chemins
différents : Rouen les dérive de BACT et PMSI, un autre établissement les
dérive des six fichiers qu'il transmet. C'est le point de rencontre : après le
build, Rouen suit exactement le même chemin que les autres. Le calcul des indicateurs est une
étape distincte, à ne lancer que si le rapport doit être produit sur cette
machine.

### 1. Contrôler les deux chemins

```console
python scripts/orchidee.py rouen --bact "C:\protected\bact22_24" --pmsi "C:\protected\pmsi" --dry-run
```

`--dry-run` vérifie les chemins, l'environnement R verrouillé et les paquets
requis sans ouvrir les objets cliniques. Attendre le `PASS`.

### 2. Lancer le build

La même commande sans `--dry-run` :

```console
python scripts/orchidee.py rouen --bact "C:\protected\bact22_24" --pmsi "C:\protected\pmsi" > build.log 2>&1
```

Il peut durer une vingtaine de minutes et rester silencieux. Sans la
redirection vers `build.log`, un échec affiche sa cause à l'écran et ne la laisse
dans aucun fichier ; avec elle, le déroulé complet, le `PASS` final et la
commande de rendu de l'étape 3 se lisent dans `build.log` plutôt qu'à l'écran.

Une exécution réussie finit par `PASS` et écrit `build_manifest.txt` : sans ce
fichier, ne pas utiliser la sortie.

La sortie par défaut est `outputs/rouen_current` ; `--output` accepte un autre
répertoire dédié, y compris protégé hors du dépôt. Le build refuse d'écrire
par-dessus une sortie existante : pour un nouveau millésime de données, donner
un `--output` distinct — les deux builds restent alors côte à côte et
comparables — ou ajouter `--force` pour remplacer la sortie précédente.

Ce que contient la sortie :

| Chemin | Rôle |
|---|---|
| `site_inputs/` | Les six blocs de construction internes : les deux exports traduits dans le format commun dont les bundles sont dérivés. |
| `bundle_v3/` | Tout le détail conservé : l'exposition hospitalière au grain fin, y compris l'activité hors périmètre RATB. C'est l'archive de référence de ce build, à conserver. |
| `bundle_v2_operational/` | Le dénominateur déjà réduit au total annuel du seul périmètre publié. C'est la seule entrée de l'étape 3. |
| `adapter_audit.rds` | Trace interne du build ; aucune action à faire dessus. |

`v3` et `v2` ne sont ni deux versions successives ni un ancien et un nouveau
format : le même build produit les deux à partir des mêmes blocs. La
microbiologie y est identique ; ce qui change est le dénominateur. `v3` garde
l'exposition au grain fin — année, UM, UF, TA, DE — et les colonnes qui disent
quelle unité entre dans le périmètre et pourquoi ; `v2` en tire le total de
nuits d'hospitalisation par année, pour le seul périmètre publié aujourd'hui.
On recalcule un `v2` depuis un `v3`, jamais l'inverse : c'est pour cela que
`v3` se conserve. Un run ordinaire n'a rien à choisir entre les deux.

Si l'objectif est seulement de transmettre les données, s'arrêter ici.

### 3. Calculer les indicateurs

Le build affiche en dernière ligne la commande de rendu, avec les chemins de ce
build déjà résolus. La copier telle quelle ; elle a cette forme :

```console
python scripts/orchidee.py render --rebuild --bundle "outputs/rouen_current/bundle_v2_operational" --workspace "outputs/rouen_current/runtime"
```

Les deux chemins disent où lire et où écrire :

- `--bundle` est ce que le rapport lit : le `bundle_v2_operational/` de l'étape
  2. Le passer explicitement, plutôt que de compter sur la valeur par défaut,
  évite de calculer les indicateurs sur le bundle d'un run précédent.
- `--workspace` est le répertoire de travail du rendu ; il n'a pas besoin
  d'exister, le rendu le crée. Il reçoit `cache/`, les calculs intermédiaires
  réutilisés d'un rendu à l'autre, et `downloads/`, les tableaux exportables du
  rapport. Son contenu dérive des données cliniques : le garder à côté du
  build, comme le fait la commande affichée, garde un millésime complet au même
  endroit et sous les mêmes règles de protection.

`--rebuild` n'est pas obligatoire : chaque rendu compare son cache de calcul au
bundle demandé et au code qui l'a produit, et le reconstruit dès que l'un des
deux a changé. Le laisser ne coûte rien de plus qu'une reconstruction certaine.

Le rapport lui-même est écrit à la racine du dépôt,
`orchidee_ratb_indicators.html` ; c'est un fichier autonome, qui s'ouvre dans
un navigateur et se transmet tel quel.

## Autre établissement

**Votre parcours est ici :
[documentation/site_contract.md](documentation/site_contract.md).** Il donne le
nom et la structure attendue de chaque fichier, les modèles à remplir et les
commandes de vérification puis de calcul. Tout ce qui suit dans cette page en
est le résumé.

Vous fournissez les résultats de microbiologie, les mouvements hospitaliers
et les correspondances entre votre vocabulaire local et celui d'ORCHIDEE.
Votre équipe les extrait de ses propres systèmes et les enregistre séparément :

1.  les résultats de microbiologie : prélèvement, bactérie, antibiotique,
    résultat S/I/R et indication diagnostic ou dépistage ;
2.  la traduction de vos noms de bactéries vers les noms ORCHIDEE ;
3.  la traduction de vos types de prélèvement ;
4.  la traduction de vos noms d'antibiotiques ;
5.  la correspondance entre vos unités d'hospitalisation et les codes TA/DE ;
6.  les séjours d'hospitalisation, une ligne par passage ininterrompu dans une
    unité, y compris les séjours sans microbiologie.

Ces fichiers peuvent être des CSV ou des objets RDS.

Vous transmettez ce que vous détenez : des résultats, des correspondances et
des séjours. Vous ne calculez pas de dénominateur et n'indiquez pas l'unité
d'un prélèvement. ORCHIDEE possède l'attribution des prélèvements aux unités,
le comptage des nuits et le périmètre, pour que ces décisions soient les mêmes
d'un établissement à l'autre. Vous déclarez en revanche la période analysée,
de la première à la dernière année incluse, la même à chaque étape.

Trois documents, dans cet ordre :

| Pour | Lire |
|---|---|
| Le contrat : chaque fichier, chaque colonne, chaque commande | [`site_contract.md`](documentation/site_contract.md) |
| Un exemple travaillé : quatre séjours inventés, les chiffres attendus | [`examples/site_handoff_worked/`](examples/site_handoff_worked/README.md) |
| Un fichier de lancement à copier et remplir | [`examples/run_site_handoff.py`](examples/run_site_handoff.py) |

Avant d'introduire des données locales, vérifier l'installation sur la fixture
synthétique versionnée :

```console
python scripts/orchidee.py site --run-smoke-test
```

Ce smoke test qualifie l'installation, pas vos données.

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
