# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this
repository.

## Project Overview

`chimera-sdk-multi` is a **minimal reference implementation** of the heterogeneous multi-binary
compilation flow for the Chimera SoC.  It demonstrates compiling one host binary (CVA6,
RV64IMC) and two device binaries (Snitch clusters, RV32) into separate ELFs that share a
common memory region at a known physical address.

Deliberately kept simple: no runtime libraries, no picolibc, no device drivers.  Read this
codebase to understand the CMake pipeline before working on the full `chimera-sdk`.

## Repository Structure

```
chimera-sdk-multi/
├── cmake/
│   ├── Chimera.cmake              # add_device_binary() / add_host_binary() functions
│   ├── toolchain_llvm.cmake       # LLVM/Clang cross-compile toolchain
│   └── scripts/
│       ├── ChimeraBuildHelpers.cmake  # symbol extraction + placement (build-time)
│       └── PrintBuildFooter.cmake     # build summary printed after every build
├── common/
│   ├── common.ldh                 # MEMORY block shared by all linker scripts
│   ├── shared.h                   # chimera_shared_data_t struct + extern shared_data
│   ├── soc_addr_map.h             # SoC base addresses, hart layout constants
│   └── soc_regs.h                 # SoC register offsets
├── devices/
│   ├── snitch_cluster_0/          # Device 0: rv32imafd / ilp32d
│   │   ├── CMakeLists.txt
│   │   ├── crt0.S                 # minimal RV32 startup
│   │   ├── link.ld.in             # linker script template (first in placement chain)
│   │   └── main.c                 # trampoline, interrupt handler, task (writes 42)
│   └── snitch_cluster_1/          # Device 1: rv32ima / ilp32  ← different ISA (no FP)
│       ├── CMakeLists.txt
│       ├── crt0.S
│       ├── link.ld.in             # INCLUDEs snitch_cluster_0_placement.ldh
│       └── main.c
├── host/
│   ├── CMakeLists.txt             # add_host_binary(host … LAST_DEVICE snitch_cluster_1)
│   ├── crt0.S                     # CVA6 startup (RV64)
│   ├── link.ld.in                 # INCLUDEs snitch_cluster_1_placement.ldh
│   └── main.c                     # cluster reset, offload, result check → return 0 if 42
├── scripts/
│   ├── check_section_overlaps.py  # memory-map printer + VMA overlap detector
│   └── merge_elf.py               # mixed-ISA ELF generator (lief)
├── build.sh                       # convenience wrapper around cmake configure + build
├── CMakeLists.txt                 # root: uv bootstrap, subdirs, CHIMERA_UNIFIED_ELF option
├── config.cmake                   # ISA/ABI/compiler variables for each core
└── pyproject.toml                 # Python deps (lief for merge_elf.py)
```

## Build Commands

### Quick start

```bash
export TOOLCHAIN_DIR=/path/to/llvm
./build.sh                     # device + host ELFs
./build.sh --unified-elf       # + merged chimera_unified.elf
./build.sh -v                  # verbose output
```

### Manual CMake

```bash
cmake -D TOOLCHAIN_DIR=$TOOLCHAIN_DIR [-D CHIMERA_UNIFIED_ELF=ON] -B build
cmake --build build -j$(nproc)
```

### Inside Docker

```bash
docker exec chimera bash -c "
    cd /app/chimera/chimera-sdk-multi &&
    export TOOLCHAIN_DIR=/app/install/llvm-18.1.4-pulp &&
    ./build.sh --unified-elf
"
```

## ISA / ABI Configuration

Defined in `config.cmake`:

| Core | Variable | ISA | ABI |
|---|---|---|---|
| Host (CVA6) | `ISA_HOST` | `rv64imafdc_zifencei` | `lp64d` |
| Device 0 (Snitch cluster 0) | `ISA_DEVICE_SNITCH_CLUSTER_0` | `rv32imafd` | `ilp32d` |
| Device 1 (Snitch cluster 1) | `ISA_DEVICE_SNITCH_CLUSTER_1` | `rv32ima` | `ilp32` |

Device 1 intentionally lacks the F/D extensions to show that each device can have a
completely independent ISA — even from other devices.

## CMake Build Pipeline

### Configure time

```
uv sync  →  .venv with lief installed
```

CMake reads `config.cmake`, processes subdirectories in placement-chain order:
1. `devices/snitch_cluster_0/`
2. `devices/snitch_cluster_1/`
3. `host/`

### Build time (per device, via `add_device_binary`)

```
compile sources → link ELF
               → objdump -h  → .sections  (overlap checker input)
               → objdump -S  → .dump      (disassembly)
               → nm          → _symbols.s + _symbols.h  (host stubs)
               → nm          → _placement.ldh           (end-address for next binary)
```

### Build time (host, via `add_host_binary`)

```
compile sources + link with device symbol stubs
→ objdump -h → .sections
post-build:
  chimera_check_overlaps  ← scripts/check_section_overlaps.py
  chimera_merge_elf       ← scripts/merge_elf.py  (CHIMERA_UNIFIED_ELF=ON only)
  chimera_footer          ← cmake/scripts/PrintBuildFooter.cmake
```

## CMake API (this project)

`cmake/Chimera.cmake` defines two functions.  Note: this project's API uses a `LINKER_SCRIPT`
argument (pointing directly to the template file) rather than `DEVICE_DIR` as in `chimera-sdk`.

### `add_device_binary(TARGET_NAME …)`

```cmake
add_device_binary(snitch_cluster_0
    ISA          ${ISA_DEVICE_SNITCH_CLUSTER_0}
    ABI          ${ABI_DEVICE_SNITCH_CLUSTER_0}
    COMPILER     ${CROSS_COMPILE_DEVICE_SNITCH_CLUSTER_0}
    COMPIERT_RT  ${COMPILER_RT_DEVICE_SNITCH_CLUSTER_0}
    LINKER_SCRIPT ${CMAKE_CURRENT_SOURCE_DIR}/link.ld.in
    SOURCES       crt0.S main.c
)
```

Outputs (in `build/devices/<TARGET_NAME>/`):
- `<TARGET_NAME>.elf` — device binary
- `<TARGET_NAME>_symbols.s` / `<TARGET_NAME>_symbols.h` — host stubs
- `<TARGET_NAME>_placement.ldh` — 4 KiB-aligned end address
- `<TARGET_NAME>_symbols` — CMake INTERFACE library for the host to link

Symbol prefix: the `TARGET_NAME` itself (e.g. `snitch_cluster_0_main`,
`snitch_cluster_0__trampoline`).

### `add_host_binary(TARGET_NAME …)`

```cmake
add_host_binary(host
    ISA          ${ISA_HOST}
    ABI          ${ABI_HOST}
    COMPILER     ${CROSS_COMPILE_HOST}
    COMPIERT_RT  ${COMPILER_RT_HOST}
    LINKER_SCRIPT ${HOST_LINKER_SCRIPT}
    SOURCES       crt0.S main.c
    DEVICE_DEPS    snitch_cluster_0 snitch_cluster_1
    DEVICE_SYMBOLS snitch_cluster_0_symbols snitch_cluster_1_symbols
    LAST_DEVICE    snitch_cluster_1
)
```

`LAST_DEVICE snitch_cluster_1` causes the host linker script to INCLUDE
`snitch_cluster_1_placement.ldh`, placing host `.text` immediately after Device 1.

## Key Design Points

### Shared `.common` section

`chimera_shared_data_t` (defined in `common/shared.h`) is the sole communication channel
between host and devices.  Both the host and each device define a `shared_data` instance in
`__attribute__((section(".common")))`.

- **Host** linker script: `.common` is loaded at `0x48000000` (normal `PT_LOAD` segment).
- **Device** linker scripts: `.common` is `NOLOAD` at `0x48000000` (no bytes emitted; the
  device accesses the host's copy over AXI).

Because all binaries compile the same `shared.h`, all `offsetof()` values are identical
across ISAs — the trampoline uses this to access struct fields before the global pointer is
set up.

### Symbol extraction and naming

`ChimeraBuildHelpers.cmake` (mode `symbols`) runs `llvm-nm --defined-only --extern-only` on
the device ELF and emits `.set TARGET_SYMBOL, 0xADDR` stubs for every public TEXT/DATA/BSS/
RODATA symbol whose name does not start with `__`.  These are assembled with the **host**
toolchain and linked into the host binary.

Symbols starting with `__` are skipped — they are linker-internal bookkeeping
(`__bss_start`, `__device_end`, `__global_pointer$`).

### Placement chain

```
snitch_cluster_0 → snitch_cluster_0_placement.ldh
  → snitch_cluster_1 (INCLUDEs ldh, adds .reserved skip)
      → snitch_cluster_1_placement.ldh
          → host (INCLUDEs ldh, adds .reserved skip)
```

Each `.ldh` file contains one line:
```
__<TARGET_NAME>_end = 0x<aligned_addr>;
```

### Trampoline (in `devices/snitch_cluster_0/main.c`)

The `_trampoline()` function is `__attribute__((naked))`.  It:
1. Sets up the global pointer (`_SETUP_GP` macro).
2. Computes `idx = (mhartid - CLUSTER_HART_BASE) * 4`.
3. Loads `sp` from `shared_data.trampoline_stack[idx]`.
4. Allocates TLS (`.tdata` + `.tbss`) on the new stack and sets `tp`.
5. Loads `fn` from `shared_data.trampoline_function[idx]`.
6. Loads `arg` from `shared_data.trampoline_args[idx]`.
7. Tail-calls `fn(arg)`.

All field accesses use `offsetof()` constants — no GP-relative addressing required before
step 1.

### Unified ELF (mixed-ISA)

`scripts/merge_elf.py` uses `lief` to:
- Use the host ELF (ELFCLASS64, `EM_RISCV`) as the base.
- Insert each device's `PT_LOAD` segments with flags `R` only (execute bit stripped).
- Write `build/chimera_unified.elf`.

Device VMAs (32-bit) fit naturally into 64-bit ELF address fields.  The simulator identifies
which core runs which region by hardware configuration, not ELF flags.

### Overlap checking

`scripts/check_section_overlaps.py` parses `llvm-objdump -h` output (which includes a `Type`
column: `TEXT`/`DATA`/`BSS`) and reports VMA range intersections between `TEXT`/`DATA`
sections across different binaries.  `BSS`/`NOLOAD` sections (`.common`) are displayed but
excluded from the overlap check.

## Python Tooling

Dependencies are declared in `pyproject.toml` and locked in `uv.lock`.  `uv sync` runs
automatically at CMake configure time to bootstrap `.venv`.

| Package | Purpose |
|---|---|
| `lief ≥ 0.14` | ELF read/modify/write for `merge_elf.py` |

Run scripts manually:

```bash
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

## Relation to chimera-sdk

| | chimera-sdk-multi | chimera-sdk |
|---|---|---|
| Purpose | Minimal reference / learning aid | Full production SDK |
| Runtime | None (bare `crt0.S`) | `runtime_host`, `runtime_cluster_snitch` |
| C library | None | picolibc (prebuilt per-ISA) |
| Drivers / HAL | None | Full driver stack |
| Symbol prefix | `TARGET_NAME` (implicit) | Explicit `DEVICE_NAME` argument |
| Linker script arg | `LINKER_SCRIPT <path>` | `DEVICE_DIR <dir>` (template inside) |
| Target selection | Hardcoded in `config.cmake` | `TARGET_PLATFORM=<target>` CMake option |

The three-stage pipeline, `.common` section design, placement chain mechanism, and
`ChimeraBuildHelpers.cmake` logic are identical between the two projects.
