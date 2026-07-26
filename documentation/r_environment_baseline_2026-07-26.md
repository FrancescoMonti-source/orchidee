---
editor_options:
  markdown:
    wrap: 80
---

# Qualification de l'environnement R du 2026-07-26

Cette note consigne la qualification du lock R adopté avec le parcours
d'onboarding Rouen. Elle ne contient ni donnée clinique ni chemin privé.

## Changement enregistré

-   R reste fixé exactement à 4.5.3.
-   Le lock contient toujours 111 paquets.
-   Les sources des paquets ne changent pas.
-   Le commit `redsan` reste
    `7dcd064a2a51efd11aed16b289b4c831480f00ea`.
-   34 versions CRAN sont actualisées ; `renv` passe de 1.1.5 à 1.2.3.

Ce refresh n'est pas cosmétique. Depuis une bibliothèque et un cache vides,
l'ancien lock demandait plusieurs versions CRAN qui n'étaient plus disponibles
comme binaires Windows pour R 4.5.3. La restauration tentait alors des builds
source et échouait sur `curl` 7.0.0 et `zip` 2.3.3, puis sur `openxlsx` par
dépendance.

## Bootstrap froid

Le 2026-07-26, `scripts/setup.ps1` a été exécuté après déplacement de la
bibliothèque de projet et avec une cache `renv` et une user-library vides.

Résultat :

-   bootstrap de `renv` 1.2.3 depuis CRAN ;
-   téléchargement puis installation des 110 autres paquets du lock ;
-   `redsan` 0.2.0 construit depuis le commit enregistré ;
-   `renv::status()` synchronisé ;
-   aucune dépendance récupérée depuis la bibliothèque utilisateur précédente.

Sur le poste de qualification, R/libcurl ne pouvait pas joindre le service de
révocation TLS alors que Windows Schannel validait le certificat. Le setup
utilise donc, uniquement pendant la restauration sous Windows, `curl` avec la
politique Schannel `--ssl-revoke-best-effort`. La chaîne du certificat reste
validée et une configuration explicite de téléchargement reste prioritaire.

## Gate fonctionnel réel

La bibliothèque restaurée à froid a ensuite servi à :

1.  exécuter les neuf tests source autonomes ;
2.  construire les six blocs Rouen, le bundle v3 et sa projection v2 à partir
    des deux exports réels ;
3.  exécuter les quatre validations du manifest ;
4.  rendre le runtime et le rapport complets ;
5.  comparer le candidat à la baseline opérationnelle acceptée du 2026-07-20.

Le gate final a confirmé à tolérance zéro :

-   l'identité des quatre objets du bundle v2, en normalisant uniquement
    `sir_wide_meta$created_at` comme prévu par le gate ;
-   l'identité du cache de dédoublonnage et de son audit ;
-   la présence des mêmes 36 classeurs ;
-   l'identité cellule par cellule de toutes leurs feuilles.

Le refresh du lock est donc installable depuis un environnement vide et ne
modifie pas les résultats opérationnels qualifiés.
