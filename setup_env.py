#!/usr/bin/env python3
# Copyright 2025 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
"""Create the project virtual environment (`.venv`) from `requirements.txt`.

Normally called by `bootstrap.sh`, but it can be run by hand with any
interpreter >= 3.8:

    python3.12 setup_env.py

The environment contains exactly the packages pinned in `requirements.txt`
(the register generator `regtool.py` is the only Python tool of the flow).
It is rebuilt from scratch whenever `requirements.txt` or the interpreter
version changes, and left untouched otherwise.
"""
import hashlib
import subprocess
import sys
import venv
from pathlib import Path

MIN_PYTHON = (3, 8)

ROOT = Path(__file__).resolve().parent
VENV_DIR = ROOT / ".venv"
REQ_FILE = ROOT / "requirements.txt"
STAMP_FILE = VENV_DIR / ".requirements.stamp"

# Modules imported by regtool.py (reggen); used as a smoke test after installing.
SMOKE_IMPORTS = ("hjson", "mako", "yaml", "tabulate", "pkg_resources")


def log(msg: str) -> None:
    print(f"[setup_env] {msg}", flush=True)


def expected_stamp() -> str:
    """Identify what the environment must contain: interpreter + requirements."""
    digest = hashlib.sha256(REQ_FILE.read_bytes()).hexdigest()
    return f"python={sys.version_info[0]}.{sys.version_info[1]}\nrequirements={digest}\n"


def smoke_test(python: Path) -> bool:
    code = "import " + ", ".join(SMOKE_IMPORTS)
    return subprocess.call([str(python), "-W", "ignore", "-c", code]) == 0


def main() -> int:
    if sys.version_info < MIN_PYTHON:
        log(f"Python >= {MIN_PYTHON[0]}.{MIN_PYTHON[1]} is required, "
            f"this is {sys.version.split()[0]} ({sys.executable}).")
        return 1
    if not REQ_FILE.is_file():
        log(f"{REQ_FILE} not found.")
        return 1

    python = VENV_DIR / "bin" / "python"
    stamp = expected_stamp()

    if python.exists() and STAMP_FILE.exists() and STAMP_FILE.read_text() == stamp \
            and smoke_test(python):
        log(f"{VENV_DIR.name} is up to date ({sys.version.split()[0]}), nothing to do.")
        return 0

    log(f"Creating {VENV_DIR.name} with {sys.executable} ({sys.version.split()[0]})...")
    venv.create(VENV_DIR, clear=True, with_pip=True)

    log(f"Installing {REQ_FILE.name}...")
    try:
        subprocess.check_call([str(python), "-m", "pip", "install", "--quiet",
                               "--disable-pip-version-check", "--no-input",
                               "-r", str(REQ_FILE)])
    except subprocess.CalledProcessError:
        log("pip failed (the packages are downloaded from PyPI, so network access is needed).")
        return 1

    if not smoke_test(python):
        log("Installed packages cannot be imported, the environment is broken.")
        return 1

    STAMP_FILE.write_text(stamp)
    log("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
