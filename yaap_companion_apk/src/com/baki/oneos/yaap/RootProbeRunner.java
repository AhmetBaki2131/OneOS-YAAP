package com.baki.oneos.yaap;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;

/**
 * Executes read-only su probes on the phone (KernelSU busybox, resetprop,
 * watchdog nodes, HAL VINTF, /data/local/tmp/oneos stage status, and YAAP IInstalld check).
 */
public final class RootProbeRunner {

    public static final class Result {
        public final int exitCode;
        public final String output;
        public final boolean timedOut;

        public Result(int exitCode, String output, boolean timedOut) {
            this.exitCode = exitCode;
            this.output = output;
            this.timedOut = timedOut;
        }
    }

    public static Result runKernelAndHalProbe() {
        String script =
            "echo '=== ROOT & BUSYBOX ==='\n" +
            "id\n" +
            "BB=''\n" +
            "for c in /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox /data/adb/magisk/busybox; do\n" +
            "  [ -x \"$c\" ] && { BB=$c; break; }\n" +
            "done\n" +
            "echo \"BB=${BB:-yok}\"\n" +
            "if [ -n \"$BB\" ]; then\n" +
            "  AP=\" $($BB --list 2>/dev/null | tr '\\n' ' ') \"\n" +
            "  miss=''\n" +
            "  for a in sh mount umount losetup unshare nsenter pivot_root setsid awk grep sed; do\n" +
            "    case \"$AP\" in *\" $a \"*) ;; *) miss=\"$miss $a\" ;; esac\n" +
            "  done\n" +
            "  echo \"missing_applets=${miss:-none}\"\n" +
            "  \"$BB\" losetup --help 2>&1 | grep -q -e '-[A-Za-z]*r' && echo 'losetup_r=OK' || echo 'losetup_r=MISSING'\n" +
            "fi\n" +
            "RP=''\n" +
            "for c in /data/adb/ksu/bin/resetprop /data/adb/ap/bin/resetprop /debug_ramdisk/resetprop /sbin/resetprop; do\n" +
            "  [ -x \"$c\" ] && { RP=$c; break; }\n" +
            "done\n" +
            "echo \"RP=${RP:-yok}\"\n" +
            "echo \"self_ns=$(readlink /proc/$$/ns/mnt 2>/dev/null)\"\n" +
            "echo \"init_ns=$(readlink /proc/1/ns/mnt 2>/dev/null)\"\n" +
            "echo \"getenforce=$(getenforce 2>/dev/null)\"\n" +
            "echo \"plat_svc_wildcard=$(grep -c '^\\*' /system/etc/selinux/plat_service_contexts 2>/dev/null)\"\n" +
            "echo '=== WATCHDOG ==='\n" +
            "ls -ln /dev/watchdog* /dev/softdog* 2>&1 || true\n" +
            "for w in /sys/class/watchdog/watchdog*; do\n" +
            "  [ -d \"$w\" ] && echo \"${w##*/}: id='$(cat $w/identity 2>/dev/null)' state=$(cat $w/state 2>/dev/null)\"\n" +
            "done\n" +
            "echo '=== COMPOSER, BACKLIGHT & AUDIO HAL ==='\n" +
            "echo \"hwservicemanager=$(pidof hwservicemanager 2>/dev/null || echo none)\"\n" +
            "echo \"imsd=$(pidof imsd 2>/dev/null || echo none)\"\n" +
            "echo \"zygote_secondary=$(getprop init.svc.zygote_secondary)\"\n" +
            "grep -rqs 'android.hardware.graphics.composer3' /vendor/etc/vintf/ 2>/dev/null && echo 'vintf_composer3=yes' || echo 'vintf_composer3=no'\n" +
            "grep -rqs 'android.hardware.audio.core' /vendor/etc/vintf/ 2>/dev/null && echo 'vintf_audio_aidl=yes' || echo 'vintf_audio_aidl=no'\n" +
            "echo \"backlight_led=$(cat /sys/class/leds/lcd-backlight/brightness 2>/dev/null || echo none)/$(cat /sys/class/leds/lcd-backlight/max_brightness 2>/dev/null || echo ?)\"\n" +
            "echo '=== KSU MODULES & STAGE ==='\n" +
            "for m in /data/adb/modules/*; do\n" +
            "  [ -d \"$m\" ] && echo \"mod=${m##*/} $(grep -E '^(version|versionCode)=' \"$m/module.prop\" 2>/dev/null | tr '\\n' ' ') $([ -f \"$m/disable\" ] && echo '[OFF]')\"\n" +
            "done\n" +
            "if [ -d /data/local/tmp/oneos ]; then\n" +
            "  echo \"stage=VAR (.oneos_stage: $(cat /data/local/tmp/oneos/.oneos_stage 2>/dev/null || echo yok))\"\n" +
            "  ls -lh /data/local/tmp/oneos/system.raw 2>/dev/null || true\n" +
            "else\n" +
            "  echo 'stage=HENUZ YOK'\n" +
            "fi\n";
        return execSu(script, 15);
    }

    public static Result runInstalldCheck() {
        String script =
            "BB=''\n" +
            "for c in /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox /data/adb/magisk/busybox; do\n" +
            "  [ -x \"$c\" ] && { BB=$c; break; }\n" +
            "done\n" +
            "DEXDUMP=/apex/com.android.art/bin/dexdump\n" +
            "SJAR=/system/framework/services.jar\n" +
            "if [ ! -x \"$DEXDUMP\" ] || [ ! -f \"$SJAR\" ] || [ -z \"$BB\" ]; then\n" +
            "  echo \"Eksik arac: dexdump=$DEXDUMP jar=$SJAR bb=$BB\"\n" +
            "  exit 2\n" +
            "fi\n" +
            "T=/data/local/tmp/oneos_probe_app_tmp\n" +
            "rm -rf \"$T\" && mkdir -p \"$T\"\n" +
            "\"$BB\" unzip -oq \"$SJAR\" 'classes*.dex' -d \"$T\" 2>/dev/null\n" +
            "for d in \"$T\"/classes*.dex; do\n" +
            "  [ -f \"$d\" ] && \"$DEXDUMP\" -f \"$d\" 2>/dev/null | awk '/Class descriptor/{k=($0~/Landroid\\/os\\/IInstalld\\$Stub(;|\\\\$Proxy;)/)} k{print}' >> \"$T/idump.txt\"\n" +
            "done\n" +
            "awk '\n" +
            "  function hex2dec(s,  i,d,c,h){h=\"0123456789abcdef\";s=tolower(s);sub(/^0x/,\"\",s);d=0;for(i=1;i<=length(s);i++){c=index(h,substr(s,i,1))-1;if(c<0)return -1;d=d*16+c}return d}\n" +
            "  BEGIN{q=sprintf(\"%c\",39)}\n" +
            "  /Class descriptor/{sec=($0~/IInstalld\\$Stub;/)?\"s\":(($0~/IInstalld\\$Stub\\$Proxy;/)?\"p\":\"\");cn=\"\";ct=\"\";next}\n" +
            "  sec==\"s\"&&/^[[:space:]]*name[[:space:]]*:/{split($0,a,q);cn=(length(a)>=2&&substr(a[2],1,12)==\"TRANSACTION_\")?substr(a[2],13):\"\";ct=\"\";next}\n" +
            "  sec==\"s\"&&cn!=\"\"&&/^[[:space:]]*type[[:space:]]*:/{split($0,a,q);ct=(length(a)>=2)?a[2]:\"\";next}\n" +
            "  sec==\"s\"&&cn!=\"\"&&ct==\"I\"&&/^[[:space:]]*value[[:space:]]*:/{v=$NF;if(v~/^0[xX]/)v=hex2dec(v);if(v~/^[0-9]+$/)codes[cn]=v+0;cn=\"\";next}\n" +
            "  sec==\"p\"&&/^[[:space:]]*name[[:space:]]*:/{split($0,a,q);cn=(length(a)>=2)?a[2]:\"\";next}\n" +
            "  sec==\"p\"&&cn!=\"\"&&/^[[:space:]]*type[[:space:]]*:/{split($0,a,q);if(length(a)>=2&&!(cn in sigs))sigs[cn]=a[2];cn=\"\";next}\n" +
            "  END{for(n in codes) printf \"%04d %s %s\\n\", codes[n], n, (n in sigs?sigs[n]:\"-\")}\n" +
            "' \"$T/idump.txt\" | sort -n | awk '{printf \"%s %d %s\\n\",$2,$1+0,$3}' > /data/local/tmp/host_installd_yaap.txt\n" +
            "rm -rf \"$T\"\n" +
            "echo \"Cikarilan metod sayisi: $(wc -l < /data/local/tmp/host_installd_yaap.txt)\"\n" +
            "sha256sum /data/local/tmp/host_installd_yaap.txt\n" +
            "awk 'BEGIN{e[\"createUserData\"]=1;e[\"setFirstBoot\"]=3;e[\"createAppData\"]=4;e[\"createAppDataBatched\"]=5;e[\"restoreconAppData\"]=7;e[\"fixupAppData\"]=12;e[\"getAppSize\"]=13;e[\"getUserSize\"]=14;e[\"getExternalSize\"]=15;e[\"getAppCrates\"]=16;e[\"getUserCrates\"]=17;e[\"controlDexOptBlocking\"]=21;e[\"mergeProfiles\"]=23;e[\"dumpProfiles\"]=24;e[\"copySystemProfile\"]=25;e[\"createProfileSnapshot\"]=29;e[\"linkNativeLibraryDirectory\"]=33;e[\"createOatDirs\"]=34;e[\"linkFile\"]=35;e[\"hashSecondaryDexFile\"]=39;e[\"invalidateMounts\"]=40;e[\"isQuotaSupported\"]=41;e[\"prepareAppProfile\"]=42;e[\"tryMountDataMirror\"]=47;e[\"getOdexVisibility\"]=51;e[\"createFsveritySetupAuthToken\"]=53;e[\"enableFsverity\"]=54}\n" +
            "{c[$1]=$2+0} END{ok=0;bad=0;fsv=0;for(k in e){if(!(k in c)){print \"EKSIK: \" k;bad++}else if(c[k]!=e[k]){print \"FARK: \" k \" yaap=\" c[k] \" oneos=\" e[k];bad++;if((k==\"createFsveritySetupAuthToken\"&&c[k]==52)||(k==\"enableFsverity\"&&c[k]==53))fsv++}else{ok++}}; if(bad==0){st=\"TAM_UYUM\"}else if(bad==2&&fsv==2){st=\"FSVERITY_2SLOT_KAYIK_REMAP_HAZIR\"}else{st=\"YAMA_GEREKLI\"}; print \"ALLOWED_27_ESLESME=\" st \" (ok=\" ok \", bad=\" bad \")\"}\n" +
            "' /data/local/tmp/host_installd_yaap.txt\n";
        return execSu(script, 30);
    }

    private static Result execSu(String script, int timeoutSec) {
        Process p = null;
        try {
            p = new ProcessBuilder("su", "-c", "/system/bin/sh").redirectErrorStream(true).start();
            try (OutputStream os = p.getOutputStream()) {
                os.write(script.getBytes(StandardCharsets.UTF_8));
                os.write("\nexit\n".getBytes(StandardCharsets.UTF_8));
                os.flush();
            }
            StringBuilder sb = new StringBuilder();
            try (BufferedReader br = new BufferedReader(new InputStreamReader(p.getInputStream(), StandardCharsets.UTF_8))) {
                String line;
                while ((line = br.readLine()) != null) {
                    sb.append(line).append('\n');
                }
            }
            boolean finished = p.waitFor(timeoutSec, TimeUnit.SECONDS);
            if (!finished) {
                p.destroyForcibly();
                return new Result(-1, sb.toString() + "\n[Zaman asimi]", true);
            }
            return new Result(p.exitValue(), sb.toString(), false);
        } catch (Throwable t) {
            if (p != null) {
                try { p.destroyForcibly(); } catch (Throwable ignored) {}
            }
            return new Result(-1, "su calistirilamadi: " + t.getMessage() + "\nKernelSU yöneticisinden uygulamaya root izni ver.", false);
        }
    }
}
