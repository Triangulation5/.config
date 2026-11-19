#!/usr/bin/env python3

import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock


SCRIPT = Path(__file__).resolve().with_name("silhouette-update.py")
SPEC = importlib.util.spec_from_file_location("silhouette_update", SCRIPT)
updater = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(updater)


class DistroDetectionTests(unittest.TestCase):
    def test_linux_families_match_the_installer_catalog(self):
        cases = {
            "fedora": "fedora",
            "alpine": "alpine",
            "artix": "arch",
            "arch": "arch",
            "ubuntu": "debian",
            "opensuse-tumbleweed": "suse",
            "gentoo": "gentoo",
            "void": "void",
        }
        with tempfile.TemporaryDirectory() as temp:
            release = Path(temp) / "os-release"
            for identity, expected in cases.items():
                release.write_text(f"ID={identity}\n")
                with (
                    mock.patch.dict(updater.os.environ, {"SILHOUETTE_OS_RELEASE": str(release)}),
                    mock.patch.object(updater.platform, "system", return_value="Linux"),
                ):
                    self.assertEqual(updater.distro_family(), expected)

    def test_bsd_and_darwin_families_use_the_platform_name(self):
        with tempfile.TemporaryDirectory() as temp:
            release = Path(temp) / "os-release"
            release.write_text("ID=unknown\n")
            for system, expected in (
                ("FreeBSD", "freebsd"),
                ("OpenBSD", "openbsd"),
                ("NetBSD", "netbsd"),
                ("DragonFly", "dragonfly"),
                ("Darwin", "darwin"),
            ):
                with (
                    mock.patch.dict(updater.os.environ, {"SILHOUETTE_OS_RELEASE": str(release)}),
                    mock.patch.object(updater.platform, "system", return_value=system),
                ):
                    self.assertEqual(updater.distro_family(), expected)


class PackageBackendTests(unittest.TestCase):
    def test_check_parsers_cover_supported_package_managers(self):
        cases = (
            ("fedora", "foo.x86_64 1.0 repo\n", ["foo.x86_64"]),
            ("gentoo", "[ebuild U ] app-misc/foo-2.0 [1.0]\n", ["app-misc/foo-2.0"]),
            ("arch", "foo 1.0 -> 2.0\n", ["foo"]),
            ("debian", "Inst foo [1.0] (2.0 repo)\n", ["foo"]),
            ("alpine", "foo-2.0 x86_64 {repo} [upgradable from: 1.0]\n", ["foo-2.0"]),
            ("suse", "v | foo | package | 2.0 | x86_64 | repo\n", ["foo"]),
            ("void", "foo-2.0 update x86_64 repo 10 5\n", ["foo-2.0"]),
            ("freebsd", "    foo: 1.0 -> 2.0\n", ["foo"]),
            ("openbsd", "Update 1: foo-2.0\n", ["foo-2.0"]),
            ("netbsd", "foo-2.0\n", ["foo-2.0"]),
            ("darwin", '{"formulae":[{"name":"foo"}],"casks":[{"token":"bar"}]}', ["foo", "bar"]),
        )
        for family, output, expected in cases:
            with self.subTest(family=family):
                self.assertEqual(updater.backend(family).parse(output), expected)

    def test_security_only_is_advertised_only_for_implemented_managers(self):
        self.assertIsNotNone(updater.backend("fedora").minimal)
        self.assertIsNotNone(updater.backend("suse").minimal)
        for family in ("alpine", "arch", "debian", "gentoo", "void", "freebsd", "openbsd", "netbsd", "darwin"):
            with self.subTest(family=family):
                self.assertIsNone(updater.backend(family).minimal)

    def test_gentoo_check_and_apply_keep_existing_contract(self):
        output = "[ebuild U ] app-misc/foo-2.0 [1.0]\n"
        with (
            mock.patch.object(updater, "distro_family", return_value="gentoo"),
            mock.patch.object(updater, "run_command", return_value=(0, output)),
        ):
            checked = updater.check()
        self.assertEqual(checked["packages"], ["app-misc/foo-2.0"])
        self.assertFalse(checked["supportsMinimal"])

        with (
            mock.patch.object(updater, "distro_family", return_value="gentoo"),
            mock.patch.object(updater, "run_command", return_value=(0, "")) as run,
        ):
            applied = updater.apply()
        self.assertTrue(applied["applied"])
        self.assertIn("@world", run.call_args.args[0].args)

    def test_invalid_homebrew_json_is_an_error_not_an_empty_update_list(self):
        with (
            mock.patch.object(updater, "distro_family", return_value="darwin"),
            mock.patch.object(updater, "run_command", return_value=(0, "not json")),
        ):
            result = updater.check()
        self.assertEqual(result["status"], "error")


class RustDispatchTests(unittest.TestCase):
    def run_rust_with_output(self, operation, output):
        completed = SimpleNamespace(stdout=output, stderr="", returncode=0)
        with (
            mock.patch.object(updater, "rust_enabled", return_value=True),
            mock.patch.object(updater.Path, "is_file", return_value=True),
            mock.patch.object(updater.os, "access", return_value=True),
            mock.patch.object(updater.subprocess, "run", return_value=completed),
            mock.patch("sys.stderr", new_callable=io.StringIO),
        ):
            return updater.run_rust(operation)

    def test_invalid_rust_output_selects_python_fallback(self):
        self.assertIsNone(self.run_rust_with_output("check", "not json"))

    def test_valid_package_manager_error_is_not_retried(self):
        result = {
            "status": "error",
            "applied": False,
            "rebootNeeded": False,
            "results": [{"command": "dnf upgrade", "success": False, "output": "failed"}],
        }
        self.assertEqual(
            self.run_rust_with_output("apply", json.dumps(result)),
            result,
        )


if __name__ == "__main__":
    unittest.main()
