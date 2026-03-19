# chimera-sdk-multi

<!-- SPDX-FileCopyrightText: 2025 ETH Zurich and University of Bologna -->
<!-- SPDX-License-Identifier: CC-BY-ND-4.0 -->

A minimal, self-contained reference implementation of the **heterogeneous multi-binary
compilation flow** for [Chimera](https://github.com/pulp-platform/chimera) — a
multi-cluster RISC-V SoC with a CVA6 host core and multiple Snitch accelerator clusters.

The project exists as a learning aid and clean-room baseline.  It has no runtime libraries,
no picolibc, and no device drivers — just two `main()` functions, the full three-stage CMake
pipeline, and the shared communication struct.  Read this before diving into the full
[chimera-sdk](https://github.com/pulp-platform/chimera-sdk).

---

## What This Example Demonstrates

| Concern | How it is shown here |
|---|---|
| **ISA separation** | Host: `rv64imafdc` (CVA6). Device 0: `rv32imafd`. Device 1: `rv32ima` (no FP) — two devices with different ISAs |
| **Separate ELFs** | Each domain gets its own ELF, linked at non-overlapping addresses in `memisl` |
| **Symbol extraction** | `llvm-nm` reads each device ELF; CMake emits `.set` stubs assembled with the host toolchain so host C code can call device functions by name |
| **Placement chain** | Device 0 → `snitch_cluster_0_placement.ldh` → Device 1 → `snitch_cluster_1_placement.ldh` → Host |
| **Shared `.common`** | `chimera_shared_data_t` struct at `0x48000000`; host loads it, devices access it `NOLOAD` over AXI |
| **End-to-end offload** | Host resets cluster 0, sets trampoline, sends interrupt → device writes `42` into `shared_data` → host checks result and returns `0` |
| **Unified ELF** | Optional: all ELFs merged into one mixed-ISA file for single-invocation simulation |

---

## Repository Structure

```
chimera-sdk-multi/
├── cmake/
│   ├── Chimera.cmake              # add_device_binary() / add_host_binary()
│   ├── toolchain_llvm.cmake       # LLVM/Clang cross-compile toolchain
│   └── scripts/
│       ├── ChimeraBuildHelpers.cmake  # symbol extraction + placement (build-time)
│       └── PrintBuildFooter.cmake     # build summary printed after every build
├── common/
│   ├── common.ldh                 # shared MEMORY block (memisl at 0x48000000)
│   ├── shared.h                   # chimera_shared_data_t + extern declaration
│   ├── soc_addr_map.h             # SoC base addresses and hart layout
│   └── soc_regs.h                 # SoC register offsets
├── devices/
│   ├── snitch_cluster_0/          # Device 0: rv32imafd / ilp32d
│   │   ├── CMakeLists.txt         # calls add_device_binary(snitch_cluster_0 …)
│   │   ├── crt0.S                 # minimal startup (RV32)
│   │   ├── link.ld.in             # linker script template
│   │   └── main.c                 # trampoline, interrupt handler, task
│   └── snitch_cluster_1/          # Device 1: rv32ima / ilp32  (no FP extensions)
│       ├── CMakeLists.txt
│       ├── crt0.S
│       ├── link.ld.in
│       └── main.c
├── host/
│   ├── CMakeLists.txt             # calls add_host_binary(host … LAST_DEVICE snitch_cluster_1)
│   ├── crt0.S                     # CVA6 startup (RV64)
│   ├── link.ld.in                 # linker script template
│   └── main.c                     # cluster reset, offload, result check
├── scripts/
│   ├── check_section_overlaps.py  # memory-map printer + VMA overlap detector
│   └── merge_elf.py               # mixed-ISA ELF generator (uses lief)
├── build.sh                       # convenience build script
├── CMakeLists.txt                 # root CMake (uv bootstrap, subdirs, options)
├── config.cmake                   # ISA/ABI/compiler settings per core
└── pyproject.toml                 # Python dependencies (uv + lief)
```

---

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| CMake | ≥ 3.19 | |
| LLVM/Clang (RISC-V) | ≥ 18 | PULP-flavoured builds include `rv32ima_xdma` support |
| `uv` | any | Python package manager — auto-installed by `build.sh` if missing |
| `lief` | ≥ 0.14 | Required only for `--unified-elf`; managed via `uv` |

Set `TOOLCHAIN_DIR` to the root of your LLVM installation before building:

```bash
export TOOLCHAIN_DIR=/path/to/llvm
```

---

## Building

### Quick start

```bash
export TOOLCHAIN_DIR=/path/to/llvm
./build.sh
```

### With unified mixed-ISA ELF

```bash
./build.sh --unified-elf
```

Produces `build/chimera_unified.elf`: the host ELF (ELFCLASS64, RV64) with all device LOAD
segments embedded as read-only `PT_LOAD` entries.  Heterogeneous simulators use this single
file to load all domains.

### Manual CMake invocation

```bash
cmake -D TOOLCHAIN_DIR=$TOOLCHAIN_DIR \
      [-D CHIMERA_UNIFIED_ELF=ON] \
      -B build
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

---

## Build Outputs

After a successful build, `build/` contains:

```
build/
├── devices/
│   ├── snitch_cluster_0/
│   │   ├── snitch_cluster_0.elf         # Device 0 binary (rv32imafd)
│   │   ├── snitch_cluster_0.dump        # disassembly
│   │   ├── snitch_cluster_0.sections    # section headers (for overlap checker)
│   │   ├── snitch_cluster_0.symbols     # full symbol table
│   │   ├── snitch_cluster_0_symbols.s   # host-linkable address stubs
│   │   ├── snitch_cluster_0_symbols.h   # extern declarations for host C code
│   │   └── snitch_cluster_0_placement.ldh  # 4 KiB-aligned end address
│   └── snitch_cluster_1/
│       └── … (same structure)
├── host/
│   ├── host.elf                         # Host binary (rv64imafdc)
│   ├── host.dump
│   └── host.sections
└── chimera_unified.elf                  # merged ELF (--unified-elf only)
```

---

## The Compilation Flow

### Stage 1 — Compile each device binary

Device 0 (`rv32imafd`) and Device 1 (`rv32ima`) are compiled independently with their own
ISA and linker script.  Device 0 is placed first in `memisl`; Device 1 follows immediately
after, using Device 0's `_placement.ldh` to skip its memory region.

### Stage 2 — Extract public symbols

`llvm-nm` reads each device ELF.  `cmake/scripts/ChimeraBuildHelpers.cmake` writes:

- `_symbols.s` — one `.set SYMBOL, 0xADDR` line per public symbol, prefixed with the target
  name (e.g. `snitch_cluster_0_main`, `snitch_cluster_0__trampoline`)
- `_symbols.h` — matching `extern char SYMBOL[];` declarations
- `_placement.ldh` — 4 KiB-aligned end address for the next binary in the chain

### Stage 3 — Compile the host binary

The host (`rv64imafdc`) is compiled after both devices.  It links against the symbol stubs so
host C code can call `snitch_cluster_0_main` or reference `snitch_cluster_0__trampoline` at
their exact run-time addresses.  The host linker script INCLUDEs
`snitch_cluster_1_placement.ldh` (via `LAST_DEVICE snitch_cluster_1`) so host `.text` starts
immediately after Device 1.

### Memory layout

```
memisl (0x48000000, 256 KiB):
  0x48000000  ┌─────────────────────┐
              │  .common (64-byte)  │  chimera_shared_data_t
              ├─────────────────────┤
              │  snitch_cluster_0   │  rv32imafd
              ├─────────────────────┤  ← snitch_cluster_0_placement.ldh
              │  snitch_cluster_1   │  rv32ima
              ├─────────────────────┤  ← snitch_cluster_1_placement.ldh
              │  host .text / .misc │  rv64imafdc
              ├─────────────────────┤
              │  host stack (↓)     │
  0x48040000  └─────────────────────┘
```

---

## What the Example Actually Does

The host `main()` in `host/main.c`:

1. Writes the address of `snitch_cluster_0__trampoline` to the cluster boot address register.
2. Fills `shared_data.trampoline_function[0]` with `snitch_cluster_0_main` and
   `shared_data.trampoline_stack[0]` with a stack address in cluster-local TCDM.
3. De-asserts cluster reset → cluster boots into the trampoline.
4. Sends a software interrupt via CLINT.
5. Sets `shared_data.host_to_device_flag[0] = 1` to signal the device.
6. Spins on `shared_data.device_to_host_flag[0]`.
7. Returns `0` if `shared_data.data_payload[0][0] == 42`, non-zero otherwise.

The device `main()` in `devices/snitch_cluster_0/main.c`:

1. Spins on `shared_data.host_to_device_flag[0]`.
2. Writes `42` into `shared_data.data_payload[0][0]`.
3. Sets `shared_data.device_to_host_flag[0] = 1`.
4. Returns `0`.

---

## Relation to chimera-sdk

This project implements the same CMake API (`add_device_binary` / `add_host_binary`) and the
same three-stage pipeline as the full `chimera-sdk`, but without any runtime libraries,
drivers, or picolibc.  Differences from `chimera-sdk`:

| | chimera-sdk-multi | chimera-sdk |
|---|---|---|
| Runtime | none (bare `crt0.S`) | `runtime_host`, `runtime_cluster_snitch` |
| C library | none | picolibc |
| `DEVICE_NAME` param | uses target name as prefix | explicit `DEVICE_NAME` argument |
| Linker script arg | `LINKER_SCRIPT` | `DEVICE_DIR` (template in subdir) |
| Targets | self-contained | platform-selectable via `TARGET_PLATFORM` |

---

## License

All licenses are listed under the `LICENSES/` folder.

- Software sources and build scripts: [Apache 2.0](https://opensource.org/licenses/Apache-2.0)
- Some hardware-description files: [Solderpad v0.51](https://solderpad.org/licenses/SHL-0.51/)
- Documentation (Markdown, text): [CC BY-ND 4.0](https://creativecommons.org/licenses/by-nd/4.0/)

Run `reuse spdx` in the repository root to extract per-file license information.
