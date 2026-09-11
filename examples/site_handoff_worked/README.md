---
editor_options:
  markdown:
    wrap: 72
---

# Exemple : des résultats de microbiologie et des mouvements aux indicateurs

Cet exemple contient des résultats de microbiologie, des mouvements hospitaliers
et leurs tables de correspondance, entièrement fictifs. Ce sont six séjours
inventés (PAT001 à PAT006), choisis pour montrer ce qu'ORCHIDEE fait des blocs
qu'un établissement lui transmet — et surtout ce qu'il en fait *tout seul*.

Ce n'est pas le smoke test d'installation ; celui-ci est dans
`examples/site_handoff_minimal/` et répond à une autre question. Ici, on lit
des chiffres et on vérifie qu'on les retrouve. Le contrat technique détaillé
est décrit dans [site_contract.md](../../documentation/site_contract.md) et la
procédure pas-à-pas dans [site_onboarding_quickstart.md](../../documentation/site_onboarding_quickstart.md).

## Les entrées

### `hospitalization_intervals.csv` — neuf lignes, six séjours

Une ligne par visite ininterrompue dans une unité. Les bornes se lisent
`[entrée, sortie)`.

| Patient | Séjour | Unité | Entrée | Sortie | Nuits 2024 |
|---|---|---|---|---|---|
| PAT001 | SEJ001 | UF_MED1 | 05/02 14:00 | 08/02 09:00 | 3 |
| PAT001 | SEJ001 | UF_REA1 | 08/02 09:00 | 15/02 11:00 | 7 |
| PAT002 | SEJ002 | UF_MED1 | 01/03 08:00 | 04/03 10:00 | 3 |
| PAT002 | SEJ002 | UF_REA1 | 04/03 10:00 | 06/03 09:00 | 2 |
| PAT002 | SEJ002 | UF_MED1 | 06/03 09:00 | 11/03 12:00 | 5 |
| PAT003 | SEJ003 | UF_MED1 | 02/04 07:00 | 12/04 16:00 | 10 |
| PAT004 | SEJ004 | UF_URG1 | 10/05 22:00 | 13/05 06:00 | 3 |
| PAT005 | SEJ005 | UF_CHIR1 | 01/06 10:00 | 08/06 14:00 | 7 |
| PAT006 | SEJ006 | UF_MED_SEM | 28/12/2023 14:00 | 05/01/2024 10:00 | 4 (8 au total) |

Plusieurs mécaniques s'y jouent :

- **Le transfert de PAT001** est adjacent : la sortie de médecine est
  l'instant même de l'entrée en réanimation. Les deux visites ne se
  chevauchent pas et le patient n'est compté qu'une fois.
- **PAT002 revient en UF_MED1** après un passage en réanimation. Les deux
  visites restent séparées : UF_MED1 reçoit 3 + 5 = 8 nuits, pas les 10 que
  donnerait un `min(entrée)` / `max(sortie)` par unité, qui avaleraient au
  passage les deux nuits de réanimation.
- **PAT003 n'a aucune microbiologie.** Ses 10 nuits comptent quand même : le
  dénominateur ne dépend pas des prélèvements.
- **PAT004 est pris en charge aux urgences (UF_URG1).** Son activité est réelle
  et conservée dans `bundle_v3`, mais sortira du périmètre d'indicateurs publié
  en `v2` (TA 10 non éligible).
- **PAT005 est hospitalisé en chirurgie (UF_CHIR1).** Ses 7 nuits contribuent au
  domaine CHIRURGIE (DE 146).
- **PAT006 chevauche la frontière de l'année civile.** Admis le 28/12/2023 et
  sorti le 05/01/2024 (8 nuits au total), ORCHIDEE découpe automatiquement
  l'exposition par année : 4 nuits sont attribuées à 2023 (écartées de
  l'analyse 2024) et seules les **4 nuits de 2024** sont retenues dans le
  dénominateur 2024. De plus, il est hébergé en hôpital de semaine (TA 20),
  parfaitement reconnu dans le périmètre publié.

### `unit_mapping.csv` — cinq unités

| SEJUF | CODE_TA | CODE_DE | Domaine | Dans le périmètre publié ? |
|---|---|---|---|---|
| UF_MED1 | 03 | 102 | MÉDECINE | oui |
| UF_REA1 | 03 | 105 | RÉANIMATION | oui |
| UF_URG1 | 10 | 211 | URGENCES | **non** (TA 10 exclu) |
| UF_CHIR1 | 03 | 146 | CHIRURGIE | oui |
| UF_MED_SEM | 20 | 102 | MÉDECINE | oui (TA 20 hospitalisation de semaine) |

`UF_URG1` est mappée correctement et son activité est réelle. Elle sort du
périmètre parce que son TA vaut 10 et non 03 ou 20 — pas parce que la donnée
serait fausse. C'est exactement la distinction que `v3` conserve et que `v2`
applique.

### `microbiology_observations.csv` — seize lignes, six prélèvements

| Prélèvement | Patient | Date, heure | Souche | Bactérie | Type | Observations |
|---|---|---|---|---|---|---|
| MIC001 | PAT001 | 10/02 06:30 | ISO001 | E. coli | hémoculture | 3 ATB (cefotaxime R, BLSE positive) |
| MIC002 | PAT002 | 02/03 10:15 | ISO002 | K. pneumoniae | ECBU | 2 ATB (cefotaxime R, BLSE positive) |
| MIC003 | PAT002 | 09/03 08:00 | ISO003 | K. pneumoniae | écouvillon rectal | 1 ATB, `ratb_diagnostic_scope = FALSE` |
| MIC004 | PAT004 | 11/05 23:00 | ISO004 | S. aureus | hémoculture | 1 ATB (oxacilline R, SARM) |
| MIC005 | PAT005 | 03/06 11:00 | ISO_PSEAUR | P. aeruginosa | hémoculture | 4 ATB (ciprofloxacine R, BLSE no_signal) |
| MIC005 | PAT005 | 03/06 11:00 | ISO_ECOLI | E. coli | hémoculture | 4 ATB (profil sensible, BLSE négative) |
| MIC006 | PAT006 | 02/01 09:30 | ISO_EFAEC | E. faecium | hémoculture | 1 ATB (vancomycine R, ERV) |

Points clés de microbiologie :

- **Attribution automatique au lit du patient :** Aucune de ces lignes ne porte
  d'unité de soins. C'est ORCHIDEE qui attribue chaque prélèvement à l'unité
  qui hébergeait le patient à l'heure exacte du prélèvement.
- **Co-infection et différenciation des souches (`souche_id`) :** Le prélèvement
  `MIC005` isole deux bactéries distinctes (*P. aeruginosa* et *E. coli*).
  Toutes deux testent la ciprofloxacine avec des résultats opposés (R pour
  Pseudomonas, S pour E. coli). Grâce à `souche_id` (`ISO_PSEAUR` vs
  `ISO_ECOLI`), ORCHIDEE gère les deux souches distinctement sans conflit.
- **Filtrage du dépistage :** `MIC003` est marqué `ratb_diagnostic_scope = FALSE`.
  Il n'a pas à être retiré manuellement du fichier : ORCHIDEE écarte toute
  l'occurrence documentaire du calcul des indicateurs diagnostiques.
- **Filtrage des antibiotiques :** Seules les molécules supportées par le
  standard RATB (`supported_atb_norm.csv`) figurent ici. Les éventuelles
  molécules hors nomenclature ont été filtrées en amont.

### Les trois blocs de correspondance

- `bacteria_mapping.csv` traduit le catalogue bactériologique local vers les
  taxons reconnus (`escherichia_coli`, `klebsiella_pneumoniae`,
  `staphylococcus_aureus`, `pseudomonas_aeruginosa`, `enterococcus_faecium`).
- `antibiotic_mapping.csv` mappe les libellés locaux vers la nomenclature
  standard (`cefotaxime`, `ciprofloxacine`, `imipeneme`, `ceftazidime`,
  `piperacilline_tazobactam`, `vancomycine`, etc.).
- `sample_type_mapping.csv` qualifie les types de prélèvement. Les types non
  ciblés par les indicateurs spécifiques (ex. `ECOUVILLON RECTAL`,
  `ASPIRATION TRACHEALE`) peuvent avoir un `naturepvt_norm` vide ; ils restent
  disponibles pour les agrégats globaux.

## Ce qu'ORCHIDEE en fait

### L'attribution

Chaque prélèvement reçoit l'unité qui hébergeait le patient à l'heure exacte
du prélèvement :

| Prélèvement | Instant | Unité active | Attribué à | Domaine |
|---|---|---|---|---|
| MIC001 | 10/02 06:30 | réanimation depuis le 08/02 09:00 | **UF_REA1** | RÉANIMATION |
| MIC002 | 02/03 10:15 | premier passage en médecine | **UF_MED1** | MÉDECINE |
| MIC004 | 11/05 23:00 | urgences | **UF_URG1** | URGENCES |
| MIC005 | 03/06 11:00 | chirurgie | **UF_CHIR1** | CHIRURGIE |
| MIC006 | 02/01 09:30 | hôpital de semaine | **UF_MED_SEM** | MÉDECINE |

`MIC001` est le cas typique : le séjour a commencé en médecine, mais le patient
était en réanimation lors du prélèvement. Un rapprochement grossier au séjour
l'aurait attribué à tort à la médecine ; ORCHIDEE l'attribue à la réanimation.

`MIC003` n'apparaît pas : son occurrence entière est écartée comme dépistage,
avant toute attribution.

### L'exposition

| Année | UM | UF | TA | DE | Domaine | Nuits 2024 |
|---|---|---|---|---|---|---|
| 2024 | UM_MED1 | UF_MED1 | 03 | 102 | MÉDECINE | **21** |
| 2024 | UM_REA1 | UF_REA1 | 03 | 105 | RÉANIMATION | **9** |
| 2024 | UM_CHIR1 | UF_CHIR1 | 03 | 146 | CHIRURGIE | **7** |
| 2024 | UM_SEM1 | UF_MED_SEM | 20 | 102 | MÉDECINE | **4** |
| 2024 | UM_URG1 | UF_URG1 | 10 | 211 | URGENCES | **3** |

Calcul des nuits 2024 :
- 21 = 3 (PAT001) + 3 + 5 (PAT002, deux visites) + 10 (PAT003).
- 9 = 7 (PAT001) + 2 (PAT002).
- 7 = 7 (PAT005).
- 4 = 4 nuits 2024 de PAT006 (les 4 nuits de 2023 ont été coupées).
- 3 = 3 (PAT004, urgences).

Total `bundle_v3` : **44 journées-patient**.
Le bundle opérationnel `bundle_v2_operational` ne retient que **41** :
`UF_URG1` sort du périmètre publié (TA 10). Les trois nuits d'urgences restent
enregistrées dans `v3` pour l'archive et l'audit.

## Le lancer

Depuis la racine du dépôt, pour l'année 2024 :

```console
python scripts/orchidee.py site --input-dir "examples/site_handoff_worked" --start-year 2024 --end-year 2024 --output "outputs/site_worked_example" --diagnose
```

Le diagnostic vérifie les règles contractuelles et annonce :

```text
5 exposure rows derived for 2024, totalling 44 patient-days over 9 unit stays.
4 nights fall in calendar years outside 2024 (2023) and are clipped out of the denominator.
Total profiled exposure 44; the spares_current projection retains 41.
6 sample occurrences were placed in the hosting unit active at sampling time.
4 of 5 distinct mapped units fall inside the current spares_current perimeter.
PASS: the six blocks satisfy the handoff contract. 0 warnings remain for review.
```

La même commande sans `--diagnose` construit les deux bundles (`bundle_v3` et
`bundle_v2_operational`).

## Ce qu'on retrouve dans le rapport Quarto

En lançant l'étape de rapport :

```console
python scripts/orchidee.py render --rebuild --bundle "outputs/site_worked_example/bundle_v2_operational" --workspace "outputs/site_worked_example/runtime" --start-year 2024 --end-year 2024 --output "outputs/site_worked_example/orchidee_ratb_indicators.html"
```

Le rapport final `orchidee_ratb_indicators.html` compile l'ensemble des
indicateurs :
- **Dénominateurs d'exposition :** 41 journées d'hospitalisation réparties entre
  Médecine (25 nuits), Réanimation (9 nuits) et Chirurgie (7 nuits).
- **Résistances bactériennes :**
  - *E. coli* : 1 souche BLSE (PAT001) et 1 souche sensible (PAT005).
  - *K. pneumoniae* : 1 souche BLSE urinaire (PAT002).
  - *S. aureus* : 0 cas comptabilisé dans les unités publiées (le SARM de PAT004
    a eu lieu aux urgences, hors périmètre).
  - *P. aeruginosa* : 1 souche résistante aux fluoroquinolones en chirurgie (PAT005).
  - *E. faecium* : 1 souche résistante aux glycopeptides / vancomycine (ERV, PAT006).

## Pour un vrai jeu de données

Ne pas modifier ces fichiers d'exemples. Pour initialiser les fichiers de votre
établissement :

1. Générer les modèles vierges et le kit de référence :
   ```console
   python scripts/orchidee.py site --emit-templates "data/mon_etablissement"
   ```
2. Consulter le [Guide de démarrage rapide](../../documentation/site_onboarding_quickstart.md)
   pour renseigner vos extractions et exécuter les étapes avec
   `examples/run_site_handoff.py`.
