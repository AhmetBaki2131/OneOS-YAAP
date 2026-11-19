#!/system/bin/sh
# Read-only OneOS compatibility & IInstalld probe for SM-A055F (YAAP Android 17).
# Touches ONLY /data/local/tmp/oneos_probe_tmp and writes:
#   /data/local/tmp/oneos_probe_report.txt
#   /data/local/tmp/host_installd_yaap.txt

OUT=/data/local/tmp/oneos_probe_report.txt
TBL=/data/local/tmp/host_installd_yaap.txt
TMP=/data/local/tmp/oneos_probe_tmp
rm -rf "$TMP"
mkdir -p "$TMP"

exec > "$OUT" 2>&1

echo "=== YAAP A05 OneOS READ-ONLY PROBE ==="
echo "Date: $(date '+%F %T')"
echo "UID: $(id -u) Context: $(id -Z 2>/dev/null || echo unknown)"
echo "Kernel: $(uname -a)"

echo ""
echo "=== 1. DEVICE / ROM / SOC PROPS ==="
for p in ro.product.brand ro.product.manufacturer ro.product.model ro.product.vendor.model \
         ro.product.device ro.product.vendor.device ro.bootloader ro.boot.hardware \
         ro.hardware ro.hardware.chipname ro.board.platform ro.soc.manufacturer ro.soc.model \
         ro.build.version.release ro.build.version.sdk ro.build.version.oneui \
         ro.vendor.api_level ro.board.api_level ro.build.fingerprint ro.product.cpu.abilist64 \
         ro.boot.verifiedbootstate ro.boot.flash.locked; do
    echo "$p=$(getprop "$p" 2>/dev/null)"
done

echo ""
echo "=== 2. CPU / ISA FEATURES ==="
grep -E '^(processor|CPU implementer|CPU part|Features|Hardware)' /proc/cpuinfo 2>/dev/null | head -n 40
ALL_FEAT=$(grep -m1 '^Features' /proc/cpuinfo 2>/dev/null)
echo "Summary features check:"
for f in asimd crc32 sve sve2 sme mops bf16 i8mm; do
    echo "$ALL_FEAT" | tr ' ' '\n' | grep -qx "$f" && echo "  $f=yes" || echo "  $f=no"
done

echo ""
echo "=== 3. ROOT TOOLS & BUSYBOX / RESETPROP / NS ==="
BB=""
for c in /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox /data/adb/magisk/busybox; do
    [ -x "$c" ] && { BB="$c"; break; }
done
[ -n "$BB" ] || BB=$(command -v busybox 2>/dev/null)
echo "BB=$BB"
if [ -n "$BB" ] && [ -x "$BB" ]; then
    APPLETS=" $("$BB" --list 2>/dev/null | tr '\n' ' ') "
    missing=""
    for a in sh mount umount losetup unshare nsenter pivot_root setsid awk grep sed; do
        case "$APPLETS" in *" $a "*) ;; *) missing="$missing $a" ;; esac
    done
    echo "missing_applets=${missing:-none}"
    "$BB" losetup --help 2>&1 | grep -q -e '-[A-Za-z]*r' && echo "losetup_r=ok" || echo "losetup_r=missing"
fi
RP=""
for c in /data/adb/ksu/bin/resetprop /data/adb/ap/bin/resetprop /debug_ramdisk/resetprop /sbin/resetprop; do
    [ -x "$c" ] && { RP="$c"; break; }
done
[ -n "$RP" ] || RP=$(command -v resetprop 2>/dev/null)
echo "RP=$RP"
if [ -n "$RP" ] && [ -x "$RP" ]; then
    echo "rp_read_fp=$("$RP" ro.build.fingerprint 2>/dev/null)"
fi
echo "self_mnt_ns=$(readlink /proc/$$/ns/mnt 2>/dev/null)"
echo "init_mnt_ns=$(readlink /proc/1/ns/mnt 2>/dev/null)"
echo "getevent=$(command -v getevent 2>/dev/null || echo missing)"
echo "sha256sum=$(command -v sha256sum 2>/dev/null || echo missing)"

echo ""
echo "=== 4. SELINUX / SERVICE CONTEXTS / PROP SPACE / FS ==="
echo "getenforce=$(getenforce 2>/dev/null)"
echo "plat_service_contexts_wildcard=$(grep -c '^\*' /system/etc/selinux/plat_service_contexts 2>/dev/null)"
PA_CTX=$(getprop -Z persist.sys.disable_rescue 2>/dev/null)
PA_DEF=$(getprop -Z oneos.unknown.name.probe 2>/dev/null)
for pf in "/dev/__properties__/${PA_CTX:-u:object_r:system_prop:s0}" "/dev/__properties__/${PA_DEF:-u:object_r:default_prop:s0}"; do
    if [ -r "$pf" ] && [ -n "$BB" ]; then
        s=$(stat -c %s "$pf" 2>/dev/null)
        u=$("$BB" od -An -tu4 -N4 "$pf" 2>/dev/null | tr -d ' ')
        echo "prop_area ${pf##*/}: size=$s used=$u free=$((s - 128 - u))"
    else
        echo "prop_area ${pf##*/}: unreadable"
    fi
done
echo "filesystems: $(tr '\n' ' ' < /proc/filesystems 2>/dev/null)"

echo ""
echo "=== 5. WATCHDOG / SOFTDOG NODES ==="
ls -lnZ /dev/watchdog* /dev/softdog* 2>&1 || true
for w in /sys/class/watchdog/watchdog*; do
    [ -d "$w" ] || continue
    echo "${w##*/}: identity='$(cat "$w/identity" 2>/dev/null)' state=$(cat "$w/state" 2>/dev/null) timeout=$(cat "$w/timeout" 2>/dev/null) timeleft=$(cat "$w/timeleft" 2>/dev/null)"
done
echo "persist.vendor.softdog=$(getprop persist.vendor.softdog 2>/dev/null)"
echo "init.svc.watchdogd=$(getprop init.svc.watchdogd 2>/dev/null)"
for p in $(pidof system_server); do
    for fd in /proc/"$p"/fd/*; do
        t=$(readlink "$fd" 2>/dev/null)
        case "$t" in /dev/watchdog*|/dev/softdog*) echo "system_server($p) holds $t" ;; esac
    done
done 2>/dev/null

echo ""
echo "=== 6. DISPLAY / AUDIO / RADIO / THERMAL HALs & ZYGOTE ==="
echo "init.svc.zygote=$(getprop init.svc.zygote)"
echo "init.svc.zygote_secondary=$(getprop init.svc.zygote_secondary)"
echo "hwservicemanager_pid=$(pidof hwservicemanager 2>/dev/null || echo none)"
echo "imsd_pid=$(pidof imsd 2>/dev/null || echo none)"
echo "composer_svcs=$(getprop | sed -n 's/^\[init\.svc\.\([^]]*\)\]: \[running\]$/\1/p' | grep -E 'hwcomposer|display\.composer|graphics\.composer' | tr '\n' ' ')"
for ifc in android.hardware.graphics.composer3 android.hardware.graphics.composer \
           android.hardware.audio.core android.hardware.audio \
           android.hardware.radio.sim android.hardware.radio; do
    if grep -rqs "$ifc" /vendor/etc/vintf/ 2>/dev/null; then
        echo "vintf:$ifc=present"
    else
        echo "vintf:$ifc=absent"
    fi
done
echo "thermal_ready=$(dumpsys thermalservice 2>/dev/null | grep -m1 'HAL Ready:' || echo unknown)"
dumpsys display 2>/dev/null | grep -E 'DisplayDeviceInfo\{|CutoutPathParserInfo|brightnessMaximum|RoundedCorner\{' | head -n 12

echo ""
echo "=== 7. STORAGE, ZYGISK & EXISTING STAGE ==="
df -h /data 2>/dev/null
for m in /data/adb/modules/*; do
    [ -d "$m" ] || continue
    disabled=""
    [ -f "$m/disable" ] && disabled=" [DISABLED]"
    echo "ksu_module: ${m##*/} ($(grep -E '^(name|version|versionCode)=' "$m/module.prop" 2>/dev/null | tr '\n' ' '))$disabled"
done
echo "stage_exists=$([ -d /data/local/tmp/oneos ] && echo yes || echo no)"
if [ -f /data/local/tmp/libtimer_chk ]; then :; fi
echo "screen_lock_locksettings=$(locksettings get-disabled 2>/dev/null || echo unknown)"

echo ""
echo "=== 8. YAAP IInstalld TABLE EXTRACTION & ALLOWED-SET DIFF ==="
DEXDUMP=/apex/com.android.art/bin/dexdump
SJAR=/system/framework/services.jar
if [ -x "$DEXDUMP" ] && [ -f "$SJAR" ] && [ -n "$BB" ]; then
    mkdir -p "$TMP/dex"
    "$BB" unzip -oq "$SJAR" 'classes*.dex' -d "$TMP/dex" 2>/dev/null || unzip -oq "$SJAR" 'classes*.dex' -d "$TMP/dex" 2>/dev/null
    DUMP="$TMP/services_iinstalld.txt"
    : > "$DUMP"
    for d in "$TMP"/dex/classes*.dex; do
        [ -f "$d" ] || continue
        "$DEXDUMP" -f "$d" 2>/dev/null | awk '
            /Class descriptor/ {
                keep = ($0 ~ /Landroid\/os\/IInstalld\$Stub(;|\$Proxy;)/)
            }
            keep { print }
        ' >> "$DUMP"
    done
    awk '
        function hex2dec(s,   i, d, ch, h) {
            h = "0123456789abcdef"
            s = tolower(s)
            sub(/^0x/, "", s)
            d = 0
            for (i = 1; i <= length(s); i++) {
                ch = index(h, substr(s, i, 1)) - 1
                if (ch < 0) return -1
                d = d * 16 + ch
            }
            return d
        }
        /Class descriptor/ {
            sec = ($0 ~ /IInstalld\$Stub;/) ? "stub" : (($0 ~ /IInstalld\$Stub\$Proxy;/) ? "proxy" : "")
            cname = ""; ctype = ""; cacc = ""; next
        }
        sec == "stub" && /^[[:space:]]*name[[:space:]]*:/ {
            if (match($0, /'\''TRANSACTION_[A-Za-z0-9_]+'\''/)) {
                cname = substr($0, RSTART + 13, RLENGTH - 14)
            } else { cname = "" }
            ctype = ""
            next
        }
        sec == "stub" && cname != "" && /^[[:space:]]*type[[:space:]]*:/ {
            if (match($0, /'\''[^'\'']+'\''/)) ctype = substr($0, RSTART + 1, RLENGTH - 2)
            next
        }
        sec == "stub" && cname != "" && ctype == "I" && /^[[:space:]]*value[[:space:]]*:/ {
            val = $NF
            if (val ~ /^0[xX]/) val = hex2dec(val)
            if (val ~ /^[0-9]+$/) codes[cname] = val + 0
            cname = ""
            next
        }
        sec == "proxy" && /^[[:space:]]*name[[:space:]]*:/ {
            if (match($0, /'\''[^'\'']+'\''/)) cname = substr($0, RSTART + 1, RLENGTH - 2)
            next
        }
        sec == "proxy" && cname != "" && /^[[:space:]]*type[[:space:]]*:/ {
            if (match($0, /'\''[^'\'']+'\''/)) {
                sig = substr($0, RSTART + 1, RLENGTH - 2)
                if (!(cname in sigs)) sigs[cname] = sig
            }
            cname = ""
            next
        }
        END {
            for (n in codes) {
                printf "%04d %s %s\n", codes[n], n, (n in sigs ? sigs[n] : "-")
            }
        }
    ' "$DUMP" | sort -n > "$TMP/table_sorted.txt"

    {
        echo "# host IInstalld: name code signature (from YAAP services.jar)"
        echo "# Build: $(getprop ro.build.fingerprint)"
        awk '{ printf "%s %d %s\n", $2, $1 + 0, $3 }' "$TMP/table_sorted.txt"
    } > "$TBL"

    grep -v '^#' "$TBL" | sha256sum | awk '{ print "yaap_installd_sha256=" $1 }'
    echo "yaap_installd_method_count=$(grep -vc '^#' "$TBL")"

    # Check the exact 27 ALLOWED methods used by OneOS guest_installd_abi.py
    awk '
        BEGIN {
            exp_code["createUserData"]=1; exp_sig["createUserData"]="(Ljava/lang/String;III)V"
            exp_code["setFirstBoot"]=3; exp_sig["setFirstBoot"]="()V"
            exp_code["createAppData"]=4; exp_sig["createAppData"]="(Landroid/os/CreateAppDataArgs;)Landroid/os/CreateAppDataResult;"
            exp_code["createAppDataBatched"]=5; exp_sig["createAppDataBatched"]="([Landroid/os/CreateAppDataArgs;)[Landroid/os/CreateAppDataResult;"
            exp_code["restoreconAppData"]=7; exp_sig["restoreconAppData"]="(Ljava/lang/String;Ljava/lang/String;IIILjava/lang/String;)V"
            exp_code["fixupAppData"]=12; exp_sig["fixupAppData"]="(Ljava/lang/String;I)V"
            exp_code["getAppSize"]=13; exp_sig["getAppSize"]="(Ljava/lang/String;[Ljava/lang/String;IIII[J[Ljava/lang/String;)[J"
            exp_code["getUserSize"]=14; exp_sig["getUserSize"]="(Ljava/lang/String;II[I[I)[J"
            exp_code["getExternalSize"]=15; exp_sig["getExternalSize"]="(Ljava/lang/String;II[I)[J"
            exp_code["getAppCrates"]=16; exp_sig["getAppCrates"]="(Ljava/lang/String;[Ljava/lang/String;I)[Landroid/os/storage/CrateMetadata;"
            exp_code["getUserCrates"]=17; exp_sig["getUserCrates"]="(Ljava/lang/String;I)[Landroid/os/storage/CrateMetadata;"
            exp_code["controlDexOptBlocking"]=21; exp_sig["controlDexOptBlocking"]="(Z)V"
            exp_code["mergeProfiles"]=23; exp_sig["mergeProfiles"]="(ILjava/lang/String;Ljava/lang/String;)I"
            exp_code["dumpProfiles"]=24; exp_sig["dumpProfiles"]="(ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;Z)Z"
            exp_code["copySystemProfile"]=25; exp_sig["copySystemProfile"]="(Ljava/lang/String;ILjava/lang/String;Ljava/lang/String;)Z"
            exp_code["createProfileSnapshot"]=29; exp_sig["createProfileSnapshot"]="(ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;)Z"
            exp_code["linkNativeLibraryDirectory"]=33; exp_sig["linkNativeLibraryDirectory"]="(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;I)V"
            exp_code["createOatDirs"]=34; exp_sig["createOatDirs"]="(Ljava/lang/String;Ljava/lang/String;Ljava/util/List;)V"
            exp_code["linkFile"]=35; exp_sig["linkFile"]="(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V"
            exp_code["hashSecondaryDexFile"]=39; exp_sig["hashSecondaryDexFile"]="(Ljava/lang/String;Ljava/lang/String;ILjava/lang/String;I)[B"
            exp_code["invalidateMounts"]=40; exp_sig["invalidateMounts"]="()V"
            exp_code["isQuotaSupported"]=41; exp_sig["isQuotaSupported"]="(Ljava/lang/String;)Z"
            exp_code["prepareAppProfile"]=42; exp_sig["prepareAppProfile"]="(Ljava/lang/String;IILjava/lang/String;Ljava/lang/String;Ljava/lang/String;)Z"
            exp_code["tryMountDataMirror"]=47; exp_sig["tryMountDataMirror"]="(Ljava/lang/String;)V"
            exp_code["getOdexVisibility"]=51; exp_sig["getOdexVisibility"]="(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I"
            exp_code["createFsveritySetupAuthToken"]=53; exp_sig["createFsveritySetupAuthToken"]="(Landroid/os/ParcelFileDescriptor;I)Landroid/os/IInstalld$IFsveritySetupAuthToken;"
            exp_code["enableFsverity"]=54; exp_sig["enableFsverity"]="(Landroid/os/IInstalld$IFsveritySetupAuthToken;Ljava/lang/String;Ljava/lang/String;)I"
        }
        /^#/ { next }
        { got_code[$1] = $2 + 0; got_sig[$1] = $3 }
        END {
            bad = 0; ok = 0
            for (m in exp_code) {
                if (!(m in got_code)) {
                    print "MISMATCH missing: " m
                    bad++
                } else if (got_code[m] != exp_code[m] || got_sig[m] != exp_sig[m]) {
                    printf "MISMATCH %s: yaap=%d %s | oneos=%d %s\n", m, got_code[m], got_sig[m], exp_code[m], exp_sig[m]
                    bad++
                } else {
                    ok++
                }
            }
            printf "INSTALLD_ALLOWED_EQUIV=%s (ok=%d bad=%d)\n", (bad == 0 ? "EXACT_MATCH" : "NEEDS_REPATCH"), ok, bad
        }
    ' "$TBL"
else
    echo "INSTALLD_EXTRACT_SKIPPED (dexdump=$DEXDUMP jar=$SJAR bb=$BB)"
fi

rm -rf "$TMP"
echo ""
echo "=== PROBE DONE ==="
