# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a heterogeneous multi-binary compilation example demonstrating how to compile separate binaries for different RISC-V cores (host and devices) with different ISAs that communicate through shared memory. The host is CVA6 (RV64IMC) and devices are Snitch clusters (RV32IMAFD).

## Build Commands

### Prerequisites
Set the LLVM toolchain path:
```bash
export TOOLCHAIN_DIR=/path/to/llvm
```

### Building
```bash
# Quick build using convenience script
./build.sh

# Manual build
cmake -D TOOLCHAIN_DIR="$TOOLCHAIN_DIR" -B build
cmake --build build -j $(nproc)

# Build specific targets
cmake --build build --target snitch_cluster_device  # Device binary first
cmake --build build --target chimera_host           # Host binary (depends on device)
```

### Build Outputs
All outputs are in `build/`:
- `devices/snitch_cluster/snitch_cluster_device.{elf,bin,dump}` - Device binary
- `devices/snitch_cluster/snitch_cluster_device_symbols.txt` - Extracted symbols (filtered)
- `devices/snitch_cluster/snitch_cluster_device_symbols.h` - Generated header with symbol declarations
- `devices/snitch_cluster/snitch_cluster_device_binary.o` - Embedded device binary object
- `host/chimera_host.{elf,bin,dump}` - Host binary (with embedded device binary)

## Architecture: Multi-Binary Compilation Flow

### Key Concept: Separate Binaries for Different ISAs
Unlike traditional single-binary compilation, this project compiles **separate binaries** for each processing unit:

1. **Device Binary** (RV32IMAFD, ilp32d ABI):
   - Compiled first with `-fPIC` (position-independent code)
   - Uses `add_device_binary()` CMake function
   - Symbols extracted automatically for host reference
   - Linker script marks `.common` section as `NOLOAD`

2. **Host Binary** (RV64IMC, lp64 ABI):
   - Compiled second, depends on device binary
   - Uses `add_host_binary()` CMake function
   - Can reference device binary symbols
   - Linker script loads `.common` section

### Shared Memory Communication

**Critical Pattern**: Host and devices communicate through a shared memory region at `0x90000000`.

**The NOLOAD Pattern**:
- Host linker script **loads** the `.common` section (initializes data)
- Device linker scripts mark `.common` as **NOLOAD** (reference only)
- This ensures data is stored only once in memory but accessible by both

**Shared Data Structure**:
```c
// In common/shared.h - always pack shared data into structs
typedef struct {
    uint32_t host_to_device_flag;
    uint32_t device_to_host_flag;
    uint32_t data_payload[16];
} chimera_shared_data_t;

// Define in host code (loaded into .common section)
chimera_shared_data_t shared_data __attribute__((section(".common"))) = {0};

// Reference in device code (NOLOAD - just references the same memory)
extern chimera_shared_data_t shared_data;
```

## Configuration System

### config.cmake - ISA/ABI Configuration
This file defines all architecture-specific settings. Modify this to change ISAs:

```cmake
# Host configuration
set(ABI_HOST lp64)           # ABI for RV64
set(ISA_HOST rv64imc)        # ISA extensions
set(COMPILERRT_HOST rv64imc) # Must match compiler-rt library available

# Device configuration
set(ABI_DEVICE ilp32d)        # ABI for RV32 with double-precision float
set(ISA_DEVICE rv32imafd)     # ISA extensions
set(COMPILERRT_DEVICE rv32imafd) # Must match compiler-rt library available
```

### cmake/toolchain_llvm.cmake
Reused from main `chimera-sdk`. Sets up LLVM/Clang toolchain:
- Uses LLD linker (`-fuse-ld=lld`)
- Links against compiler-rt builtins (not libgcc)
- Provides `CMAKE_OBJCOPY`, `CMAKE_OBJDUMP`, `CMAKE_NM` variables

### cmake/ChimeraUtils.cmake - Build Helper Functions

**`add_device_binary(TARGET_NAME LINKER_SCRIPT linker.ld SOURCES ...)`**:
- Compiles device binary with PIC
- Generates `.bin` and `.dump` files
- Automatically extracts symbols to `${TARGET_NAME}_symbols.txt` (filtered, no `__*` symbols)
- Generates `${TARGET_NAME}_symbols.h` header file with extern declarations
- Creates `${TARGET_NAME}_symbols` interface library for linking with host
- Embeds device binary into `${TARGET_NAME}_binary.o` object file
- Uses ISA_DEVICE, ABI_DEVICE from config.cmake

**`add_host_binary(TARGET_NAME LINKER_SCRIPT linker.ld SOURCES ... DEVICE_DEPS device_target DEVICE_SYMBOLS device_symbols_lib)`**:
- Compiles host binary
- Links with device symbol libraries (embeds device binaries)
- Ensures device dependencies are built first
- Uses ISA_HOST, ABI_HOST from config.cmake
- Generates `.bin` and `.dump` files
- Host can include `${device}_symbols.h` to access device symbols

## Memory Layout

### Host Memory Regions
- `0x48000000` (256KB) - MEMISL: Host code and data
- `0x80000000` (8MB) - DRAM: Large storage, embedded device binaries
- `0x90000000` (64KB) - Common: Shared communication (loaded by host)

### Device Memory Regions
- `0x10000000` (128KB) - L1 TCDM: Device code and data
- `0x90000000` (64KB) - Common: Shared communication (NOLOAD reference)

Memory regions are defined in:
- `common/common.ldh` - Common definitions for shared section
- `host/link.ld` - Host-specific memory layout
- `devices/snitch_cluster/link.ld` - Device-specific memory layout

## Adding New Devices

1. Create `devices/new_device/` directory with:
   - `crt0.S` - Device startup code
   - `link.ld` - Linker script with NOLOAD for `.common` section
   - `main.c` - Device main function
   - `CMakeLists.txt` - Build configuration

2. In `devices/new_device/CMakeLists.txt`:
   ```cmake
   add_device_binary(new_device
       LINKER_SCRIPT ${CMAKE_CURRENT_SOURCE_DIR}/link.ld
       SOURCES crt0.S main.c
   )
   ```

3. Update `config.cmake` if device uses different ISA/ABI

4. Add to root `CMakeLists.txt`:
   ```cmake
   add_subdirectory(devices/new_device)
   ```

5. Update host to reference device binary symbols if needed

## Adding Shared Functions/Data

### For Shared Data
1. Add to `common/shared.h` as part of shared struct
2. Pack into struct to maintain alignment across ISAs
3. Use `__attribute__((section(".common")))` in host code
4. Use `extern` reference in device code

### For Function Offloading
1. Implement function in device source file
2. The function will automatically be exported in the generated `${device}_symbols.h` header
3. In host code, include the generated header:
   ```c
   #include "snitch_cluster_device_symbols.h"
   ```
4. Host can reference device functions (note: these are symbols for inspection, not directly callable):
   ```c
   void* func_ptr = (void*)device_function;  // Get function address in device binary
   ```

## Important Constraints

### LLVM Toolchain Requirements
- LLVM version 12+ required, 16+ recommended (linker relaxation support)
- Must have RISC-V targets enabled
- Compiler-rt libraries must be available for both RV32 and RV64
- `TOOLCHAIN_DIR` must point to LLVM installation root

### Compilation Order
Device binaries **must** be built before host binary. CMake enforces this through `add_dependencies()`.

### Linker Script Rules
- Host linker script includes `.common` section normally (loads data)
- Device linker scripts mark `.common` as `NOLOAD` (references only)
- Both must use identical memory address for `.common` section

### Symbol Extraction and Linking
- Symbols are automatically extracted from device `.elf` files (not `.bin`)
- Linker-generated symbols (prefixed with `__`) are filtered out
- A header file `${device}_symbols.h` is auto-generated with extern declarations
- The device binary is embedded into the host via an object file
- Host includes the generated header to access device symbols:
  - `${device}_binary_start`, `${device}_binary_end`, `${device}_binary_size` for the embedded binary
  - All device functions and global variables for reference/inspection

## Toolchain Flags Explained

### Device Compilation Flags
- `--target=riscv32-unknown-elf` - Cross-compile to RV32
- `-march=${ISA_DEVICE} -mabi=${ABI_DEVICE}` - Architecture from config
- `-fPIC` - Position-independent code for flexibility
- `-nostartfiles -nostdlib` - Bare metal (no C runtime)
- `-rtlib=compiler-rt` - Use LLVM runtime, not libgcc
- `-lclang_rt.builtins-riscv32` - Link compiler builtins

### Host Compilation Flags
- `--target=riscv64-unknown-elf` - Cross-compile to RV64
- `-march=${ISA_HOST} -mabi=${ABI_HOST}` - Architecture from config
- `-mcmodel=medany` - Medium addressing for 64-bit
- `-nostartfiles` - Bare metal, custom startup code
- `-rtlib=compiler-rt` - Use LLVM runtime
- `-lclang_rt.builtins-riscv64` - Link compiler builtins

## Common Issues

### Build Fails: "TOOLCHAIN_DIR not set"
Set environment variable: `export TOOLCHAIN_DIR=/path/to/llvm`

### Build Fails: "cannot find -lclang_rt.builtins-riscvXX"
Check that compiler-rt libraries exist at:
`$TOOLCHAIN_DIR/lib/clang/${LLVM_VERSION_MAJOR}/lib/baremetal/${COMPILERRT_HOST or COMPILERRT_DEVICE}/`

### Linker Error: "multiple definition of symbol in .common"
Ensure device linker script uses `(NOLOAD)` for `.common` section.

### Symbol Not Found in Host Binary
Make sure you:
1. Added the device symbol library to `DEVICE_SYMBOLS` parameter in `add_host_binary()`
2. Included the generated header in your host code: `#include "${device}_symbols.h"`
3. The generated header is in the build directory, so it's automatically in the include path

### Generated Header File Location
The `${device}_symbols.h` file is generated in the device's build directory (e.g., `build/devices/snitch_cluster/`). The build system automatically adds this to the host's include path when you link against the device symbol library.
