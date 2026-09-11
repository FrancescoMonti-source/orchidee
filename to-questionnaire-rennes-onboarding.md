# Questionnaire d'intégration ORCHIDEE — Données et Environnement CHU de Rennes

**Objet :** Identifier les caractéristiques des données sources et de l'infrastructure du CHU de Rennes pour calibrer l'intégration au projet national ORCHIDEE (surveillance RATB).

**De :** Équipe pilote ORCHIDEE, **À :** Équipe Entrepôt de Données de Santé (EDS) / Direction des Services Numériques du CHU de Rennes, **Usage des réponses :** Calibrer les règles d'extraction, ajuster les tolérances du pipeline d'intégration et assurer la compatibilité technique de l'environnement d'exécution.

## Contexte

Le projet ORCHIDEE calcule les indicateurs de surveillance de la résistance aux antibiotiques (RATB / mission SPARES) à partir des résultats de bactériologie et des séjours d'hospitalisation de l'établissement. Pour intégrer les données du CHU de Rennes sans adaptateur spécifique préalable, ORCHIDEE utilise un contrat d'interface en 6 blocs de données standardisés (microbiologie, mouvements de séjours, tables de correspondance). Ce questionnaire vise à identifier les spécificités de vos bases sources pour anticiper les points de blocage avant toute extraction lourde.

## Modalités de réponse

Ce questionnaire demande environ 15 à 20 minutes de relecture par l'équipe en charge des extractions de données. Les réponses partielles ou les mentions « à investiguer » sont parfaitement acceptées : signalez ce qui est incertain plutôt que de laisser une question sans réponse.

---

## 1. Données de microbiologie et antibiogrammes

### L'identifiant patient (IPP) et l'identifiant de séjour (NDA / numéro de venue) sont-ils partagés de façon identique et cohérente sur l'ensemble de vos datamarts (laboratoire, mouvements, PMSI), permettant de les relier sans ambiguïté ?

_Pourquoi c'est important : Pour relier un résultat bactériologique au séjour d'hospitalisation correspondant, les clés `PATID` et `EVTID` doivent coïncider strictement entre toutes les tables sources (mêmes valeurs, sans troncature de zéros initiaux ni préfixes divergents selon le système)._

>

### Tous les prélèvements de bactériologie portent-ils un identifiant de séjour (ex. NDA / numéro de venue), y compris pour les urgences et les consultations externes ?

_Pourquoi c'est important : ORCHIDEE exige la présence d'un identifiant de séjour sur chaque résultat. Une absence d'identifiant de séjour entraîne le rejet de la ligne._

>

### Dans vos extractions de bactériologie, l'heure exacte du prélèvement est-elle renseignée de manière fiable ?

_Pourquoi c'est important : ORCHIDEE attribue chaque prélèvement à l'unité de soins qui hébergeait le patient à la minute exacte du prélèvement. Sans heure valide, le prélèvement ne peut pas être situé dans un séjour et est exclu du calcul des indicateurs._

>

### Si l'heure du prélèvement n'est pas saisie par le soignant, quelle valeur apparaît dans la base ?

_Pourquoi c'est important : Savoir si le système renseigne une valeur nulle (vide / NA), l'heure d'enregistrement au laboratoire, ou une heure par défaut comme 00:00:00 (ce qui risque de faire sortir le prélèvement d'un séjour commencé à 08:00)._

>

### Disposez-vous d'une information distinguant les prélèvements à visée diagnostique des prélèvements de dépistage systématique (ex. dépistage de portage BMR à l'admission) ? Sous quel format (champ structuré ou texte libre) ?

_Pourquoi c'est important : Le protocole national RATB impose d'exclure l'ensemble des prélèvements de dépistage du calcul des indicateurs. ORCHIDEE attend une colonne `ratb_diagnostic_scope` (TRUE/FALSE) ; nous devons savoir si vous disposez d'un indicateur direct ou s'il faudra construire une règle basée sur le libellé de l'analyse ou le service demandeur._

>

### Arrive-t-il qu'un même prélèvement contienne plusieurs antibiogrammes pour la même espèce bactérienne (ex. deux lignes pour *Escherichia coli* correspondant à deux colonies distinctes) ? Si oui, disposez-vous d'un identifiant de souche ou d'isolat pour les distinguer ?

_Pourquoi c'est important : Si deux antibiogrammes coexistent pour la même espèce sur un prélèvement sans identifiant d'isolat (`souche_id`), ORCHIDEE fusionne les deux lignes sous un même isolat dérivé ; tout résultat contradictoire (ex. l'une S et l'autre R sur une molécule) bloquera alors le diagnostic comme une incohérence de lecture._

>

### Les marqueurs de résistance particuliers (notamment BLSE et carbapénémases) sont-ils présents sous forme de champs structurés, ou uniquement en texte libre / commentaires ?

_Pourquoi c'est important : ORCHIDEE dispose d'un champ optionnel pour ces statuts ; s'ils sont structurés, leur transmission directe fiabilise le calcul des indicateurs associés._

>

### Périmètre des antibiotiques testés : appliquez-vous le filtre sur la nomenclature standard lors de la préparation du fichier ?

_Pourquoi c'est important : Au point de jonction (seam) contractuel, le fichier `microbiology_observations.csv` transmis à ORCHIDEE doit contenir uniquement les résultats pour les molécules supportées par le catalogue national RATB (référencées dans `mapping_reference/supported_atb_norm.csv`). Tout antibiotique hors nomenclature doit être filtré avant transmission. Peu importe si votre extraction amont depuis le datamart extrait un périmètre plus large : l'essentiel est de savoir si ce filtre est appliqué de votre côté lors de la constitution du bloc standardisé (ce qui est le comportement attendu par le contrat)._

>

---

## 2. Mouvements et séjours d'hospitalisation

### Dans votre entrepôt de données, les séjours d'hospitalisation sont-ils intégrés uniquement une fois le séjour administrativement clôturé (patient sorti), ou des séjours en cours d'hospitalisation sont-ils également présents dans vos tables de mouvements ?

_Pourquoi c'est important : Si l'entrepôt n'intègre que les séjours clôturés, une extraction sur une période passée (ex. 2022–2024) garantit que tous les séjours sont complets avec une date de sortie réelle (`DATSORT`), écartant le risque d'anomalie liée à des séjours ouverts sans date de sortie._

>

### Dans votre base de mouvements, des transferts entre unités présentent-ils des chevauchements d'horaires pour un même patient ?

_Pourquoi c'est important : Il arrive fréquemment qu'une sortie de réanimation soit enregistrée administrativement à 14h30 alors que l'entrée en médecine a été validée à 14h15. Actuellement, ORCHIDEE refuse tout chevauchement d'unité de durée strictement positive._

>

---

## 3. Structure hospitalière et typologie des unités

### Disposez-vous d'une table faisant le lien entre vos unités d'hébergement et les codes nationaux PMSI (codes d'autorisation TA et codes de discipline d'équipement DE) ?

_Pourquoi c'est important : Le périmètre de publication RATB (MCO) est filtré sur les autorisations nationales TA (03, 20) et les disciplines DE éligibles (Médecine, Chirurgie, Réanimation, etc.). Chaque unité locale doit être mise en correspondance._

>

---

## 4. Environnement technique et infrastructure

### Sur quel type d'environnement ORCHIDEE sera-t-il exécuté (serveur Linux interne, machine virtuelle Windows, poste d'analyse sécurisé) ?

_Pourquoi c'est important : Pour calibrer la syntaxe des scripts de lancement et les chemins de fichiers (barres obliques, droits d'accès)._

>

### Quelle version de R est actuellement disponible ou déployable sur cet environnement ?

_Pourquoi c'est important : Le projet a été gelé sur R 4.5.3, mais dispose d'un mode de compatibilité pour fonctionner avec les versions R 4.3.x et 4.4.x installées sur les serveurs institutionnels._

>

### Cet environnement dispose-t-il d'un accès à Internet (direct ou via un proxy d'établissement) pour installer les paquets R depuis le CRAN ?

_Pourquoi c'est important : L'installation automatisée du projet télécharge les bibliothèques R requises. Si le serveur est totalement hors-ligne (zone étanche / sans accès CRAN), un bundle d'installation pré-packagé ou une image conteneur devra être prévu._

>

### Les outils Quarto, Python (version 3.8 ou plus récente) et Git sont-ils utilisables sur cet environnement ?

_Pourquoi c'est important : Ce sont les prérequis d'orchestration et de génération du rapport HTML final._

>

---

## 5. Remarques et particularités locales

### Y a-t-il des spécificités de votre entrepôt de données ou de vos systèmes de laboratoire que nous n'avons pas mentionnées et qui pourraient impacter ces extractions ?

>
