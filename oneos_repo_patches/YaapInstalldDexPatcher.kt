package com.fahadali.oneos.session

import android.content.Context
import com.fahadali.oneos.core.model.Hashes
import com.fahadali.oneos.core.model.InstalldDerivation
import com.fahadali.oneos.core.model.InstalldExpected
import java.io.ByteArrayOutputStream
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
 * Remaps OneOS's OneOSInstalldProxy fsverity transaction codes on YAAP Android 17 hosts:
 *   createFsveritySetupAuthToken: 53 (0x35) -> 52 (0x34)
 *   enableFsverity:               54 (0x36) -> 53 (0x35)
 *
 * All 25 remaining ALLOWED IInstalld methods (slots 1..51) match SM-A055F YAAP 17 identically.
 */
object YaapInstalldDexPatcher {

    private val REMAP = mapOf(
        "createFsveritySetupAuthToken" to (53 to 52),
        "enableFsverity" to (54 to 53),
    )

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

    fun cachedMeta(ctx: Context, origSha256: String): PatchedRef? {
        val meta = File(dir(ctx), "meta_$origSha256")
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
    ): List<AppAssets.Staged> {
        if (!InstalldExpected.needsYaapFsverityPatch(derivation)) return files
        val svc = files.firstOrNull { it.name == "services_patched.jar" } ?: return files
        val ref = cachedMeta(ctx, svc.sha256) ?: buildPatchedJar(ctx, svc)
        return files.map { f ->
            if (f.name == "services_patched.jar") AppAssets.Staged(f.name, ref.sha256, ref.bytes, f.source) else f
        }
    }

    private fun buildPatchedJar(ctx: Context, svc: AppAssets.Staged): PatchedRef {
        val outDir = dir(ctx)
        val tmpSrc = File(outDir, "src_${svc.sha256}.jar")
        val tmpDst = File(outDir, "dst_${svc.sha256}.jar")
        try {
            AppAssets.open(ctx, svc).use { input ->
                FileOutputStream(tmpSrc).use { input.copyTo(it) }
            }
            patchJarFile(tmpSrc, tmpDst)
            val bytes = tmpDst.length()
            val sha = Hashes.sha256(tmpDst.readBytes())
            val finalFile = File(outDir, sha)
            if (finalFile.exists()) finalFile.delete()
            check(tmpDst.renameTo(finalFile)) { "Could not store YAAP-patched services jar" }
            File(outDir, "meta_${svc.sha256}").writeText("$sha $bytes")
            return PatchedRef(sha, bytes)
        } finally {
            tmpSrc.delete()
            tmpDst.delete()
        }
    }

    internal fun patchJarFile(srcJar: File, dstJar: File) {
        var foundCreate = false
        var foundEnable = false
        ZipFile(srcJar).use { zin ->
            ZipOutputStream(FileOutputStream(dstJar)).use { zout ->
                val entries = zin.entries()
                while (entries.hasMoreElements()) {
                    val entry = entries.nextElement()
                    val rawBytes = zin.getInputStream(entry).use { it.readBytes() }
                    val outBytes = if (entry.name.startsWith("classes") && entry.name.endsWith(".dex")) {
                        val res = patchDexBytes(rawBytes)
                        foundCreate = foundCreate || res.createHandled
                        foundEnable = foundEnable || res.enableHandled
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
        check(foundCreate && foundEnable) {
            "YAAP IInstalld patcher missing fsverity methods in OneOSInstalldProxy (create=$foundCreate, enable=$foundEnable)"
        }
    }

    private data class DexResult(val bytes: ByteArray, val createHandled: Boolean, val enableHandled: Boolean)

    private fun patchDexBytes(src: ByteArray): DexResult {
        val raw = src.copyOf()
        val buf = ByteBuffer.wrap(raw).order(ByteOrder.LITTLE_ENDIAN)
        if (raw.size < 0x70 || String(raw, 0, 4, Charsets.US_ASCII) != "dex\n") {
            return DexResult(raw, createHandled = false, enableHandled = false)
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
        var createOk = false
        var enableOk = false

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
                    val mapping = REMAP[mname] ?: continue

                    val patchedMethod = patchMethodCode(raw, buf, codeOff, mapping.first, mapping.second, ::getMethod)
                    if (patchedMethod.valid) {
                        if (patchedMethod.changed) modified = true
                        if (mname == "createFsveritySetupAuthToken") createOk = true
                        if (mname == "enableFsverity") enableOk = true
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
        return DexResult(raw, createOk, enableOk)
    }

    private data class MethodPatch(val valid: Boolean, val changed: Boolean)

    private fun patchMethodCode(
        raw: ByteArray,
        buf: ByteBuffer,
        codeOff: Int,
        wantOld: Int,
        wantNew: Int,
        getMethod: (Int) -> Pair<String, String>,
    ): MethodPatch {
        val insnsUnits = buf.getInt(codeOff + 12)
        val insnsOff = codeOff + 16
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
            if (op == 0x13 && ((w0 ushr 8) and 0xff) == codeReg) {
                val immOff = insnsOff + (unit + 1) * 2
                val cur = buf.getShort(immOff).toInt()
                if (cur == wantNew) return MethodPatch(valid = true, changed = false)
                if (cur == wantOld) {
                    buf.putShort(immOff, wantNew.toShort())
                    return MethodPatch(valid = true, changed = true)
                }
                return MethodPatch(valid = false, changed = false)
            }
            if (op == 0x14 && ((w0 ushr 8) and 0xff) == codeReg) {
                val immOff = insnsOff + (unit + 1) * 2
                val cur = buf.getInt(immOff)
                if (cur == wantNew) return MethodPatch(valid = true, changed = false)
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
