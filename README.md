# Chimera SDK Multi-Binary Compilation Example

This project demonstrates a heterogeneous multi-cluster compilation flow using CMake. The system consists of one host core and multiple devices (e.g. Snitch cluster with RV32IMAFD), each compiled into separate binaries.

- Common infrastructure: Shared header, linker includes, and memory layout definitions
- Host binary (CVA6, RV64IMC): Entry point that orchestrates device execution
- Device binaries (2x Snitch clusters with RV32): Task accelerators that execute work
- Communication: Shared data structure in common memory region (0x48000000)
- Build flow: Devices compiled first with symbol extraction, then host linked with device symbols
