---
editor_options:
  markdown:
    wrap: 72
---

# Sources méthodologiques et documents privés

Ce dépôt conserve les contrats exécutables et les décisions nécessaires pour
comprendre et reproduire la chaîne RATB. Il ne sert pas d'archive de documents
binaires institutionnels, de comptes rendus de réunion ou d'extractions
locales.

## Autorité versionnée dans le dépôt

- `documentation/ratb_indicator_spec.csv` définit le catalogue publié des
  indicateurs.
- `documentation/ratb_implementation_decisions.qmd` décrit les conventions
  méthodologiques effectivement implémentées.
- `documentation/external_bundle/` définit la frontière entre les adaptations
  locales et les bundles canoniques.

Ces fichiers sont les références à utiliser pour relire le code. Une source
externe ou un document de travail ne modifie pas à lui seul le comportement du
pipeline : la décision retenue doit d'abord être transcrite dans un contrat ou
un document versionné.

## Sources publiques

- [Mission SPARES — résultats de surveillance en établissement de
  santé](https://www.santepubliquefrance.fr/infections-associees-aux-soins/rapportsynthese/surveillance-de-la-consommation-des-antibiotiques-des-antifongiques-et-des-resistances-bacteriennes)
  : cadre national de surveillance des consommations et résistances.
- [Comité de l'antibiogramme de la Société française de
  microbiologie](https://www.sfm-microbiologie.org/presentation-de-la-sfm/sections-et-groupes-de-travail/comite-de-lantibiogramme/)
  : recommandations CA-SFM/EUCAST et catégories de sensibilité.
- [ECDC — surveillance et données sur la résistance aux
  antimicrobiens](https://www.ecdc.europa.eu/en/antimicrobial-resistance/surveillance-and-disease-data)
  : protocoles et rapports EARS-Net.
- [OMS — Global antibiotic resistance surveillance report
  2025](https://www.who.int/publications/i/item/9789240116337) : contexte de
  surveillance mondiale GLASS.
- [OMS — Bacterial Priority Pathogens List
  2024](https://www.who.int/publications/i/item/9789240093461) : hiérarchisation
  internationale des bactéries résistantes prioritaires.

Les liens pointent vers les pages éditoriales officielles afin que la version
courante puisse être identifiée sans conserver une copie PDF dans Git.

## Sources privées ou locales

Le document de travail `Expression_besoins_RATB_2-10-25.docx` est conservé
hors Git. Les décisions qui en découlent et qui sont actuellement exécutées
sont représentées par le catalogue et le mémo méthodologique versionnés
ci-dessus.

Le classeur de structure CONSORES est également un input opérationnel privé.
Le chemin par défaut est
`data/consores_structure_intranet_maj_2025.xlsx`; il peut être remplacé sans
modifier le code :

```powershell
$env:ORCHIDEE_CONSORES_STRUCTURE_PATH = "C:\chemin\protege\structure.xlsx"
```

Les présentations, comptes rendus, extractions locales, exports de pharmacie
et autres documents historiques ont été retirés de l'arbre public. Le corpus
retiré comprend 97 binaires et trois fichiers textuels sans consumer. Une
archive privée accompagnée de manifestes SHA-256 est conservée pour l'audit de
provenance. Aucun de ces fichiers n'est un input requis d'un clone public.
