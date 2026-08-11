---
editor_options:
  markdown:
    wrap: 80
---

# Flux opérationnel ORCHIDEE

Cette page décrit uniquement le chemin actuellement ratifié. Les procédures
opérateur et les schémas détaillés restent autoritaires pour leurs périmètres.

## Flux canonique

```text
ROUEN                                  RENNES / AUTRE SITE
export BACT + PMSI redsan              six blocs préparés par le site
        |                                       |
        v                                       |
adaptateur Rouen versionné                      |
        |                                       |
        +---------------+-----------------------+
                        |
                        v
             six blocs de handoff complets
                        |
                        v
               builder partagé ORCHIDEE
                        |
                        +--> bundle v3 complet et conservé
                        |           |
                        |     projection fermée
                        |       spares_current
                        |           |
                        |           v
                        +--> bundle v2 opérationnel
                                    |
                                    v
                         runtime RATB partagé
                                    |
                       périmètre et plausibilité
                       dédoublonnage SPARES
                       indicateurs annuels
                       rapport
```

Rouen et un site externe diffèrent seulement avant les six blocs. Ils utilisent
ensuite le même builder, le même runtime et la même méthode.

## Responsabilités

-   **`redsan`** possède l'accès EDSaN, le batching, la normalisation PMSI/BIOL
    et la politique source PMSI `C > DW`.
-   **L'adaptateur local** possède les décisions dépendantes du site :
    screening, mappings, attribution de l'UF d'hébergement et construction de
    l'exposition.
-   **Le builder partagé** valide les six blocs, construit le bundle v3 et
    matérialise sa projection v2.
-   **Le runtime RATB** applique le périmètre, la plausibilité biologique, le
    dédoublonnage et le catalogue d'indicateurs.
-   **Le rapport** restitue les résultats ; il ne redéfinit ni la méthode ni le
    périmètre.

## Frontière v3 vers v2

`v2` et `v3` ne sont pas deux versions successives d'un protocole, et `v2`
n'est pas un état ancien resté en place. Ce sont deux formes du même bundle,
produites ensemble par le même build.

Le bundle v3 est le contrat de construction complet. Il conserve les quatre
fichiers canoniques et l'exposition profilée au grain année + UM + UF + TA + DE.

Le contexte fermé `spares_current` sélectionne le périmètre TA/DE ratifié et le
profil `midnight_presence`, puis produit un bundle v2 distinct. Le v3 n'est ni
écrasé ni utilisé directement par les notebooks.

Le bundle v2 est l'unique entrée opérationnelle. Il transporte le dénominateur
annuel requis par les indicateurs actuels :

```text
calendar_year + hospital_nights
```

Le détail v3 permet de conserver une exposition plus riche, mais ORCHIDEE ne
publie pas encore de densités stratifiées par UM, UF, TA ou DE. Une telle
publication demanderait aussi les numérateurs, le dédoublonnage contextuel et
les unités correspondantes ; elle ne s'active pas par configuration.

## Sémantique de l'unité

Dans les deux contrats, `sir_wide$SEJUF` désigne l'UF d'hébergement active au
moment du prélèvement. L'adaptateur doit établir cette attribution avant le
handoff. Une attribution absente ou ambiguë reste auditée et ne retombe pas
silencieusement sur l'UF microbiologique.

Le runtime vérifie également que les codes TA, DE et domaine DE de l'exposition
v3 concordent avec la référence de périmètre des prélèvements avant de produire
le total annuel v2.

## Chemin analytique actif

Le runtime calcule uniquement le chemin brut, sans complétion. La complétion
exploratoire et `chu_native` sont retirés de l'arbre actif ; leur dernière
implémentation cohérente reste consultable au tag
`archive/completion-chu-native-2026-07-22`.

Un rendu complet passe par `scripts/render_orchidee.ps1`, qui construit le cache
brut canonique puis rend le rapport. Il affiche les chemins effectivement
consommés et échoue avant le calcul si le bundle ou l'environnement est
invalide. Les commandes et la matrice de rendu vivent dans le
[`runbook de maintenance`](maintenance_runbook.md).
