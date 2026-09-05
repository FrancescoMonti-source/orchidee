---
editor_options:
  markdown:
    wrap: 72
---

# Exemple : des résultats de microbiologie et des mouvements aux indicateurs

Cet exemple contient des résultats de microbiologie, des mouvements hospitaliers
et leurs tables de correspondance, entièrement fictifs. Ce sont quatre séjours
inventés, choisis pour montrer ce qu'ORCHIDEE fait des blocs qu'un
établissement lui transmet — et surtout ce qu'il en fait *tout seul*.

Ce n'est pas le smoke test d'installation ; celui-ci est dans
`examples/site_handoff_minimal/` et répond à une autre question. Ici, on lit
des chiffres et on vérifie qu'on les retrouve. Le contrat lui-même est décrit
dans [site_contract.md](../../documentation/site_contract.md).

## Les entrées

### `hospitalization_intervals.csv` — sept lignes

Une ligne par visite ininterrompue dans une unité. Les bornes se lisent
`[entrée, sortie)`.

| Patient | Séjour | Unité | Entrée | Sortie | Nuits |
|---|---|---|---|---|---|
| PAT001 | SEJ001 | UF_MED1 | 05/02 14:00 | 08/02 09:00 | 3 |
| PAT001 | SEJ001 | UF_REA1 | 08/02 09:00 | 15/02 11:00 | 7 |
| PAT002 | SEJ002 | UF_MED1 | 01/03 08:00 | 04/03 10:00 | 3 |
| PAT002 | SEJ002 | UF_REA1 | 04/03 10:00 | 06/03 09:00 | 2 |
| PAT002 | SEJ002 | UF_MED1 | 06/03 09:00 | 11/03 12:00 | 5 |
| PAT003 | SEJ003 | UF_MED1 | 02/04 07:00 | 12/04 16:00 | 10 |
| PAT004 | SEJ004 | UF_URG1 | 10/05 22:00 | 13/05 06:00 | 3 |

Trois choses s'y jouent :

- **Le transfert de PAT001** est adjacent : la sortie de médecine est
  l'instant même de l'entrée en réanimation. Les deux visites ne se
  chevauchent pas et le patient n'est compté qu'une fois.
- **PAT002 revient en UF_MED1** après un passage en réanimation. Les deux
  visites restent séparées : UF_MED1 reçoit 3 + 5 = 8 nuits, pas les 10 que
  donnerait un `min(entrée)` / `max(sortie)` par unité, qui avaleraient au
  passage les deux nuits de réanimation.
- **PAT003 n'a aucune microbiologie.** Ses 10 nuits comptent quand même : le
  dénominateur ne dépend pas des prélèvements.

### `unit_mapping.csv` — trois unités

| SEJUF | CODE_TA | CODE_DE | Domaine | Dans le périmètre publié ? |
|---|---|---|---|---|
| UF_MED1 | 03 | 102 | MÉDECINE | oui |
| UF_REA1 | 03 | 105 | RÉANIMATION | oui |
| UF_URG1 | 10 | 211 | URGENCES | **non** |

`UF_URG1` est mappée correctement et son activité est réelle. Elle sort du
périmètre parce que son TA vaut 10 et non 03 ou 20 — pas parce que la donnée
serait fausse. C'est exactement la distinction que `v3` conserve et que `v2`
applique.

### `microbiology_observations.csv` — sept lignes, quatre prélèvements

| Prélèvement | Patient | Date, heure | Bactérie | Type | Lignes |
|---|---|---|---|---|---|
| MIC001 | PAT001 | 10/02 06:30 | E. coli | hémoculture | 3 antibiotiques |
| MIC002 | PAT002 | 02/03 10:15 | K. pneumoniae | ECBU | 2 antibiotiques |
| MIC003 | PAT002 | 09/03 08:00 | K. pneumoniae | écouvillon rectal | 1, dépistage |
| MIC004 | PAT004 | 11/05 23:00 | S. aureus | hémoculture | 1 antibiotique |

Aucune de ces lignes ne porte d'unité. C'est voulu : dans ce parcours, c'est
ORCHIDEE qui décide où le patient était au moment du prélèvement, à partir du
bloc précédent. Le site n'a pas à faire ce rapprochement, et ne peut donc pas
le faire différemment d'un établissement à l'autre.

`MIC003` est marqué `ratb_diagnostic_scope = FALSE`. Il n'a pas à être retiré
du fichier : il suffit de le marquer.

### Les trois blocs de correspondance

`bacteria_mapping`, `sample_type_mapping` et `antibiotic_mapping` traduisent le
vocabulaire local. `ECOUVILLON RECTAL` est mappé vers un `naturepvt_norm` vide :
c'est permis, et cela veut dire que la ligne reste disponible pour les
indicateurs globaux sans pouvoir contribuer à une analyse par type de
prélèvement. Ici la question ne se pose pas, le prélèvement étant de toute
façon écarté comme dépistage.

## Ce qu'ORCHIDEE en fait

### L'attribution

Chaque prélèvement reçoit l'unité qui hébergeait le patient à l'heure exacte
du prélèvement :

| Prélèvement | Instant | Unité active | Attribué à |
|---|---|---|---|
| MIC001 | 10/02 06:30 | réanimation depuis le 08/02 09:00 | **UF_REA1** |
| MIC002 | 02/03 10:15 | premier passage en médecine | UF_MED1 |
| MIC004 | 11/05 23:00 | urgences | UF_URG1 |

`MIC001` est le cas intéressant : le séjour a commencé en médecine, et un
rapprochement au séjour l'aurait rangé là. Il appartient à la réanimation.

`MIC003` n'apparaît pas : son occurrence entière est écartée comme dépistage,
avant toute attribution.

### L'exposition

| Année | UM | UF | TA | DE | Domaine | Nuits |
|---|---|---|---|---|---|---|
| 2024 | UM_MED1 | UF_MED1 | 03 | 102 | MÉDECINE | **21** |
| 2024 | UM_REA1 | UF_REA1 | 03 | 105 | RÉANIMATION | **9** |
| 2024 | UM_URG1 | UF_URG1 | 10 | 211 | URGENCES | **3** |

21 = 3 (PAT001) + 3 + 5 (PAT002, deux visites) + 10 (PAT003).
9 = 7 (PAT001) + 2 (PAT002).

Total `v3` : **33 journées-patient**. Le bundle `v2` opérationnel n'en retient
que **30** : `UF_URG1` sort du périmètre publié. Les trois nuits ne sont pas
perdues, elles restent dans `v3`.

## Le lancer

Depuis la racine du dépôt, période 2024 :

```console
python scripts/orchidee.py site --microbiology-observations "examples/site_handoff_worked/microbiology_observations.csv" --bacteria-mapping "examples/site_handoff_worked/bacteria_mapping.csv" --sample-type-mapping "examples/site_handoff_worked/sample_type_mapping.csv" --antibiotic-mapping "examples/site_handoff_worked/antibiotic_mapping.csv" --unit-mapping "examples/site_handoff_worked/unit_mapping.csv" --hospitalization-intervals "examples/site_handoff_worked/hospitalization_intervals.csv" --start-year 2024 --end-year 2024 --output "outputs/site_worked_example" --diagnose
```

`--diagnose` n'écrit qu'un rapport. Il annonce, entre autres :

```text
3 exposure rows derived for 2024, totalling 33 patient-days over 7 unit stays.
Total profiled exposure 33; the spares_current projection retains 30.
4 sample occurrences were placed in the hosting unit active at sampling time.
2 of 3 distinct mapped units fall inside the current spares_current perimeter.
```

La même commande sans `--diagnose` construit les deux bundles. Le
dénominateur annuel de `bundle_v2_operational/denominator_bundle.rds` vaut
alors 30, et `bundle_v3/denominator_bundle.rds` porte les trois lignes du
tableau ci-dessus.

Le rendu du rapport est une étape distincte, à ne lancer que si les
indicateurs doivent être calculés sur cette machine ; la commande est affichée
en fin de build. Sur quatre séjours, les proportions publiées n'ont évidemment
aucun sens clinique : ce qui se vérifie ici est le chemin, pas le résultat.

## Pour un vrai jeu de données

Ne pas partir de ces fichiers. Générer des modèles vides et le kit de
correspondance ORCHIDEE :

```console
python scripts/orchidee.py site --emit-templates "data/site_handoff"
```

et copier `examples/run_site_handoff.py` à côté des données protégées pour
enchaîner diagnostic, build et rendu sans retaper les six chemins.
