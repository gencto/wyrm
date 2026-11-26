#!/usr/bin/env python3
"""Writes config regions the crate `wyrm-image` refuses to write, for first_boot.sh.

usage: mkregion.py OUT [--len N] [--garbage] [--mode OCTAL] ENTRY...

ENTRY is `name=content` (a regular file), `name->target` (a symbolic link) or
`name=>target` (a hard link). `--len` writes N as the payload length instead of the
real one, `--garbage` puts a byte that is not zero after the payload, `--mode` is the
mode of every entry (default 0600). The regions the device must accept come from
`wyr image build`, never from here.
"""
import hashlib
import struct
import sys

SIZE = 4 * 1024 * 1024


def header(name: bytes, size: int, kind: bytes, link: bytes, mode: int) -> bytes:
    h = bytearray(512)
    h[0 : len(name)] = name
    h[100:108] = b"%07o\0" % mode
    h[108:116] = b"0000000\0"
    h[116:124] = b"0000000\0"
    h[124:136] = b"%011o\0" % size
    h[136:148] = b"00000000000\0"
    h[148:156] = b" " * 8
    h[156:157] = kind
    h[157 : 157 + len(link)] = link
    h[257:263] = b"ustar\0"
    h[263:265] = b"00"
    h[148:156] = b"%06o\0 " % sum(h)
    return bytes(h)


def main() -> None:
    out, args = sys.argv[1], sys.argv[2:]
    length, garbage, mode, tar = None, False, 0o600, b""
    while args:
        arg = args.pop(0)
        if arg == "--len":
            length = int(args.pop(0))
        elif arg == "--garbage":
            garbage = True
        elif arg == "--mode":
            mode = int(args.pop(0), 8)
        elif "=>" in arg:
            name, target = arg.split("=>", 1)
            tar += header(name.encode(), 0, b"1", target.encode(), mode)
        elif "->" in arg:
            name, target = arg.split("->", 1)
            tar += header(name.encode(), 0, b"2", target.encode(), mode)
        else:
            name, content = arg.split("=", 1)
            data = content.encode().decode("unicode_escape").encode("latin-1")
            tar += header(name.encode(), len(data), b"0", b"", mode) + data
            tar += b"\0" * (-len(data) % 512)
    tar += b"\0" * 1024
    region = b"WYRMCFG1" + struct.pack("<Q", len(tar) if length is None else length)
    region += hashlib.sha256(tar).digest() + tar
    if garbage:
        region += b"\x01"
    region += b"\0" * (SIZE - len(region))
    with open(out, "wb") as f:
        f.write(region)


main()
