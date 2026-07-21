---
editor_options:
  markdown:
    wrap: 72
---

# Décision d'adoption opérationnelle du bundle v2 — 2026-07-19

## Décision

`external_bundle_v2` devient l'entrée opérationnelle canonique et la valeur
par défaut des notebooks. `chu_native` reste disponible explicitement pour la
comparaison historique et le rollback ; ce changement ne le supprime pas et
n'ajoute aucun fallback entre les deux chemins.

Cette décision concerne le runtime des notebooks. Les builders demandent
désormais explicitement v2 ou v3 : un site ne doit déclarer aucun de ces
contrats avant d'avoir attribué à `SEJUF` l'UF d'hébergement active au
prélèvement, conformément à `sir_wide.md`.

## Éléments observés avant adoption

La comparaison locale 2022–2024, exécutée depuis la baseline ORCHIDEE
`48a960d`, a parcouru les deux chemins jusqu'aux panels publiés, avec uniquement
des agrégats non identifiants conservés ici. Les écarts observés ont été revus
et acceptés avant le changement de valeur par défaut.

- Le chemin natif contenait 48 666 lignes SIR en amont, contre 48 600 pour le
  bundle v2.
- Après périmètre et plausibilité, les populations analytiques contenaient
  respectivement 29 082 et 26 427 lignes, dont 26 040 isolats communs.
- Pour ces isolats communs, les résultats antibiotiques bruts et les flags de
  phénotype étaient identiques.
- Les 5 970 clés de publication attendues étaient présentes dans les deux
  exécutions ; aucune clé n'était propre à un seul chemin.
- Les dénominateurs annuels v2 différaient du natif de -0,39 % en 2022,
  -0,32 % en 2023 et -0,41 % en 2024.
- La variation médiane relative de densité d'incidence était de -7,04 % ; elle
  provenait principalement du numérateur et du périmètre, pas du dénominateur.

Les écarts ne sont donc pas interprétés comme une régression du moteur RATB.
Ils résultent principalement de la décision méthodologique v2 : utiliser l'UF
d'hébergement au prélèvement et laisser les attributions non résolues hors du
périmètre, sans fallback vers l'UF microbiologique.

## Limites et suites séparées

Cette adoption ne valide pas automatiquement l'adaptateur brut d'un autre
établissement. Chaque site doit encore démontrer son attribution d'UF, ses
mappings et son dénominateur avant de déclarer un bundle v2.

La suppression éventuelle de `chu_native` et la généralisation d'un outil de
comparaison restent des décisions ultérieures et séparées. Le contrat de
compatibilité antérieur a depuis été retiré sans modifier le runtime v2.
