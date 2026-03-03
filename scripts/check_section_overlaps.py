#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2024 ETH Zurich and University of Bologna
# SPDX-License-Identifier: Apache-2.0
#
# Post-build memory-map printer and section-overlap checker.
#
# Parses one `llvm-objdump -h` output file per binary, prints a memory map
# sorted by VMA, and checks for unintended overlaps between loaded (TEXT/DATA)
# sections of different binaries.
#
# BSS / NOLOAD sections (e.g. the shared .common region) are displayed but
# excluded from overlap checks because they are intentionally mapped at the
# same physical address on all cores.
#
# This is a Python port of cmake/scripts/CheckSectionOverlaps.cmake.
#
# Usage:
#   python scripts/check_section_overlaps.py \
#       --binary <name> <sections_file> \
#       --binary <name> <sections_file> \
#       ...

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import List

# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------


@dataclass
class Section:
    binary: str  # display name of the owning binary
    name: str  # ELF section name (e.g. ".text", ".data")
    start: int  # VMA start address (inclusive)
    end: int  # VMA end address   (exclusive, = start + size)
    sec_type: str  # type string from objdump: TEXT, DATA, BSS, …


# ---------------------------------------------------------------------------
# objdump -h section parser
# ---------------------------------------------------------------------------

# llvm-objdump -h section line format:
#   <spaces> <idx> <name> <size_hex> <vma_hex> <TYPE>
#
# Example (32-bit ELF):
#   0 .text    0000018c 80000000 TEXT
# Example (64-bit ELF):
#   0 .text    000001bc 0000000080000000 TEXT
#
# The VMA width differs between 32- and 64-bit ELFs; the regex accepts both.
_SECTION_RE = re.compile(
    r'^\s+\d+\s+'  # leading whitespace + index
    r'(\S+)\s+'  # (1) section name
    r'([0-9a-fA-F]+)\s+'  # (2) size  (hex)
    r'([0-9a-fA-F]+)\s+'  # (3) VMA   (hex)
    r'([A-Z]+)',  # (4) type  (TEXT / DATA / BSS / …)
    re.MULTILINE,
)


def parse_sections_file(path: Path, binary_name: str) -> List[Section]:
    """Parse one llvm-objdump -h output file; return a list of Section objects."""
    if not path.exists():
        print(
            f"[CHIMERA] WARNING: sections file not found "
            f"(binary not yet built?): {path}",
            file = sys.stderr,
        )
        return []

    sections: List[Section] = []
    for m in _SECTION_RE.finditer(path.read_text()):
        sec_name = m.group(1)
        size = int(m.group(2), 16)
        vma = int(m.group(3), 16)
        sec_type = m.group(4)

        # Skip empty sections and metadata sections (VMA == 0 → debug/reloc)
        if vma == 0:
            continue

        sections.append(
            Section(
                binary = binary_name,
                name = sec_name,
                start = vma,
                end = vma + size,
                sec_type = sec_type,
            ))

    return sections


# ---------------------------------------------------------------------------
# Memory-map printer
# ---------------------------------------------------------------------------


def print_memory_map(all_sections: List[Section], verbose = False) -> None:
    """Print a memory map table sorted by VMA."""
    print("[CHIMERA] ===================================================================")
    print("[CHIMERA]  Memory Map  (all non-empty sections, sorted by VMA)")
    print("[CHIMERA] ===================================================================")
    print("[CHIMERA]  VMA Start           VMA End             Size        Type  Binary / Section")
    print("[CHIMERA] ---------------------------------------------------------------------------")

    for sec in all_sections:
        size = sec.end - sec.start
        start_hex = f"0x{sec.start:016x}"
        end_hex = f"0x{sec.end:016x}"
        size_hex = f"0x{size:08x}"
        tag = "" if sec.sec_type in ("TEXT", "DATA") else "  [shared/NOLOAD]"

        if sec.sec_type in ("TEXT", "DATA"):
            print(f"[CHIMERA]  {start_hex}  {end_hex}  {size_hex:>10s}"
                  f"  {sec.sec_type:<4s}  {sec.binary} / {sec.name}{tag}")
        elif verbose:
            print(f"[CHIMERA]  {start_hex}  {end_hex}  {size_hex:>10s}"
                  f"  {sec.sec_type:<4s}  {sec.binary} / {sec.name}{tag}")

    print("[CHIMERA] ===================================================================")


# ---------------------------------------------------------------------------
# Overlap detector
# ---------------------------------------------------------------------------


def check_overlaps(loaded: List[Section]) -> bool:
    """Check all pairs of loaded (TEXT/DATA) sections from *different* binaries.

    Two ranges [s1, e1) and [s2, e2) overlap iff  s1 < e2  AND  s2 < e1.

    Returns True if at least one overlap was found, False otherwise.
    """
    found = False
    n = len(loaded)

    for i in range(n):
        a = loaded[i]
        for j in range(i + 1, n):
            b = loaded[j]

            # Sections within the same binary never conflict with each other
            if a.binary == b.binary:
                continue

            if a.start < b.end and b.start < a.end:
                print(
                    f"[CHIMERA] OVERLAP: {a.binary} / {a.name} "
                    f"[0x{a.start:x}, 0x{a.end:x}) overlaps "
                    f"{b.binary} / {b.name} [0x{b.start:x}, 0x{b.end:x})",
                    file = sys.stderr,
                )
                found = True

    return found


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(
        description = ("Chimera section-overlap checker — "
                       "Python port of cmake/scripts/CheckSectionOverlaps.cmake"),
        formatter_class = argparse.RawDescriptionHelpFormatter,
        epilog = ("Example:\n"
                  "  %(prog)s \\\n"
                  "    --binary build/devices/snitch_cluster_0/snitch_cluster_0.sections \\\n"
                  "    --binary build/devices/snitch_cluster_1/snitch_cluster_1.sections \\\n"
                  "    --binary build/host/host.sections"),
    )
    parser.add_argument(
        "--binary",
        "-b",
        action = "append",
        required = True,
        help = "Binary name and its llvm-objdump -h sections file (repeatable)",
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action = "store_true",
        help = "Also print non-loaded sections (e.g. BSS, NOLOAD) in the memory map",
    )
    args = parser.parse_args()

    all_sections: List[Section] = []
    for sections_file in args.binary:
        name = sections_file.split("/")[-1].split(".")[0]
        all_sections.extend(parse_sections_file(Path(sections_file), name))

    if not all_sections:
        print("[CHIMERA] No non-empty sections found.")
        return 0

    # Sort by VMA start; use (binary, name) as tiebreaker for stable output
    all_sections.sort(key = lambda s: (s.start, s.binary, s.name))

    print_memory_map(all_sections, verbose = args.verbose)

    # Overlap check is limited to TEXT and DATA sections
    loaded = [s for s in all_sections if s.sec_type in ("TEXT", "DATA")]
    found_overlap = check_overlaps(loaded)

    if found_overlap:
        print(
            "[CHIMERA] ERROR: Section overlaps detected — see warnings above.\n"
            "Verify the placement chain in cmake/ChimeraUtils.cmake and "
            "each device's __device_end symbol.",
            file = sys.stderr,
        )
        return 1

    print("[CHIMERA] => No section overlaps detected. Layout is clean.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
