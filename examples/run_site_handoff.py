#!/usr/bin/env python3
"""Fichier de lancement ORCHIDEE, à copier et à modifier.

Ce fichier ne contient aucun calcul. Il enregistre les décisions d'un
établissement — où sont ses données, où écrire, quelles années publier — et appelle
`python scripts/orchidee.py`, qui fait le travail.

Marche à suivre :

1. copier ce fichier hors du dépôt, à côté des données protégées ;
2. remplir le bloc RÉGLAGES ci-dessous ;
3. le lancer tel quel. Il démarre au stade `diagnostics`, qui ne construit
   rien et ne peut rien écraser ;
4. lire le rapport, corriger ce qui est signalé BLOCKING, relancer ;
5. quand le diagnostic passe, mettre STAGE à `build`, puis à `report` si les
   indicateurs doivent être calculés sur cette machine.

Lancement :

    python run_site_handoff.py

Il n'y a rien d'autre à installer que ce que `python scripts/orchidee.py
setup` a déjà mis en place.
"""

import subprocess
import sys
from pathlib import Path

# ===========================================================================
# RÉGLAGES — la seule partie à modifier
# ===========================================================================

# Racine du clone ORCHIDEE. Laisser tel quel si ce fichier est resté dans
# examples/ ; sinon donner le chemin complet du clone.
ORCHIDEE_REPO = Path(__file__).resolve().parent.parent

# Extractions de microbiologie et de mouvements, et tables de correspondance.
# Formats acceptés : .csv,
# .tsv, .tab, .txt ou .rds. Ces chemins peuvent pointer hors du dépôt, dans
# un espace protégé ; ne pas committer les fichiers eux-mêmes.
SITE_INPUTS = {
    "microbiology-observations": r"D:\ORCHIDEE\entrees\microbiology_observations.csv",
    "bacteria-mapping": r"D:\ORCHIDEE\entrees\bacteria_mapping.csv",
    "sample-type-mapping": r"D:\ORCHIDEE\entrees\sample_type_mapping.csv",
    "antibiotic-mapping": r"D:\ORCHIDEE\entrees\antibiotic_mapping.csv",
    "unit-mapping": r"D:\ORCHIDEE\entrees\unit_mapping.csv",
    "hospitalization-intervals": r"D:\ORCHIDEE\entrees\hospitalization_intervals.csv",
}

# Répertoire de sortie dédié : bundles, diagnostics et, au stade `report`,
# caches et exports. Son contenu dérive des données cliniques ; le placer
# sous les mêmes règles de protection qu'elles.
OUTPUT_DIR = r"D:\ORCHIDEE\site_current"

# Première et dernière année à analyser, bornes comprises (une seule année possible).
# Elle sélectionne les lignes de microbiologie, découpe l'exposition et
# devient la période publiée par le rapport. Ce sont les mêmes deux nombres
# à chaque stade ; ils ne sont écrits qu'ici.
START_YEAR = 2022
END_YEAR = 2024

# Stade à exécuter :
#   "diagnostics" — contrôle les données fournies, n'écrit qu'un rapport ;
#   "build"       — relance le diagnostic, puis construit les bundles ;
#   "report"      — calcule les indicateurs depuis le build déjà terminé.
# Ne passer au stade suivant qu'après avoir lu la sortie du précédent.
STAGE = "diagnostics"

# Mettre à True pour remplacer une sortie complète déjà construite au même
# endroit. Sans cela, `build` refuse d'écraser et le dit.
REPLACE_EXISTING_OUTPUT = False

# ===========================================================================
# EXÉCUTION — rien à modifier en dessous
# ===========================================================================

STAGES = ("diagnostics", "build", "report")


def run(step, arguments):
    """Lance une commande ORCHIDEE et s'arrête si elle échoue."""

    command = [sys.executable, str(ORCHIDEE_REPO / "scripts" / "orchidee.py")]
    command.extend(arguments)
    print()
    print(f"=== {step} ===")
    print("> " + subprocess.list2cmdline(command))
    print()
    # check=False : le code de sortie est interprété ici, pour distinguer des
    # constats bloquants d'un échec technique. Les deux arrêtent le fichier,
    # mais ils ne demandent pas la même chose à l'opérateur.
    completed = subprocess.run(command, cwd=str(ORCHIDEE_REPO), check=False)
    return completed.returncode


def site_input_arguments():
    arguments = []
    for flag, path in SITE_INPUTS.items():
        arguments.extend(["--" + flag, str(path)])
    return arguments


def period_arguments():
    return [
        "--start-year",
        str(START_YEAR),
        "--end-year",
        str(END_YEAR),
    ]


def main():
    if STAGE not in STAGES:
        print(f"STAGE doit valoir l'un de {', '.join(STAGES)} ; lu : {STAGE!r}")
        return 2
    if END_YEAR < START_YEAR:
        print(f"END_YEAR ({END_YEAR}) précède START_YEAR ({START_YEAR}).")
        return 2

    print(f"Dépôt   : {ORCHIDEE_REPO}")
    print(f"Sortie  : {OUTPUT_DIR}")
    print(f"Période : {START_YEAR}-{END_YEAR}")
    print(f"Stade   : {STAGE}")

    if STAGE != "report":
        # Étape 1 — contrôle préalable des chemins et des colonnes. Elle lit les en-têtes CSV
        # ou désérialise les RDS et ne crée pas de répertoire de sortie.
        status = run(
            "1/4 contrôle des chemins et des colonnes",
            ["site", *site_input_arguments(), *period_arguments(), "--dry-run"],
        )
        if status != 0:
            print(
                "\nLes chemins ou les colonnes ne conviennent pas. Corriger le "
                "message ci-dessus et relancer ; rien n'a été construit."
            )
            return status

        # Étape 2 — diagnostic complet. Il lit les données fournies une fois et signale
        # tous les problèmes de contrat en une passe.
        status = run(
            "2/4 diagnostic des données",
            [
                "site",
                *site_input_arguments(),
                *period_arguments(),
                "--output",
                str(OUTPUT_DIR),
                "--diagnose",
            ],
        )
        if status == 1:
            print(
                "\nDes constats BLOCKING subsistent : aucun bundle n'est "
                "construit tant qu'ils ne sont pas corrigés. Les avertissements "
                "WARNING n'arrêtent rien mais méritent une lecture."
            )
            return status
        if status != 0:
            print(
                "\nLe diagnostic n'a pas pu aboutir. Ce n'est pas un verdict sur "
                "les données fournies ; voir le message ci-dessus."
            )
            return status
        if STAGE == "diagnostics":
            print(
                "\nDiagnostic passé. Relire les WARNING, puis mettre "
                'STAGE = "build" dans ce fichier et le relancer.'
            )
            return 0

        # Étape 3 — build. La CLI relance elle-même le diagnostic sur les mêmes
        # blocs et la même période, et refuse de construire sur un constat
        # bloquant : aucun résultat contradictoire ne peut être tranché en
        # silence par le builder.
        build_arguments = [
            "site",
            *site_input_arguments(),
            *period_arguments(),
            "--output",
            str(OUTPUT_DIR),
        ]
        if REPLACE_EXISTING_OUTPUT:
            build_arguments.append("--force")
        status = run("3/4 construction des bundles", build_arguments)
        if status != 0:
            print("\nLe build n'a pas abouti ; voir le message ci-dessus.")
            return status
        if STAGE == "build":
            print(
                "\nBundles construits. Si les indicateurs doivent être calculés "
                'ici, mettre STAGE = "report" et relancer ; sinon, la '
                "transmission est terminée."
            )
            return 0

    # Étape 4 — indicateurs. La période est transmise au rendu pour ce
    # processus seulement ; config/pipeline.R n'est pas modifié.
    status = run(
        "4/4 calcul des indicateurs",
        [
            "render",
            "--rebuild",
            "--bundle",
            str(Path(OUTPUT_DIR) / "bundle_v2_operational"),
            "--workspace",
            str(Path(OUTPUT_DIR) / "runtime"),
            "--start-year",
            str(START_YEAR),
            "--end-year",
            str(END_YEAR),
        ],
    )
    if status != 0:
        print("\nLe rendu n'a pas abouti ; voir le message ci-dessus.")
        return status

    print(
        "\nTerminé. Le rapport est écrit à la racine du dépôt, "
        "orchidee_ratb_indicators.html."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
