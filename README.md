# axi_tmu

RTL sources, register description, software headers and testbench of the `axi_tmu` IP.

## Quick start

```bash
git clone <repository-url> axi_tmu
cd axi_tmu
source bootstrap.sh
```

That single command prepares the current shell for all the work on this repository.
When it finishes, `bender`, `vsim` and the project Python environment are
available **in the shell where you ran it**.

> **`bootstrap.sh` must be sourced, not executed.**
> `module load` and `source .venv/bin/activate` only change the environment of
> the shell that runs them. A script started as `./bootstrap.sh` runs in a child
> process, so everything it loaded would be lost as soon as it exits (the script
> detects this and refuses to run). Source it again in every new shell.

## What `bootstrap.sh` does

1. **Loads the environment modules** `bender/0.32.1` and `questa/2026.1_2`
   (the most recent versions at the time of writing, both tested with this
   repository). If the `module` command is not defined in the shell (batch jobs,
   cron, `env -i`, ...), it initialises it first. It only prints a note if newer
   modules appear; it never switches version on its own.
2. **Creates or updates the Python virtual environment** `.venv` by calling
   `setup_env.py`, then activates it. See [Python environment](#python-environment).
3. **Checks out the Bender dependencies** with `bender checkout`, at the exact
   revisions pinned in `Bender.lock`. See [Dependencies](#dependencies).
4. Prints the versions of bender, Questa and Python that are now active.

The script is idempotent: running it again takes a couple of seconds and changes
nothing if nothing changed.

### Repository layout

| Path | Purpose |
|---|---|
| `bootstrap.sh` | Source it: loads the modules, builds/activates `.venv`, checks out the Bender dependencies. |
| `setup_env.py` | Builds `.venv` from `requirements.txt` (called by `bootstrap.sh`). |
| `requirements.txt` | Pinned Python packages (register generator only). |
| `Bender.yml`, `Bender.lock`, `Bender.local` | Dependency manifest, pinned revisions, local version override. |
| `Makefile` | Entry point of `make`. Defines `TMU_ROOT` (the repository root, i.e. the directory `make` is run from) and `BENDER` (`bender -d $(TMU_ROOT)`), includes `axi_tmu.mk`, and warns when `.venv` is not active (see [Register generation](#register-generation)). |
| `axi_tmu.mk` | The actual make targets: `regen_regs`, `tmu-sim-init`, `tmu-build`, `tmu-sim`, `synth-ips`, `bender`. It expects `TMU_ROOT` and `BENDER` from the `Makefile`, so run `make` from the repository root. |
| `src/rtl/` | RTL modules. |
| `src/registers/` | Generated register RTL (`axi_tmu_<variant>_reg_pkg.sv`, `axi_tmu_<variant>_reg_top.sv`). |
| `src/registers/regmap/` | Register descriptions in hjson (`axi_tmu_<variant>_regs.hjson`), the only files to edit by hand. |
| `sw/include/regs/` | Generated C header of the registers. |
| `target/sim/vsim/` | Questa scripts. |
| `test/` | Testbench and stimuli. |

Always give `make` an explicit target. Without one it runs the first target of
`axi_tmu.mk`, `bender`, which downloads an old bender (0.24.0) into `./bender`;
that is not needed, because `bootstrap.sh` loads the bender module.

### Requirements of the machine

- `bash` and the Environment Modules `module` command, with the `bender` and
  `questa` modules available.
- Python **3.8 or newer** with the `venv` module. The default `python3` of some
  machines is too old (3.6 on the cluster this was developed on); the script
  picks the newest of `python3.12 … python3.8` it finds.
- `git` and GNU `make`.
- Network access to GitHub (Bender dependencies) and PyPI (Python packages).

### Overrides

Set these before sourcing the script:

| Variable        | Meaning                              | Default                                  |
|-----------------|--------------------------------------|------------------------------------------|
| `BENDER_MODULE` | bender module to load                | `bender/0.32.1`                          |
| `QUESTA_MODULE` | Questa module to load                | `questa/2026.1_2`                        |
| `PYTHON`        | interpreter used to build `.venv`    | newest `python3.x` (3.8 or newer) found |

```bash
QUESTA_MODULE=questa/2025.3 PYTHON=python3.11 source bootstrap.sh
```

## Python environment

Python is used by exactly one tool of the flow: the register generator
`regtool.py` (OpenTitan's `reggen`, shipped in the `register_interface`
dependency), run by `make regen_regs`. Building and simulating the IP does not
use Python, so there is **no** development requirements file: only
`requirements.txt` exists.

- `requirements.txt` pins every package to an exact version, including the
  transitive `MarkupSafe`, so the environment is the same on every machine. The
  pins were checked on Python 3.8, 3.11 and 3.12: they install on all of them and
  regenerate register files identical to the committed ones.
- `setuptools` is listed on purpose: `reggen` imports `pkg_resources`, which
  Python >= 3.12 virtual environments do not ship and recent `setuptools`
  releases removed. See the comments in `requirements.txt`.
- `setup_env.py` builds `.venv` from that file. `.venv` is rebuilt from scratch
  whenever `requirements.txt` or the interpreter version changes, and left alone
  otherwise. Treat `.venv` as generated output (it is git-ignored): never edit it
  by hand, delete it freely.
- To change a dependency, edit `requirements.txt` and source `bootstrap.sh` again.

`setup_env.py` can also be run on its own with any interpreter >= 3.8
(`python3.12 setup_env.py`); it then only creates `.venv`, without loading modules.

## Dependencies

The RTL dependencies (`common_cells`, `axi`, `register_interface`, and their
transitive ones) are declared in `Bender.yml` and resolved with
[Bender](https://github.com/pulp-platform/bender).

- `Bender.lock` is tracked and pins every dependency to a git revision.
  `bootstrap.sh` checks out exactly those revisions, and **refuses to continue if
  `Bender.lock` is missing**, because bender would then silently resolve the
  newest compatible versions and the build would no longer be reproducible.
- `Bender.local` overrides the `axi` version requirement (see the file).
- There is deliberately no `make clean` target. To start from scratch delete
  `.bender/` (the checkouts) and, if needed, `.venv/`, never `Bender.lock`. If
  `Bender.lock` gets deleted, restore it with `git checkout -- Bender.lock`.
- To update the dependencies on purpose, run `bender update`, review the
  diff of `Bender.lock` and commit it together with the reason for the update.

## Register generation

The control/status registers of each variant are described in
`src/registers/regmap/axi_tmu_<variant>_regs.hjson`, with `<variant>` being `ilt`, `clt`
or `plt`. Every name `regtool` generates (package, modules, types, C macros) is
derived from the `name:` field of that file (`axi_tmu_<variant>`), not from its
file name, so the two must agree: `make regen_regs` stops with an error otherwise.
The generated files are committed, three per variant:

- `src/registers/axi_tmu_<variant>_reg_pkg.sv`
- `src/registers/axi_tmu_<variant>_reg_top.sv`
- `sw/include/regs/axi_tmu_<variant>_reg.h`

Because of the per-variant names the register blocks of the three variants can be
compiled together without clashes, and `Bender.yml` lists all of them.

After editing an hjson file, regenerate and commit the results:

```bash
source bootstrap.sh      # once per shell
make regen_regs          # all variants; only those whose hjson changed are rebuilt
git status               # the generated files of the edited variant show up as modified
```

`make regen_regs TMU_VARIANTS=ilt` limits the run to the listed variants. To add a
variant, create its `axi_tmu_<variant>_regs.hjson` and add its name to
`TMU_VARIANTS` in `axi_tmu.mk`.

`make regen_regs` finds `regtool.py` through `bender path register_interface` and
starts it through its `#!/usr/bin/env python3` shebang, i.e. with the first
`python3` in `PATH`. After `source bootstrap.sh` that is the `.venv` interpreter.

Nothing forces this, so the `Makefile` checks it: if the shell did not source
`bootstrap.sh` (or another environment is active), `make regen_regs` prints

```
Makefile:NN: The project Python environment (.venv) is NOT active: regtool.py will run with /usr/bin/python3. Run 'source bootstrap.sh' first so that the flow uses the pinned environment
```

and carries on with that interpreter. It is only a warning: the generated files
are normally identical, but the flow is then not using the pinned environment.
The check only runs for `make regen_regs` (not for the simulation targets, which
do not use Python). To make it fatal, change `$(warning …)` into `$(error …)` in
the `Makefile`.

## Simulation

The simulation flow (`make tmu-build`, `make tmu-sim`, defined in `axi_tmu.mk`)
is **not covered by `bootstrap.sh` yet** and is going to be reworked. Known
points to keep in mind until then:

- The testbench is chosen with `TBENCH`: `tb_axi_tmu_ilt` (default, in
  `test/tb_axi_tmu_ilt.sv`) runs the top in `ILT_MODE`, `tb_axi_tmu_clt` (in
  `test/tb_axi_tmu_clt.sv`) runs it in `CLT_MODE`. For example:
  `make -B tmu-build tmu-sim QUESTA= TBENCH=tb_axi_tmu_clt`. The name of the
  testbench is written in the generated `target/sim/vsim/compile.tmu.tcl`, which
  `make` only regenerates when `Bender.yml` changes: use `-B` on `tmu-build`
  every time `TBENCH` changes.
- `axi_tmu.mk` defaults to `QUESTA ?= questa-2023.4`, a wrapper command that does
  not exist on every machine. With the module loaded by `bootstrap.sh`, `vsim` is
  already in `PATH`, so pass an empty value: `make tmu-build QUESTA=`.
- `make tmu-sim` always exits with status 0. Check the log for `# Errors: 0` and
  for the absence of `** Error` / `Fatal` lines.

## Troubleshooting

| Message / symptom | Cause and fix |
|---|---|
| `bootstrap.sh must be sourced, not executed` | Use `source bootstrap.sh` (or `. bootstrap.sh`). |
| `Bender.lock is missing` | `git checkout -- Bender.lock`, then source again. |
| `cannot load module …` | The module does not exist on this machine. Check `module avail bender questa`, then set `BENDER_MODULE` / `QUESTA_MODULE`. |
| `no Python >= 3.8 found` | Install or load one and set `PYTHON=/path/to/python3.x`. |
| `The project Python environment (.venv) is NOT active` (from `make regen_regs`) | The shell did not source `bootstrap.sh`, or another venv is active. Run `source bootstrap.sh` and repeat. |
| `pip failed` | PyPI is not reachable. Behind a mirror/proxy set `PIP_INDEX_URL` (or the usual pip variables) before sourcing. |
| Something looks stale | `rm -rf .venv` and/or `rm -rf .bender`, then source `bootstrap.sh` again. |
