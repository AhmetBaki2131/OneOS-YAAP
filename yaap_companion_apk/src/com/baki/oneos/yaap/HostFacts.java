package com.baki.oneos.yaap;

import android.app.KeyguardManager;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.BatteryManager;
import android.os.Build;
import android.os.Environment;
import android.os.StatFs;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

/**
 * Non-root device & OneOS-compatibility probe adapted for YAAP Android 17 (SM-A055F / MT6768).
 */
public final class HostFacts {

    public enum Level { OK, INFO, WARN, BLOCK }

    public static final class CheckItem {
        public final String id;
        public final Level level;
        public final String title;
        public final String detail;

        public CheckItem(String id, Level level, String title, String detail) {
            this.id = id;
            this.level = level;
            this.title = title;
            this.detail = detail;
        }
    }

    public static final class Snapshot {
        public String brand = "";
        public String manufacturer = "";
        public String model = "";
        public String vendorModel = "";
        public String device = "";
        public String bootloader = "";
        public String socManufacturer = "";
        public String socModel = "";
        public String platform = "";
        public String hardware = "";
        public String oneUiRaw = "";
        public String systemFingerprint = "";
        public String yaapVersion = "";
        public String androidRelease = "";
        public int sdk = 0;
        public String vendorApi = "";
        public String kernel = "";
        public List<String> abis64 = new ArrayList<>();
        public Set<String> cpuFeatures = new LinkedHashSet<>();
        public int cpuCores = 0;
        public long freeDataBytes = -1L;
        public long totalDataBytes = -1L;
        public int batteryPercent = -1;
        public boolean charging = false;
        public float batteryTempC = Float.NaN;
        public Boolean screenLockSet = null;
        public boolean rootManagerDetected = false;
        public String detectedRootHint = "Bulunamadi";
    }

    private static volatile Method sPropGetMethod = null;

    public static String getProp(String key) {
        try {
            if (sPropGetMethod == null) {
                Class<?> sp = Class.forName("android.os.SystemProperties");
                sPropGetMethod = sp.getMethod("get", String.class, String.class);
            }
            Object v = sPropGetMethod.invoke(null, key, "");
            return v != null ? v.toString().trim() : "";
        } catch (Throwable ignored) {
            return "";
        }
    }

    public static Snapshot collect(Context ctx) {
        Snapshot s = new Snapshot();
        s.brand = nonEmpty(getProp("ro.product.brand"), Build.BRAND);
        s.manufacturer = nonEmpty(getProp("ro.product.manufacturer"), Build.MANUFACTURER);
        s.model = nonEmpty(getProp("ro.product.model"), Build.MODEL);
        s.vendorModel = getProp("ro.product.vendor.model");
        s.device = firstNonEmpty(getProp("ro.product.device"), getProp("ro.product.vendor.device"), Build.DEVICE);
        s.bootloader = nonEmpty(Build.BOOTLOADER, getProp("ro.bootloader"));
        s.socManufacturer = nonEmpty(getProp("ro.soc.manufacturer"), Build.SOC_MANUFACTURER);
        s.platform = getProp("ro.board.platform");
        s.hardware = nonEmpty(getProp("ro.hardware"), Build.HARDWARE);
        String rawSoc = nonEmpty(getProp("ro.soc.model"), Build.SOC_MODEL);
        if (rawSoc.isEmpty() && s.platform.toLowerCase(Locale.ROOT).startsWith("mt")) {
            rawSoc = s.platform.toUpperCase(Locale.ROOT);
        } else if ("MT6769V/CZ".equalsIgnoreCase(rawSoc) || "mt6768".equalsIgnoreCase(s.platform)) {
            if (!rawSoc.isEmpty() && !"MT6768".equalsIgnoreCase(rawSoc)) {
                rawSoc = "MT6768 (" + rawSoc + ")";
            }
        }
        s.socModel = rawSoc;
        s.oneUiRaw = getProp("ro.build.version.oneui");
        s.systemFingerprint = getProp("ro.system.build.fingerprint");
        s.yaapVersion = firstNonEmpty(getProp("ro.yaap.version"), getProp("ro.yaap.build.version"), s.systemFingerprint, getProp("ro.build.display.id"));
        s.androidRelease = Build.VERSION.RELEASE != null ? Build.VERSION.RELEASE : "";
        s.sdk = Build.VERSION.SDK_INT;
        s.vendorApi = firstNonEmpty(getProp("ro.vendor.api_level"), getProp("ro.board.api_level"));
        s.kernel = System.getProperty("os.version", "");
        s.abis64 = Arrays.asList(Build.SUPPORTED_64_BIT_ABIS);

        parseCpuInfo(s);
        readStorage(s);
        readBattery(ctx, s);
        s.screenLockSet = readScreenLock(ctx);
        detectRootHint(s);
        return s;
    }

    public static List<CheckItem> evaluate(Snapshot s) {
        List<CheckItem> list = new ArrayList<>();

        boolean isSamsung = "samsung".equalsIgnoreCase(s.brand) || "samsung".equalsIgnoreCase(s.manufacturer);
        if (isSamsung) {
            list.add(new CheckItem("hw", Level.OK, "Samsung donanım doğrulandı",
                s.model + " (" + s.device + ") • Bootloader: " + nonEmpty(s.bootloader, "?")));
        } else {
            list.add(new CheckItem("hw", Level.BLOCK, "Samsung donanım görünmüyor",
                "Brand=" + s.brand + ", Model=" + s.model));
        }

        if (s.abis64.contains("arm64-v8a")) {
            list.add(new CheckItem("abi", Level.OK, "64-bit ARMv8 (arm64-v8a) uyumlu",
                "Çekirdek sayısı: " + s.cpuCores + ", asimd=" + hasFeat(s, "asimd") + ", crc32=" + hasFeat(s, "crc32")));
        } else {
            list.add(new CheckItem("abi", Level.BLOCK, "arm64-v8a eksik",
                "Desteklenen 64-bit ABI: " + s.abis64));
        }

        boolean isYaapSys = s.systemFingerprint.toLowerCase(Locale.ROOT).contains("yaap")
                || s.yaapVersion.toLowerCase(Locale.ROOT).contains("yaap");
        if (isYaapSys && !s.oneUiRaw.isEmpty()) {
            list.add(new CheckItem("rom", Level.WARN, "YAAP 17 Ev Sahibi (Modül One UI Spoof: " + s.oneUiRaw + ")",
                "Sistem YAAP (" + s.systemFingerprint + "), ancak bir modül ro.build.version.oneui=" + s.oneUiRaw
                    + " (One UI <8.0) veriyor. Resmi OneOS bunu desteklemez; YAAP uyarlama modu + IInstalld 52/53 yaması gerekir."));
        } else if (s.oneUiRaw.isEmpty()) {
            list.add(new CheckItem("rom", Level.WARN, "YAAP / Custom AOSP Ev Sahibi (One UI yok)",
                "Resmi OneOS APK 'ro.build.version.oneui' arayıp engeller. YAAP 17 uyarlaması gerekli (" + nonEmpty(s.yaapVersion, "AOSP") + ")."));
        } else {
            list.add(new CheckItem("rom", Level.OK, "One UI tespit edildi", "ro.build.version.oneui=" + s.oneUiRaw));
        }

        if (s.sdk == 37) {
            list.add(new CheckItem("sdk", Level.OK, "Android 17 (SDK 37) eşleşmesi tamam",
                "SDK 37 misafir imajlarıyla uyumlu. En küçük ve uyumlu adaylar: LineageOS 24 (1.08 GB) ve Nothing OS 5.0 A (3.07 GB)."));
        } else {
            list.add(new CheckItem("sdk", Level.WARN, "Android SDK " + s.sdk,
                "OneOS ana imajları Android 17 (SDK 37) ister."));
        }

        boolean hasSve2 = s.cpuFeatures.contains("sve2");
        boolean hasSme = s.cpuFeatures.contains("sme");
        if (hasSve2 && hasSme) {
            list.add(new CheckItem("isa", Level.OK, "Tüm CPU ISA özellikleri mevcut (SVE2/SME)",
                "Pixel 11 dahil tüm misafir imajlar desteklenir."));
        } else {
            list.add(new CheckItem("isa", Level.WARN, "Yonga Seti: " + nonEmpty(s.socModel, s.platform) + " (ARMv8.2 — SVE/SVE2/SME yok)",
                "Pixel 11 (SVE2) ve Pixel 9 Pro XL (ARMv8.2 SIGILL) çalışmaz. Uyumlu adaylar: LineageOS 24, Nothing OS 5.0 (A), Infinity-X 4.1, HyperOS (GMS'siz) ve ColorOS 17 (alan yeterse)."));
        }

        if (Boolean.TRUE.equals(s.screenLockSet)) {
            list.add(new CheckItem("lock", Level.BLOCK, "Ekran kilidi aktif!",
                "Geçiş (Switch) öncesi Ayarlar > Güvenlik > Ekran kilidini 'Yok' veya 'Kaydır' yapmalısın; aksi halde hata durumunda veri sıfırlama gerekebilir."));
        } else if (Boolean.FALSE.equals(s.screenLockSet)) {
            list.add(new CheckItem("lock", Level.OK, "Ekran kilidi kapalı (güvenli)",
                "Switch sırasında ana sistem şifreleme kilidi sorunu yaşanmaz."));
        } else {
            list.add(new CheckItem("lock", Level.WARN, "Ekran kilidi okunamadı", "Durum elle doğrulanmalı."));
        }

        double freeGb = s.freeDataBytes > 0 ? (s.freeDataBytes / (1024.0 * 1024.0 * 1024.0)) : -1.0;
        if (freeGb >= 24.0) {
            list.add(new CheckItem("space", Level.OK,
                String.format(Locale.US, "/data boş alan geniş (%.1f GB)", freeGb),
                "ColorOS 17 (~22 GB imaj) dahil tüm uyumlu imajlar ve misafir /data için yeterli."));
        } else if (freeGb >= 12.0) {
            list.add(new CheckItem("space", Level.OK,
                String.format(Locale.US, "/data boş alan orta/yeterli (%.1f GB)", freeGb),
                "LineageOS 24 (~3.4 GB), Nothing OS 5.0 A (~9 GB) ve Infinity-X (~10 GB) sığar; ColorOS 17 (~22+ GB) için daha fazla yer gerekir."));
        } else if (freeGb > 0) {
            list.add(new CheckItem("space", Level.BLOCK,
                String.format(Locale.US, "/data boş alan yetersiz (%.1f GB)", freeGb),
                "En az 12-18 GB boş alan açılmalı."));
        }

        if (s.batteryPercent >= 0) {
            boolean batOk = (s.batteryPercent >= 30 || s.charging) && (Float.isNaN(s.batteryTempC) || s.batteryTempC < 42f);
            list.add(new CheckItem("bat", batOk ? Level.OK : Level.BLOCK,
                String.format(Locale.US, "Pil: %%%d (%s, %.1f°C)", s.batteryPercent, s.charging ? "Şarj oluyor" : "Pil", s.batteryTempC),
                batOk ? "OneOS pil/ısı sınırına uygun (>=%30 veya şarjda, <42°C)." : "Geçiş için en az %30 pil (veya şarj) ve <42°C gerekir."));
        }

        list.add(new CheckItem("roothint", s.rootManagerDetected ? Level.OK : Level.INFO,
            "Root göstergesi: " + s.detectedRootHint,
            "Kesin doğrulama için aşağıdaki 'Root & Kernel Kontrol (su)' butonunu çalıştır."));

        return list;
    }

    private static String hasFeat(Snapshot s, String f) {
        return s.cpuFeatures.contains(f) ? "evet" : "hayır";
    }

    private static void parseCpuInfo(Snapshot s) {
        File f = new File("/proc/cpuinfo");
        if (!f.canRead()) return;
        try (BufferedReader br = new BufferedReader(new FileReader(f))) {
            String line;
            while ((line = br.readLine()) != null) {
                int idx = line.indexOf(':');
                if (idx <= 0) continue;
                String k = line.substring(0, idx).trim().toLowerCase(Locale.ROOT);
                String v = line.substring(idx + 1).trim();
                if ("processor".equals(k)) {
                    s.cpuCores++;
                } else if ("features".equals(k)) {
                    for (String tok : v.split("\\s+")) {
                        if (!tok.isEmpty()) s.cpuFeatures.add(tok.toLowerCase(Locale.ROOT));
                    }
                }
            }
        } catch (Throwable ignored) {}
    }

    private static void readStorage(Snapshot s) {
        try {
            StatFs sf = new StatFs(Environment.getDataDirectory().getPath());
            s.freeDataBytes = sf.getAvailableBytes();
            s.totalDataBytes = sf.getTotalBytes();
        } catch (Throwable ignored) {}
    }

    private static void readBattery(Context ctx, Snapshot s) {
        try {
            Intent bi = ctx.registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
            if (bi == null) return;
            int level = bi.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
            int scale = bi.getIntExtra(BatteryManager.EXTRA_SCALE, 100);
            int status = bi.getIntExtra(BatteryManager.EXTRA_STATUS, -1);
            int tempTenths = bi.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Integer.MIN_VALUE);
            if (level >= 0 && scale > 0) s.batteryPercent = (level * 100) / scale;
            s.charging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL;
            if (tempTenths != Integer.MIN_VALUE) s.batteryTempC = tempTenths / 10f;
        } catch (Throwable ignored) {}
    }

    private static Boolean readScreenLock(Context ctx) {
        try {
            KeyguardManager km = (KeyguardManager) ctx.getSystemService(Context.KEYGUARD_SERVICE);
            return km != null ? km.isDeviceSecure() : null;
        } catch (Throwable ignored) {
            return null;
        }
    }

    private static void detectRootHint(Snapshot s) {
        String[] paths = {"/data/adb/ksu/bin/busybox", "/data/adb/ksud", "/system/bin/su", "/vendor/bin/su"};
        for (String p : paths) {
            if (new File(p).exists()) {
                s.rootManagerDetected = true;
                s.detectedRootHint = "Bulundu (" + p + ")";
                return;
            }
        }
        String ksuVer = getProp("ro.boot.ksu");
        if (!ksuVer.isEmpty()) {
            s.rootManagerDetected = true;
            s.detectedRootHint = "KernelSU prop: " + ksuVer;
        }
    }

    private static String nonEmpty(String a, String b) {
        if (a != null && !a.trim().isEmpty()) return a.trim();
        return b != null ? b.trim() : "";
    }

    private static String firstNonEmpty(String... vals) {
        for (String v : vals) {
            if (v != null && !v.trim().isEmpty()) return v.trim();
        }
        return "";
    }
}
