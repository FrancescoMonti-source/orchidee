#!/usr/bin/env python3
"""Fichier de lancement ORCHIDEE, à copier et à modifier.

Ce fichier ne contient aucun calcul. Il enregistre les décisions d'un
établissement — où sont ses données, où écrire, quelles années publier — et appelle
`python scripts/orchidee.py`, qui fait le travail.

Marche à suivre :

1. copier ce fichier hors du dépôt, à côté des données protégées ;
2. remplir le bloc RÉGLAGES ci-dessous (ou utiliser les options CLI) ;
3. le lancer tel quel. Il démarre au stade `diagnostics`, qui ne construit
   rien et ne peut rien écraser ;
4. lire le rapport, corriger ce qui est signalé BLOCKING, relancer ;
5. quand le diagnostic passe, passer au stade `build`, puis à `report` si les
   indicateurs doivent être calculés sur cette machine.

Lancement :

    python run_site_handoff.py
    # ou via arguments CLI :
    python run_site_handoff.py --stage build
    python run_site_handoff.py --input-dir /chemin/vers/entrees --stage diagnostics

Il n'y a rien d'autre à installer que ce que `python scripts/orchidee.py
setup` a déjà mis en place.
"""

import argparse
import subprocess
import sys
from pathlib import Path

# ===========================================================================
# RÉGLAGES — la seule partie à modifier
# ===========================================================================

# Racine du clone ORCHIDEE. Détecte automatiquement si ce fichier est resté
# dans examples/ ou s'il a été copié à la racine du dépôt.
_candidate = Path(__file__).resolve().parent
if (_candidate / "scripts" / "orchidee.py").is_file():
    ORCHIDEE_REPO = _candidate
else:
    ORCHIDEE_REPO = _candidate.parent

# Option A (recommandée) : Répertoire contenant les 6 fichiers de transmission canoniques
# (microbiology_observations.csv, bacteria_mapping.csv, sample_type_mapping.csv,
# antibiotic_mapping.csv, unit_mapping.csv, hospitalization_intervals.csv).
# Si renseigné (ou passé via --input-dir en ligne de commande), ce dossier est
# utilisé directement et SITE_INPUTS ci-dessous est ignoré.
INPUT_DIR = None
# Exemple : INPUT_DIR = r"D:\ORCHIDEE\entrees"

# Option B : Chemins individuels pour chaque extraction ou table de correspondance.
# Formats acceptés : .csv, .tsv, .tab, .txt ou .rds. Ces chemins peuvent
# pointer hors du dépôt, dans un espace protégé ; ne pas committer les fichiers.
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
OUTPUT_DIR = r"outputs/site_current"
# Exemple externe protégé : OUTPUT_DIR = r"D:\ORCHIDEE\site_current"

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
# (Peut aussi être surchargé en ligne de commande via --stage).
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


def site_input_arguments(input_dir=None):
    effective_input_dir = input_dir if input_dir is not None else INPUT_DIR
    if effective_input_dir:
        return ["--input-dir", str(effective_input_dir)]
    arguments = []
    for flag, path in SITE_INPUTS.items():
        arguments.extend(["--" + flag, str(path)])
    return arguments


def period_arguments(start_year=None, end_year=None):
    sy = start_year if start_year is not None else START_YEAR
    ey = end_year if end_year is not None else END_YEAR
    return [
        "--start-year",
        str(sy),
        "--end-year",
        str(ey),
    ]


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Fichier de lancement ORCHIDEE pour site partenaire.",
    )
    parser.add_argument(
        "--stage",
        choices=STAGES,
        default=None,
        help=(
            "Stade d'exécution ('diagnostics', 'build' ou 'report'). "
            "Si omis, la valeur de STAGE définie dans le script s'applique."
        ),
    )
    parser.add_argument(
        "--input-dir",
        default=None,
        help=(
            "Répertoire contenant les six fichiers canoniques de transmission. "
            "Si fourni, surcharge la variable INPUT_DIR et le dictionnaire SITE_INPUTS."
        ),
    )
    parser.add_argument(
        "--output-dir",
        default=None,
        help=(
            "Répertoire de sortie dédié. Si fourni, surcharge la variable OUTPUT_DIR."
        ),
    )
    parser.add_argument(
        "--start-year",
        type=int,
        default=None,
        help="Première année de la période (surcharge START_YEAR).",
    )
    parser.add_argument(
        "--end-year",
        type=int,
        default=None,
        help="Dernière année de la période (surcharge END_YEAR).",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        default=False,
        help="Remplacer une sortie existante (surcharge REPLACE_EXISTING_OUTPUT).",
    )
    return parser.parse_args(argv)


def main(argv=None):
    parsed = parse_args(argv)
    stage = parsed.stage if parsed.stage is not None else STAGE
    input_dir = parsed.input_dir if parsed.input_dir is not None else INPUT_DIR
    output_dir = parsed.output_dir if parsed.output_dir is not None else OUTPUT_DIR
    start_year = parsed.start_year if parsed.start_year is not None else START_YEAR
    end_year = parsed.end_year if parsed.end_year is not None else END_YEAR
    force = parsed.force or REPLACE_EXISTING_OUTPUT

    if stage not in STAGES:
        print(f"STAGE doit valoir l'un de {', '.join(STAGES)} ; lu : {stage!r}")
        return 2
    if end_year < start_year:
        print(f"END_YEAR ({end_year}) précède START_YEAR ({start_year}).")
        return 2

    print(f"Dépôt   : {ORCHIDEE_REPO}")
    if input_dir:
        print(f"Entrées : {input_dir} (--input-dir)")
    print(f"Sortie  : {output_dir}")
    print(f"Période : {start_year}-{end_year}")
    print(f"Stade   : {stage}")

    input_args = site_input_arguments(input_dir)
    period_args = period_arguments(start_year, end_year)

    if stage != "report":
        # Étape 1 — contrôle préalable des chemins et des colonnes. Elle lit les en-têtes CSV
        # ou désérialise les RDS et ne crée pas de répertoire de sortie.
        status = run(
            "1/4 contrôle des chemins et des colonnes",
            ["site", *input_args, *period_args, "--dry-run"],
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
                *input_args,
                *period_args,
                "--output",
                str(output_dir),
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
        if stage == "diagnostics":
            print(
                "\nDiagnostic passé. Relire les WARNING, puis mettre "
                'STAGE = "build" (ou passer --stage build) et relancer.'
            )
            return 0

        # Étape 3 — build. La CLI relance elle-même le diagnostic sur les mêmes
        # blocs et la même période, et refuse de construire sur un constat
        # bloquant : aucun résultat contradictoire ne peut être tranché en
        # silence par le builder.
        build_arguments = [
            "site",
            *input_args,
            *period_args,
            "--output",
            str(output_dir),
        ]
        if force:
            build_arguments.append("--force")
        status = run("3/4 construction des bundles", build_arguments)
        if status != 0:
            print("\nLe build n'a pas abouti ; voir le message ci-dessus.")
            return status
        if stage == "build":
            print(
                "\nBundles construits. Si les indicateurs doivent être calculés "
                'ici, mettre STAGE = "report" (ou passer --stage report) et relancer ; sinon, la '
                "transmission est terminée."
            )
            return 0

    # Étape 4 — indicateurs. La période est transmise au rendu pour ce
    # processus seulement ; config/pipeline.R n'est pas modifié.
    report_output_file = Path(output_dir) / "orchidee_ratb_indicators.html"
    status = run(
        "4/4 calcul des indicateurs",
        [
            "render",
            "--rebuild",
            "--bundle",
            str(Path(output_dir) / "bundle_v2_operational"),
            "--workspace",
            str(Path(output_dir) / "runtime"),
            "--start-year",
            str(start_year),
            "--end-year",
            str(end_year),
            "--output",
            str(report_output_file),
        ],
    )
    if status != 0:
        print("\nLe rendu n'a pas abouti ; voir le message ci-dessus.")
        return status

    print(
        f"\nTerminé. Le rapport est disponible sous : {report_output_file}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
