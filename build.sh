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
cmake -D TOOLCHAIN_DIR="$TOOLCHAIN_DIR" -B build

# Build
echo "Building..."
cmake --build build -j $(nproc)
