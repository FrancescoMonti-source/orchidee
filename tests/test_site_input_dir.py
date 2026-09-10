#!/usr/bin/env python3
"""Unit tests for site --input-dir auto-discovery in scripts/orchidee.py.

Tests Python 3.8+ compatibility, extension handling (.csv, .tsv, etc.),
precedence of explicit CLI flags, ambiguous file handling, missing input
error reporting, and mutual exclusion rules.
"""

from __future__ import annotations

import argparse
import os
import sys
import tempfile
import unittest
from pathlib import Path

# Add repo root to sys.path so we can import from scripts.orchidee
REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from scripts.orchidee import (  # noqa: E402
    OrchideeError,
    SITE_INPUTS,
    SITE_INPUT_EXTENSIONS,
    _add_site_arguments,
    _discover_site_inputs,
    _site_input_values,
    _validate_site_arguments,
    build_parser,
    command_site,
    resolve_input_directory,
    run_site,
)


class TestSiteInputDirDiscovery(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.input_dir = Path(self.temp_dir.name)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def _create_site_files(
        self,
        extensions: dict[str, str] | None = None,
        exclude: set[str] | None = None,
    ) -> dict[str, Path]:
        created: dict[str, Path] = {}
        exclude_set = exclude or set()
        ext_map = extensions or {}
        for dest, _, _ in SITE_INPUTS:
            if dest in exclude_set:
                continue
            ext = ext_map.get(dest, ".csv")
            file_path = self.input_dir / f"{dest}{ext}"
            file_path.write_text("c1,c2\nv1,v2\n", encoding="utf-8")
            created[dest] = file_path
        return created

    def test_discover_all_csv_files(self) -> None:
        created = self._create_site_files()
        discovered = _discover_site_inputs(self.input_dir)
        self.assertEqual(len(discovered), 6)
        for dest in created:
            self.assertEqual(discovered[dest], created[dest].resolve())

    def test_discover_mixed_supported_extensions(self) -> None:
        mixed_extensions = {
            "microbiology_observations": ".csv",
            "bacteria_mapping": ".tsv",
            "sample_type_mapping": ".tab",
            "antibiotic_mapping": ".txt",
            "unit_mapping": ".rds",
            "hospitalization_intervals": ".csv",
        }
        created = self._create_site_files(extensions=mixed_extensions)
        discovered = _discover_site_inputs(self.input_dir)
        self.assertEqual(len(discovered), 6)
        for dest, ext in mixed_extensions.items():
            self.assertTrue(discovered[dest].name.endswith(ext))

    def test_discover_uppercase_extension(self) -> None:
        created = self._create_site_files(
            extensions={
                "microbiology_observations": ".CSV",
                "bacteria_mapping": ".RDS",
            }
        )
        discovered = _discover_site_inputs(self.input_dir)
        self.assertEqual(
            discovered["microbiology_observations"],
            created["microbiology_observations"].resolve(),
        )
        self.assertEqual(
            discovered["bacteria_mapping"],
            created["bacteria_mapping"].resolve(),
        )

    def test_discover_ignores_unsupported_extensions(self) -> None:
        (self.input_dir / "microbiology_observations.xlsx").write_text(
            "dummy", encoding="utf-8"
        )
        (self.input_dir / "microbiology_observations.parquet").write_text(
            "dummy", encoding="utf-8"
        )
        discovered = _discover_site_inputs(self.input_dir)
        self.assertNotIn("microbiology_observations", discovered)

    def test_discover_ignores_unrelated_files_and_subdirectories(self) -> None:
        (self.input_dir / "README.md").write_text("readme", encoding="utf-8")
        (self.input_dir / "other_data.csv").write_text("data", encoding="utf-8")
        sub_dir = self.input_dir / "microbiology_observations"
        sub_dir.mkdir()
        discovered = _discover_site_inputs(self.input_dir)
        self.assertEqual(discovered, {})

    def test_ambiguous_matching_files_raises_error(self) -> None:
        (self.input_dir / "bacteria_mapping.csv").write_text(
            "1", encoding="utf-8"
        )
        (self.input_dir / "bacteria_mapping.tsv").write_text(
            "2", encoding="utf-8"
        )
        with self.assertRaises(OrchideeError) as ctx:
            _discover_site_inputs(self.input_dir)
        err = str(ctx.exception)
        self.assertIn("Ambiguous site input for 'bacteria_mapping'", err)
        self.assertIn("bacteria_mapping.csv", err)
        self.assertIn("bacteria_mapping.tsv", err)
        self.assertIn("--bacteria-mapping", err)

    def test_ambiguity_skipped_if_destination_overridden(self) -> None:
        (self.input_dir / "bacteria_mapping.csv").write_text(
            "1", encoding="utf-8"
        )
        (self.input_dir / "bacteria_mapping.tsv").write_text(
            "2", encoding="utf-8"
        )
        (self.input_dir / "microbiology_observations.csv").write_text(
            "data", encoding="utf-8"
        )
        discovered = _discover_site_inputs(
            self.input_dir,
            skip_destinations={"bacteria_mapping"},
        )
        self.assertNotIn("bacteria_mapping", discovered)
        self.assertIn("microbiology_observations", discovered)


class TestSiteArgumentsAndPrecedence(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.input_dir = Path(self.temp_dir.name)
        for dest, _, _ in SITE_INPUTS:
            file_path = self.input_dir / f"{dest}.csv"
            file_path.write_text("col\nval\n", encoding="utf-8")

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_resolve_input_directory_success(self) -> None:
        resolved = resolve_input_directory(self.input_dir)
        self.assertEqual(resolved, self.input_dir.resolve())

    def test_resolve_input_directory_nonexistent(self) -> None:
        with self.assertRaises(OrchideeError) as ctx:
            resolve_input_directory(self.input_dir / "missing")
        self.assertIn("Input directory not found", str(ctx.exception))

    def test_resolve_input_directory_file(self) -> None:
        sample_file = self.input_dir / "bacteria_mapping.csv"
        with self.assertRaises(OrchideeError) as ctx:
            resolve_input_directory(sample_file)
        self.assertIn(
            "--input-dir must be a directory, not an existing file",
            str(ctx.exception),
        )

    def test_resolve_input_directory_empty_string(self) -> None:
        with self.assertRaises(OrchideeError) as ctx:
            resolve_input_directory("")
        self.assertIn("--input-dir path cannot be empty", str(ctx.exception))

    def test_site_input_values_all_discovered(self) -> None:
        parser = build_parser()
        args = parser.parse_args([
            "site",
            "--input-dir", str(self.input_dir),
            "--start-year", "2024",
            "--end-year", "2024",
        ])
        values = _site_input_values(args)
        self.assertEqual(len(values), 6)
        for dest, _, _ in SITE_INPUTS:
            expected = (self.input_dir / f"{dest}.csv").resolve()
            self.assertEqual(Path(values[dest]).resolve(), expected)

    def test_explicit_flag_overrides_discovered_file(self) -> None:
        parser = build_parser()
        custom_file = self.input_dir / "custom_bacteria.csv"
        custom_file.write_text("custom", encoding="utf-8")
        args = parser.parse_args([
            "site",
            "--input-dir", str(self.input_dir),
            "--bacteria-mapping", str(custom_file),
            "--start-year", "2024",
            "--end-year", "2024",
        ])
        values = _site_input_values(args)
        self.assertEqual(values["bacteria_mapping"], str(custom_file))
        self.assertEqual(
            Path(values["microbiology_observations"]).resolve(),
            (self.input_dir / "microbiology_observations.csv").resolve(),
        )

    def test_missing_files_error_explains_input_dir(self) -> None:
        (self.input_dir / "unit_mapping.csv").unlink()
        (self.input_dir / "hospitalization_intervals.csv").unlink()
        parser = build_parser()
        args = parser.parse_args([
            "site",
            "--input-dir", str(self.input_dir),
            "--start-year", "2024",
            "--end-year", "2024",
        ])
        with self.assertRaises(OrchideeError) as ctx:
            _validate_site_arguments(args)
        error_msg = str(ctx.exception)
        expected_prefix = (
            "Missing required site inputs: --unit-mapping, "
            "--hospitalization-intervals"
        )
        self.assertIn(expected_prefix, error_msg)
        self.assertIn(
            "neither supplied explicitly nor found in --input-dir",
            error_msg,
        )
        self.assertIn(str(self.input_dir), error_msg)

    def test_supplying_missing_file_explicitly_satisfies_validation(
        self,
    ) -> None:
        (self.input_dir / "unit_mapping.csv").unlink()
        custom_unit = self.input_dir / "standalone_unit.csv"
        custom_unit.write_text("unit", encoding="utf-8")
        parser = build_parser()
        args = parser.parse_args([
            "site",
            "--input-dir", str(self.input_dir),
            "--unit-mapping", str(custom_unit),
            "--start-year", "2024",
            "--end-year", "2024",
        ])
        _validate_site_arguments(args)
        self.assertEqual(args.unit_mapping, str(custom_unit))
        self.assertEqual(
            Path(args.bacteria_mapping).resolve(),
            (self.input_dir / "bacteria_mapping.csv").resolve(),
        )

    def test_missing_files_without_input_dir_retains_legacy_error(
        self,
    ) -> None:
        parser = build_parser()
        args = parser.parse_args([
            "site",
            "--bacteria-mapping", "some/path.csv",
            "--start-year", "2024",
            "--end-year", "2024",
        ])
        with self.assertRaises(OrchideeError) as ctx:
            _validate_site_arguments(args)
        error_msg = str(ctx.exception)
        self.assertTrue(error_msg.startswith("Missing required site inputs:"))
        self.assertNotIn(
            "neither supplied explicitly nor found in --input-dir",
            error_msg,
        )

    def test_input_dir_with_run_smoke_test_rejected(self) -> None:
        parser = build_parser()
        args = parser.parse_args([
            "site",
            "--run-smoke-test",
            "--input-dir", str(self.input_dir),
        ])
        with self.assertRaises(OrchideeError) as ctx:
            _validate_site_arguments(args)
        self.assertIn(
            "--run-smoke-test cannot be combined with site input options",
            str(ctx.exception),
        )

    def test_input_dir_with_emit_templates_rejected(self) -> None:
        parser = build_parser()
        args = parser.parse_args([
            "site",
            "--emit-templates", str(self.input_dir / "templates"),
            "--input-dir", str(self.input_dir),
        ])
        with self.assertRaises(OrchideeError) as ctx:
            _validate_site_arguments(args)
        self.assertIn(
            "--emit-templates cannot be combined with build options",
            str(ctx.exception),
        )

    def test_run_site_alias_exists_and_callable(self) -> None:
        self.assertIs(run_site, command_site)


class TestResolveRscriptTolerance(unittest.TestCase):
    def test_explicit_orchidee_r_with_version_mismatch_proceeds_with_warning(self) -> None:
        from unittest.mock import patch
        from scripts.orchidee import resolve_rscript

        fake_rscript = Path(__file__).resolve()
        with patch.dict(os.environ, {"ORCHIDEE_R": str(fake_rscript)}):
            with patch("scripts.orchidee.rscript_version", return_value="4.4.2"):
                resolved = resolve_rscript()
                self.assertEqual(resolved, fake_rscript)

    def test_allow_r_mismatch_uses_available_installation(self) -> None:
        from unittest.mock import patch
        from scripts.orchidee import resolve_rscript

        fake_rscript = Path(__file__).resolve()
        with patch.dict(os.environ, {"ORCHIDEE_ALLOW_R_MISMATCH": "1"}, clear=False):
            if "ORCHIDEE_R" in os.environ:
                del os.environ["ORCHIDEE_R"]
            with patch("scripts.orchidee._unique_paths", return_value=[fake_rscript]):
                with patch("scripts.orchidee.rscript_version", return_value="4.4.2"):
                    resolved = resolve_rscript()
                    self.assertEqual(resolved, fake_rscript)

    def test_error_message_mentions_orchidee_r_and_allow_mismatch(self) -> None:
        from unittest.mock import patch
        from scripts.orchidee import resolve_rscript, OrchideeError

        with patch.dict(os.environ, {"ORCHIDEE_ALLOW_R_MISMATCH": ""}, clear=False):
            if "ORCHIDEE_R" in os.environ:
                del os.environ["ORCHIDEE_R"]
            with patch("scripts.orchidee._unique_paths", return_value=[]):
                with self.assertRaises(OrchideeError) as ctx:
                    resolve_rscript()
                self.assertIn("ORCHIDEE_R", str(ctx.exception))
                self.assertIn("ORCHIDEE_ALLOW_R_MISMATCH", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
