# OneOS Custom ROM Android 17 (SM-A055F / MT6768) Uyarlama Paketi

Bu dal YAAP ile sınırlı değildir. Android 17 tabanlı özel ROM ev sahiplerini ROM adına göre değil, gerçek `IInstalld` işlem tablosu ile kamera, sensör ve grafik HAL uyumluluğuna göre değerlendirir. YAAP, canlı doğrulamanın yapıldığı ev sahibi ROM'lardan biridir.

GitHub Actions derlemesi güncel kararlı upstream `OneOS 0.5.32` (`v0.5.32`) sürümünü temel alır.

## 2026-11-21 ColorOS 17 canlı doğrulaması

- Kablosuz ADB ile `SM-A055F`, Android 17 / SDK 37 ve `720x1600 @ 300 dpi` doğrulandı.
- Kamera HAL'i 5 aygıt bildiriyor. İsteğe bağlı WingCam aktarımı ColorOS'ta AppOps'a paket yerine `paket/aktivite` gönderdiği için `CAMERA_DISABLED` oluyor; bu aktarım artık varsayılan olarak kapalıdır (`ONEOS_GUEST_WINGCAM=1` ile deneysel olarak açılabilir).
- Çentik yolu ile Oplus ekran deliği koordinatları ayrıldı. ColorOS'un 160 px üst boşluk bırakmasına yol açan yanlış format giderildi; A05 hedefi 58 px delik ve 66 px durum çubuğudur.
- ColorOS Lite uygulama gizleme işlemi varsayılan olarak kapalıdır (`ONEOS_GUEST_COLOROS_LITE=1` ile açılır). Kullanıcının ekran zaman aşımı, uyku ve kamera uygulaması korunur.
- Cihaz sensör servisinde ivmeölçer, ışık ve yakınlık sensörleri çalışıyor. Manyetometre bildirilmediği için pusula yönü bu cihaz/ROM birleşiminde yazılımla üretilemez.

Bu klasör, açık kaynak [`fahadalijaved/OneOS`](../OneOS/README.md) projesini **Samsung Galaxy A05 (`SM-A055F`, MediaTek MT6768 / Helio G85, KernelSU, YAAP Android 17)** ortamına uyarlamak için hazırlanmış araçları ve yamaları içerir.

> [!WARNING]
> **Deneysel Sistem İşlemi:** OneOS benzeri container switch araçları root yetkisiyle `/data` bind mount'ları ve `zygote`/`system_server` değişimi yapar. Probe ve Companion araçları salt okunurdur (risksizdir); gerçek geçiş aşamasına gelmeden önce **tam yedek alınmalı** ve **ekran kilidi (`Yok`/`Kaydır`) kaldırılmalıdır**.

---

## İçerik

1. **`scripts/yaap_a05_probe.sh` & `scripts/run_yaap_probe.ps1`** (Önce çalıştırılacak zararsız test)
   - Telefon açıldığında ADB ile çalıştırılır (hiçbir sistem dosyasına yazmaz).
   - `ro.product.device`, `ro.soc.model`, `/proc/cpuinfo`, KernelSU `busybox` applet'leri (`losetup -r`, `pivot_root`, `nsenter`, `unshare`), `resetprop`, `/dev/watchdog*` düğümleri, `plat_service_contexts` `*` izni, HAL'ler (`composer`, `audio`, `thermal`, `hwservicemanager`), Zygisk Next sürümü ve `/data` boş alanını raporlar.
   - `/system/framework/services.jar` içinden YAAP 17'nin gerçek `IInstalld` tablosunu (`/data/local/tmp/host_installd_yaap.txt`) çıkarıp OneOS'un `ALLOWED` 27 metodu ile birebir karşılaştırır (`EXACT_MATCH` vs `NEEDS_REPATCH`).

2. **`yaap_companion_apk/` (`com.baki.oneos.yaap`)** (Doğrudan telefonda Termux araçlarıyla derlenebilen Android APK)
   - PC'de Android Studio/Gradle olmasa bile telefondaki `javac + d8 + aapt + apksigner` (`android-37.0`) ile derlenir (`deploy_companion.ps1`).
   - Ekrandan cihaz uyumluluğunu, ISA desteğini (Pixel dışındaki SVE gerektirmeyen `LineageOS 24`, `Infinity-X 4.1`, `Nothing OS 5.0 A-series`, `HyperOS`, `ColorOS 17 Find X9U` imajlarına göre), ekran kilidi/pil/depolama durumunu, root + `IInstalld` testini çalıştırır ve geçiş için `GapSplashActivity` sağlar.

3. **`oneos_repo_patches/apply_yaap_patches.ps1`**
   - Upstream [OneOS](../OneOS) reposunu `SM-A055F + YAAP 17` desteğine hazırlayan yamalar:
     - `Soc.kt`: `MT6769V/CZ -> MT6768` normalizasyonu ve `mt6768 -> MT6768 (MediaTek Helio G85)` eşlemesi
     - `CustomRom.kt` & `Gates.kt`: `allowCustomAospHost` opsiyonuyla One UI dışı YAAP 17 ev sahibini bloklamak yerine uyarı ile açma
     - `Profiles.kt` & `ApkSeries.kt`: `Galaxy A05 (SM-A055 / a05m)` profili
     - `InstalldTable.kt`: Samsung'un 85 metodluk hash'i yerine YAAP'taki 27 kritik `ALLOWED` `IInstalld` çağrısının denkliğini ve YAAP'ın `52/53` fsverity kaymasını tanıma
     - `oneos_switch.sh` & `guest_start.sh`: Samsung `imsd` olmayan YAAP ev sahibinde `ims_watchdog` döngüsünü atlama, dil fallback'i ve HIDL `composer@2.x` desteği

4. **`scripts/patch_guest_installd_yaap.py`**
   - Canlı `services.jar` testinin bulduğu `-1` slot kaymasını (`createFsveritySetupAuthToken`: `53 -> 52`, `enableFsverity`: `54 -> 53`) `OneOSInstalldProxy` DEX bayt kodunda yerinde düzelten ve DEX SHA-1/Adler-32 imzalarını yenileyen Python aracı.

---

## Canlı Cihaz Doğrulama Sonucu (`probe_results/`, 2026-11-18)

- **Donanım & KernelSU:** `SM-A055F` (`a05m`), `MT6769V/CZ` (`mt6768`), Kernel `6.6.144-4k`, Android `17` (`SDK 37`), `vendor API 34`, BusyBox (`missing_applets=none`, `losetup -r OK`), `resetprop OK`, `plat_service_contexts_wildcard=1`, `/dev/softdog -> /dev/watchdog1`, `composer3 + composer` mevcut, `/sys/class/leds/lcd-backlight` mevcut, ekran kilidi kapalı, `/data` boş alan **`19 GB` (`102G` toplam / `83G` dolu)**.
- **CPU / ROM Filtresi:** `asimd`, `crc32` var; `sve`/`sve2`/`sme`/`bf16`/`i8mm` yok (`Pixel 11` ve `Pixel 9 Pro XL` çalışmaz; `LineageOS 24` ve `Nothing OS 5.0 A-series` `19 GB` alana sığar).
- **IInstalld 27 ALLOWED Metod:** **25/27 (`1..51`) birebir eşleşti**, sadece `createFsveritySetupAuthToken` (`yaap=52`, `oneos=53`) ve `enableFsverity` (`yaap=53`, `oneos=54`) `-1` slot kayık.

---

## Komutlar

1. Salt-okunur cihaz taraması (güncellemek için):
   ```powershell
   powershell -ExecutionPolicy Bypass -File "c:\Users\Baki\Desktop\New folder\OneOS-YAAP\scripts\run_yaap_probe.ps1" -Target "192.168.1.2:PORT"
   ```
2. Companion APK'yı telefonda derleyip kurmak için:
   ```powershell
   powershell -ExecutionPolicy Bypass -File "c:\Users\Baki\Desktop\New folder\OneOS-YAAP\yaap_companion_apk\deploy_companion.ps1" -Target "192.168.1.2:PORT"
   ```
3. `sets-1` içinden çıkan misafir `services_patched.jar` dosyasını YAAP `52/53` slotlarına uyarlamak için:
   ```sh
   python3 patch_guest_installd_yaap.py services_patched.jar --patch
   ```
4. Yamaları `OneOS` reposuna doğrulamak için (`-DryRun` veya kalıcı uygulamak için parametresiz):
   ```powershell
   powershell -ExecutionPolicy Bypass -File "c:\Users\Baki\Desktop\New folder\OneOS-YAAP\oneos_repo_patches\apply_yaap_patches.ps1" -DryRun
   ```

