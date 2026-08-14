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

## Les six fichiers attendus

| Fichier | Contenu |
|---|---|
| `microbiology_observations` | Résultats de microbiologie : prélèvement, bactérie, antibiotique, résultat S/I/R et indication diagnostic ou dépistage. |
| `bacteria_mapping` | Correspondance entre les noms locaux des bactéries et les noms ORCHIDEE. |
| `sample_type_mapping` | Correspondance entre les types locaux de prélèvement et les types ORCHIDEE. |
| `antibiotic_mapping` | Correspondance entre les noms locaux des antibiotiques et les noms ORCHIDEE. |
| `unit_mapping` | Correspondance entre les unités d'hospitalisation et les codes TA/DE. |
| `incidence_exposure_by_year_um_uf_ta_de_profile` | Journées d'hospitalisation par année et par unité. |

Les noms ci-dessus ne portent pas de numéro de version. ORCHIDEE produit
lui-même ses fichiers internes v2 et v3 ; l'établissement ne doit pas les
construire.

Formats acceptés : `.rds`, `.csv`, `.tsv`, `.tab` ou `.txt`. Les CSV peuvent
utiliser la virgule ou le point-virgule. Les fichiers texte doivent être en
UTF-8. Les sections suivantes donnent les colonnes attendues dans chaque
fichier. Ces colonnes sont exactement celles que valide
`orchidee_handoff_site_input_spec()` dans `R/external_handoff_helpers.R` ; ce
document en explique le sens pour un lecteur qui ne lit pas le code R, il n'en
redéfinit pas la liste.

Avant de lancer une commande ORCHIDEE sur un clone frais, restaurer
l'environnement R depuis `renv.lock` :

```powershell
& .\scripts\setup.ps1
```

Avant de travailler sur des données locales protégées, contrôler
l'installation :

```powershell
& .\scripts\build_site.ps1 -RunSmokeTest
```

Cette commande n'utilise que les fichiers de `examples/site_handoff_minimal/`
et écrit sous `outputs/site_smoke_test/`. Elle exécute le même build v3, la
même projection v2 et la même validation stricte qu'une vraie transmission,
sur une observation synthétique unique : elle qualifie l'installation, pas
vos données, et n'enseigne pas le contrat. Sur une répétition, choisir un
autre `-Output` ou suivre le message de collision.

Si les six fichiers n'existent pas encore, générer des modèles CSV vides avec
les en-têtes canoniques et le kit de référence de correspondance ORCHIDEE :

```powershell
$handoff = "data/site_handoff"
& .\scripts\build_site.ps1 -EmitTemplates $handoff
```

La commande refuse d'écraser un fichier généré déjà existant. Remplir les six
modèles de premier niveau avec les données locales protégées ; ne pas les
committer. `$handoff` peut aussi désigner un répertoire protégé hors du
checkout.

## Cibles de correspondance fournies par ORCHIDEE

ORCHIDEE ne peut pas décider ce que signifie un libellé local de Rennes ou
d'un autre hôpital. C'est le site qui possède cette interprétation et
remplit les blocs de correspondance. ORCHIDEE possède la surface cible : il
doit montrer les valeurs canoniques exactes et les références nationales
vers lesquelles le site peut mapper.

`-EmitTemplates` crée donc :

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
| `supported_atb_norm.csv`, `allowed_denominator_profiles.csv` | Valeurs fermées acceptées par le builder actuel. |
| `recognized_bact_norm.csv` | Cibles canoniques de bactéries reconnues par la taxonomie embarquée, avec leur ordre, famille et genre quand ils sont connus. Ce n'est pas une liste blanche valable pour tout le bundle. |
| `current_indicator_naturepvt_norm.csv` | Cibles de type de prélèvement sélectionnées par le rapport actuel. Ce n'est pas une liste blanche valable pour tout le bundle. |
| `reference_code_ta.csv`, `reference_code_de.csv` | Références nationales complètes. `included_in_spares_current` indique si ce composant TA ou du domaine DE est sélectionné aujourd'hui ; l'éligibilité effective de l'unité exige les deux. `FALSE` signifie hors du périmètre d'analyse actuel, pas une activité v3 invalide. |

Le kit de référence n'est pas un septième bloc de transmission et n'est pas
retourné à ORCHIDEE. Par exemple, ORCHIDEE fournit `cefotaxime` comme cible
supportée ; c'est le site qui décide si des libellés locaux comme `CTX` ou
`CEFOTAX` signifient `cefotaxime`.

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

## Bloc 1 : microbiology_observations

Ce bloc contient une ligne par résultat local S/I/R pour un prélèvement, une
bactérie et un antibiotique.

Colonnes requises :

| Colonne | Signification |
| --- | --- |
| `PATID` | Identifiant patient. |
| `ELTID` | Identifiant du prélèvement / événement de microbiologie. |
| `DATEPRELEV` | Date de prélèvement. Dans un fichier texte : `YYYY-MM-DD`, `DD/MM/YYYY` ou `YYYY/MM/DD`, formats mélangeables dans la même colonne, une heure en fin de valeur étant ignorée. Dans un `.rds` : une `Date` ou un numéro de jour entier. L'heure du prélèvement appartient à `HEUREPRELEV` ; le reste est refusé plutôt que deviné. |
| `SEJUF` | UF d'hospitalisation active au moment du prélèvement ; c'est au site d'établir cette attribution avant la transmission. ORCHIDEE l'utilise pour appliquer le périmètre RATB TA/DE. |
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
| `EVTID` | Identifiant du séjour / de l'épisode d'hospitalisation. Il garde séparés des identifiants de prélèvement réutilisés d'un séjour à l'autre. Fournir la colonne renseignée sur toutes les lignes, ou ne pas la fournir du tout. |
| `HEUREPRELEV` | Heure de prélèvement, `HH:MM` ou `HH:MM:SS`, ou dans un `.rds` un `difftime` ou un nombre de secondes. L'heure doit être réelle et rester dans la journée : l'heure 24 et une seconde intercalaire sont refusées plutôt que reportées. |
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
PATID,EVTID,ELTID,DATEPRELEV,HEUREPRELEV,SEJUF,bacteria_local,sample_type_local,antibiotic_local,sir_result,ratb_diagnostic_scope
P001,S001,MIC001,2024-03-12,09:15,UF1234,Escherichia coli,Urine,Amoxicilline acide clavulanique,R,TRUE
```

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
ORCHIDEE la supprime avant tout calcul et `-Diagnose` la signale en
`WARNING` avec son décompte. La règle porte sur le fichier entier et non sur
chaque groupe : une seule valeur renseignée suffit à rendre anormales toutes
les lignes vides.

Plusieurs lignes peuvent viser la même cellule ORCHIDEE. Quand elles
s'accordent, elles fusionnent. Quand elles se contredisent, `-Diagnose`
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
passage `-Diagnose` qui garantit qu'il n'a rien à trancher.

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
TA/DE. Il doit couvrir chaque `SEJUF` présent dans l'exposition profilée.
Les codes UF de microbiologie observés devraient aussi être listés quand une
correspondance existe ; un UF non résolu reste visible en audit seul plutôt
que de recevoir une correspondance inférée.

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

## Bloc 6 : incidence_exposure_by_year_um_uf_ta_de_profile

Ce bloc contient l'exposition hospitalière indépendamment des lignes de
microbiologie. Il préserve la structure fine dont v3 a besoin ; ORCHIDEE en
dérive le dénominateur annuel v2 pour le runtime actuel.

Colonnes requises :

| Colonne | Signification |
| --- | --- |
| `calendar_year` | Année civile. |
| `SEJUM` | UM d'hospitalisation du séjour dans l'unité. |
| `SEJUF` | UF d'hospitalisation du séjour dans l'unité. |
| `CODE_TA` | Code TA joint à `SEJUF`. |
| `CODE_DE` | Code DE joint à `SEJUF`. |
| `de_domain_ref` | Domaine DE national joint à `CODE_DE`. |
| `denominator_profile_id` | Profil de comptage fermé ; actuellement `midnight_presence`. |
| `exposure_value` | Exposition à ce grain exact. |
| `exposure_unit` | Unité fixée par le profil ; actuellement `patient_days`. |

Grain attendu : une ligne par
`calendar_year + SEJUM + SEJUF + CODE_TA + CODE_DE + de_domain_ref +
denominator_profile_id`.

Les neuf colonnes sont toutes requises et non manquantes. Inclure
l'exposition positive de toute activité mappée valide, même quand son TA/DE
est hors du périmètre RATB actuel. La projection sélectionne
`spares_current` et en dérive le total annuel actuel ; ne pas fournir une
seconde table annuelle calculée indépendamment.

`unit_mapping` doit couvrir chaque `SEJUF` de ce bloc. Ses valeurs de TA, DE
et domaine DE doivent concorder exactement ; la validation stricte rejette
les correspondances croisées manquantes ou contradictoires.
Le couple profil/unité accepté est généré dans
`mapping_reference/allowed_denominator_profiles.csv`.

## Construire et valider les bundles ORCHIDEE

Depuis la racine du dépôt, lancer d'abord le contrôle préalable sans risque :

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

Cette commande ne lit que les en-têtes des fichiers délimités ; les entrées
RDS doivent être désérialisées pour en inspecter les colonnes. Elle vérifie
que les six fichiers existent et portent les colonnes attendues. Elle ne
regarde pas leur contenu et ne crée pas de répertoire de sortie.

Une fois que `-DryRun` passe, remplacer `-DryRun` par `-Diagnose` dans la
même commande :

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
  -Diagnose
```

`-Diagnose` lit les six blocs une seule fois et signale **tous** les
problèmes de contrat en une seule passe, classés en :

| Niveau | Signification |
| --- | --- |
| `BLOCKING` | Le build ne peut pas aboutir tant que ce n'est pas corrigé. |
| `WARNING` | Le build aboutit, mais les lignes perdent de la valeur analytique ; à revoir. |
| `INFO` | Décomptes décrivant la transmission, y compris la couverture du périmètre. |

Le builder s'arrête à la première classe invalide ; `-Diagnose` agrège
l'ensemble du travail. Les constats de correspondance incluent des
décomptes de lignes et d'occurrences de document par libellé local. Le
résumé est concis et `finding_values.csv` conserve la liste complète des
valeurs, jointe par `finding_id`.

Le rapport est écrit dans un sous-répertoire `diagnostics` de `-Output`
quand on en passe un, sinon sous `outputs\site_diagnostics` ; `-Report`
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

`-Diagnose` répond à une seule question : les six blocs satisfont-ils le
contrat de transmission ? Elle ne prédit pas quels indicateurs le rapport
publiera.

Un `PASS` est une promesse : le build que cette procédure lance ensuite
aboutit sur ces blocs — bundle v3, projection `spares_current` vers le v2
opérationnel, et validation stricte des deux.

Quand elle signale `PASS`, relancer exactement la même commande sans
`-DryRun` ni `-Diagnose` pour un premier build. Si le contrôle préalable
signale une sortie existante complète, choisir un autre `-Output` ou,
après revue, ajouter `-Force` comme l'indique son avertissement.

Ajouter `-Output "D:\ORCHIDEE\site_current"` quand les bundles générés
doivent vivre dans un espace de travail externe protégé. Utiliser
`Get-Help .\scripts\build_site.ps1 -Full` pour voir tous les réglages
supportés.

Le wrapper valide d'abord le bundle v3. Il applique ensuite le contexte
fermé `spares_current`, matérialise un bundle v2 strict séparé, et valide
et smoke-teste cette sortie. Il n'adopte pas v3 comme entrée runtime de
notebook. `-Force` sert uniquement à une répétition volontaire d'un build
sur une sortie complète déjà créée par ce même workflow ; il ne fait pas
partie de la commande de premier build.

## Utiliser le bundle obtenu

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

```powershell
$bundle = (Resolve-Path `
  "outputs/site_current/bundle_v2_operational").Path
$workspace = Join-Path (Get-Location) "outputs/site_current/runtime"

& .\scripts\render_orchidee.ps1 -Target full `
  -Bundle $bundle `
  -Workspace $workspace
```

Le wrapper affiche cette commande avec les chemins exacts résolus à la fin
du build. Le rendu `full` calcule les indicateurs opérationnels et écrit ses
caches et exports de rapport sous l'espace de travail privé sélectionné.

## En cas d'échec de la validation

Lancer `-Diagnose` d'abord : il liste tous les problèmes à la fois, alors
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
- le calcul de l'exposition hospitalière profilée, indépendamment de la
  microbiologie.

ORCHIDEE possède :

- la validation des blocs de transmission ;
- la dérivation des quatre fichiers internes du bundle ;
- l'exclusion du dépistage / matériel non diagnostique au niveau de
  l'occurrence de document, avec l'identité et la règle d'anomalie `EVTID`
  décrites sous le Bloc 1 ;
- l'application du périmètre RATB ;
- l'exécution de la déduplication brute et du calcul des indicateurs.
