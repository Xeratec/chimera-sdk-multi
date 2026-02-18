#!/bin/bash
# SPDX-FileCopyrightText: 2024 ETH Zurich and University of Bologna
# SPDX-License-Identifier: Apache-2.0

# Build script for chimera-sdk-multi

set -e

# Check if TOOLCHAIN_DIR is set
if [ -z "$TOOLCHAIN_DIR" ]; then
    echo "Error: TOOLCHAIN_DIR environment variable is not set"
    echo "Please set it to your LLVM installation path:"
    echo "  export TOOLCHAIN_DIR=/path/to/llvm"
    exit 1
fi

# Check if TOOLCHAIN_DIR exists
if [ ! -d "$TOOLCHAIN_DIR" ]; then
    echo "Error: TOOLCHAIN_DIR points to non-existent directory: $TOOLCHAIN_DIR"
    exit 1
fi

echo "Using LLVM toolchain at: $TOOLCHAIN_DIR"

# Configure
echo "Configuring..."
cmake -D TOOLCHAIN_DIR="$TOOLCHAIN_DIR" -B build

# Build
echo "Building..."
cmake --build build -j $(nproc)

echo ""
echo "========================================="
echo "Build completed successfully!"
echo "========================================="
echo "  Host Binary:            build/host/chimera_host.elf"
echo "  Host Disassembly:       build/host/chimera_host.dump"
echo "  Host Sections:          build/host/chimera_host.sections"
echo "  Host All Symbols:       build/host/chimera_host.symbols"
echo "-----------------------------------------"
echo "  Device Binary:          build/devices/snitch_cluster/snitch_cluster_device.elf"
echo "  Device Disassembly:     build/devices/snitch_cluster/snitch_cluster_device.dump"
echo "  Device sections:        build/devices/snitch_cluster/snitch_cluster_device.sections"
echo "  Device All symbols:     build/devices/snitch_cluster/snitch_cluster_device.symbols"
echo "  Device Export Symbols:  build/devices/snitch_cluster/snitch_cluster_device_symbols.h"
echo "========================================="
echo ""
echo "Shared .common section layout:"
echo "  Address: 0x48000000"
echo "  Host:    loaded (initialised to 0)"
echo "  Device:  NOLOAD"
echo "========================================="
