"""Running a script from an installed Skill folder must not leave __pycache__ there."""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parents[2] / "skills" / "travel-handbook" / "scripts"


@pytest.mark.parametrize("name", ["build_map", "build_charts", "fetch_photos", "check_docs"])
def test_a_run_writes_no_bytecode_next_to_the_scripts(tmp_path, name):
    folder = tmp_path / "scripts"
    shutil.copytree(SCRIPTS, folder, ignore=shutil.ignore_patterns("__pycache__"))
    environment = {key: value for key, value in os.environ.items()
                   if key != "PYTHONDONTWRITEBYTECODE"}
    environment["MPLBACKEND"] = "Agg"

    result = subprocess.run([sys.executable, str(folder / f"{name}.py"), "--help"],
                            env=environment, capture_output=True, text=True, timeout=120)

    assert result.returncode == 0, result.stderr
    assert not (folder / "__pycache__").exists()
