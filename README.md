# Chimera SDK Multi-Binary Compilation Example

This project demonstrates a heterogeneous multi-cluster compilation flow using CMake. The system consists of one host core (CVA6 with RV64IMC) and device cores (Snitch cluster with RV32IMAFD), each compiled into separate binaries.

## Features

- **Multi-binary compilation**: Separate binaries for host and device with different ISAs/ABIs
- **Position-independent code (PIC)**: Device binaries compiled with PIC for flexibility
- **Shared communication**: Common section in linker scripts for host-device communication
- **CMake-based build system**: User-friendly build configuration
- **Symbol extraction**: Device symbols extracted for host linking

## Project Structure

```
chimera-sdk-multi/
├── cmake/              # CMake helper modules
│   └── ChimeraUtils.cmake
├── common/             # Shared files between host and devices
│   ├── common.ldh      # Common linker definitions
│   └── shared.h        # Shared data structures and function declarations
├── host/               # Host binary (CVA6, RV64IMC)
│   ├── crt0.S          # Host startup code
│   ├── link.ld         # Host linker script
│   ├── main.c          # Host main function
│   └── uart.c          # UART functions
├── devices/
│   └── snitch_cluster/ # Snitch cluster device binary (RV32IMAFD)
│       ├── crt0.S     #  Device startup code
│       ├── link.ld     # Device linker script
│       └── main.c      # Device main function
└── CMakeLists.txt      # Root CMake configuration
```

## Compilation Flow

The build system follows a multi-stage compilation flow:

1. **Device Binary Compilation**
   - Device binaries are compiled first with position-independent code (PIC)
   - Uses device-specific ISA/ABI (RV32IMAFD with ilp32d)
   - Generates `.elf`, `.bin`, and `.dump` files

2. **Symbol Extraction**
   - Relevant symbols are extracted from device binaries
   - These symbols can be used by the host for reference

3. **Host Binary Compilation**
   - Host binary is compiled with host-specific ISA/ABI (RV64IMC with lp64)
   - Links with device symbols and can embed device binaries
   - Generates `.elf`, `.bin`, and `.dump` files

## Shared Communication

### Common Section
- Defined in `common/common.ldh` at a known memory location (0x90000000)
- Host linker script loads the common section
- Device linker scripts mark it as `NOLOAD` (to avoid duplicate loading)

### Shared Data Structure
All shared data is packed into a struct (`chimera_shared_data_t`) placed in the `.common` section:
- Ensures consistent ordering and alignment across binaries
- Defined in `common/shared.h`

### Offloadable Functions
Functions that can be offloaded to devices are declared as `extern` in `common/shared.h`.

## Building the Project

### Prerequisites
- CMake 3.19 or later
- LLVM/Clang toolchain with RISC-V support (version 12+, recommended 16+)
- The `TOOLCHAIN_DIR` environment variable must be set to your LLVM installation path

### Setting up the Toolchain

Export the LLVM toolchain directory:

```bash
export TOOLCHAIN_DIR=/path/to/your/llvm-installation
```

For example:
```bash
export TOOLCHAIN_DIR=/opt/llvm
# or
export TOOLCHAIN_DIR=$HOME/tools/llvm-17.0.0
```

### Build Commands

```bash
# Create build directory
mkdir build && cd build

# Configure with CMake
cmake ..

# Build all binaries
make

# Or build specific targets
make snitch_cluster_device     # Build device binary
make chimera_host              # Build host binary
```

### Quick Build Script

A convenience script is provided:

```bash
./build.sh
```

This will create the build directory, configure, and build all targets.

### Build Outputs

After building, you'll find:
- `host/chimera_host.elf` - Host ELF executable
- `host/chimera_host.bin` - Host binary file
- `host/chimera_host.dump` - Host disassembly
- `devices/snitch_cluster/snitch_cluster_device.elf` - Device ELF executable
- `devices/snitch_cluster/snitch_cluster_device.bin` - Device binary file
- `devices/snitch_cluster/snitch_cluster_device.dump` - Device disassembly
- `devices/snitch_cluster/snitch_cluster_device_symbols.txt` - Extracted device symbols

## Customization

### Adding New Devices

To add a new device:

1. Create a new directory under `devices/` (e.g., `devices/my_device/`)
2. Add the device's startup code, linker script, and source files
3. Create a `CMakeLists.txt` in the device directory
4. Use the `add_device_binary()` function to define the build
5. Add the device directory to the root `CMakeLists.txt`

### Modifying ISA/ABI

The architectures can be configured by editing `config.cmake`:

```cmake
# Host configuration (CVA6)
set(ABI_HOST lp64)
set(ISA_HOST rv64imc)

# Device configuration (Snitch Cluster)
set(ABI_DEVICE ilp32d)
set(ISA_DEVICE rv32imafd)
```

This follows the same pattern as the main `chimera-sdk` for consistency.

### Adding Shared Functions

1. Declare the function as `extern` in `common/shared.h`
2. Implement the function in the appropriate device source file
3. Call the function from the host code

## License

SPDX-License-Identifier: Apache-2.0

Copyright 2024 ETH Zurich and University of Bologna
