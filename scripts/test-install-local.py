#!/usr/bin/env python3
"""Exercise installation/rollback in a temporary filesystem with fake macOS tools."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parent


class LocalInstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="langswitcher-install-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.apps = self.root / "Applications"
        self.apps.mkdir()
        self.installed = self.apps / "LangSwitcher.app"
        self.installed.mkdir()
        (self.installed / "version").write_text("old")
        self.source = self.root / "source.app"
        (self.source / "Contents/MacOS").mkdir(parents=True)
        (self.source / "version").write_text("new")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.events = self.root / "events"
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        HOME=str(self.root), LANGSWITCHER_SIGNING_IDENTITY="test-certificate",
                        TEST_EVENTS=str(self.events))
        # Substitute only fixed installation paths, never exercise /Applications.
        source = (SCRIPTS / "install-local.sh").read_text()
        self.assertIn('installed_app="/Applications/LangSwitcher.app"', source)
        self.assertIn('mktemp -d /Applications/.LangSwitcher-install.XXXXXX', source)
        source = source.replace('/Applications/', str(self.apps) + '/')
        self.installer = self.root / "install-local.sh"
        self.installer.write_text(source)
        self.tool(self.root / "sign-app.sh", 'echo sign >> "$TEST_EVENTS"; exit "${TEST_SIGN_EXIT:-0}"')
        self.tool(self.bin / "codesign", r'''if [[ "$*" == *--requirements* ]]; then
  echo 'designated => identifier "com.langswitcher.app" and anchor apple generic'
elif [[ "$*" == *--display* ]]; then
  echo "${TEST_SIGNATURE:-Authority=Test certificate}" >&2
else
  echo verify >> "$TEST_EVENTS"
  exit "${TEST_VERIFY_EXIT:-0}"
fi''')
        self.tool(self.bin / "ditto", r'''if [[ "$1" == "-c" ]]; then
  echo backup >> "$TEST_EVENTS"
  touch "${@: -1}"
else
  /bin/cp -R "$1" "$2"
fi''')
        self.tool(self.bin / "pgrep", 'exit 1')
        self.tool(self.bin / "open", 'echo open >> "$TEST_EVENTS"')
        self.tool(self.bin / "mv", r'''if [[ "${TEST_FAIL_REPLACEMENT:-}" == 1 && "$2" == */.LangSwitcher-install.*/LangSwitcher.app ]]; then
  exit 1
fi
exec /bin/mv "$@"''')

    def tool(self, path, content):
        path.write_text('#!/bin/bash\nset -e\n' + content + '\n')
        path.chmod(0o755)

    def run_installer(self, **overrides):
        return subprocess.run(['bash', str(self.installer), str(self.source)],
                              env=dict(self.env, **overrides), capture_output=True, text=True)

    def assert_old_preserved(self):
        self.assertEqual((self.installed / "version").read_text(), "old")

    def test_requires_certificate_before_staging(self):
        for identity in ("", "-"):
            with self.subTest(identity=identity):
                self.assertNotEqual(self.run_installer(LANGSWITCHER_SIGNING_IDENTITY=identity).returncode, 0)
                self.assert_old_preserved()
                self.assertFalse(self.events.exists())

    def test_signing_failure_preserves_installation(self):
        self.assertNotEqual(self.run_installer(TEST_SIGN_EXIT="1").returncode, 0)
        self.assert_old_preserved()
        self.assertEqual(self.events.read_text().splitlines(), ["sign"])

    def test_identity_mismatch_preserves_installation(self):
        self.assertNotEqual(self.run_installer(TEST_VERIFY_EXIT="1").returncode, 0)
        self.assert_old_preserved()
        self.assertEqual(self.events.read_text().splitlines(), ["sign", "verify"])

    def test_install_checks_identity_and_archives_backup(self):
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.installed / "version").read_text(), "new")
        self.assertEqual(self.events.read_text().splitlines(), ["sign", "verify", "backup", "open"])
        self.assertEqual(len(list((self.root / "Library/Application Support/LangSwitcher/Backups").glob("*.zip"))), 1)
        self.assertFalse(list(self.apps.glob(".LangSwitcher-install.*")))

    def test_failed_replacement_restores_old_bundle(self):
        self.assertNotEqual(self.run_installer(TEST_FAIL_REPLACEMENT="1").returncode, 0)
        self.assert_old_preserved()
        self.assertNotIn("open", self.events.read_text().splitlines())

    def test_adhoc_migration_is_explicit(self):
        result = self.run_installer(TEST_SIGNATURE="Signature=adhoc")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("renew Accessibility consent", result.stdout)
        self.assertNotIn("verify", self.events.read_text().splitlines())

    def test_sign_helper_does_not_default_to_adhoc(self):
        result = subprocess.run(['bash', str(SCRIPTS / 'sign-app.sh'), str(self.source)],
                                env=dict(self.env, LANGSWITCHER_SIGNING_IDENTITY=""),
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Set LANGSWITCHER_SIGNING_IDENTITY", result.stderr)


if __name__ == '__main__':
    unittest.main()
