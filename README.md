# Chimera SDK Multi-Binary Compilation Example

This project demonstrates a heterogeneous multi-cluster compilation flow using CMake. The system consists of one host core and multiple devices (e.g. Snitch cluster with RV32IMAFD), each compiled into separate binaries.

- Common infrastructure: Shared header, linker includes, and memory layout definitions
- Host binary (CVA6, RV64IMC): Entry point that orchestrates device execution
- Device binaries (2x Snitch clusters with RV32): Task accelerators that execute work
- Communication: Shared data structure in common memory region (0x48000000)
- Build flow: Devices compiled first with symbol extraction, then host linked with device symbols


## License
All licenses used in this repository are listed under the `LICENSES` folder. Unless specified otherwise in the respective file headers, all code checked into this repository is made available under a permissive license.
- Most software sources and tool scripts are licensed under the [Apache 2.0 license](https://opensource.org/licenses/Apache-2.0).
- Some files are licensed under the [Solderpad v0.51 license](https://solderpad.org/licenses/SHL-0.51/).
- Markdown, JSON, text files, pictures, PDFs, are licensed under the [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0) license (CC BY 4.0).

To extract license information for all files, you can use the [reuse tool](https://reuse.software/) and by running `reuse spdx` in the root directory of this repository.
