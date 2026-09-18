#!/usr/bin/env python3
"""Rewrite the DT_SONAME of an ELF shared library in place.

The OHOS Node shared build names its library ``libnode.so`` but records the
ABI-suffixed SONAME ``libnode.so.137``. hvigor only packs native libraries
whose file name ends in ``.so``, so the shipped file stays ``libnode.so`` and
the host would otherwise record an unloadable ``DT_NEEDED`` entry. This tool
normalizes the staged library's SONAME so the link name matches the packed
file name.

The replacement is written into the existing dynamic string table and padded
with NUL bytes; the new name must not be longer than the current one.
"""

from __future__ import annotations

import struct
import sys

SHT_STRTAB = 3
DT_NULL = 0
DT_STRTAB = 5
DT_SONAME = 14
ELF64_HEADER = struct.Struct("<16sHHIQQQIHHHHHH")
ELF64_SECTION = struct.Struct("<IIQQQQIIQQ")
ELF64_DYNAMIC = struct.Struct("<qQ")
ELF64_SHDR_SIZE = ELF64_SECTION.size


def _fail(message: str) -> None:
    raise SystemExit(f"set-elf-soname: {message}")


def find_soname_offset(data: bytes) -> tuple[int, int, bytes]:
    """Returns (file offset of the SONAME string, its length, whole file bytes)."""
    if data[:4] != b"\x7fELF":
        _fail("not an ELF file")
    if data[4] != 2 or data[5] != 1:
        _fail("only 64-bit little-endian ELF is supported")

    header = ELF64_HEADER.unpack_from(data, 0)
    section_offset = header[6]
    section_size = header[11]
    section_count = header[12]
    if section_offset == 0 or section_count == 0:
        _fail("ELF has no section header table")

    sections = []
    for index in range(section_count):
        offset = section_offset + index * section_size
        sections.append(ELF64_SECTION.unpack_from(data, offset))

    dynamic = next((section for section in sections if section[1] == 6), None)
    if dynamic is None:
        _fail("ELF has no dynamic section")

    dynamic_offset, dynamic_size = dynamic[4], dynamic[5]
    string_address = None
    soname_value = None
    for offset in range(dynamic_offset, dynamic_offset + dynamic_size, ELF64_DYNAMIC.size):
        tag, value = ELF64_DYNAMIC.unpack_from(data, offset)
        if tag == DT_NULL:
            break
        if tag == DT_STRTAB:
            string_address = value
        elif tag == DT_SONAME:
            soname_value = value

    if string_address is None or soname_value is None:
        _fail("ELF does not declare a SONAME")

    dynstr = next(
        (section for section in sections if section[1] == SHT_STRTAB and section[3] == string_address),
        None,
    )
    if dynstr is None:
        _fail("cannot locate the dynamic string table")

    dynstr_offset = dynstr[4]
    string_offset = dynstr_offset + soname_value
    end = data.index(b"\x00", string_offset)
    return string_offset, end - string_offset, data


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        _fail("usage: set-elf-soname.py <library> <new-soname>")

    path, new_soname = argv[1], argv[2]
    encoded = new_soname.encode("utf-8")
    if b"\x00" in encoded:
        _fail("new SONAME must not contain NUL bytes")

    with open(path, "rb") as handle:
        data = bytearray(handle.read())

    string_offset, length, _ = find_soname_offset(bytes(data))
    current = bytes(data[string_offset : string_offset + length])
    if len(encoded) > length:
        _fail(f"new SONAME {encoded!r} does not fit inside the existing {current!r}")
    if current == encoded:
        print(f"set-elf-soname: {path} already declares {new_soname}")
        return 0

    data[string_offset : string_offset + length] = encoded.ljust(length, b"\x00")
    with open(path, "wb") as handle:
        handle.write(data)
    print(f"set-elf-soname: {path} SONAME {current.decode()} -> {new_soname}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
