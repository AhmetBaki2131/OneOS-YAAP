#!/usr/bin/env python3
"""Inspect or remap YAAP-17 IInstalld transaction codes in OneOS services_patched.jar.

Measured on SM-A055F YAAP Android 17 (host_installd_yaap.txt):
  - 25 of 27 ALLOWED methods (slots 1..51) match switcher/patches/host_installd.txt byte-for-byte.
  - Only the two fsverity methods are shifted by -1 slot:
      createFsveritySetupAuthToken : OneOS 53 (0x35) -> YAAP 52 (0x34)
      enableFsverity               : OneOS 54 (0x36) -> YAAP 53 (0x35)

This script scans OneOSInstalldProxy in services_patched.jar classes*.dex,
verifies the exact const/16 (or const) argument passed to IBinder.transact(),
and rewrites only those two codes (plus DEX SHA-1 signature & Adler-32 checksum).
"""

from __future__ import annotations

import argparse
import hashlib
import os
import struct
import sys
import zipfile
import zlib
from typing import Dict, List, Optional, Tuple

DEFAULT_REMAP: Dict[str, Tuple[int, int]] = {
    "createFsveritySetupAuthToken": (53, 52),
    "enableFsverity": (54, 53),
}

# Exact Dalvik instruction sizes in 16-bit code units (standard Android DEX opcodes 0x00..0xff).
DALVIK_OP_WIDTHS: List[int] = [
    1, 1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 1, 1, 1, 1, 1,  # 0x00..0x0f
    1, 1, 1, 2, 3, 2, 2, 3, 5, 2, 2, 3, 2, 1, 1, 2,  # 0x10..0x1f
    2, 1, 2, 2, 3, 3, 3, 1, 1, 2, 3, 3, 3, 2, 2, 2,  # 0x20..0x2f
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1,  # 0x30..0x3f
    1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,  # 0x40..0x4f
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,  # 0x50..0x5f
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 3,  # 0x60..0x6f
    3, 3, 3, 1, 3, 3, 3, 3, 3, 1, 1, 1, 1, 1, 1, 1,  # 0x70..0x7f
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,  # 0x80..0x8f
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,  # 0x90..0x9f
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,  # 0xa0..0xaf
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,  # 0xb0..0xbf
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,  # 0xc0..0xcf
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,  # 0xd0..0xdf
    2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,  # 0xe0..0xef
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 4, 4, 3, 3, 2, 2,  # 0xf0..0xff
]


def read_uleb128(data: bytes, pos: int) -> Tuple[int, int]:
    result = 0
    shift = 0
    while True:
        b = data[pos]
        pos += 1
        result |= (b & 0x7F) << shift
        if (b & 0x80) == 0:
            return result, pos
        shift += 7


def skip_uleb128(data: bytes, pos: int, count: int) -> int:
    for _ in range(count):
        _, pos = read_uleb128(data, pos)
    return pos


class DexParser:
    def __init__(self, raw: bytearray) -> None:
        self.raw = raw
        if not raw.startswith(b"dex\n") or raw[7] != 0:
            raise ValueError("Not a valid DEX header")
        self.string_ids_size, self.string_ids_off = struct.unpack_from("<II", raw, 0x38)
        self.type_ids_size, self.type_ids_off = struct.unpack_from("<II", raw, 0x40)
        self.method_ids_size, self.method_ids_off = struct.unpack_from("<II", raw, 0x58)
        self.class_defs_size, self.class_defs_off = struct.unpack_from("<II", raw, 0x60)

    def get_string(self, sidx: int) -> str:
        off = struct.unpack_from("<I", self.raw, self.string_ids_off + sidx * 4)[0]
        _, pos = read_uleb128(self.raw, off)
        end = self.raw.find(b"\x00", pos)
        return self.raw[pos:end].decode("utf-8", errors="replace")

    def get_type(self, tidx: int) -> str:
        sidx = struct.unpack_from("<I", self.raw, self.type_ids_off + tidx * 4)[0]
        return self.get_string(sidx)

    def get_method(self, midx: int) -> Tuple[str, str]:
        class_idx, _proto_idx, name_idx = struct.unpack_from("<HHI", self.raw, self.method_ids_off + midx * 8)
        return self.get_type(class_idx), self.get_string(name_idx)

    def iter_class_methods(self, class_suffix: str) -> List[Tuple[str, str, int]]:
        hits: List[Tuple[str, str, int]] = []
        for i in range(self.class_defs_size):
            base = self.class_defs_off + i * 32
            class_idx = struct.unpack_from("<I", self.raw, base)[0]
            class_data_off = struct.unpack_from("<I", self.raw, base + 24)[0]
            if class_data_off == 0:
                continue
            cname = self.get_type(class_idx)
            if not cname.endswith(class_suffix):
                continue
            pos = class_data_off
            static_fields_size, pos = read_uleb128(self.raw, pos)
            instance_fields_size, pos = read_uleb128(self.raw, pos)
            direct_methods_size, pos = read_uleb128(self.raw, pos)
            virtual_methods_size, pos = read_uleb128(self.raw, pos)
            pos = skip_uleb128(self.raw, pos, (static_fields_size + instance_fields_size) * 2)
            for count in (direct_methods_size, virtual_methods_size):
                midx = 0
                for _ in range(count):
                    diff, pos = read_uleb128(self.raw, pos)
                    _flags, pos = read_uleb128(self.raw, pos)
                    code_off, pos = read_uleb128(self.raw, pos)
                    midx += diff
                    _, mname = self.get_method(midx)
                    if code_off != 0:
                        hits.append((cname, mname, code_off))
        return hits


def decode_insn_units(raw: bytearray, insns_off: int, insns_units: int) -> List[Tuple[int, int]]:
    """Return list of (unit_index, opcode) over the method body."""
    out: List[Tuple[int, int]] = []
    u = 0
    while u < insns_units:
        w0 = struct.unpack_from("<H", raw, insns_off + u * 2)[0]
        op = w0 & 0xFF
        if w0 in (0x0100, 0x0200, 0x0300):
            # Payloads only appear after switch/fill-array instructions at end of block;
            # compute exact payload width in code units if encountered.
            if w0 == 0x0100:  # packed-switch-payload
                cnt = struct.unpack_from("<H", raw, insns_off + (u + 1) * 2)[0]
                width = 4 + cnt * 2
            elif w0 == 0x0200:  # sparse-switch-payload
                cnt = struct.unpack_from("<H", raw, insns_off + (u + 1) * 2)[0]
                width = 2 + cnt * 4
            else:  # fill-array-data-payload
                ew = struct.unpack_from("<H", raw, insns_off + (u + 1) * 2)[0]
                ec = struct.unpack_from("<I", raw, insns_off + (u + 2) * 2)[0]
                width = 4 + (ew * ec + 1) // 2
        else:
            width = DALVIK_OP_WIDTHS[op]
        out.append((u, op))
        u += width
    return out


def find_transact_code_site(
    dex: DexParser, code_off: int
) -> Optional[Tuple[int, int, int]]:
    """Locate the constant instruction feeding IBinder.transact(code, ...).

    Returns (imm_byte_offset, imm_size_bytes, current_code) or None.
    """
    insns_units = struct.unpack_from("<I", dex.raw, code_off + 12)[0]
    insns_off = code_off + 16
    insns = decode_insn_units(dex.raw, insns_off, insns_units)

    transact_idx = None
    code_reg = None
    for idx, (u, op) in enumerate(insns):
        if op not in (0x72, 0x78):  # invoke-interface / invoke-interface/range
            continue
        w0, midx, w2 = struct.unpack_from("<HHH", dex.raw, insns_off + u * 2)
        cls_name, mname = dex.get_method(midx)
        if cls_name == "Landroid/os/IBinder;" and mname == "transact":
            if op == 0x72:
                code_reg = (w2 >> 4) & 0xF  # 2nd arg register (D)
            else:
                code_reg = w2 + 1
            transact_idx = idx
            break

    if transact_idx is None or code_reg is None:
        return None

    for j in range(transact_idx - 1, -1, -1):
        u, op = insns[j]
        w0 = struct.unpack_from("<H", dex.raw, insns_off + u * 2)[0]
        if op == 0x13 and ((w0 >> 8) & 0xFF) == code_reg:  # const/16 vAA, #+BBBB
            imm_off = insns_off + (u + 1) * 2
            val = struct.unpack_from("<h", dex.raw, imm_off)[0]
            return imm_off, 2, val
        if op == 0x14 and ((w0 >> 8) & 0xFF) == code_reg:  # const vAA, #+BBBBBBBB
            imm_off = insns_off + (u + 1) * 2
            val = struct.unpack_from("<i", dex.raw, imm_off)[0]
            return imm_off, 4, val
    return None


def update_dex_hashes(raw: bytearray) -> None:
    sha1 = hashlib.sha1(raw[32:]).digest()
    raw[12:32] = sha1
    adler = zlib.adler32(raw[12:]) & 0xFFFFFFFF
    struct.pack_into("<I", raw, 8, adler)


def process_jar(
    jar_path: str,
    class_suffix: str,
    remap: Dict[str, Tuple[int, int]],
    apply_patch: bool,
    out_path: Optional[str],
) -> int:
    if not os.path.isfile(jar_path):
        print(f"ERROR: JAR not found: {jar_path}", file=sys.stderr)
        return 2

    findings: Dict[str, str] = {}
    new_entries: List[Tuple[zipfile.ZipInfo, bytes]] = []
    dex_modified = False

    with zipfile.ZipFile(jar_path, "r") as zin:
        for info in zin.infolist():
            data = zin.read(info.filename)
            if info.filename.startswith("classes") and info.filename.endswith(".dex"):
                raw = bytearray(data)
                dex = DexParser(raw)
                methods = dex.iter_class_methods(class_suffix)
                changed_this_dex = False
                for cname, mname, code_off in methods:
                    if mname not in remap:
                        continue
                    want_old, want_new = remap[mname]
                    site = find_transact_code_site(dex, code_off)
                    if site is None:
                        findings[mname] = f"{info.filename} {cname}->{mname}: no IBinder.transact const site"
                        continue
                    imm_off, imm_len, cur = site
                    if cur == want_new:
                        findings[mname] = f"ALREADY_YAAP ({info.filename} {cname}->{mname}: code={cur})"
                    elif cur == want_old:
                        if apply_patch:
                            fmt = "<h" if imm_len == 2 else "<i"
                            struct.pack_into(fmt, raw, imm_off, want_new)
                            changed_this_dex = True
                            findings[mname] = f"PATCHED ({info.filename} {cname}->{mname}: {cur} -> {want_new})"
                        else:
                            findings[mname] = f"NEEDS_PATCH ({info.filename} {cname}->{mname}: {cur}, want {want_new})"
                    else:
                        findings[mname] = f"UNEXPECTED_CODE ({info.filename} {cname}->{mname}: got {cur}, expected {want_old} or {want_new})"
                if changed_this_dex:
                    update_dex_hashes(raw)
                    data = bytes(raw)
                    dex_modified = True
            new_entries.append((info, data))

    for m in sorted(remap):
        print(f"{m}: {findings.get(m, 'NOT_FOUND')}")

    missing = [m for m in remap if m not in findings]
    bad = [m for m, msg in findings.items() if msg.startswith(("UNEXPECTED", "no IBinder")) or (" no " in msg)]
    if missing or bad:
        return 1

    if apply_patch:
        target = out_path or jar_path
        tmp = target + ".tmp"
        with zipfile.ZipFile(tmp, "w") as zout:
            for info, data in new_entries:
                zi = zipfile.ZipInfo(info.filename, date_time=info.date_time)
                zi.compress_type = info.compress_type
                zi.external_attr = info.external_attr
                zout.writestr(zi, data)
        os.replace(tmp, target)
        with open(target, "rb") as f:
            digest = hashlib.sha256(f.read()).hexdigest()
        print(f"OUT={target} modified={dex_modified} sha256={digest}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Check or patch OneOS services_patched.jar IInstalld fsverity slots for YAAP 17.")
    ap.add_argument("jar", help="Path to services_patched.jar")
    ap.add_argument("--check", action="store_true", help="Inspect only (do not modify JAR)")
    ap.add_argument("--patch", action="store_true", help="Patch DEX transaction codes in place or to --out")
    ap.add_argument("--out", help="Output JAR path when using --patch")
    ap.add_argument("--class-suffix", default="OneOSInstalldProxy;", help="Target proxy class descriptor suffix")
    args = ap.parse_args()

    if args.check == args.patch:
        ap.error("Specify exactly one of --check or --patch")

    return process_jar(args.jar, args.class_suffix, DEFAULT_REMAP, args.patch, args.out)


if __name__ == "__main__":
    sys.exit(main())
