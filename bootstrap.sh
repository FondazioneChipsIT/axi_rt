#!/usr/bin/env bash
# Copyright 2025 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Prepare the current shell for working on axi_tmu. This file MUST be sourced:
#
#     source bootstrap.sh
#
# (executing it would load the modules in a child process and lose them on exit).
#
# What it does:
#   1. loads the bender and Questa environment modules into the current shell;
#   2. creates/updates the Python virtual environment (.venv, see setup_env.py
#      and requirements.txt) and activates it;
#   3. checks out the Bender dependencies at the revisions pinned in Bender.lock.
#
# Optional overrides, set before sourcing:
#   BENDER_MODULE   bender module to load      (default: bender/0.32.1)
#   QUESTA_MODULE   Questa module to load      (default: questa/2026.1_2)
#   PYTHON          interpreter used for .venv (default: newest python3.x >= 3.8)

if [ -z "${BASH_VERSION:-}" ]; then
    echo "bootstrap.sh: bash is required. Run: bash, then: source bootstrap.sh" >&2
    return 1 2>/dev/null || exit 1
fi
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    echo "bootstrap.sh must be sourced, not executed, otherwise the modules and the" >&2
    echo "virtual environment are lost when it exits. Run: source bootstrap.sh" >&2
    exit 1
fi

_bs_log() { echo "[bootstrap] $*"; }
_bs_err() { echo "[bootstrap] ERROR: $*" >&2; }

# Make the `module` command usable even in shells that did not inherit it
# (batch jobs, cron, `env -i`, ...).
_bs_module_init() {
    local f
    for f in /etc/profile.d/00-modulepath.sh /etc/profile.d/modules.sh /etc/profile.d/99-modulepath.sh; do
        [ -r "$f" ] && . "$f"
    done
    type module >/dev/null 2>&1
}

# $1: module name, $2: command that must be on PATH once it is loaded.
_bs_load_module() {
    local mod="$1" cmd="$2"
    if module load "$mod" 2>/dev/null && command -v "$cmd" >/dev/null 2>&1; then
        return 0
    fi
    # A module can be listed as loaded while its PATH entry is gone (for instance
    # restored by a venv deactivation): `module load` is then a no-op, so reload it.
    module unload "$mod" 2>/dev/null
    if module load "$mod" 2>/dev/null && command -v "$cmd" >/dev/null 2>&1; then
        return 0
    fi
    # The site module trees may be missing from MODULEPATH: add them and retry once.
    _bs_module_init || return 1
    module load "$mod" && command -v "$cmd" >/dev/null 2>&1
}

# $1: loaded module (e.g. bender/0.32.1). Only informs, never switches version.
_bs_note_newer() {
    local family="${1%%/*}" latest
    latest="$(module avail -t "$family" 2>&1 | grep "^${family}/" | sort -V | tail -n 1)"
    if [ -n "$latest" ] && [ "$latest" != "$1" ] \
        && [ "$(printf '%s\n%s\n' "$1" "$latest" | sort -V | tail -n 1)" = "$latest" ]; then
        _bs_log "note: a newer module exists ($latest), using $1; set the *_MODULE variable to try it"
    fi
}

# Print the interpreter to use for the venv: $PYTHON, or the newest python3.x >= 3.8.
_bs_find_python() {
    local c
    local -a candidates
    if [ -n "${PYTHON:-}" ]; then
        candidates=("$PYTHON")
    else
        candidates=(python3.12 python3.11 python3.10 python3.9 python3.8 python3)
    fi
    for c in "${candidates[@]}"; do
        command -v "$c" >/dev/null 2>&1 || continue
        if "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>/dev/null; then
            command -v "$c"
            return 0
        fi
    done
    return 1
}

_axi_tmu_bootstrap() {
    local root bender_mod questa_mod py

    root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || return 1
    bender_mod="${BENDER_MODULE:-bender/0.32.1}"
    questa_mod="${QUESTA_MODULE:-questa/2026.1_2}"

    if [ ! -f "$root/Bender.lock" ]; then
        _bs_err "Bender.lock is missing. It pins the dependency versions; without it bender"
        _bs_err "would silently resolve the latest ones. Restore it with: git checkout -- Bender.lock"
        return 1
    fi

    # 0. Leave any active venv --------------------------------------------------
    # This must come before loading the modules: deactivating restores the PATH
    # saved when the venv was activated, which would drop the module paths added
    # in the meantime. It also lets setup_env.py rebuild .venv from scratch.
    if [ -n "${VIRTUAL_ENV:-}" ] && [ "$(type -t deactivate 2>/dev/null)" = function ]; then
        deactivate
    fi

    # 1. Modules ---------------------------------------------------------------
    if ! type module >/dev/null 2>&1 && ! _bs_module_init; then
        _bs_err "the 'module' command is not available on this machine."
        return 1
    fi
    _bs_load_module "$bender_mod" bender || { _bs_err "cannot load module $bender_mod"; return 1; }
    _bs_load_module "$questa_mod" vsim   || { _bs_err "cannot load module $questa_mod"; return 1; }
    _bs_note_newer "$bender_mod"
    _bs_note_newer "$questa_mod"

    # 2. Python virtual environment --------------------------------------------
    py="$(_bs_find_python)" || { _bs_err "no Python >= 3.8 found (set PYTHON=/path/to/python3.x)"; return 1; }
    "$py" "$root/setup_env.py" || { _bs_err "setup_env.py failed"; return 1; }
    # shellcheck disable=SC1091
    . "$root/.venv/bin/activate" || return 1

    # 3. Bender dependencies (exact revisions from Bender.lock) ----------------
    bender -d "$root" checkout || { _bs_err "bender checkout failed"; return 1; }

    _bs_log "ready:"
    _bs_log "  $(bender --version) ($(command -v bender))"
    _bs_log "  $(vsim -version 2>&1 | head -n 1)"
    _bs_log "  $(python --version 2>&1) ($(command -v python))"
    _bs_log "  dependencies checked out at the revisions pinned in Bender.lock"
}

if _axi_tmu_bootstrap; then
    unset -f _axi_tmu_bootstrap _bs_log _bs_err _bs_module_init _bs_load_module _bs_note_newer _bs_find_python
    return 0
else
    unset -f _axi_tmu_bootstrap _bs_log _bs_err _bs_module_init _bs_load_module _bs_note_newer _bs_find_python
    return 1
fi
