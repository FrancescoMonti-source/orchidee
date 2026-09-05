# Contrats protégés par les tests

Cet inventaire décrit les assertions existantes, pas une couverture souhaitée.
Une ligne regroupe les cas qui protègent une même décision ; un fichier peut
donc apparaître plusieurs fois. Les fixtures sont synthétiques.

**Commun** concerne Rouen et Rennes (et tout autre établissement sans
adaptateur). **Site** concerne le parcours de Rennes et des autres
établissements sans adaptateur. **Rouen** concerne ses exports et références.
Ce périmètre indique qui subirait la régression, pas qui doit réparer le code :
la suite est entretenue par les mainteneurs ORCHIDEE. Les équipes locales
restent responsables de leurs extractions et correspondances.

Depuis la racine du dépôt :

```console
python scripts/orchidee.py run-r tests/run_tests.R
```

Le lanceur découvre les `tests/test_*.R`, chacun dans un processus R séparé,
et s'arrête au premier fichier en échec. Pour un seul fichier, remplacer
`tests/run_tests.R` par son chemin. Ce n'est pas une suite `testthat`.

| Test / groupe de cas | Concernés | Contrat effectivement vérifié | Régression que le cas détecterait |
|---|---|---|---|
| [documentation_references](../tests/test_documentation_references.R) | Commun, mainteneurs | Les fichiers et fonctions nommés dans les tableaux de `methods.md` existent ; les fonctions sont dans les fichiers cités. | Déplacement ou suppression de code laissant un pointeur méthodologique périmé. Ne vérifie pas la vérité du texte. |
| [external_bundle_v2_semantics](../tests/test_external_bundle_v2_semantics.R) | Commun | Version v2 et sens de `SEJUF` explicitement déclarés ; rapport de validation de même version. | Acceptation d'une unité de microbiologie à la place de l'unité d'hébergement, ou validation réutilisée pour une autre version. |
| [external_bundle_v3_denominator](../tests/test_external_bundle_v3_denominator.R) — exposition | Commun | Grain fin unique, profil/unité autorisés, valeurs entières finies ; activité hors périmètre conservée ; UF et TA/DE cohérents entre artefacts. | Double compte, unité d'exposition incohérente, activité perdue dans l'archive, ou dénominateur impossible à rattacher au périmètre. |
| Même fichier — projection | Commun | v3 → v2 conserve exactement la microbiologie et agrège seulement l'exposition éligible ; fixture : 100 et 75 nuits. | Projection qui change les prélèvements ou inclut les nuits hors périmètre. |
| Même fichier — construction CLI R | Site | Construction des deux bundles validés avec identifiant de build commun ; sorties distinctes ; échec de validation sans modification du build précédent, même avec `--force`. | Paire v3/v2 incohérente, collision de chemins, écrasement d'une sortie valide par des entrées invalides. |
| [external_handoff_screening_document_key](../tests/test_external_handoff_screening_document_key.R) | Commun | Identité obligatoire `PATID + EVTID + ELTID` ; lignes sans séjour écartées avant dépistage ; colonne absente ou entièrement vide refusée ; bundle sans identifiant de séjour refusé ; résultat SIR et phénotypes agrégés sur une seule ligne. | Repli silencieux au seul patient, `ELTID` réutilisé supprimant un autre patient/séjour, dépistage propagé par une ligne écartée ou agrégation incorrecte. |
| [operational_v2_gate](../tests/test_operational_v2_gate.R) | Commun, mainteneurs | Le comparateur ignore l'heure de build mais refuse une modification de version, de nuits ou de cellule Excel. | Porte de comparaison qui laisse passer une dérive ou refuse seulement un nouvel horodatage. Ne prouve pas la justesse des chiffres comparés. |
| [ratb_denominator_interval_union](../tests/test_ratb_denominator_interval_union.R) | Rouen ; union partagée | Le constructeur PMSI compte A → B → A comme 6 nuits et fusionne les chevauchements d'une unité en 4 nuits. | Fusion des deux visites A à travers B ou addition des lignes recouvrantes. |
| [ratb_hospitalization_unit_attribution](../tests/test_ratb_hospitalization_unit_attribution.R) | Commun ; départage par unité source propre à Rouen | Attribution à l'instant du prélèvement, bornes semi-ouvertes, absence/ambiguïté sans rattachement arbitraire, interprétation de l'heure locale ; trous entre visites préservés. | Mauvaise unité à un transfert, rattachement dans un trou de séjour ou résolution silencieuse d'une heure ambiguë. |
| [ratb_operational_input_runtime](../tests/test_ratb_operational_input_runtime.R) | Commun | Chargement strict v2 ; séparation des sorties et chemins protégés, y compris les chemins lexicaux vers des dossiers absents. | Métadonnées manquantes acceptées ou collision masquée par `./`, `..` ou un dossier inexistant. |
| [ratb_raw_runtime](../tests/test_ratb_raw_runtime.R) — calcul | Commun | Valeurs antibiotiques inchangées, aucun remplissage ; déduplication globale sélectionnant L2/L3 et par type L1/L2/L3. | Imputation de résultats absents, perte de la distinction globale/par type ou mauvais représentant dans cette fixture. |
| Même fichier — cache | Commun | Réutilisation seulement si bundle, code et mapping concordent ; métadonnées illisibles ou anciennes invalidées. | Publication de résultats calculés avec d'autres entrées, une ancienne déduplication ou taxonomie. Vérifie la décision d'invalidation, pas un rendu complet. |
| [rouen_raw_handoff](../tests/test_rouen_raw_handoff.R) — microbiologie | Rouen | Traduction de libellés ATB proches mais distincts, exclusions documentaires, vocabulaire SIR, mappings et signal phénotypique lu sur le brut. | Mauvais breakpoint/molécule, dépistage retenu, espèce ambiguë conservée ou signal BLSE perdu. |
| Même fichier — PMSI et bundles | Rouen | Références locales, fenêtre PMSI, unité d'hébergement ; 32 nuits archivées dont 31 dans le périmètre ; projection et construction CLI, manifeste et verrou. | Attribution de secours, nuits hors fenêtre/périmètre, perte d'activité dans v3, build incomplet ou écriture concurrente. Le CLI testé ici est le constructeur R. |
| [rouen_structure_path](../tests/test_rouen_structure_path.R) | Rouen | Référence par défaut et remplacement explicite par `ORCHIDEE_ROUEN_STRUCTURE_PATH`, lus par la configuration et le chargeur de références. | Un des deux chemins ignore le fichier de structure explicitement choisi. |
| [site_hospitalization_intervals](../tests/test_site_hospitalization_intervals.R) — nuits | Site ; union partagée | Retours, doublons, chevauchements, borne annuelle, séjour sans microbiologie et séjour de jour ; totaux attendus par unité. | Nuits comptées deux fois, hors période, ou perdues faute de prélèvement ; séjour de jour compté comme une nuit. |
| Même fichier — attribution et refus | Site | Unité dérivée des intervalles ; prélèvement non situable conservé hors périmètre ; double occupation, intervalle inversé, clé absente et horodatage invalide refusés ; build bloqué pour double occupation. | Mauvaise unité attribuée ou construction malgré une occupation contradictoire ; disparition silencieuse d'une anomalie d'intervalle. |
| Même fichier — période | Site + défaut Rouen | Microbiologie filtrée ; paire d'années d'environnement lue par la configuration, borne isolée refusée ; retour au même défaut après remplacement, sans figer ses années. | Période partiellement devinée ou configuration ignorant les années explicites ou conservant le remplacement. Ne teste pas la transmission de ces variables par le processus de rendu Python. |
| [site_input_diagnostics](../tests/test_site_input_diagnostics.R) — verdict | Site | Ensemble des problèmes indépendants, distinction BLOCKING/WARNING/INFO ; pour les fixtures acceptées, construction v3 et v2 réellement exécutée. | Faux PASS, avertissement devenu blocage ou première erreur masquant les suivantes. Cette implication est vérifiée sur les fixtures, pas sur toute entrée possible. |
| Même fichier — interprétation | Site | Dates/heures CSV et RDS, formes mixtes, suffixes et fractions ; dates stockées dans le bundle ; conflits de grain et SIR avant/après mapping distingués ; colonne de séjours entièrement vide bloquante. | Date lisible mais erronée, heure tronquée, grain scindé par une fraction invisible, mauvais diagnostic d'un conflit ou faux PASS sans séjour utilisable. |
| Même fichier — rapport | Site | Comptes d'occurrences distinctes, exposition totale/éligible, liste complète des valeurs et lien aux constats ; absence des identifiants patients synthétiques dans les fichiers. | Double compte d'un document, valeurs à corriger tronquées ou identifiants des fixtures divulgués. Ce dernier contrôle n'est pas une garantie générale d'anonymisation. |
| Même fichier — publication et CLI | Site | Statuts 0/1/2, aucun bundle en mode diagnostic, retrait des artefacts périmés, ancien rapport préservé en cas d'échec, manifeste et possession du verrou. | Échec technique attribué aux données du site, rapport mêlant deux runs ou libération du verrou d'un autre run. Le cas de manifeste indélébile est exercé seulement sous Windows. |
| [site_onboarding](../tests/test_site_onboarding.R) — installation et modèles | Site | Six blocs publics, modèles et fixture cohérents, références de mapping exportées ; précontrôle d'un mapping échangé sans build. | Site recevant des colonnes/modèles inutilisables ou précontrôle acceptant les mauvais fichiers. |
| Même fichier — parcours opérateur | Site ; précontrôle de rendu commun | CLI Python : smoke build, chemins avec caractères spéciaux, paire de manifestes, collision/reprise/force/verrou ; précontrôle R de rendu sur bundle valide/invalide. | Arguments mal transmis, sorties écrasées ou bundle invalide admis au précontrôle. Ne lance pas Quarto. |

`tests/python_cli_helpers.R` choisit Python et capture le statut des commandes ;
`tests/run_tests.R` orchestre les fichiers. Ils n'ont pas de contrat analytique
propre. `ORCHIDEE_PYTHON` permet aux tests de choisir un interpréteur explicite.

## Ce qu'un PASS de cette suite ne démontre pas

- Les formules de `compute_ratb_indicator_result()` : dénominateur S+R,
  priorité des molécules, phénotypes, densité d'incidence. Le test de la porte
  de comparaison utilise des cellules inventées, sans calculer les indicateurs.
- L'ensemble des décisions de déduplication : conflit S↔R, ZIT non informatif,
  séparation des années, ordre glouton et tous les départages. La fixture du
  runtime n'en exerce qu'un cas simple.
- Le filtrage de plausibilité espèce/ATB et l'affichage final du rapport.
  Le sentinelle Rouen vérifie certains mappings et leur appartenance au panel,
  pas toute l'application du filtre.
- La validité d'une extraction réelle, la comparabilité entre établissements,
  le lancement Python Rouen complet ou un rendu Quarto. Le test de références
  documentaires ne contrôle pas non plus tous les liens du dépôt.

Pour une modification analytique, la procédure de vérification complémentaire
reste celle de [knobs.md](knobs.md) : suite, rendu et comparaison opérationnelle
sur les artefacts protégés. Ajouter un test exige d'abord de nommer la décision
et le résultat attendu indépendamment du code qui la calcule.
