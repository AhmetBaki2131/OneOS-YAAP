param(
    [Parameter(Mandatory=$true)]
    [string]$Target,
    [string]$AdbPath = "C:\Users\Baki\.gemini\antigravity\brain\98f58b36-003b-4e7e-8970-674d07e2db74\scratch\pt\platform-tools\adb.exe"
)

$ErrorActionPreference = "Stop"
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path

& $AdbPath connect $Target
& $AdbPath -s $Target shell "rm -rf /data/local/tmp/oneos_yaap_app_src && mkdir -p /data/local/tmp/oneos_yaap_app_src/src/com/baki/oneos/yaap /data/local/tmp/oneos_yaap_app_src/res/values /data/local/tmp/oneos_yaap_app_src/res/drawable"
& $AdbPath -s $Target push (Join-Path $dir "AndroidManifest.xml") /data/local/tmp/oneos_yaap_app_src/AndroidManifest.xml
& $AdbPath -s $Target push (Join-Path $dir "res/values/styles.xml") /data/local/tmp/oneos_yaap_app_src/res/values/styles.xml
& $AdbPath -s $Target push (Join-Path $dir "res/drawable/bg_glass_card.xml") /data/local/tmp/oneos_yaap_app_src/res/drawable/bg_glass_card.xml
& $AdbPath -s $Target push (Join-Path $dir "res/drawable/bg_pill_btn.xml") /data/local/tmp/oneos_yaap_app_src/res/drawable/bg_pill_btn.xml

Get-ChildItem (Join-Path $dir "src/com/baki/oneos/yaap") -File | ForEach-Object {
    & $AdbPath -s $Target push $_.FullName "/data/local/tmp/oneos_yaap_app_src/src/com/baki/oneos/yaap/$($_.Name)"
}

& $AdbPath -s $Target push (Join-Path $dir "build_on_phone.sh") /data/local/tmp/build_oneos_yaap.sh
& $AdbPath -s $Target shell "tr -d '\r' < /data/local/tmp/build_oneos_yaap.sh > /data/local/tmp/build_oneos_yaap_lf.sh && su -c 'sh /data/local/tmp/build_oneos_yaap_lf.sh'"
