#!/usr/bin/env python3

import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPTS = Path(__file__).resolve().parent


def load_script(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


rice_update = load_script("rice_update", SCRIPTS / "rice-update.py")
package_update = load_script("package_update", SCRIPTS / "silhouette-update.py")


class GentooSupportTests(unittest.TestCase):
    def test_portage_vdb_matches_exact_package_names(self):
        with tempfile.TemporaryDirectory() as vdb:
            category = Path(vdb) / "app-misc"
            (category / "cliphist-tools-1.0").mkdir(parents=True)
            with mock.patch.object(rice_update, "PORTAGE_VDB", vdb):
                self.assertFalse(rice_update.gentoo_installed("app-misc/cliphist"))
                self.assertFalse(rice_update.gentoo_installed("app-misc/clip"))
                self.assertTrue(rice_update.gentoo_installed("app-misc/cliphist-tools"))
                (category / "cliphist-0.7.0").mkdir()
                self.assertTrue(rice_update.gentoo_installed("app-misc/cliphist"))

    def test_core_packages_are_read_from_installer_catalog(self):
        with tempfile.TemporaryDirectory() as checkout:
            catalog = Path(checkout) / "scripts" / "installer" / "packages.sh"
            catalog.parent.mkdir(parents=True)
            catalog.write_text("CORE_gentoo=(sys-apps/dbus sys-auth/elogind)\n")
            with mock.patch.object(rice_update, "distro_family", return_value="gentoo"):
                self.assertEqual(
                    rice_update.core_packages(checkout),
                    ["sys-apps/dbus", "sys-auth/elogind"],
                )

    def test_gentoo_dependency_install_uses_portage(self):
        command = rice_update.install_command("gentoo", ["sys-auth/elogind"])
        self.assertEqual(command[0], "emerge")
        self.assertIn("--autounmask-continue=y", command)
        self.assertEqual(command[-1], "sys-auth/elogind")

    def test_emerge_plan_is_parsed_and_security_mode_is_disabled(self):
        output = "\n".join([
            "[ebuild  U  ] app-misc/cliphist-0.7.0 [0.6.0]",
            "[ebuild  N  ~] sys-auth/elogind-252.9",
            "The following packages will be merged:",
        ])
        self.assertEqual(
            package_update.parse_emerge_check(output),
            ["app-misc/cliphist-0.7.0", "sys-auth/elogind-252.9"],
        )
        with (
            mock.patch.object(package_update, "distro_family", return_value="gentoo"),
            mock.patch.object(package_update, "run_command", return_value=(0, output)),
        ):
            result = package_update.check()
        self.assertFalse(result["supportsMinimal"])
        self.assertEqual(result["updates"], 2)

    def test_gentoo_apply_uses_world_update(self):
        with (
            mock.patch.object(package_update, "distro_family", return_value="gentoo"),
            mock.patch.object(package_update, "run_command", return_value=(0, "")) as run,
        ):
            result = package_update.apply()
        self.assertTrue(result["applied"])
        self.assertIn("@world", run.call_args.args[0].args)


if __name__ == "__main__":
    unittest.main()
