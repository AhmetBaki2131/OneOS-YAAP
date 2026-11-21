#!/usr/bin/env python3
"""Apply validated ROM-independent fixes after the legacy patches; no device writes."""
from pathlib import Path
import argparse
MODEL = "app-android/core/model/src/main/kotlin/com/fahadali/oneos/core/model/"
def transform(root):
    edits = {}
    def edit(name, old, new, count=1):
        text = edits.get(name, (root / name).read_text(encoding="utf-8"))
        if text.count(old) != count:
            raise ValueError(f"{name}: expected {count} anchors, found {text.count(old)}: {old[:100]}")
        edits[name] = text.replace(old, new)
    switch = "switcher/assets/oneos_switch.sh"
    prepare = "switcher/assets/guest_prepare.sh"
    props = "switcher/assets/guest_props.sh"
    # rect_px/hole_px are SVG paths, not Oplus's x,y:x,y property.
    edit(switch, 'echo "rect_px=328,0:392,58"; echo "hole_px=328,0:392,58"',
         'echo "rect_px=M -32,0 L -32,58 L 32,58 L 32,0 Z"; echo "hole_px=M -32,0 L -32,58 L 32,58 L 32,0 Z"')
    edit(switch, '''    *a05m*)
        { echo "spec=M -32,0 L -32,58 L 32,58 L 32,0 Z";''',
         '''    *a05m*)
        # Preserve measured geometry; fallback only for the known A05 panel.
        if [ ! -s "$STAGE/host_statusbar" ] && [ "$(cat "$STAGE/host_panel_size" 2>/dev/null)" = "720 1600" ]; then
        { echo "spec=M -32,0 L -32,58 L 32,58 L 32,0 Z";''')
    edit(switch, 'echo "Host status bar: A05 fixed cutout written" ;;',
         'echo "Host status bar: A05 fallback cutout written"\n        fi ;;')
    edit(switch, r'if [ \"$GUEST_AOSP_SYSUI$GUEST_MIUI\" != 00 ] && [ $GUEST_FOLD_FORM = 0 ] && [ -f $STAGE/data/oneos_overlay_dimen.dex ]; then',
         r'if [ $GUEST_FOLD_FORM = 0 ] && [ -f $STAGE/data/oneos_overlay_dimen.dex ]; then')
    edit(prepare, '${ONEOS_GUEST_COLOROS_LITE:-1}', '${ONEOS_GUEST_COLOROS_LITE:-0}')
    edit(switch, 'if [ "${MT:-9999999}" -lt 5000000 ]; then',
         'if [ "${ONEOS_GUEST_COLOROS_LITE:-0}" = 1 ] && [ "${MT:-9999999}" -lt 5000000 ]; then')
    edit(switch, r'''            # Prevent early screen-off sleep crash (OplusDisplayPowerControllerExtImpl.onGoToSleepFinish NPE)
            $BB nsenter -t \$PID -m /system/bin/sh /data/oneos_genv.sh /system/bin/settings put system screen_off_timeout 600000 2>/dev/null
            $BB nsenter -t \$PID -m /system/bin/sh /data/oneos_genv.sh /system/bin/svc power stayon true 2>/dev/null
''', '''            # Respect the user's screen timeout and charging sleep policy.
''')
    edit(props, '''        for kv in sys.gcsupression.optimize.enable=false persist.sys.oplus.anim_level=2 \\
                  dalvik.vm.dex2oat-threads=2 dalvik.vm.background-dex2oat-threads=1 \\
                  log.tag.ANDR-PERF-CLIENT-SYS=S log.tag.UAH_CLIENT=S; do''',
         '''        # Keep diagnostics visible; limit background compilation on low-memory hosts.
        CO_PERF="sys.gcsupression.optimize.enable=false"
        CO_MEM=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
        case "$CO_MEM" in
            ''|*[!0-9]*) ;;
            *) [ "$CO_MEM" -ge 5000000 ] || CO_PERF="$CO_PERF dalvik.vm.background-dex2oat-threads=1" ;;
        esac
        for kv in $CO_PERF; do''')
    edit(props, 'echo "guest_props: ColorOS Lite props set (sys.gcsupression.optimize.enable=false, dex2oat-threads=2, ANDR-PERF-CLIENT-SYS/UAH_CLIENT silenced)"',
         'echo "guest_props: ColorOS compatibility props: $CO_PERF (diagnostic logs retained)"')
    # WingCam passes a component name to AppOps on ColorOS (live A05 evidence).
    edit(prepare, 'if [ -f "$WCAPK" ] && [ -d "$WCMP" ]',
         'if [ "${ONEOS_GUEST_WINGCAM:-0}" = 1 ] && [ -f "$WCAPK" ] && [ -d "$WCMP" ]')
    edit(prepare, '|| [ -f /system/priv-app/WingCam-N28/WingCam-N28.apk ]; }; then',
         '|| { [ "${ONEOS_GUEST_WINGCAM:-0}" = 1 ] && [ -f /system/priv-app/WingCam-N28/WingCam-N28.apk ]; }; }; then')
    edit(prepare, '''    # A copy installed from /data would shadow the system app.
    rm -rf "$STAGE"/data/app/*/com.sec.android.app.camera-* 2>/dev/null''',
         '''    # Preserve installed user cameras and Android's normal update precedence.''')
    edit(switch, '''# WingCam permissions.
n=0;''', '''# Optional WingCam only; permissions cannot repair an attribution/ABI mismatch.
if [ "${ONEOS_GUEST_WINGCAM:-0}" = 1 ]; then
n=0;''')
    edit(switch, '''    echo "WingCam permissions granted"
fi
# SD card:''', '''    echo "WingCam permissions requested; camera operation not verified"
fi
fi
# SD card:''')
    edit(MODEL + "CustomRom.kt", "Custom AOSP host (experimental YAAP mode)", "Custom Android host (experimental)")
    edit(MODEL + "CustomRom.kt", "Switching requires YAAP-matched host_installd and HAL checks.",
         "Switching requires a verified host installd table and compatible camera, sensor and graphics HALs.")
    edit(MODEL + "InstalldTable.kt", '''        val byName = derived.methods.associateBy { it.name }
        val exact =''', '''        if (!derived.ok) return false
        val byName = derived.methods.associateBy { it.name }
        if (byName.size != derived.methods.size) return false
        if (derived.methods.map { it.code }.toSet().size != derived.methods.size) return false
        val exact =''')
    edit(MODEL + "InstalldTable.kt",
         '''            got.signature == want.second && (got.code == want.first || (yaapShift != null && got.code == yaapShift.first))''',
         '''            got.signature == want.second && got.code == (yaapShift?.first ?: want.first)''')
    edit(MODEL + "InstalldTable.kt",
         '''        if (derived == null || !derived.ok) return false
        val byName = derived.methods.associateBy { it.name }
        return byName["createFsveritySetupAuthToken"]?.code == 52''',
         '''        if (derived == null || !allowedSubsetCompatible(derived)) return false
        val byName = derived.methods.associateBy { it.name }
        return byName["createFsveritySetupAuthToken"]?.code == 52''')
    return edits
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, required=True)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    for name, content in transform(args.root).items():
        if not args.check:
            (args.root / name).write_text(content, encoding="utf-8", newline="\n")
        print(("CHECK " if args.check else "PATCH ") + name)
if __name__ == "__main__":
    main()

