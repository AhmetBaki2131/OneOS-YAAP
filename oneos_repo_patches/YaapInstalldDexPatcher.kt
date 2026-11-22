package com.fahadali.oneos.session

import android.content.Context
import com.fahadali.oneos.core.model.Hashes
import com.fahadali.oneos.core.model.InstalldDerivation
import com.fahadali.oneos.core.model.InstalldExpected
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.zip.Adler32
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

/**
 * Dynamically remaps OneOSInstalldProxy transaction codes when a custom ROM's host IInstalld
 * differs from the carried One UI table.
 *
 * Sets from OneOS 0.5.28+ carrying [OneOSInstalldCodes] resolve every host transaction code at
 * runtime from `/data/system/oneos_installd_codes`, so they need no DEX patch and are returned
 * untouched. Older/SDK-36 sets (such as `oxygen16`) still bake `const/16` codes into
 * `OneOSInstalldProxy` and are remapped per host table hash.
 */
object YaapInstalldDexPatcher {

    private val LEGACY_YAAP_REMAP = mapOf(
        "createFsveritySetupAuthToken" to (53 to 52),
        "enableFsverity" to (54 to 53),
    )

    private const val RUNTIME_CODES_CLASS = "Lcom/android/server/pm/OneOSInstalldCodes;"

    private val DALVIK_OP_WIDTHS = intArrayOf(
        1, 1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 1, 1, 1, 1, 1, // 0x00..0x0f
        1, 1, 1, 2, 3, 2, 2, 3, 5, 2, 2, 3, 2, 1, 1, 2, // 0x10..0x1f
        2, 1, 2, 2, 3, 3, 3, 1, 1, 2, 3, 3, 3, 2, 2, 2, // 0x20..0x2f
        2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, // 0x30..0x3f
        1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, // 0x40..0x4f
        2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, // 0x50..0x5f
        2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 3, // 0x60..0x6f
        3, 3, 3, 1, 3, 3, 3, 3, 3, 1, 1, 1, 1, 1, 1, 1, // 0x70..0x7f
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, // 0x80..0x8f
        2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, // 0x90..0x9f
        2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, // 0xa0..0xaf
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, // 0xb0..0xbf
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, // 0xc0..0xcf
        2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, // 0xd0..0xdf
        2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, // 0xe0..0xef
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 4, 4, 3, 3, 2, 2, // 0xf0..0xff
    )

    data class PatchedRef(val sha256: String, val bytes: Long)

    fun dir(ctx: Context): File = File(ctx.applicationContext.filesDir, "oneos-yaap-files").apply { mkdirs() }

    fun cachedFile(ctx: Context, sha256: String, bytes: Long): File? =
        File(dir(ctx), sha256).takeIf { it.isFile && it.length() == bytes }

    private fun svcMetaName(origSha256: String, hostKey: String?): String =
        if (hostKey.isNullOrEmpty()) "meta_$origSha256" else "meta_${origSha256}_$hostKey"

    private fun guardsMetaName(origGuardsSha256: String, origSvcSha256: String, hostKey: String?): String =
        if (hostKey.isNullOrEmpty()) "gmeta_${origGuardsSha256}_${origSvcSha256}" else "gmeta_${origGuardsSha256}_${origSvcSha256}_$hostKey"

    fun cachedMeta(ctx: Context, origSha256: String, hostKey: String? = null): PatchedRef? =
        readMeta(ctx, svcMetaName(origSha256, hostKey))
            ?: if (hostKey != null) readMeta(ctx, svcMetaName(origSha256, null)) else null

    fun cachedGuardsMeta(
        ctx: Context,
        origGuardsSha256: String,
        origSvcSha256: String,
        hostKey: String? = null,
    ): PatchedRef? =
        readMeta(ctx, guardsMetaName(origGuardsSha256, origSvcSha256, hostKey))
            ?: if (hostKey != null) readMeta(ctx, guardsMetaName(origGuardsSha256, origSvcSha256, null)) else null

    private fun readMeta(ctx: Context, metaName: String): PatchedRef? {
        val meta = File(dir(ctx), metaName)
        if (!meta.isFile) return null
        val parts = runCatching { meta.readText().trim().split(' ') }.getOrNull() ?: return null
        if (parts.size != 2) return null
        val sha = parts[0]
        val len = parts[1].toLongOrNull() ?: return null
        if (!Regex("[0-9a-f]{64}").matches(sha) || len <= 0) return null
        return cachedFile(ctx, sha, len)?.let { PatchedRef(sha, len) }
    }

    fun applyToStageList(
        ctx: Context,
        files: List<AppAssets.Staged>,
        derivation: InstalldDerivation?,
        sdk: Int = 37,
    ): List<AppAssets.Staged> {
        if (!InstalldExpected.needsCustomRomRemap(derivation, sdk)) return files
        val svc = files.firstOrNull { it.name == "services_patched.jar" } ?: return files
        val hostKey = InstalldExpected.hostTableHash(derivation)?.take(16) ?: return files
        val remap = InstalldExpected.customRomCodeRemap(derivation, sdk)
        if (remap.isEmpty()) return files

        val svcRef = cachedMeta(ctx, svc.sha256, hostKey) ?: buildPatchedJar(ctx, svc, hostKey, remap)
            ?: return files
        val guards = files.firstOrNull { it.name == "guards.txt" }
        val guardsRef = guards?.let { g ->
            cachedGuardsMeta(ctx, g.sha256, svc.sha256, hostKey)
                ?: buildPatchedGuards(ctx, g, svc.sha256, svcRef.sha256, hostKey)
        }
        return files.map { f ->
            when {
                f.name == "services_patched.jar" -> AppAssets.Staged(f.name, svcRef.sha256, svcRef.bytes, f.source)
                f.name == "guards.txt" && guardsRef != null -> AppAssets.Staged(f.name, guardsRef.sha256, guardsRef.bytes, f.source)
                else -> f
            }
        }
    }

    private fun buildPatchedGuards(
        ctx: Context,
        guards: AppAssets.Staged,
        origSvcSha: String,
        newSvcSha: String,
        hostKey: String,
    ): PatchedRef {
        val outDir = dir(ctx)
        val raw = AppAssets.open(ctx, guards).use { it.readBytes() }.toString(Charsets.UTF_8)
        val re = Regex("(?m)^${Regex.escape(origSvcSha)}(\\s+services_patched\\.jar)\\r?$")
        val updated = re.replace(raw) { m -> "$newSvcSha${m.groupValues[1]}" }
        check(updated != raw) {
            "Custom ROM guards.txt patcher did not find services_patched.jar hash $origSvcSha in guards.txt"
        }
        val outBytes = updated.toByteArray(Charsets.UTF_8)
        val sha = Hashes.sha256(outBytes)
        val finalFile = File(outDir, sha)
        val tmpFile = File(outDir, "g_${guards.sha256}_$hostKey.tmp")
        try {
            tmpFile.writeBytes(outBytes)
            if (finalFile.exists()) finalFile.delete()
            check(tmpFile.renameTo(finalFile)) { "Could not store remapped guards.txt" }
            File(outDir, guardsMetaName(guards.sha256, origSvcSha, hostKey)).writeText("$sha ${outBytes.size}")
            return PatchedRef(sha, outBytes.size.toLong())
        } finally {
            tmpFile.delete()
        }
    }

    private fun buildPatchedJar(
        ctx: Context,
        svc: AppAssets.Staged,
        hostKey: String,
        remap: Map<String, Pair<Int, Int>>,
    ): PatchedRef? {
        val outDir = dir(ctx)
        val tmpSrc = File(outDir, "src_${svc.sha256}.jar")
        val tmpDst = File(outDir, "dst_${svc.sha256}_$hostKey.jar")
        try {
            AppAssets.open(ctx, svc).use { input ->
                FileOutputStream(tmpSrc).use { input.copyTo(it) }
            }
            if (usesRuntimeCodes(tmpSrc)) return null
            patchJarFile(tmpSrc, tmpDst, remap)
            val bytes = tmpDst.length()
            val sha = Hashes.sha256(tmpDst.readBytes())
            val finalFile = File(outDir, sha)
            if (finalFile.exists()) finalFile.delete()
            check(tmpDst.renameTo(finalFile)) { "Could not store remapped services_patched.jar" }
            File(outDir, svcMetaName(svc.sha256, hostKey)).writeText("$sha $bytes")
            return PatchedRef(sha, bytes)
        } finally {
            tmpSrc.delete()
            tmpDst.delete()
        }
    }

    internal fun usesRuntimeCodes(srcJar: File): Boolean {
        ZipFile(srcJar).use { zin ->
            val entries = zin.entries()
            while (entries.hasMoreElements()) {
                val entry = entries.nextElement()
                if (!entry.name.startsWith("classes") || !entry.name.endsWith(".dex")) continue
                val bytes = zin.getInputStream(entry).use { it.readBytes() }
                if (dexHasClass(bytes, RUNTIME_CODES_CLASS)) return true
            }
        }
        return false
    }

    private fun dexHasClass(raw: ByteArray, descriptor: String): Boolean {
        if (raw.size < 0x70 || String(raw, 0, 4, Charsets.US_ASCII) != "dex\n") return false
        val buf = ByteBuffer.wrap(raw).order(ByteOrder.LITTLE_ENDIAN)
        val stringIdsOff = buf.getInt(0x3c)
        val typeIdsOff = buf.getInt(0x44)
        val classDefsSize = buf.getInt(0x60)
        val classDefsOff = buf.getInt(0x64)
        for (i in 0 until classDefsSize) {
            val cidx = buf.getInt(classDefsOff + i * 32)
            val sidx = buf.getInt(typeIdsOff + cidx * 4)
            var pos = buf.getInt(stringIdsOff + sidx * 4)
            while (pos < raw.size && (raw[pos++].toInt() and 0x80) != 0) {
                // skip uleb128 string length
            }
            var end = pos
            while (end < raw.size && raw[end] != 0.toByte()) end++
            if (String(raw, pos, end - pos, Charsets.UTF_8) == descriptor) return true
        }
        return false
    }

    internal fun patchJarFile(srcJar: File, dstJar: File) =
        patchJarFile(srcJar, dstJar, LEGACY_YAAP_REMAP)

    internal fun patchJarFile(srcJar: File, dstJar: File, remap: Map<String, Pair<Int, Int>>) {
        val handled = mutableSetOf<String>()
        ZipFile(srcJar).use { zin ->
            ZipOutputStream(FileOutputStream(dstJar)).use { zout ->
                val entries = zin.entries()
                while (entries.hasMoreElements()) {
                    val entry = entries.nextElement()
                    val rawBytes = zin.getInputStream(entry).use { it.readBytes() }
                    val outBytes = if (entry.name.startsWith("classes") && entry.name.endsWith(".dex")) {
                        val res = patchDexBytes(rawBytes, remap)
                        handled += res.handled
                        res.bytes
                    } else {
                        rawBytes
                    }
                    val copy = ZipEntry(entry.name)
                    copy.time = entry.time
                    if (entry.method == ZipEntry.STORED) {
                        copy.method = ZipEntry.STORED
                        copy.size = outBytes.size.toLong()
                        copy.compressedSize = outBytes.size.toLong()
                        val crc = CRC32()
                        crc.update(outBytes)
                        copy.crc = crc.value
                    } else {
                        copy.method = ZipEntry.DEFLATED
                    }
                    zout.putNextEntry(copy)
                    zout.write(outBytes)
                    zout.closeEntry()
                }
            }
        }
        val missing = remap.keys - handled
        check(missing.isEmpty()) {
            "Custom ROM IInstalld patcher missing methods in OneOSInstalldProxy: ${missing.sorted().joinToString()}"
        }
    }

    private data class DexResult(val bytes: ByteArray, val handled: Set<String>)

    private fun patchDexBytes(src: ByteArray, remap: Map<String, Pair<Int, Int>>): DexResult {
        val raw = src.copyOf()
        val buf = ByteBuffer.wrap(raw).order(ByteOrder.LITTLE_ENDIAN)
        if (raw.size < 0x70 || String(raw, 0, 4, Charsets.US_ASCII) != "dex\n") {
            return DexResult(raw, emptySet())
        }
        val stringIdsOff = buf.getInt(0x3c)
        val typeIdsOff = buf.getInt(0x44)
        val methodIdsOff = buf.getInt(0x5c)
        val classDefsSize = buf.getInt(0x60)
        val classDefsOff = buf.getInt(0x64)

        fun readUleb128(posRef: IntArray): Int {
            var res = 0
            var shift = 0
            while (true) {
                val b = raw[posRef[0]++].toInt() and 0xff
                res = res or ((b and 0x7f) shl shift)
                if ((b and 0x80) == 0) return res
                shift += 7
            }
        }

        fun getString(sidx: Int): String {
            val off = buf.getInt(stringIdsOff + sidx * 4)
            val p = intArrayOf(off)
            readUleb128(p)
            var end = p[0]
            while (end < raw.size && raw[end] != 0.toByte()) end++
            return String(raw, p[0], end - p[0], Charsets.UTF_8)
        }

        fun getType(tidx: Int): String = getString(buf.getInt(typeIdsOff + tidx * 4))

        fun getMethod(midx: Int): Pair<String, String> {
            val base = methodIdsOff + midx * 8
            val cidx = buf.getShort(base).toInt() and 0xffff
            val nidx = buf.getInt(base + 4)
            return getType(cidx) to getString(nidx)
        }

        var modified = false
        val handled = mutableSetOf<String>()

        for (i in 0 until classDefsSize) {
            val base = classDefsOff + i * 32
            val cidx = buf.getInt(base)
            val classDataOff = buf.getInt(base + 24)
            if (classDataOff == 0) continue
            val cname = getType(cidx)
            if (!cname.endsWith("OneOSInstalldProxy;")) continue

            val pos = intArrayOf(classDataOff)
            val sf = readUleb128(pos)
            val inf = readUleb128(pos)
            val dm = readUleb128(pos)
            val vm = readUleb128(pos)
            repeat((sf + inf) * 2) { readUleb128(pos) }

            for (cnt in intArrayOf(dm, vm)) {
                var midx = 0
                for (m in 0 until cnt) {
                    midx += readUleb128(pos)
                    readUleb128(pos) // flags
                    val codeOff = readUleb128(pos)
                    if (codeOff == 0) continue
                    val mname = getMethod(midx).second
                    val mapping = remap[mname] ?: continue

                    val patchedMethod = patchMethodCode(raw, buf, codeOff, mname, mapping.first, mapping.second, ::getMethod)
                    if (patchedMethod.valid) {
                        if (patchedMethod.changed) modified = true
                        handled += mname
                    }
                }
            }
        }

        if (modified) {
            val sha1 = MessageDigest.getInstance("SHA-1").digest(raw.copyOfRange(32, raw.size))
            System.arraycopy(sha1, 0, raw, 12, 20)
            val adler = Adler32()
            adler.update(raw, 12, raw.size - 12)
            buf.putInt(8, adler.value.toInt())
        }
        return DexResult(raw, handled)
    }

    private data class MethodPatch(val valid: Boolean, val changed: Boolean)

    private fun patchMethodCode(
        raw: ByteArray,
        buf: ByteBuffer,
        codeOff: Int,
        mname: String,
        wantOld: Int,
        wantNew: Int,
        getMethod: (Int) -> Pair<String, String>,
    ): MethodPatch {
        val insnsUnits = buf.getInt(codeOff + 12)
        val insnsOff = codeOff + 16
        var sigBridged = false

        // SDK 36 -> SDK 37 bridge for getAppSize (70 units) and getUserSize (61 units):
        // Compact 8-word asBinder()+Parcel.obtain(IBinder) prologue into 4-word Parcel.obtain()
        // and insert the extra Android 17 Parcel argument (writeInt(0) / writeIntArray(null)).
        if ((mname == "getAppSize" && insnsUnits == 70) || (mname == "getUserSize" && insnsUnits == 61)) {
            val w3 = buf.getShort(insnsOff + 3 * 2).toInt() and 0xffff
            val w7 = buf.getShort(insnsOff + 7 * 2).toInt() and 0xffff
            val w11 = buf.getShort(insnsOff + 11 * 2).toInt() and 0xffff
            if (w3 == 0x000c && w7 == 0x000c && w11 == 0x010c) {
                val insns = IntArray(insnsUnits) { k -> buf.getShort(insnsOff + k * 2).toInt() and 0xffff }
                val insertAfter = if (mname == "getAppSize") 32 else 29
                val writeCallFrom = if (mname == "getAppSize") 29 else 26
                val writeMid = insns[writeCallFrom + 1]
                val patched = IntArray(insnsUnits)
                var p = 0
                // 0..3: invoke-static {}, Parcel.obtain(); move-result-object v0
                patched[p++] = insns[8]; patched[p++] = insns[9]; patched[p++] = insns[10]; patched[p++] = 0x000c
                // 4..7: invoke-static {}, Parcel.obtain(); move-result-object v1
                patched[p++] = insns[8]; patched[p++] = insns[9]; patched[p++] = insns[10]; patched[p++] = 0x010c
                for (k in 12 until insertAfter) patched[p++] = insns[k]
                // Extra Android 17 arg: const/4 v3, 0; invoke-virtual {v0, v3}, writeInt/writeIntArray
                patched[p++] = 0x0312; patched[p++] = 0x206e; patched[p++] = writeMid; patched[p++] = 0x0030
                for (k in insertAfter until insnsUnits) patched[p++] = insns[k]
                check(p == insnsUnits)
                for (k in 0 until insnsUnits) buf.putShort(insnsOff + k * 2, patched[k].toShort())
                var endInsns = insnsOff + insnsUnits * 2
                if (insnsUnits % 2 == 1) endInsns += 2
                val startAddr = buf.getInt(endInsns)
                val insnCnt = buf.getShort(endInsns + 4).toInt() and 0xffff
                if (startAddr == 12) {
                    buf.putInt(endInsns, 8)
                    buf.putShort(endInsns + 4, (insnCnt + 4).toShort())
                }
                sigBridged = true
            }
        }

        val units = ArrayList<Pair<Int, Int>>()
        var u = 0
        while (u < insnsUnits) {
            val w0 = buf.getShort(insnsOff + u * 2).toInt() and 0xffff
            val op = w0 and 0xff
            val width = when (w0) {
                0x0100 -> 4 + (buf.getShort(insnsOff + (u + 1) * 2).toInt() and 0xffff) * 2
                0x0200 -> 2 + (buf.getShort(insnsOff + (u + 1) * 2).toInt() and 0xffff) * 4
                0x0300 -> {
                    val ew = buf.getShort(insnsOff + (u + 1) * 2).toInt() and 0xffff
                    val ec = buf.getInt(insnsOff + (u + 2) * 2)
                    4 + (ew * ec + 1) / 2
                }
                else -> DALVIK_OP_WIDTHS[op]
            }
            units += u to op
            u += width
        }

        var transactIdx = -1
        var codeReg = -1
        for (idx in units.indices) {
            val (unit, op) = units[idx]
            if (op != 0x72 && op != 0x78) continue
            val midx = buf.getShort(insnsOff + (unit + 1) * 2).toInt() and 0xffff
            val w2 = buf.getShort(insnsOff + (unit + 2) * 2).toInt() and 0xffff
            val (cls, name) = getMethod(midx)
            if (cls == "Landroid/os/IBinder;" && name == "transact") {
                codeReg = if (op == 0x72) (w2 ushr 4) and 0xf else w2 + 1
                transactIdx = idx
                break
            }
        }
        if (transactIdx < 0 || codeReg < 0) return MethodPatch(valid = false, changed = false)

        for (j in transactIdx - 1 downTo 0) {
            val (unit, op) = units[j]
            val w0 = buf.getShort(insnsOff + unit * 2).toInt() and 0xffff
            if (op == 0x12 && ((w0 ushr 8) and 0xf) == codeReg) {
                val cur = (((w0 ushr 12) and 0xf) shl 28) shr 28
                if (cur == wantNew) return MethodPatch(valid = true, changed = sigBridged)
                if (cur == wantOld && wantNew in -8..7) {
                    buf.putShort(insnsOff + unit * 2, ((w0 and 0x0fff) or ((wantNew and 0xf) shl 12)).toShort())
                    return MethodPatch(valid = true, changed = true)
                }
                return MethodPatch(valid = false, changed = false)
            }
            if (op == 0x13 && ((w0 ushr 8) and 0xff) == codeReg) {
                val immOff = insnsOff + (unit + 1) * 2
                val cur = buf.getShort(immOff).toInt()
                if (cur == wantNew) return MethodPatch(valid = true, changed = sigBridged)
                if (cur == wantOld) {
                    buf.putShort(immOff, wantNew.toShort())
                    return MethodPatch(valid = true, changed = true)
                }
                return MethodPatch(valid = false, changed = false)
            }
            if (op == 0x14 && ((w0 ushr 8) and 0xff) == codeReg) {
                val immOff = insnsOff + (unit + 1) * 2
                val cur = buf.getInt(immOff)
                if (cur == wantNew) return MethodPatch(valid = true, changed = sigBridged)
                if (cur == wantOld) {
                    buf.putInt(immOff, wantNew)
                    return MethodPatch(valid = true, changed = true)
                }
                return MethodPatch(valid = false, changed = false)
            }
        }
        return MethodPatch(valid = false, changed = false)
    }
}
