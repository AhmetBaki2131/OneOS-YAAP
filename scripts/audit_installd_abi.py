#!/usr/bin/env python3
"""Read-only IInstalld transaction compatibility audit for OneOS.

Input: two host_installd.txt-format tables ("name code signature").
This tool does not patch or start Android. A matching IInstalld subset does
NOT demonstrate ART, SELinux, data isolation, HAL or cross-SDK boot safety.
"""
import argparse
import json
import re
from pathlib import Path

# The 27 methods proxied by the Android 17 guest_installd_abi patch.
ALLOWED = (
    "createUserData", "setFirstBoot", "createAppData",
    "createAppDataBatched", "restoreconAppData", "fixupAppData",
    "getAppSize", "getUserSize", "getExternalSize", "getAppCrates",
    "getUserCrates", "controlDexOptBlocking", "mergeProfiles",
    "dumpProfiles", "copySystemProfile", "createProfileSnapshot",
    "linkNativeLibraryDirectory", "createOatDirs", "linkFile",
    "hashSecondaryDexFile", "invalidateMounts", "isQuotaSupported",
    "prepareAppProfile", "tryMountDataMirror", "getOdexVisibility",
    "createFsveritySetupAuthToken", "enableFsverity",
)
NAME = re.compile(r"^[A-Za-z_][A-Za-z_0-9]*$")
SIG = re.compile(r"^\([^\s()]*\)\S+$")
MAX_BYTES = 128 * 1024


def parse_table(text):
    if len(text.encode("utf-8")) > MAX_BYTES:
        raise ValueError("table exceeds size limit")
    methods, codes = {}, {}
    for lineno, raw in enumerate(text.splitlines(), 1):
        row = raw.strip()
        if not row or row.startswith("#"):
            continue
        parts = row.split()
        if len(parts) != 3 or not NAME.fullmatch(parts[0]) or not SIG.fullmatch(parts[2]):
            raise ValueError(f"invalid table row {lineno}")
        name, code_str, sig = parts
        if not code_str.isdecimal() or not 1 <= int(code_str) <= 16_777_215:
            raise ValueError(f"invalid transaction code on row {lineno}")
        code = int(code_str)
        if name in methods:
            raise ValueError(f"duplicate method {name} on row {lineno}")
        if code in codes:
            raise ValueError(f"duplicate transaction code {code} on row {lineno}")
        methods[name] = (code, sig)
        codes[code] = name
    if not methods or len(methods) > 512:
        raise ValueError("table must have 1..512 methods")
    return methods


def audit(reference, host, guest_sdk=None, host_sdk=None):
    """Assess exactly the 27 protected guest calls, not the entire framework."""
    if not reference or not host:
        raise ValueError("both tables are required")
    rows = []
    host_by_code = {code: name for name, (code, _) in host.items()}
    signature_failures = 0
    missing = 0
    shifted = 0
    direct = 0
    for name in ALLOWED:
        want = reference.get(name)
        got = host.get(name)
        if want is None or got is None:
            state = "missing"
            missing += 1
        elif want[1] != got[1]:
            state = "signature_mismatch"
            signature_failures += 1
        elif want[0] != got[0]:
            state = "code_shift"
            shifted += 1
        else:
            state = "direct"
            direct += 1
        item = {
            "method": name, "status": state,
            "guest_code": want[0] if want else None,
            "host_code": got[0] if got else None,
        }
        if state == "code_shift":
            # Helps diagnose code collisions. Remapping must be performed in a
            # verified guest proxy; changing the host's binder dispatch is unsafe.
            item["original_code_is_host_method"] = host_by_code.get(want[0])
        if state == "signature_mismatch":
            item["guest_signature"] = want[1]
            item["host_signature"] = got[1]
        rows.append(item)

    sdk_mismatch = (host_sdk is not None and guest_sdk is not None and host_sdk != guest_sdk)
    if missing or signature_failures:
        status = "incompatible_methods"
    elif shifted:
        status = "proxy_remap_candidate"
    else:
        status = "method_subset_matches"
    launch_verified = False  # Never claim launch safety from method comparison alone.
    return {
        "status": status,
        "host_sdk": host_sdk,
        "guest_sdk": guest_sdk,
        "sdk_mismatch": sdk_mismatch,
        "methods_compared": len(ALLOWED),
        "direct": direct,
        "code_shifts": shifted,
        "signature_mismatches": signature_failures,
        "missing": missing,
        "launch_verified": launch_verified,
        "needs_other_checks": [
            "guest framework and system_server", "ART and zygote",
            "SELinux and filesystem isolation", "kernel/vendor HALs",
            "data safety and rollback",
        ],
        "mapping": rows,
    }


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--reference", type=Path, required=True, help="guest proxy's original IInstalld table")
    p.add_argument("--host", type=Path, required=True, help="captured host IInstalld table")
    p.add_argument("--guest-sdk", type=int, choices=(35, 36, 37))
    p.add_argument("--host-sdk", type=int, choices=(35, 36, 37))
    p.add_argument("--json", action="store_true", help="emit machine-readable report")
    args = p.parse_args()
    try:
        reference = parse_table(args.reference.read_text(encoding="utf-8"))
        host = parse_table(args.host.read_text(encoding="utf-8"))
        report = audit(reference, host, args.guest_sdk, args.host_sdk)
    except (OSError, UnicodeError, ValueError) as e:
        p.error(str(e))
    if args.json:
        print(json.dumps(report, sort_keys=True, indent=2))
    else:
        print(f"ABI audit: {report['status']} (guest SDK {args.guest_sdk}, host SDK {args.host_sdk})")
        print(f"27 guest calls: {report['direct']} matching, {report['code_shifts']} code shifts, " +
              f"{report['signature_mismatches']} signature changes, {report['missing']} missing")
        for item in report["mapping"]:
            if item["status"] != "direct":
                print(f"  {item['method']}: {item['status']} ({item['guest_code']} -> {item['host_code']})")
        print("Launch verified: NO. Requires framework/ART/HAL/SELinux and data-safety validation.")


if __name__ == "__main__":
    main()
