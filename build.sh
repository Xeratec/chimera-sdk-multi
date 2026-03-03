#!/bin/bash
# SPDX-FileCopyrightText: 2024 ETH Zurich and University of Bologna
# SPDX-License-Identifier: Apache-2.0

# Build script for chimera-sdk-multi

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Check TOOLCHAIN_DIR
# ---------------------------------------------------------------------------
if [ -z "$TOOLCHAIN_DIR" ]; then
    echo "Error: TOOLCHAIN_DIR environment variable is not set"
    echo "Please set it to your LLVM installation path:"
    echo "  export TOOLCHAIN_DIR=/path/to/llvm"
    exit 1
fi

if [ ! -d "$TOOLCHAIN_DIR" ]; then
    echo "Error: TOOLCHAIN_DIR points to non-existent directory: $TOOLCHAIN_DIR"
    exit 1
fi

# ---------------------------------------------------------------------------
# Check / install uv
# ---------------------------------------------------------------------------
if ! command -v uv &>/dev/null; then
    echo ""
    echo "uv (Python package manager) is not installed."
    echo "Installing uv …"
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # Reload PATH so the newly installed uv is visible
    export PATH="$HOME/.local/bin:$PATH"
fi

if ! command -v uv &>/dev/null; then
    echo "Error: 'uv' could not be installed or is not in PATH."
    echo "Install manually: https://docs.astral.sh/uv/getting-started/installation/"
    exit 1
fi

# ---------------------------------------------------------------------------
# Parse optional flags
# ---------------------------------------------------------------------------
UNIFIED_ELF=OFF
VERBOSE=OFF
for arg in "$@"; do
    case "$arg" in
        --unified-elf) UNIFIED_ELF=ON ;;
        -v|--verbose) VERBOSE=ON ;;
        -h|--help)
            echo "Usage: $0 [--unified-elf] [-v|--verbose]"
            echo ""
            echo "Options:"
            echo "  --unified-elf   Generate a unified mixed-ISA ELF after the build"
            echo "                  (requires lief; managed automatically via uv)"
            echo "  -v, --verbose   Enable verbose configure and build output"
            exit 0
            ;;
    esac
done

CONFIGURE_LOG_LEVEL=()
BUILD_VERBOSE_FLAG=()
if [ "$VERBOSE" = "ON" ]; then
    CONFIGURE_LOG_LEVEL+=(--log-level=trace)
    BUILD_VERBOSE_FLAG+=(--verbose)
fi

# ---------------------------------------------------------------------------
# Configure
# ---------------------------------------------------------------------------
echo ""
echo "Configuring …"
cmake \
    -D TOOLCHAIN_DIR="$TOOLCHAIN_DIR" \
    -D CHIMERA_UNIFIED_ELF="$UNIFIED_ELF" \
    -B "$SCRIPT_DIR/build" \
    -S "$SCRIPT_DIR" \
    "${CONFIGURE_LOG_LEVEL[@]}"

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
echo ""
echo "Building …"
cmake --build "$SCRIPT_DIR/build" "${BUILD_VERBOSE_FLAG[@]}" -j "$(nproc 2>/dev/null || sysctl -n hw.logicalcpu)"
