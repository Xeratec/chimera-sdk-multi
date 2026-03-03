# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Heterogeneous multi-binary compilation example for RISC-V systems with different ISAs.
One **host** core (CVA6, RV64IMC) and one or more **device** cores (Snitch cluster, RV32IMAFD)
each get their own ELF binary. Communication happens through a shared `.common` section
placed at a known physical address.

Optionally, all per-core ELFs can be merged into a single **unified ELF** (host base with
device LOAD segments embedded as read-only data) for single-invocation simulator loading.

## Repository Structure

```
chimera-sdk-multi/
├── cmake/
│   ├── Chimera.cmake              # add_device_binary() / add_host_binary() functions
│   ├── toolchain_llvm.cmake       # LLVM/Clang cross-compile toolchain
│   └── scripts/
│       ├── ChimeraBuildHelpers.cmake  # symbol extraction + placement (build-time)
│       ├── CheckSectionOverlaps.cmake # (legacy CMake version, superseded by Python)
│       └── PrintBuildFooter.cmake     # build summary printed after every build
├── common/
│   ├── common.ldh                 # shared linker header (common section layout)
│   └── shared.h                   # shared data struct + extern declarations
├── devices/
│   └── snitch_cluster_{0,1}/
│       ├── CMakeLists.txt
│       ├── crt0.S                 # minimal startup for Snitch (RV32)
│       ├── link.ld.in             # linker script template
│       └── main.c
├── host/
│   ├── CMakeLists.txt
│   ├── crt0.S                     # CVA6 startup (RV64)
│   ├── link.ld.in                 # linker script template
│   └── main.c
├── scripts/                       # Python post-build tools (managed via uv)
│   ├── check_section_overlaps.py  # memory-map printer + VMA overlap detector
│   └── merge_elf.py               # unified mixed-ISA ELF generator (uses lief)
├── build.sh                       # convenience build script
├── CMakeLists.txt                 # root CMake (options, uv bootstrap, subdirs)
├── config.cmake                   # ISA/ABI/compiler settings per core
├── pyproject.toml                 # Python project (uv manages .venv)
└── uv.lock                        # locked dependency versions
```

## Build Commands

### Standard build (inside Docker)

```sh
docker exec chimera bash -c "
   cd /app/chimera/chimera-sdk-multi &&
   export TOOLCHAIN_DIR=/app/install/llvm-18.1.4-pulp &&
   rm -rf build &&
   ./build.sh
"
```

### With unified mixed-ISA ELF generation

```sh
docker exec  bash -c "
   cd /app/chimera/chimera-sdk-multi &&
   export TOOLCHAIN_DIR=/app/install/llvm-18.1.4-pulp &&
   rm -rf build &&
   ./build.sh --unified-elf
"
```

This produces `build/chimera_unified.elf`: the host ELF (ELFCLASS64, RV64) with all
device LOAD segments embedded as read-only (non-executable) PT_LOAD entries.

### CMake option directly

```sh
cmake -D TOOLCHAIN_DIR=... -D CHIMERA_UNIFIED_ELF=ON -B build
cmake --build build -j$(nproc)
```

## Python Tooling (uv)

Python dependencies are declared in `pyproject.toml` and locked in `uv.lock`.
`uv sync` runs automatically during `cmake` configure to bootstrap the `.venv`.

| Package | Purpose |
|---------|---------|
| `lief >= 0.14` | ELF read/modify/write for `merge_elf.py` |

To run scripts manually:
```sh
# Overlap check
uv run python scripts/check_section_overlaps.py \
    --binary build/devices/snitch_cluster_0/snitch_cluster_0.sections \
    --binary build/devices/snitch_cluster_1/snitch_cluster_1.sections \
    --binary build/host/host.sections

# ELF merge
uv run python scripts/merge_elf.py \
    --host   build/host/host.elf \
    --device build/devices/snitch_cluster_0/snitch_cluster_0.elf \
    --device build/devices/snitch_cluster_1/snitch_cluster_1.elf \
    --output build/chimera_unified.elf
```

## CMake Build Flow

```
configure time:
  uv sync  →  .venv with lief installed

build time (per device):
  compile → link → objdump -h → .sections
                 → nm         → _symbols.s + _symbols.h
                 → nm         → _placement.ldh

build time (host, after all devices):
  compile + link (with device symbol stubs)
  → objdump -h → .sections

post-build:
  chimera_check_overlaps   ← Python: check_section_overlaps.py
  chimera_merge_elf        ← Python: merge_elf.py  (only if CHIMERA_UNIFIED_ELF=ON)
  chimera_footer           ← CMake:  PrintBuildFooter.cmake
```

## Key Design Decisions

### Shared `.common` section
All shared data lives in a struct in `.common`, placed at a known fixed address.
Only the host linker script loads it (`LOAD`); device scripts mark it `NOLOAD`.
This ensures identical layout and avoids double-loading.

### Symbol extraction
After compiling each device, `llvm-nm` extracts public symbols.
They are written as `.set SYMBOL, 0xADDR` absolute-address stubs, assembled with
the host toolchain, and linked into the host binary so host C code can reference
device symbols by name.

### Unified ELF (mixed-ISA)
A single ELF cannot contain two ISA machine types. The merge strategy:
- Use the host ELF (ELFCLASS64, `EM_RISCV`, RV64) as the base.
- Embed each device's LOAD segments as new `PT_LOAD` segments with flags `R` only
  (execute bit stripped), so the host ISA cannot accidentally run device code.
- Device VMAs (32-bit) fit naturally into 64-bit ELF address fields.
- Heterogeneous simulators identify which core runs which region by hardware
  configuration, not by ELF flags.

### Overlap checking
`check_section_overlaps.py` parses `llvm-objdump -h` section headers (which include
a `Type` column: `TEXT`/`DATA`/`BSS`) and detects VMA range intersections between
`TEXT`/`DATA` sections of *different* binaries. `BSS`/`NOLOAD` sections (the shared
`.common`) are displayed but excluded from the check.
