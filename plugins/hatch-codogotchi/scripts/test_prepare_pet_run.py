#!/usr/bin/env python3
import json
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parent / "prepare_pet_run.py"


class PreparePetRunTests(unittest.TestCase):
    def test_write_pet_json_includes_required_spritesheet_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            run_root = Path(tmp)
            subprocess.run(
                [
                    "python",
                    str(SCRIPT),
                    "--description",
                    "manifest smoke pet",
                    "--pet-id",
                    "manifest-smoke",
                    "--pet-name",
                    "Manifest Smoke",
                    "--tier",
                    "codex",
                    "--out-dir",
                    str(run_root),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            subprocess.run(
                [
                    "python",
                    str(SCRIPT),
                    "--write-pet-json",
                    "--run-dir",
                    str(run_root / "manifest-smoke"),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            manifest = json.loads((run_root / "manifest-smoke" / "pet.json").read_text())
            self.assertEqual(manifest["id"], "manifest-smoke")
            self.assertEqual(manifest["displayName"], "Manifest Smoke")
            self.assertEqual(manifest["spritesheetPath"], "spritesheet.webp")


if __name__ == "__main__":
    unittest.main()
