# Orchidee Onboarding & Handoff

Vocabulaire et concepts régissant l'intégration des établissements hospitaliers et la transmission des données vers ORCHIDEE.

## Language

**Parcours standard**:
Le parcours universel d'intégration fondé sur les six blocs de données décrits dans le contrat de site (`documentation/site_contract.md`). Concerne Rennes et tout établissement sans adaptateur dédié dans le dépôt.
_Avoid_: Autre établissement, parcours externe, mode générique

**Parcours adapté**:
Le parcours d'intégration s'appuyant sur un adaptateur source versionné dans le dépôt traduisant directement des exports bruts en blocs internes (actuellement Rouen BACT + PMSI).
_Avoid_: Parcours natif, mode interne

**Bloc de transmission**:
L'un des six fichiers normalisés (microbiologie, séjours, correspondances) préparés et possédés par l'établissement.
_Avoid_: Table intermédiaire, input brut, fichier source

**Stade d'exécution**:
L'une des trois étapes séquentielles du pipeline d'intégration d'un site (`diagnostics`, `build`, `report`).
_Avoid_: Phase, step, mode de run
