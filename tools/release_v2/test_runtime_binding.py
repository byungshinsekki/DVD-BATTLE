"""Synthetic regression checks for Windows Python alias handling; no engines/profiles."""
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock, patch

import release


class RuntimeBinding(unittest.TestCase):
    def test_binary_provenance_uses_interpreter_without_opening_launcher_alias(self):
        runner = object.__new__(release.Release)
        with patch.object(release.shutil, "which", return_value="powershell.exe") as locate, \
                patch.object(release, "file_evidence", side_effect=lambda values: list(values)):
            paths = runner.binary_hashes()
        locate.assert_called_once_with("powershell")
        self.assertIn(sys.executable, paths)
        self.assertFalse(any(str(path).lower().endswith("/py.exe") for path in paths))

    def test_render_helper_receives_exact_hashed_interpreter(self):
        runner = object.__new__(release.Release)
        runner.project = Path("synthetic_project")
        runner.process = Mock(side_effect=RuntimeError("capture_command_only"))
        with patch.object(release, "ensure_helper", return_value={}):
            with self.assertRaisesRegex(RuntimeError, "capture_command_only"):
                runner.helper("uitest", "synthetic", ["-Suite", "preview_ui_14"])
        command, name = runner.process.call_args.args
        self.assertEqual(name, "synthetic")
        self.assertEqual(command.count("-PythonExe"), 1)
        self.assertEqual(command[command.index("-PythonExe") + 1], sys.executable)
        self.assertIn("-File", command)

    def test_missing_powershell_remains_a_failure(self):
        runner = object.__new__(release.Release)
        with patch.object(release.shutil, "which", return_value=None):
            with self.assertRaisesRegex(RuntimeError, "PowerShell"):
                runner.binary_hashes()


if __name__ == "__main__":
    unittest.main(verbosity=2)
