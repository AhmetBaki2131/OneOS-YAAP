#!/system/bin/sh
set -e
export PATH=/data/data/com.termux/files/usr/bin:/system/bin:$PATH
export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib

ANDROID_JAR=/data/data/com.termux/files/home/HyperOSP/.android-sdk/platforms/android-37.0/android.jar
STG=/data/local/tmp/oneos_yaap_app_src
WORK=/data/local/tmp/oneos_yaap_build

rm -rf "$WORK"
mkdir -p "$WORK/gen" "$WORK/classes"
cp -r "$STG/res" "$WORK/res"
cp -f "$STG/AndroidManifest.xml" "$WORK/AndroidManifest.xml"

# Compile R.java via aapt and package base resources
aapt package -f -m -J "$WORK/gen" -M "$WORK/AndroidManifest.xml" -S "$WORK/res" -I "$ANDROID_JAR" -F "$WORK/unsigned.apk"

javac -encoding UTF-8 -source 11 -target 11 -cp "$ANDROID_JAR" -d "$WORK/classes" $(find "$WORK/gen" "$STG/src" -name "*.java")
d8 --lib "$ANDROID_JAR" --output "$WORK" $(find "$WORK/classes" -name "*.class")
cd "$WORK" && zip -j -0 "$WORK/unsigned.apk" "$WORK/classes.dex" >/dev/null
zipalign -f -p 4 "$WORK/unsigned.apk" "$WORK/aligned.apk"
apksigner sign --ks /data/local/tmp/baki_lg.jks --ks-pass pass:123456 --out "$WORK/OneOS-YAAP.apk" "$WORK/aligned.apk"

pm install -r "$WORK/OneOS-YAAP.apk"
dumpsys package com.baki.oneos.yaap | grep -E "versionCode|versionName"
echo "ONEOS_YAAP_COMPANION_INSTALLED"
