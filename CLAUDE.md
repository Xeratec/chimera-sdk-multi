# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a heterogeneous multi-binary compilation example demonstrating how to compile separate binaries for different RISC-V cores (host and devices) with different ISAs that communicate through shared memory.

## Build Commands

```sh
docker exec chimera bash -c "
   cd /app/chimera/chimera-sdk-multi &&
   export TOOLCHAIN_DIR=/app/install/llvm-18.1.4-pulp &&
   rm -rf build &&
   ./build.sh
"
```