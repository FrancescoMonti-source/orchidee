---
editor_options:
  markdown:
    wrap: 72
---

# Données à préparer dans un autre établissement

Cette procédure concerne Rennes et tout établissement qui n'a pas d'adaptateur
ORCHIDEE versionné. Elle décrit ce qu'ORCHIDEE attend en entrée. Chaque
établissement reste libre de décider comment produire ces données depuis ses
propres systèmes.

Pour Rouen, ne pas suivre cette procédure : fournir uniquement les chemins BACT
et PMSI, comme décrit dans la section Rouen du [README](../README.md).

Cette procédure requiert Python 3.8 ou plus récent, sur Linux comme sur
Windows. Les commandes emploient `python` ; utiliser `python3` si c'est le nom
du lanceur installé.

## Commencer ici

Votre travail consiste à extraire les données locales et à préparer les
correspondances. ORCHIDEE attribue les prélèvements aux unités, compte les
nuits et calcule les indicateurs. Vous pouvez suivre ce parcours sans connaître
le fonctionnement de Rouen.

### 1. Vérifier que les données sont disponibles

Lire d'abord [l'exemple commenté](../examples/site_handoff_worked/README.md).
Il montre quatre séjours inventés, les fichiers d'entrée et les résultats attendus.
Vérifier dans vos sources :

- des résultats de microbiologie avec date et heure du prélèvement et indication
  diagnostic ou dépistage ;
- les mouvements entre unités avec leurs dates et heures d'entrée et de sortie,
  y compris pour les hospitalisations sans microbiologie ;
- les mêmes identifiants de patient et de séjour dans les deux extractions.

Si ces liens ou ces horaires ne sont pas disponibles, établir ce point avec
l'équipe ORCHIDEE avant de préparer l'extraction complète.

### 2. Installer et essayer avec des données inventées

Récupérer le dépôt ORCHIDEE depuis l'accès transmis par l'équipe du projet.
Sur Windows ou Linux, installer Git, Python 3.8 ou plus récent, Quarto et
**R 4.5.3** (version déclarée dans `renv.lock`). Ouvrir un terminal dans le
dossier du dépôt, celui qui contient `README.md` et `scripts/`.
Toutes les commandes ci-dessous se lancent depuis ce dossier.

```console
python scripts/orchidee.py setup
```

`setup` installe les bibliothèques R aux versions prévues par le projet, dans
une bibliothèque dédiée, puis vérifie leur installation. Il demande un accès
aux sources de paquets et peut prendre plusieurs minutes. Il n'installe pas R,
Python ou Quarto. Attendre le message `PASS`; en cas d'erreur, corriger le
problème indiqué avant de continuer.

```console
python scripts/orchidee.py site --run-smoke-test
```

Cette commande essaie la construction avec des données inventées, sans ouvrir
vos données. Attendre `PASS`. Elle écrit dans `outputs/site_smoke_test`.
Pour répéter l'essai, utiliser un nouveau dossier avec `--output`.

### 3. Extraire les données et préparer les correspondances

```console
python scripts/orchidee.py site --emit-templates "data/site_handoff"
```

Deux extractions sont nécessaires : les résultats de microbiologie et les
mouvements entre unités d'hospitalisation. Vous préparez aussi quatre tables de
correspondance : bactéries, types de prélèvement, antibiotiques et unités.
Chaque extraction ou table est enregistrée dans son propre fichier.

La commande ci-dessus crée un modèle CSV pour chacun et un dossier `mapping_reference` contenant
les valeurs de correspondance autorisées ou reconnues. Remplir les modèles à
partir de vos sources ; les colonnes sont expliquées plus bas. Conserver les
identifiants et les codes comme du texte, notamment leurs zéros initiaux.
Les fichiers peuvent aussi être placés dans un dossier protégé hors du dépôt.
Ne pas les ajouter à Git. La commande refuse d'écraser des modèles existants.

### 4. Contrôler vos données

Copier [run_site_handoff.py](../examples/run_site_handoff.py) dans votre dossier
de travail protégé et ouvrir cette copie dans votre éditeur. Dans le bloc
`RÉGLAGES`, renseigner :

- `ORCHIDEE_REPO` : chemin complet du dépôt ;
- `SITE_INPUTS` : chemins complets des extractions et des tables de correspondance ;
- `OUTPUT_DIR` : dossier protégé où écrire les résultats ;
- `START_YEAR` et `END_YEAR` : première et dernière année, incluses
  (par exemple 2022 et 2024, ou 2024 et 2024).

Garder `STAGE = "diagnostics"`, enregistrer, puis lancer la copie :

```console
python "chemin/vers/run_site_handoff.py"
```

Le contrôle affiche les constats et écrit le détail dans `diagnostics/` sous
votre dossier de sortie. Corriger les `BLOCKING` puis relancer. Lire aussi les
`WARNING` : ils n'arrêtent pas le calcul, mais signalent des limites des données.
Un diagnostic réussi confirme que les fichiers sont exploitables ; il ne valide
pas à votre place le sens des correspondances locales.

### 5. Construire, puis produire le rapport

Dans la même copie, mettre `STAGE = "build"`, enregistrer et relancer la même
commande. Le build recontrôle les données puis prépare les entrées du calcul.
Attendre le message de réussite avant de continuer.

Mettre ensuite `STAGE = "report"` et relancer. Cette étape utilise le build
terminé ; elle ne le reconstruit pas. Le rapport est
`orchidee_ratb_indicators.html`, à la racine du dépôt : l'ouvrir dans un navigateur.
Les caches et tableaux exportés sont dans `runtime/` sous votre dossier de sortie.
Le rapport et ces sorties dérivent des données hospitalières : les conserver
avec les mêmes protections.

Si vous changez les données, les correspondances ou les années, reprendre au
stade `diagnostics`, puis `build`, avec un nouveau `OUTPUT_DIR` pour conserver
l'ancien résultat. Un simple nouveau rendu utilise `STAGE = "report"`.

Les sections suivantes servent de référence pendant la préparation des fichiers.
Les commandes CLI détaillées en fin de page sont une alternative au fichier de
lancement ; il n'est pas nécessaire de suivre les deux parcours.

## Contenu et structure des données à fournir

| Fichier | Contenu |
|---|---|
| `microbiology_observations` | Résultats de microbiologie : prélèvement, bactérie, antibiotique, résultat S/I/R et indication diagnostic ou dépistage. |
| `bacteria_mapping` | Correspondance entre les noms locaux des bactéries et les noms ORCHIDEE. |
| `sample_type_mapping` | Correspondance entre les types locaux de prélèvement et les types ORCHIDEE. |
| `antibiotic_mapping` | Correspondance entre les noms locaux des antibiotiques et les noms ORCHIDEE. |
| `unit_mapping` | Correspondance entre les unités d'hospitalisation et les codes TA/DE. |
| `hospitalization_intervals` | Séjours d'hospitalisation : une ligne par passage ininterrompu dans une unité. |

Les noms ci-dessus ne portent pas de numéro de version. ORCHIDEE produit
lui-même ses fichiers internes v2 et v3 ; l'établissement ne doit pas les
construire.

L'établissement transmet ce qu'il détient : des résultats, des
correspondances et des séjours. Il ne calcule pas de dénominateur et
n'indique pas l'unité d'un prélèvement. ORCHIDEE possède l'attribution des
prélèvements aux unités, le comptage des nuits et le périmètre : ce sont des
décisions d'analyse, et elles doivent être les mêmes d'un établissement à
l'autre pour que les chiffres se comparent.

Un exemple travaillé, quatre séjours inventés commentés ligne à ligne avec les
chiffres attendus, est dans
[`examples/site_handoff_worked/README.md`](../examples/site_handoff_worked/README.md).

Formats acceptés : `.rds`, `.csv`, `.tsv`, `.tab` ou `.txt`. Les CSV peuvent
utiliser la virgule ou le point-virgule. Les fichiers texte doivent être en
UTF-8. Les sections suivantes donnent les colonnes attendues dans chaque
fichier. Ces colonnes sont exactement celles que valide
`orchidee_site_public_input_spec()` dans `R/site_handoff_preparation_helpers.R` ; ce
document en explique le sens pour un lecteur qui ne lit pas le code R, il n'en
redéfinit pas la liste.

## La période d'analyse

La période est définie par une première et une dernière année,
`--start-year` et `--end-year`, bornes comprises. Ce n'est pas un filtre
appliqué à la fin : la période

- sélectionne les lignes de microbiologie, celles datées hors période étant
  écartées avant tout autre contrôle et leur nombre signalé ;
- découpe l'exposition, un séjour à cheval sur une borne ne conservant que
  les nuits situées à l'intérieur ;
- devient la période publiée par le rapport, transmise au rendu pour ce seul
  processus.

Les deux mêmes nombres servent donc au diagnostic, au build et au rendu.
`config/pipeline.R` n'est pas à modifier : la commande de rendu accepte
`--start-year` et `--end-year`, et sans eux la valeur déclarée dans ce
fichier — celle de Rouen — s'applique inchangée.

Les horodatages de `hospitalization_intervals` sont des lectures d'horloge
locale. Le fuseau qui en fait des instants est déclaré, pas deviné : il vaut
`Europe/Paris` par défaut et se change avec `--timezone`.

## Cibles de correspondance fournies par ORCHIDEE

ORCHIDEE ne peut pas décider ce que signifie un libellé local de Rennes ou
d'un autre hôpital. C'est le site qui possède cette interprétation et
remplit les blocs de correspondance. ORCHIDEE possède la surface cible : il
doit montrer les valeurs canoniques exactes et les références nationales
vers lesquelles le site peut mapper.

`--emit-templates` crée donc :

```text
mapping_reference/
  README.txt
  supported_atb_norm.csv
  recognized_bact_norm.csv
  current_indicator_naturepvt_norm.csv
  reference_code_ta.csv
  reference_code_de.csv
  allowed_denominator_profiles.csv
```

Ces fichiers ont quatre rôles délibérément différents :

| Fichiers | Signification |
| --- | --- |
| `supported_atb_norm.csv` | Valeurs fermées acceptées par le builder actuel. |
| `allowed_denominator_profiles.csv` | Profil de comptage et unité d'exposition qu'ORCHIDEE applique lui-même en dérivant l'exposition du bloc 6. Informatif : il n'y a rien à y choisir. |
| `recognized_bact_norm.csv` | Cibles canoniques de bactéries reconnues par la taxonomie embarquée, avec leur ordre, famille et genre quand ils sont connus. Ce n'est pas une liste blanche valable pour tout le bundle. |
| `current_indicator_naturepvt_norm.csv` | Cibles de type de prélèvement sélectionnées par le rapport actuel. Ce n'est pas une liste blanche valable pour tout le bundle. |
| `reference_code_ta.csv`, `reference_code_de.csv` | Références nationales complètes. `included_in_spares_current` indique si ce composant TA ou du domaine DE est sélectionné aujourd'hui ; l'éligibilité effective de l'unité exige les deux. `FALSE` signifie hors du périmètre d'analyse actuel, pas une activité v3 invalide. |

Le kit de référence n'est pas un septième bloc de transmission et n'est pas
retourné à ORCHIDEE. Par exemple, ORCHIDEE fournit `cefotaxime` comme cible
supportée ; c'est le site qui décide si des libellés locaux comme `CTX` ou
`CEFOTAX` signifient `cefotaxime`.

## Bloc 1 : microbiology_observations

Ce bloc contient une ligne par résultat local S/I/R pour un prélèvement, une
bactérie et un antibiotique.

Colonnes requises :

| Colonne | Signification |
| --- | --- |
| `PATID` | Identifiant patient. |
| `EVTID` | Identifiant du séjour / de l'épisode d'hospitalisation. Il relie le prélèvement à `hospitalization_intervals` et garde séparés des identifiants de prélèvement réutilisés d'un séjour à l'autre. La colonne est attendue ; une valeur manquante coûte au prélèvement son unité, pas le build. |
| `ELTID` | Identifiant du prélèvement / événement de microbiologie. |
| `HEUREPRELEV` | Heure de prélèvement, `HH:MM` ou `HH:MM:SS`, ou dans un `.rds` un `difftime` ou un nombre de secondes. L'heure doit être réelle et rester dans la journée : l'heure 24 et une seconde intercalaire sont refusées plutôt que reportées. La colonne est attendue ; sans valeur, le prélèvement ne peut pas être situé dans un séjour et sort du périmètre. |
| `DATEPRELEV` | Date de prélèvement. Dans un fichier texte : `YYYY-MM-DD`, `DD/MM/YYYY` ou `YYYY/MM/DD`, formats mélangeables dans la même colonne, une heure en fin de valeur étant ignorée. Dans un `.rds` : une `Date` ou un numéro de jour entier. L'heure du prélèvement appartient à `HEUREPRELEV` ; le reste est refusé plutôt que deviné. |
| `bacteria_local` | Libellé local de la bactérie. |
| `sample_type_local` | Libellé local du type de prélèvement. |
| `antibiotic_local` | Libellé local de l'antibiotique. |
| `sir_result` | Résultat local S/I/R. |
| `ratb_diagnostic_scope` | `TRUE` si la ligne appartient à de la microbiologie RATB diagnostique, `FALSE` pour du dépistage / non diagnostique. L'exclusion s'applique par occurrence de document — voir plus bas. |

Une seule colonne de périmètre diagnostique est requise. Ses noms acceptés
sont `ratb_diagnostic_scope`, `diagnostic_scope` et `is_diagnostic` ; ne pas
en fournir plus d'une dans le même fichier. Utiliser `ratb_diagnostic_scope`
pour une nouvelle transmission.

Colonnes optionnelles :

| Colonne | Signification |
| --- | --- |
| `souche_id` ou `isolate_local_id` | Identifiant local de souche quand le laboratoire distingue plusieurs isolats pour un même prélèvement. |
| `blse_status_row` ou `blse_status` | Statut BLSE optionnel : `positive`, `negative`, `unknown`, `no_signal`. |
| `carbapenemase_status_row` ou `carbapenemase_status` | Statut carbapénémase optionnel : `positive`, `negative`, `unknown`, `no_signal`. |

Valeurs acceptées pour `sir_result` :

- `S`, `SFP` et `---S` deviennent `S` ;
- `R` et `---R` deviennent `R` ;
- `I` et `ZIT` deviennent `ZIT` ;
- `NC` et les valeurs vides deviennent manquantes.

Toute autre valeur est refusée : le build s'arrête plutôt que de deviner ce
qu'elle voulait dire.

Exemple minimal :

```csv
PATID,EVTID,ELTID,DATEPRELEV,HEUREPRELEV,bacteria_local,sample_type_local,antibiotic_local,sir_result,ratb_diagnostic_scope
P001,S001,MIC001,2024-03-12,09:15,Escherichia coli,Urine,Amoxicilline acide clavulanique,R,TRUE
```

Ce bloc ne porte pas d'unité d'hospitalisation. C'est ORCHIDEE qui retient
l'unité qui hébergeait le patient à l'heure exacte du prélèvement, à partir
de `hospitalization_intervals`. Un prélèvement qu'il ne peut pas situer — pas
d'`EVTID`, pas d'heure, ou aucun intervalle actif à cet instant — garde sa
ligne, reste auditable et sort du périmètre d'analyse ; `--diagnose` en donne
le décompte et la raison. Une colonne `SEJUF` transmise malgré tout est
ignorée, et signalée comme telle.

Important : `ratb_diagnostic_scope` n'est pas le périmètre hospitalier
TA/DE. C'est la décision locale de microbiologie qui écarte le dépistage et
le matériel non diagnostique avant qu'ORCHIDEE n'applique le périmètre
d'unité hospitalière.

L'exclusion s'applique au niveau de l'occurrence de document : si une ligne
d'une occurrence `PATID + EVTID + ELTID` est marquée `FALSE` (dépistage /
non diagnostique), ORCHIDEE écarte cette occurrence entière, toutes
bactéries, antibiotiques et phénotypes confondus. C'est la règle RATB : un
prélèvement de dépistage est exclu en totalité. Il n'est donc pas nécessaire
de retirer soi-même ces lignes, il suffit de les marquer.

L'identité du document est `PATID + EVTID + ELTID` quand le fichier porte
des `EVTID`, `PATID + ELTID` quand il n'en porte aucun. Le dépistage n'est
jamais propagé par le seul `ELTID` entre patients.

Une ligne sans `EVTID` dans un fichier qui en contient par ailleurs est une
anomalie du système d'information hospitalier, pas un cas à traiter :
ORCHIDEE la supprime avant tout calcul et `--diagnose` la signale en
`WARNING` avec son décompte. La règle porte sur le fichier entier et non sur
chaque groupe : une seule valeur renseignée suffit à rendre anormales toutes
les lignes vides.

Plusieurs lignes peuvent viser la même cellule ORCHIDEE. Quand elles
s'accordent, elles fusionnent. Quand elles se contredisent, `--diagnose`
signale un constat bloquant plutôt que de choisir : une cellule contient un
résultat, et trancher par position ferait dépendre la valeur publiée de
l'ordre dans lequel l'export a été écrit. Le rapport distingue les deux
causes, car la correction n'est pas la même :

- le même libellé `antibiotic_local` portant deux résultats est une question
  pour le laboratoire, ou le signe que deux isolats doivent être distingués
  par `souche_id` ou `isolate_local_id` ;
- deux libellés différents que votre `antibiotic_mapping` envoie vers le même
  antibiotique ORCHIDEE est une question pour la correspondance. Une lecture
  en contexte urinaire et une lecture générale ne sont pas interchangeables.
  Mapper chaque libellé vers l'antibiotique qu'il a réellement testé, ou ne
  garder que la lecture que le RATB doit compter.

Le builder, lui, tranche en gardant la dernière valeur reçue. C'est le
passage `--diagnose` qui garantit qu'il n'a rien à trancher.

## Bloc 2 : bacteria_mapping

Ce bloc mappe les libellés locaux de bactéries vers les noms de bactéries
ORCHIDEE.

Colonnes requises :

| Colonne | Signification |
| --- | --- |
| `bacteria_local` | Libellé local de la bactérie tel qu'il apparaît dans `microbiology_observations`. |
| `bact_norm` | Jeton canonique de bactérie ORCHIDEE. |

Exemple :

```csv
bacteria_local,bact_norm
Escherichia coli,escherichia_coli
Klebsiella pneumoniae,klebsiella_pneumoniae
```

Utiliser `mapping_reference/recognized_bact_norm.csv` pour les jetons
exacts reconnus par la taxonomie embarquée. Les colonnes de taxonomie
expliquent quels jetons contribuent aussi à des indicateurs poolés comme
Enterobacterales. Un `bact_norm` différent peut rester une microbiologie
portable valide, mais ne crée pas automatiquement d'indicateur publié.

## Bloc 3 : sample_type_mapping

Ce bloc mappe les libellés locaux de type de prélèvement vers les types
ORCHIDEE.

Colonnes requises :

| Colonne | Signification |
| --- | --- |
| `sample_type_local` | Libellé local du type de prélèvement tel qu'il apparaît dans `microbiology_observations`. |
| `naturepvt_norm` | Type de prélèvement ORCHIDEE. |

Exemple :

```csv
sample_type_local,naturepvt_norm
Urine,urines
Hemoculture,hemoculture
```

`naturepvt_norm` peut être laissé vide quand un type de prélèvement local
ne peut pas être classé de façon fiable. Ces lignes restent disponibles pour
les indicateurs globaux, mais ne peuvent pas contribuer aux analyses qui
exigent un type de prélèvement connu. Le nombre de correspondances vides
devrait être revu pendant l'onboarding.
`mapping_reference/current_indicator_naturepvt_norm.csv` liste les types de
prélèvement sélectionnés par le rapport actuel ; ce n'est pas une liste
blanche valable pour tout le bundle.

## Bloc 4 : antibiotic_mapping

Ce bloc mappe les libellés locaux d'antibiotiques vers les colonnes
d'antibiotiques ORCHIDEE.

Colonnes requises :

| Colonne | Signification |
| --- | --- |
| `antibiotic_local` | Libellé local de l'antibiotique tel qu'il apparaît dans `microbiology_observations`. |
| `atb_norm` | Colonne d'antibiotique ORCHIDEE. |

Exemple :

```csv
antibiotic_local,atb_norm
Amoxicilline acide clavulanique,amoxicilline_acide_clavulanique
Cefotaxime,cefotaxime
```

N'inclure que les lignes de résultat d'antibiotique qui mappent vers des
colonnes d'antibiotique ORCHIDEE supportées. Le builder échoue si `atb_norm`
n'est pas une de ces colonnes. La liste fermée exacte est générée dans
`mapping_reference/supported_atb_norm.csv`.

## Bloc 5 : unit_mapping

Ce bloc mappe les codes UF d'hospitalisation vers la structure nationale
TA/DE. Il doit couvrir chaque `SEJUF` présent dans `hospitalization_intervals`
— toute unité qui héberge un patient. Une unité qui héberge sans être mappée
est un constat bloquant : ORCHIDEE n'infère pas de correspondance.

Colonnes requises :

| Colonne | Signification |
| --- | --- |
| `SEJUF` | UF d'hospitalisation. Doit correspondre aux autres blocs de transmission. |
| `CODE_TA` | Code TA de l'unité. |
| `CODE_DE` | Code DE national de l'unité. |
| `de_domain_ref` | Domaine DE national correspondant à `CODE_DE`. |

Grain attendu : une ligne par `SEJUF`.

```csv
SEJUF,CODE_TA,CODE_DE,de_domain_ref
UF1234,03,102,MÉDECINE
UF5678,10,211,URGENCES
```

Utiliser `mapping_reference/reference_code_ta.csv` et
`mapping_reference/reference_code_de.csv` pour traduire la structure locale
du site. Ils contiennent les références nationales complètes et identifient
le périmètre `spares_current` actuel sans traiter le reste de l'activité
mappée comme invalide.

## Bloc 6 : hospitalization_intervals

Ce bloc contient les séjours d'hospitalisation, indépendamment de la
microbiologie. Il remplace la table d'exposition qu'un site devait autrefois
calculer lui-même : un établissement détient ses mouvements, pas la convention
de comptage d'ORCHIDEE, et lui demander un dénominateur revenait à lui
demander de deviner cette convention.

ORCHIDEE en dérive deux choses : l'exposition profilée dont le dénominateur est
tiré, et l'unité de chaque prélèvement.

Grain attendu : **une ligne par passage ininterrompu d'un patient dans une
unité d'hébergement**. Un transfert crée une nouvelle ligne. Inclure les
hospitalisations sans aucune microbiologie : elles comptent au dénominateur.

Colonnes requises :

| Colonne | Signification |
| --- | --- |
| `PATID` | Identifiant patient. |
| `EVTID` | Identifiant du séjour / de l'épisode d'hospitalisation. Le même que celui porté par `microbiology_observations`. |
| `DATENT` | Date et heure d'entrée dans l'unité. |
| `DATSORT` | Date et heure de sortie de l'unité. |
| `SEJUM` | UM d'hospitalisation. |
| `SEJUF` | UF d'hospitalisation. Doit figurer dans `unit_mapping`. |

```csv
PATID,EVTID,DATENT,DATSORT,SEJUM,SEJUF
P001,S001,2024-03-10 14:00,2024-03-12 09:00,UM1234,UF1234
P001,S001,2024-03-12 09:00,2024-03-18 11:00,UM5678,UF5678
```

### Comment les bornes se lisent

Un intervalle est **`[entrée, sortie)`** : l'instant d'entrée appartient au
séjour, l'instant de sortie non. Il en découle :

- **un transfert est adjacent, pas un chevauchement.** Une sortie à 09:00 et
  l'entrée suivante à 09:00 décrivent un patient qui ne se trouve qu'à un seul
  endroit ; il n'est pas compté deux fois ;
- **des lignes dupliquées ou qui se recouvrent pour la même unité et le même
  séjour fusionnent** en un seul intervalle occupé. Un export qui répète un
  mouvement ne gonfle pas le dénominateur ;
- **un retour dans une même unité après un passage ailleurs reste deux
  visites.** Les nuits passées entre les deux ne sont pas absorbées ;
- **une entrée et une sortie le même jour** sont valides. Le séjour compte zéro
  nuit — une nuit est un changement de date — et peut malgré tout héberger un
  prélèvement.

### Ce qui arrête le workflow

Ces situations sont bloquantes : elles n'ont pas de correction par défaut
qu'ORCHIDEE puisse appliquer sans décider à la place du site.

| Constat | Pourquoi |
| --- | --- |
| `PATID`, `EVTID`, `SEJUM` ou `SEJUF` manquant | Un intervalle sans patient, sans épisode ou sans unité ne se rattache à rien. |
| `DATENT` ou `DATSORT` manquant, illisible ou hors calendrier | Une borne absente ou impossible n'est pas une borne. |
| `DATSORT` antérieur à `DATENT` | Une sortie avant son entrée est une erreur de source, pas un séjour de durée nulle. |
| Horodatage inexistant dans le fuseau déclaré | L'heure sautée au passage à l'heure d'été ne désigne aucun instant. |
| Horodatage ambigu dans le fuseau déclaré | L'heure répétée au passage à l'heure d'hiver en désigne deux ; ORCHIDEE n'en choisit pas une. |
| Deux unités différentes occupées en même temps dans un même séjour, sur une durée strictement positive | Il n'existe pas de partage défendable de la nuit entre les deux unités. |

Le dernier point vise les doubles occupations réelles, pas les transferts :
une sortie et l'entrée suivante au même instant ne se chevauchent pas.

### Représentation des horodatages

Stricte, et volontairement plus stricte que `DATEPRELEV`. Les formes acceptées
dans un fichier texte sont :

```text
YYYY-MM-DD
YYYY-MM-DD HH:MM
YYYY-MM-DD HH:MM:SS
```

`T` est accepté à la place de l'espace. Une date seule vaut minuit. Toute
autre écriture est refusée plutôt qu'interprétée : `12/03/2024` désigne deux
jours différents selon la convention, et une borne d'hospitalisation ne se
devine pas. Dans un `.rds`, un `POSIXct` ou une `Date` sont lus directement.

Les valeurs sont lues dans le fuseau donné par `--timezone`, `Europe/Paris`
par défaut.

### Ce qu'ORCHIDEE en dérive

L'exposition profilée interne, au grain `année + UM + UF + TA + DE + domaine +
profil`, en journées-patient `midnight_presence`, jointe à `unit_mapping` pour
le TA/DE. La projection `spares_current` en tire ensuite le total annuel du
seul périmètre publié. Un site ne construit ni ne configure aucune de ces deux
tables.

## Construire et valider les bundles ORCHIDEE

Depuis la racine du dépôt, lancer d'abord le contrôle préalable sans risque :

```console
python scripts/orchidee.py site --microbiology-observations "data/site_handoff/microbiology_observations.csv" --bacteria-mapping "data/site_handoff/bacteria_mapping.csv" --sample-type-mapping "data/site_handoff/sample_type_mapping.csv" --antibiotic-mapping "data/site_handoff/antibiotic_mapping.csv" --unit-mapping "data/site_handoff/unit_mapping.csv" --hospitalization-intervals "data/site_handoff/hospitalization_intervals.csv" --start-year 2022 --end-year 2024 --dry-run
```

Cette commande ne lit que les en-têtes des fichiers délimités ; les entrées
RDS doivent être désérialisées pour en inspecter les colonnes. Elle vérifie
que les six fichiers existent et portent les colonnes attendues. Elle ne
regarde pas leur contenu et ne crée pas de répertoire de sortie.

Une fois que `--dry-run` passe, remplacer `--dry-run` par `--diagnose` dans la
même commande :

```console
python scripts/orchidee.py site --microbiology-observations "data/site_handoff/microbiology_observations.csv" --bacteria-mapping "data/site_handoff/bacteria_mapping.csv" --sample-type-mapping "data/site_handoff/sample_type_mapping.csv" --antibiotic-mapping "data/site_handoff/antibiotic_mapping.csv" --unit-mapping "data/site_handoff/unit_mapping.csv" --hospitalization-intervals "data/site_handoff/hospitalization_intervals.csv" --start-year 2022 --end-year 2024 --diagnose
```

`--diagnose` lit les six blocs une seule fois et signale **tous** les
problèmes de contrat en une seule passe, classés en :

| Niveau | Signification |
| --- | --- |
| `BLOCKING` | Le build ne peut pas aboutir tant que ce n'est pas corrigé. |
| `WARNING` | Le build aboutit, mais les lignes perdent de la valeur analytique ; à revoir. |
| `INFO` | Décomptes décrivant la transmission, y compris la couverture du périmètre. |

Le builder s'arrête à la première classe invalide ; `--diagnose` agrège
l'ensemble du travail. Les constats de correspondance incluent des
décomptes de lignes et d'occurrences de document par libellé local. Le
résumé est concis et `finding_values.csv` conserve la liste complète des
valeurs, jointe par `finding_id`.

Le rapport est écrit dans un sous-répertoire `diagnostics` de `--output`
quand on en passe un, sinon sous `outputs/site_diagnostics` ; `--report`
prime sur les deux. Au-delà des six chemins d'entrée qu'il enregistre pour
traçabilité, il ne contient que des décomptes agrégés et votre propre
vocabulaire local ; il n'écrit jamais d'identifiant patient.

Un code de sortie 1 signifie des constats bloquants. Un code de sortie 2
signifie qu'aucun verdict n'a pu être produit à cause d'un échec technique
ou de publication.

`report_manifest.txt` marque un rapport complet. Une seule exécution à la
fois peut publier dans un répertoire de rapport ; une exécution interrompue
peut laisser `.orchidee_diagnostics.lock`. Ne supprimer ce verrou qu'après
avoir confirmé qu'aucun diagnostic n'utilise encore le répertoire.

`--diagnose` répond à une seule question : les six blocs satisfont-ils le
contrat de transmission ? Elle ne prédit pas quels indicateurs le rapport
publiera.

Un `PASS` est une promesse : le build que cette procédure lance ensuite
aboutit sur ces blocs — bundle v3, projection `spares_current` vers le v2
opérationnel, et validation stricte des deux.

Le build relance lui-même ce diagnostic, sur les mêmes six blocs et la même
période, et refuse de construire tant qu'un constat bloquant subsiste. Aucun
appel de la CLI ne peut donc contourner le diagnostic : deux résultats S/I/R
qui se contredisent, en particulier, ne peuvent pas être tranchés en silence
par le builder en gardant la dernière ligne reçue.

Quand elle signale `PASS`, relancer exactement la même commande sans
`--dry-run` ni `--diagnose` pour un premier build. Si le contrôle préalable
signale une sortie existante complète, choisir un autre `--output` ou,
après revue, ajouter `--force` comme l'indique son avertissement.

Ajouter `--output "D:\ORCHIDEE\site_current"` quand les bundles générés
doivent vivre dans un espace de travail externe protégé. Utiliser
`python scripts/orchidee.py site --help` pour voir toutes les options
supportées.

Pour ne pas retaper six chemins et deux années à chaque étape, copier
[`examples/run_site_handoff.py`](../examples/run_site_handoff.py) à côté des
données protégées. Ce fichier ne contient aucun calcul : il enregistre les
chemins, la sortie et la période en haut, et enchaîne les mêmes
commandes que ci-dessus. Il démarre au stade `diagnostics` ; on passe à
`build` puis à `report` après avoir lu la sortie du stade précédent.

La CLI valide d'abord le bundle v3. Elle applique ensuite le contexte
fermé `spares_current`, matérialise un bundle v2 strict séparé, et valide
et smoke-teste cette sortie. Elle n'adopte pas v3 comme entrée runtime de
notebook. `--force` sert uniquement à une répétition volontaire d'un build
sur une sortie complète déjà créée par ce même workflow ; il ne fait pas
partie de la commande de premier build.

## Utiliser le bundle obtenu

ORCHIDEE écrit quatre fichiers internes par bundle matérialisé après
validation :

- `sir_wide.rds`
- `sir_wide_meta.rds`
- `sample_scope_reference.rds`
- `denominator_bundle.rds`

Ne pas construire ces quatre fichiers à la main pour une première
transmission. Les noms de version de bundle décrivent ces sorties
matérialisées, pas les six blocs possédés par le site.

Le build conserve un bundle v3 complet et en dérive un bundle v2 strict, seule
entrée du runtime. Il sélectionne pour cela le contexte fermé
`spares_current` : périmètre RATB actuel (TA 03/20 et domaines DE ratifiés)
et comptage de journées-patient `midnight_presence`. Un site ne configure pas
cette sélection.


La disposition de sortie par défaut est :

```text
outputs/site_current/
  bundle_v3/
    build_manifest.txt
  bundle_v2_operational/
    build_manifest.txt
  runtime/                    # créé uniquement par un rendu ultérieur
```

Chaque répertoire de bundle contient aussi les quatre fichiers RDS. Le
manifeste est écrit en dernier, après la validation stricte, le smoke test
runtime canonique et la publication : sans lui, considérer ce répertoire
comme incomplet. Les deux manifestes doivent porter le même `build_id` ; une
différence signifie que la paire ne vient pas d'un même run complet. Le
manifeste est une métadonnée du builder, pas un cinquième fichier requis
par le contrat runtime v2 ou v3.

Le build exécute déjà le smoke test runtime v2. Conserver `bundle_v3` comme
le bundle complet validé. Pour calculer les indicateurs à partir du bundle
v2 produit par ce même build :

```console
python scripts/orchidee.py render --rebuild --bundle "outputs/site_current/bundle_v2_operational" --workspace "outputs/site_current/runtime" --start-year 2022 --end-year 2024
```

`--start-year` et `--end-year` doivent répéter la période du build : ce sont
les années que le rapport publie. Elles ne valent que pour ce processus et ne
modifient pas `config/pipeline.R`, dont la valeur déclarée reste celle de
Rouen.

La CLI affiche cette commande avec les chemins exacts résolus à la fin du
build. `--rebuild` construit le cache brut canonique avant de calculer les
indicateurs ; les caches et les exports de rapport sont écrits sous l'espace de
travail privé sélectionné.

## En cas d'échec de la validation

Lancer `--diagnose` d'abord : il liste tous les problèmes à la fois, alors
que les messages ci-dessous apparaissent un par un. Les échecs les plus
fréquents sont :

- une colonne requise manque ;
- une bactérie, un type de prélèvement ou un antibiotique local n'a pas de
  correspondance ;
- un antibiotique mappe vers une valeur absente de
  `mapping_reference/supported_atb_norm.csv` ;
- toutes les lignes de microbiologie sont marquées hors
  `ratb_diagnostic_scope` ;
- `SEJUF` est dupliqué dans `unit_mapping` ;
- une unité de `hospitalization_intervals` n'a pas de ligne dans
  `unit_mapping` ;
- un intervalle est renversé, incomplet, ou porte un horodatage que le fuseau
  déclaré rend impossible ou ambigu ;
- un séjour place le patient dans deux unités à la fois ;
- `DATEPRELEV` ou `HEUREPRELEV` a un format non supporté ;
- deux lignes donnent des résultats S/I/R contradictoires pour le même
  prélèvement, la même bactérie, le même isolat et le même antibiotique.

Si un laboratoire rapporte plusieurs isolats de la même espèce dans un même
prélèvement, fournir `souche_id` ou `isolate_local_id` pour qu'ORCHIDEE
puisse les garder distincts.

## Qui est responsable de quoi ?

L'hôpital possède :

- l'extraction des données depuis le HDW local ou les systèmes source ;
- la décision de savoir quelles lignes de microbiologie sont des lignes
  RATB diagnostiques ;
- la correspondance des bactéries, types de prélèvement et antibiotiques
  locaux vers les valeurs ORCHIDEE ;
- la correspondance des unités locales vers l'information TA/DE ;
- l'extraction des séjours d'hospitalisation au grain unité, y compris ceux
  sans microbiologie ;
- la déclaration de la période d'analyse.

ORCHIDEE possède :

- la validation des blocs de transmission ;
- la dérivation des quatre fichiers internes du bundle ;
- l'exclusion du dépistage / matériel non diagnostique au niveau de
  l'occurrence de document, avec l'identité et la règle d'anomalie `EVTID`
  décrites sous le Bloc 1 ;
- l'attribution de chaque prélèvement à l'unité qui hébergeait le patient à
  l'heure du prélèvement ;
- le comptage des nuits, l'union des intervalles et le découpage annuel ;
- l'application du périmètre RATB ;
- l'exécution de la déduplication brute et du calcul des indicateurs.
