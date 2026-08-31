#!/usr/bin/env python3
"""Cross-platform operator entry point for ORCHIDEE.

Python owns CLI parsing, paths and process sequencing. The existing R scripts
remain the owners of bundle validation and analytical behavior.

Requires Python 3.8 or newer.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence


REPO_ROOT = Path(__file__).resolve().parent.parent
SITE_INPUTS = (
    (
        "microbiology_observations",
        "microbiology_observations",
        "microbiology_observations.csv",
    ),
    ("bacteria_mapping", "bacteria_mapping", "bacteria_mapping.csv"),
    (
        "sample_type_mapping",
        "sample_type_mapping",
        "sample_type_mapping.csv",
    ),
    ("antibiotic_mapping", "antibiotic_mapping", "antibiotic_mapping.csv"),
    ("unit_mapping", "unit_mapping", "unit_mapping.csv"),
    (
        "incidence_exposure",
        "incidence_exposure_by_year_um_uf_ta_de_profile",
        "incidence_exposure_by_year_um_uf_ta_de_profile.csv",
    ),
)


class OrchideeError(RuntimeError):
    """An operator-facing failure that should stop the command."""


@dataclass(frozen=True)
class LockMetadata:
    path: Path
    r_version: str
    package_count: int


def read_lock_metadata() -> LockMetadata:
    lock_path = REPO_ROOT / "renv.lock"
    if not lock_path.is_file():
        raise OrchideeError(f"Missing R dependency lockfile: {lock_path}")
    try:
        lock = json.loads(lock_path.read_text(encoding="utf-8"))
        r_version = str(lock["R"]["Version"]).strip()
        packages = lock["Packages"]
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise OrchideeError(
            f"Cannot read R dependency lockfile: {lock_path}"
        ) from error
    if not r_version:
        raise OrchideeError(
            f"renv.lock does not declare an R version: {lock_path}"
        )
    if not isinstance(packages, dict):
        raise OrchideeError(
            f"renv.lock does not contain a package registry: {lock_path}"
        )
    return LockMetadata(
        path=lock_path.resolve(),
        r_version=r_version,
        package_count=len(packages),
    )


def run_process(
    command: Sequence[str | Path],
    *,
    env: dict[str, str] | None = None,
    capture_output: bool = False,
) -> subprocess.CompletedProcess[str]:
    args = [str(value) for value in command]
    try:
        return subprocess.run(
            args,
            cwd=REPO_ROOT,
            env=env,
            check=False,
            text=True,
            capture_output=capture_output,
        )
    except OSError as error:
        raise OrchideeError(f"Cannot run {args[0]}: {error}") from error


def rscript_version(candidate: Path) -> str | None:
    result = run_process(
        [
            candidate,
            "--vanilla",
            "-e",
            "cat(as.character(getRversion()))",
        ],
        capture_output=True,
    )
    if result.returncode != 0:
        return None
    return result.stdout.strip() or None


def _unique_paths(candidates: Sequence[Path | None]) -> list[Path]:
    unique: list[Path] = []
    seen: set[str] = set()
    for candidate in candidates:
        if candidate is None:
            continue
        key = os.path.normcase(os.path.abspath(candidate))
        if key in seen:
            continue
        seen.add(key)
        unique.append(Path(candidate))
    return unique


def resolve_rscript(*additional_candidates: str | Path | None) -> Path:
    lock = read_lock_metadata()
    explicit = os.environ.get("ORCHIDEE_R")
    if explicit:
        path = Path(explicit).expanduser()
        if not path.is_file():
            raise OrchideeError(
                f"ORCHIDEE_R does not point to an existing file: {path}"
            )
        resolved = path.resolve()
        actual = rscript_version(resolved)
        if actual != lock.r_version:
            raise OrchideeError(
                f"ORCHIDEE_R points to R {actual or 'unknown'}, but "
                f"renv.lock requires R {lock.r_version}: {resolved}"
            )
        return resolved

    candidates: list[Path | None] = []
    if os.name == "nt":
        program_files = os.environ.get("ProgramFiles")
        local_app_data = os.environ.get("LOCALAPPDATA")
        if program_files:
            candidates.append(
                Path(program_files)
                / "R"
                / f"R-{lock.r_version}"
                / "bin"
                / "Rscript.exe"
            )
        if local_app_data:
            candidates.append(
                Path(local_app_data)
                / "Programs"
                / "R"
                / f"R-{lock.r_version}"
                / "bin"
                / "Rscript.exe"
            )
    candidates.extend(
        Path(value).expanduser() if value else None
        for value in additional_candidates
    )
    on_path = shutil.which("Rscript") or shutil.which("Rscript.exe")
    candidates.append(Path(on_path) if on_path else None)

    mismatches: list[str] = []
    for candidate in _unique_paths(candidates):
        if not candidate.is_file():
            continue
        resolved = candidate.resolve()
        actual = rscript_version(resolved)
        if actual == lock.r_version:
            return resolved
        if actual:
            mismatches.append(f"{resolved} (R {actual})")

    message = (
        f"Rscript for R {lock.r_version} was not found. Install that version "
        "or set ORCHIDEE_R to its Rscript executable."
    )
    if mismatches:
        message += " Other R installations were ignored: " + ", ".join(
            mismatches
        ) + "."
    raise OrchideeError(message)


def resolve_repo_path(value: str | Path) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = REPO_ROOT / path
    return Path(os.path.abspath(path))


def resolve_nonempty_repo_path(value: str | Path, label: str) -> Path:
    if not str(value).strip():
        raise OrchideeError(f"{label} path cannot be empty.")
    return resolve_repo_path(value)


def path_at_or_below(path: Path, directory: Path) -> bool:
    # This guard is lexical because an output directory may not exist yet.
    candidate = os.path.normcase(os.path.abspath(path))
    parent = os.path.normcase(os.path.abspath(directory))
    try:
        return os.path.commonpath([candidate, parent]) == parent
    except ValueError:
        return False


def resolve_input_file(value: str | Path, label: str) -> Path:
    path = resolve_repo_path(value)
    if not path.is_file():
        raise OrchideeError(f"{label} input not found: {path}")
    return path.resolve()


def assert_safe_output_directory(
    output: str | Path,
    *,
    inputs: Sequence[Path] = (),
    input_label: str = "Inputs",
) -> Path:
    path = resolve_repo_path(output)
    if path.is_file():
        raise OrchideeError(
            f"Output must be a directory, not an existing file: {path}"
        )
    root = Path(path.anchor)
    if path_at_or_below(REPO_ROOT, path) or path == root:
        raise OrchideeError(
            "Output must be a dedicated directory, not a filesystem root or "
            f"an ancestor of the repository: {path}"
        )

    repo_outputs = REPO_ROOT / "outputs"
    if path_at_or_below(path, REPO_ROOT) and (
        not path_at_or_below(path, repo_outputs) or path == repo_outputs
    ):
        raise OrchideeError(
            "An output inside the repository must be a dedicated directory "
            f"under outputs/: {path}"
        )

    inside = [value for value in inputs if path_at_or_below(value, path)]
    if inside:
        joined = ", ".join(str(value) for value in inside)
        raise OrchideeError(
            f"{input_label} must be outside the output directory: {joined}"
        )
    return path


def assert_safe_template_directory(value: str | Path) -> Path:
    path = resolve_repo_path(value)
    if path.is_file():
        raise OrchideeError(f"Template destination must be a directory: {path}")
    root = Path(path.anchor)
    if path_at_or_below(REPO_ROOT, path) or path == root:
        raise OrchideeError(
            "Template destination must be a dedicated directory, not a "
            f"filesystem root or an ancestor of the repository: {path}"
        )
    repo_data = REPO_ROOT / "data"
    if path_at_or_below(path, REPO_ROOT) and (
        not path_at_or_below(path, repo_data) or path == repo_data
    ):
        raise OrchideeError(
            "A template destination inside the repository must be a dedicated "
            f"directory under data/: {path}"
        )
    return path


def read_manifest(path: Path) -> list[str]:
    if not path.is_file():
        return []
    try:
        return path.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        raise OrchideeError(f"Cannot read manifest: {path}") from error


def manifest_value(path: Path, key: str) -> str | None:
    prefix = f"{key}: "
    for line in read_manifest(path):
        if line.startswith(prefix):
            return line[len(prefix) :].strip()
    return None


def valid_site_manifest(path: Path, version: str, role: str) -> bool:
    lines = set(read_manifest(path))
    return {
        "status: complete",
        "workflow: site_handoff",
        f"contract_version: {version}",
        f"role: {role}",
        "runtime_smoke: PASS",
    } <= lines


def format_command(command: Sequence[str | Path]) -> str:
    values = [str(value) for value in command]
    if os.name == "nt":
        return subprocess.list2cmdline(values)
    return shlex.join(values)


def print_warning(message: str) -> None:
    print(f"WARNING: {message}", file=sys.stderr)


def resolve_quarto() -> Path:
    explicit = os.environ.get("ORCHIDEE_QUARTO")
    if explicit:
        path = Path(explicit).expanduser()
        if not path.is_file():
            raise OrchideeError(
                "ORCHIDEE_QUARTO must point to a Quarto executable file: "
                f"{path}"
            )
        return path.resolve()

    candidates: list[Path | None] = []
    on_path = shutil.which("quarto") or shutil.which("quarto.exe")
    candidates.append(Path(on_path) if on_path else None)
    if os.name == "nt":
        candidates.extend(
            [
                Path(
                    r"C:\Program Files\Positron\resources\app\quarto\bin\quarto.exe"
                ),
                Path(
                    r"C:\Program Files\RStudio\resources\app\bin\quarto\bin\quarto.exe"
                ),
                Path(r"C:\Program Files\Quarto\bin\quarto.exe"),
            ]
        )
    for candidate in _unique_paths(candidates):
        if candidate.is_file():
            return candidate.resolve()
    raise OrchideeError(
        "Quarto executable not found. Set ORCHIDEE_QUARTO or install Quarto."
    )


def command_setup(args: argparse.Namespace) -> int:
    lock = read_lock_metadata()
    rscript = resolve_rscript()
    print(f"Repo:     {REPO_ROOT}")
    print(f"R:        {rscript}")
    print(f"Lock:     {lock.path}")
    print(f"Packages: {lock.package_count}")
    if args.dry_run:
        print("PASS: R and renv.lock are available; no packages were changed.")
        return 0

    environment = os.environ.copy()
    environment["ORCHIDEE_SETUP"] = "1"
    setup_script = REPO_ROOT / "scripts" / "setup_r_environment.R"
    result = run_process(
        [rscript, "--no-save", "--no-restore", setup_script],
        env=environment,
    )
    if result.returncode != 0:
        raise OrchideeError(
            f"R dependency restore failed (exit {result.returncode})."
        )
    return 0


def command_run_r(args: argparse.Namespace) -> int:
    rscript = resolve_rscript()
    command: list[str | Path] = [rscript, "--no-save", "--no-restore"]
    if args.expression is not None:
        if args.script is not None or args.script_args:
            raise OrchideeError(
                "run-r accepts either --expression or an R script, not both."
            )
        command.extend(["-e", args.expression])
        description = "R expression"
    else:
        if args.script is None:
            raise OrchideeError(
                "run-r requires an R script or --expression."
            )
        script = resolve_repo_path(args.script)
        if not script.is_file():
            raise OrchideeError(f"R script not found: {script}")
        script_args = list(args.script_args)
        if script_args[:1] == ["--"]:
            script_args = script_args[1:]
        command.extend([script, *script_args])
        description = str(script)

    result = run_process(command)
    if result.returncode != 0:
        raise OrchideeError(
            f"{description} failed (exit {result.returncode})."
        )
    return 0


def _site_input_values(args: argparse.Namespace) -> dict[str, str]:
    if args.run_smoke_test:
        fixture = REPO_ROOT / "examples" / "site_handoff_minimal"
        return {
            dest: str(fixture / filename)
            for dest, _, filename in SITE_INPUTS
        }
    return {dest: getattr(args, dest) for dest, _, _ in SITE_INPUTS}


def _validate_site_arguments(args: argparse.Namespace) -> None:
    supplied = [
        dest for dest, _, _ in SITE_INPUTS if getattr(args, dest) is not None
    ]
    if args.emit_templates is not None:
        if supplied or args.output or args.report or args.force:
            raise OrchideeError(
                "--emit-templates cannot be combined with build options."
            )
        return
    if args.run_smoke_test:
        if supplied or args.report:
            raise OrchideeError(
                "--run-smoke-test cannot be combined with site input options."
            )
        return
    missing = [dest for dest, _, _ in SITE_INPUTS if dest not in supplied]
    if missing:
        flags = ", ".join("--" + value.replace("_", "-") for value in missing)
        raise OrchideeError(f"Missing required site inputs: {flags}")
    if args.report and not args.diagnose:
        raise OrchideeError("--report is available only with --diagnose.")
    if args.diagnose and args.force:
        raise OrchideeError("--force is unavailable with --diagnose.")


def _run_site_templates(args: argparse.Namespace) -> int:
    rscript = resolve_rscript()
    target = assert_safe_template_directory(args.emit_templates)
    print(f"Templates: {target}")
    print(f"R:         {rscript}")
    writer = REPO_ROOT / "scripts" / "emit_site_handoff_templates.R"
    result = run_process(
        [rscript, "--no-save", "--no-restore", writer, target]
    )
    if result.returncode != 0:
        raise OrchideeError(
            f"Site template generation failed (exit {result.returncode})."
        )
    return 0


def _diagnose_setup_failure(message: str) -> int:
    print()
    print(
        "The diagnostics could not start: "
        f"{message} This is not a verdict on the six blocks, and no report "
        "was written."
    )
    return 2


def _run_site_diagnose(args: argparse.Namespace) -> int:
    try:
        rscript = resolve_rscript()
        values = _site_input_values(args)
        input_paths = tuple(
            resolve_input_file(values[dest], label)
            for dest, label, _ in SITE_INPUTS
        )
        if args.report:
            report_root = resolve_repo_path(args.report)
        elif args.output:
            report_root = resolve_repo_path(args.output) / "diagnostics"
        else:
            report_root = REPO_ROOT / "outputs" / "site_diagnostics"
        report_root = assert_safe_output_directory(
            report_root,
            inputs=input_paths,
            input_label="Site handoff inputs",
        )
    except OrchideeError as error:
        return _diagnose_setup_failure(str(error))

    for (_, label, _), path in zip(SITE_INPUTS, input_paths):
        print(f"{label}: {path}")
    print(f"Report: {report_root}")
    print(f"R:      {rscript}")

    diagnoser = REPO_ROOT / "scripts" / "diagnose_site_inputs.R"
    try:
        result = run_process(
            [
                rscript,
                "--no-save",
                "--no-restore",
                diagnoser,
                *input_paths,
                report_root,
            ]
        )
    except OrchideeError as error:
        return _diagnose_setup_failure(str(error))

    if result.returncode == 1:
        print()
        print(
            "Correct the blocking findings above and rerun --diagnose. "
            "No bundle was built."
        )
        return 1
    if result.returncode == 2:
        print()
        print(
            "The diagnostics could not run or publish their report; this is "
            "not a verdict on the six blocks. See the message above. "
            f"Report: {report_root}"
        )
        return 2
    if result.returncode != 0:
        print()
        print(
            "Site input diagnostics failed unexpectedly "
            f"(exit {result.returncode}); this is not a verdict on the six "
            "blocks."
        )
        return 2
    return 0


def _run_site_build(args: argparse.Namespace) -> int:
    rscript = resolve_rscript()
    values = _site_input_values(args)
    if args.run_smoke_test:
        print("Mode: installation smoke test on the versioned synthetic fixture")
    input_paths = tuple(
        resolve_input_file(values[dest], label)
        for dest, label, _ in SITE_INPUTS
    )

    default_output = (
        "outputs/site_smoke_test"
        if args.run_smoke_test
        else "outputs/site_current"
    )
    output_root = assert_safe_output_directory(
        args.output or default_output,
        inputs=input_paths,
        input_label="Site handoff inputs",
    )
    bundle_v3 = output_root / "bundle_v3"
    bundle_v2 = output_root / "bundle_v2_operational"
    runtime = output_root / "runtime"
    manifest_v3 = bundle_v3 / "build_manifest.txt"
    manifest_v2 = bundle_v2 / "build_manifest.txt"

    for (_, label, _), path in zip(SITE_INPUTS, input_paths):
        print(f"{label}: {path}")
    print(f"Output: {output_root}")
    print(f"R:      {rscript}")

    incompatible = [
        output_root / "site_inputs",
        output_root / "adapter_audit.rds",
        output_root / "bundle",
    ]
    if any(path.exists() for path in incompatible):
        raise OrchideeError(
            "Output contains artifacts from another build layout: "
            f"{output_root}. Choose a distinct --output; --force cannot "
            "replace this layout."
        )

    existing_bundles = [path for path in (bundle_v3, bundle_v2) if path.exists()]
    build_id_v3 = manifest_value(manifest_v3, "build_id")
    build_id_v2 = manifest_value(manifest_v2, "build_id")
    complete = (
        valid_site_manifest(manifest_v3, "v3", "durable_v3")
        and valid_site_manifest(manifest_v2, "v2", "operational_v2")
        and bool(build_id_v3)
        and build_id_v3 == build_id_v2
    )
    if existing_bundles and not complete:
        raise OrchideeError(
            "Output contains an incomplete or incompatible site build: "
            f"{output_root}. Choose another --output. After confirming no "
            "build is running, remove the two partial bundle directories "
            "before reusing this output."
        )
    if complete:
        if args.dry_run:
            suffix = (
                "; a real build with --force would replace the two bundles."
                if args.force
                else "; use --force or another --output for a real build."
            )
            print_warning(
                f"Complete site outputs already exist under {output_root}{suffix}"
            )
        elif not args.force:
            raise OrchideeError(
                f"Complete site outputs already exist under {output_root}. "
                "Review them, then pass --force or choose another --output."
            )
    elif args.force:
        print_warning(
            "--force is unnecessary because no compatible output exists."
        )

    environment_probe = REPO_ROOT / "scripts" / "check_site_environment.R"
    probe = run_process(
        [
            rscript,
            "--no-save",
            "--no-restore",
            environment_probe,
            *input_paths,
        ]
    )
    if probe.returncode != 0:
        raise OrchideeError(
            "The site build environment or input columns are not ready. Run "
            "the setup command if packages are missing, correct the named "
            "input error above, then retry."
        )
    if args.dry_run:
        print(
            "PASS: paths, locked R, required packages and input columns are "
            "available; no bundle was built."
        )
        return 0

    builder = REPO_ROOT / "scripts" / "build_external_bundle_from_site_inputs.R"
    command: list[str | Path] = [
        rscript,
        "--no-save",
        "--no-restore",
        builder,
        *input_paths,
        bundle_v3,
        f"--operational-v2-output={bundle_v2}",
        "--no-next-steps",
    ]
    if args.force:
        command.append("--force")
    result = run_process(command)
    if result.returncode != 0:
        raise OrchideeError(f"Site bundle build failed (exit {result.returncode}).")

    if not valid_site_manifest(manifest_v3, "v3", "durable_v3"):
        raise OrchideeError(
            "Site build ended without a valid v3 completion marker."
        )
    if not valid_site_manifest(manifest_v2, "v2", "operational_v2"):
        raise OrchideeError(
            "Site build ended without a valid operational-v2 completion marker."
        )
    built_id_v3 = manifest_value(manifest_v3, "build_id")
    built_id_v2 = manifest_value(manifest_v2, "build_id")
    if not built_id_v3 or built_id_v3 != built_id_v2:
        raise OrchideeError(
            "Site build ended without matching v3 and operational-v2 build "
            "IDs. Do not use either bundle."
        )

    print(
        "PASS: site handoff build, strict bundle validation and "
        "operational-v2 runtime smoke are complete."
    )
    print(f"V3 manifest: {manifest_v3}")
    print(f"V2 manifest: {manifest_v2}")
    print("Handoff complete; no further command is required.")
    print("Optional indicator render from this same build:")
    print(
        format_command(
            [
                sys.executable,
                Path(__file__).resolve(),
                "render",
                "--rebuild",
                "--bundle",
                bundle_v2,
                "--workspace",
                runtime,
            ]
        )
    )
    return 0


def command_site(args: argparse.Namespace) -> int:
    _validate_site_arguments(args)
    if args.emit_templates is not None:
        return _run_site_templates(args)
    if args.diagnose:
        return _run_site_diagnose(args)
    return _run_site_build(args)


def command_rouen(args: argparse.Namespace) -> int:
    bact = resolve_input_file(args.bact, "BACT")
    pmsi = resolve_input_file(args.pmsi, "PMSI")
    output = assert_safe_output_directory(
        args.output or "outputs/rouen_current",
        inputs=(bact, pmsi),
        input_label="BACT and PMSI inputs",
    )
    operational_v2 = output / "bundle_v2_operational"
    rscript = resolve_rscript()

    print(f"BACT:   {bact}")
    print(f"PMSI:   {pmsi}")
    print(f"Output: {output}")
    print(f"R:      {rscript}")

    incompatible = [
        output / "bundle",
        output / "site_inputs" / "denominator_by_year.rds",
    ]
    if any(path.exists() for path in incompatible):
        raise OrchideeError(
            "Output contains artifacts from another Rouen build layout: "
            f"{output}. Choose a distinct --output; --force cannot replace a "
            "different layout. No build was run."
        )

    known = [
        output / "site_inputs",
        output / "bundle_v3",
        operational_v2,
        output / "adapter_audit.rds",
        output / "build_manifest.txt",
        output / "build_manifest.txt.tmp",
    ]
    if any(path.exists() for path in known):
        if args.dry_run:
            action = (
                "a real build with --force would replace this compatible layout"
                if args.force
                else "use --force or another --output for a real build"
            )
            print_warning(f"Rouen outputs already exist under {output}; {action}.")
        elif not args.force:
            raise OrchideeError(
                f"Rouen outputs already exist under {output}. Review them, "
                "then pass --force to replace them or choose another --output."
            )

    probe = REPO_ROOT / "scripts" / "check_rouen_environment.R"
    probe_result = run_process(
        [rscript, "--no-save", "--no-restore", probe]
    )
    if probe_result.returncode != 0:
        raise OrchideeError(
            "The Rouen R environment is not ready. Run the setup command from "
            "the repository root, then retry."
        )
    if args.dry_run:
        print(
            "PASS: inputs, locked R and required Rouen packages are available; "
            "no build was run."
        )
        return 0

    builder = REPO_ROOT / "scripts" / "build_rouen_external_bundle.R"
    command: list[str | Path] = [
        rscript,
        "--no-save",
        "--no-restore",
        builder,
        bact,
        pmsi,
        output,
        f"--operational-v2-output={operational_v2}",
    ]
    if args.force:
        command.append("--force")
    result = run_process(command)
    if result.returncode != 0:
        raise OrchideeError(f"Rouen build failed (exit {result.returncode}).")

    manifest = output / "build_manifest.txt"
    if not manifest.is_file():
        raise OrchideeError(
            f"Rouen build ended without its completion marker: {manifest}"
        )

    print(f"PASS: Rouen build complete. Manifest: {manifest}")
    print("Handoff complete; no further command is required.")
    print("Optional indicator render from this same build:")
    print(
        format_command(
            [
                sys.executable,
                Path(__file__).resolve(),
                "render",
                "--rebuild",
                "--bundle",
                operational_v2,
                "--workspace",
                output / "runtime",
            ]
        )
    )
    return 0


def command_render(args: argparse.Namespace) -> int:
    environment = os.environ.copy()
    bundle_was_explicit = args.bundle is not None
    workspace_was_explicit = args.workspace is not None
    if bundle_was_explicit:
        environment["ORCHIDEE_EXTERNAL_BUNDLE_V2_DIR"] = str(
            resolve_nonempty_repo_path(args.bundle, "Bundle")
        )
    if workspace_was_explicit:
        environment["ORCHIDEE_EXTERNAL_WORKSPACE_DIR"] = str(
            resolve_nonempty_repo_path(args.workspace, "Workspace")
        )

    quarto = resolve_quarto()
    version_result = run_process([quarto, "--version"], capture_output=True)
    if version_result.returncode != 0:
        raise OrchideeError(
            f"Quarto failed its version check (exit {version_result.returncode}): "
            f"{quarto}"
        )
    quarto_version = version_result.stdout.strip()
    if not re.fullmatch(
        r"\d+\.\d+(?:\.\d+)?(?:[-+][0-9A-Za-z.-]+)?",
        quarto_version,
    ):
        raise OrchideeError(
            f"Unexpected Quarto version output from {quarto}: {quarto_version}"
        )

    rscript = resolve_rscript(environment.get("QUARTO_R"))
    environment["QUARTO_R"] = str(rscript)

    print(f"Repo: {REPO_ROOT}")
    print(f"Rebuild: {args.rebuild}")
    print(f"Quarto: {quarto} ({quarto_version})")
    print(f"QUARTO_R: {rscript}")

    bundle_value = environment.get("ORCHIDEE_EXTERNAL_BUNDLE_V2_DIR")
    workspace_value = environment.get("ORCHIDEE_EXTERNAL_WORKSPACE_DIR")
    bundle_source = (
        "--bundle parameter"
        if bundle_was_explicit
        else (
            "environment variable ORCHIDEE_EXTERNAL_BUNDLE_V2_DIR"
            if bundle_value
            else "config/pipeline.R default"
        )
    )
    workspace_source = (
        "--workspace parameter"
        if workspace_was_explicit
        else (
            "environment variable ORCHIDEE_EXTERNAL_WORKSPACE_DIR"
            if workspace_value
            else "config/pipeline.R default"
        )
    )
    print(f"Bundle source: {bundle_source}")
    print(f"Workspace source: {workspace_source}")
    if not bundle_was_explicit and bundle_value:
        print_warning(
            "A bundle environment override is active. This render may not use "
            "the bundle just built. Pass --bundle explicitly to bind the "
            "intended bundle to this invocation."
        )

    render_probe = REPO_ROOT / "scripts" / "check_render_environment.R"
    probe = run_process(
        [rscript, "--no-save", "--no-restore", render_probe],
        env=environment,
    )
    if probe.returncode != 0:
        raise OrchideeError(
            "Render preflight failed. Review the R error above; correct the "
            "bundle/workspace path or run the setup command when packages are "
            "missing."
        )

    raw_builder = REPO_ROOT / "scripts" / "build_ratb_raw_runtime.R"
    raw_command: list[str | Path] = [
        rscript,
        "--no-save",
        "--no-restore",
        raw_builder,
    ]
    if args.rebuild:
        raw_command.append("--force")
    print("> " + format_command(raw_command))
    if not args.dry_run:
        raw_result = run_process(raw_command, env=environment)
        if raw_result.returncode != 0:
            raise OrchideeError(
                f"Raw RATB cache build failed (exit {raw_result.returncode})."
            )

    target = REPO_ROOT / "orchidee_ratb_indicators.qmd"
    if not target.is_file():
        raise OrchideeError(f"Missing render target: {target.name}")
    quarto_command = [quarto, "render", target.name]
    print("> " + format_command(quarto_command))
    if not args.dry_run:
        render_result = run_process(quarto_command, env=environment)
        if render_result.returncode != 0:
            raise OrchideeError(
                f"Quarto render failed for {target.name} "
                f"(exit {render_result.returncode})."
            )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    setup_parser = subparsers.add_parser(
        "setup",
        help="restore the R environment declared by renv.lock",
    )
    setup_parser.add_argument(
        "--dry-run",
        action="store_true",
        help="check R and renv.lock without changing packages",
    )
    setup_parser.set_defaults(handler=command_setup)

    run_parser = subparsers.add_parser(
        "run-r",
        help="run an R script or expression with the locked R version",
    )
    run_parser.add_argument("--expression")
    run_parser.add_argument("script", nargs="?")
    run_parser.add_argument("script_args", nargs=argparse.REMAINDER)
    run_parser.set_defaults(handler=command_run_r)

    site_parser = subparsers.add_parser(
        "site",
        help="build or diagnose the six-block handoff from an external site",
    )
    site_mode = site_parser.add_mutually_exclusive_group()
    site_mode.add_argument(
        "--run-smoke-test",
        action="store_true",
        help="run the complete workflow on the versioned synthetic fixture",
    )
    site_mode.add_argument(
        "--emit-templates",
        metavar="DIRECTORY",
        help="create the six templates and mapping-reference kit",
    )
    site_mode.add_argument(
        "--dry-run",
        action="store_true",
        help="check paths, R packages and input columns without building",
    )
    site_mode.add_argument(
        "--diagnose",
        action="store_true",
        help="report all handoff-contract findings without building",
    )
    for dest, label, _ in SITE_INPUTS:
        site_parser.add_argument(
            "--" + dest.replace("_", "-"),
            dest=dest,
            metavar="PATH",
            help=f"path to {label}",
        )
    site_parser.add_argument("--output", metavar="DIRECTORY")
    site_parser.add_argument(
        "--report",
        metavar="DIRECTORY",
        help="diagnostic report directory (with --diagnose only)",
    )
    site_parser.add_argument(
        "--force",
        action="store_true",
        help="replace a complete compatible build",
    )
    site_parser.set_defaults(handler=command_site)

    rouen_parser = subparsers.add_parser(
        "rouen",
        help="build the Rouen bundles from BACT and PMSI inputs",
    )
    rouen_parser.add_argument("--bact", required=True, metavar="PATH")
    rouen_parser.add_argument("--pmsi", required=True, metavar="PATH")
    rouen_parser.add_argument("--output", metavar="DIRECTORY")
    rouen_parser.add_argument("--force", action="store_true")
    rouen_parser.add_argument("--dry-run", action="store_true")
    rouen_parser.set_defaults(handler=command_rouen)

    render_parser = subparsers.add_parser(
        "render",
        help="build the canonical cache and render the indicator report",
    )
    render_parser.add_argument(
        "--rebuild",
        action="store_true",
        help="force rebuilding a cache that is already current",
    )
    render_parser.add_argument("--bundle", metavar="DIRECTORY")
    render_parser.add_argument("--workspace", metavar="DIRECTORY")
    render_parser.add_argument(
        "--dry-run",
        action="store_true",
        help="preflight and print commands without building or rendering",
    )
    render_parser.set_defaults(handler=command_render)

    return parser


def main(argv: Sequence[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(line_buffering=True)
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return int(args.handler(args))
    except OrchideeError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
