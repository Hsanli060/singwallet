package com.singwallet.app.security

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

/**
 * 原生 SWBK v1 跨平台加密备份容器编解码器.
 *
 * 严格对齐 `docs/跨平台架构与数据规范.md` §5：
 * - 46 字节 Big-Endian Header：
 *   - 0x00..0x03: Magic Number `SWBK` (4B)
 *   - 0x04..0x05: Version `0x0001` (uint16 Big-Endian)
 *   - 0x06..0x09: KDF Iterations (uint32 Big-Endian, 默认 100_000)
 *   - 0x0A..0x19: KDF Salt (16B)
 *   - 0x1A..0x25: AES-GCM IV (12B)
 *   - 0x26..0x2D: Ciphertext Payload Length N (uint64 Big-Endian, 不含 16B Tag)
 * - 0x2E..(0x2E+N-1): AES-256-GCM Ciphertext
 * - (0x2E+N)..(0x2E+N+15): AES-256-GCM 16B Auth Tag
 *
 * 密码学算法：PBKDF2WithHmacSHA256 (256-bit) + AES/GCM/NoPadding (128-bit Tag, 6B AAD = `SWBK\u0000\u0001`)
 */
object SwbkCryptoCodec {

    private val MAGIC = byteArrayOf(0x53, 0x57, 0x42, 0x4B) // "SWBK"
    const val VERSION_V1: Short = 0x0001
    const val DEFAULT_ITERATIONS: Int = 100_000
    private const val MAX_ITERATIONS: Long = 10_000_000L

    private const val SALT_LEN = 16
    private const val IV_LEN = 12
    private const val TAG_LEN_BYTES = 16
    private const val GCM_TAG_BITS = 128
    private const val HEADER_LEN = 46
    private const val AAD_LEN = 6
    private const val AES_KEY_BITS = 256

    private val secureRandom = SecureRandom()

    /**
     * 快速检测字节流前 6 字节是否为 SWBK v1 容器魔数与版本号
     */
    fun isSwbkContainer(bytes: ByteArray?): Boolean {
        if (bytes == null || bytes.size < HEADER_LEN + TAG_LEN_BYTES) return false
        return bytes[0] == MAGIC[0] &&
            bytes[1] == MAGIC[1] &&
            bytes[2] == MAGIC[2] &&
            bytes[3] == MAGIC[3] &&
            bytes[4] == 0x00.toByte() &&
            bytes[5] == 0x01.toByte()
    }

    /**
     * 将 UTF-8 明文使用口令加密为 SWBK v1 二进制容器
     */
    fun encrypt(
        plainUtf8: String,
        password: String,
        iterations: Int = DEFAULT_ITERATIONS
    ): ByteArray {
        require(password.isNotEmpty()) { "Backup password must not be empty" }
        require(iterations > 0 && iterations <= MAX_ITERATIONS) { "Invalid PBKDF2 iterations: $iterations" }

        val plainBytes = plainUtf8.toByteArray(Charsets.UTF_8)
        val salt = ByteArray(SALT_LEN).also { secureRandom.nextBytes(it) }
        val iv = ByteArray(IV_LEN).also { secureRandom.nextBytes(it) }

        val keyBytes = deriveAesKey(password, salt, iterations)
        try {
            val aad = byteArrayOf(
                MAGIC[0], MAGIC[1], MAGIC[2], MAGIC[3],
                ((VERSION_V1.toInt() ushr 8) and 0xFF).toByte(),
                (VERSION_V1.toInt() and 0xFF).toByte()
            )
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(keyBytes, "AES"), GCMParameterSpec(GCM_TAG_BITS, iv))
            cipher.updateAAD(aad, 0, AAD_LEN)
            val cipherAndTag = cipher.doFinal(plainBytes)

            val payloadLen = (cipherAndTag.size - TAG_LEN_BYTES).toLong()
            require(payloadLen >= 0L) { "Invalid GCM output size" }

            val outBuf = ByteBuffer.allocate(HEADER_LEN + cipherAndTag.size)
                .order(ByteOrder.BIG_ENDIAN)
            outBuf.put(MAGIC)
            outBuf.putShort(VERSION_V1)
            outBuf.putInt(iterations)
            outBuf.put(salt)
            outBuf.put(iv)
            outBuf.putLong(payloadLen)
            outBuf.put(cipherAndTag)
            return outBuf.array()
        } finally {
            keyBytes.fill(0)
        }
    }

    /**
     * 解密 SWBK v1 二进制容器并返回 UTF-8 明文 JSON
     */
    fun decrypt(swbkBytes: ByteArray, password: String): String {
        require(password.isNotEmpty()) { "Backup password must not be empty" }
        require(swbkBytes.size >= HEADER_LEN + TAG_LEN_BYTES) {
            "Invalid SWBK container size: ${swbkBytes.size}"
        }

        val buf = ByteBuffer.wrap(swbkBytes).order(ByteOrder.BIG_ENDIAN)
        val magic = ByteArray(4).also { buf.get(it) }
        require(magic.contentEquals(MAGIC)) { "Invalid SWBK magic header" }

        val version = buf.short
        require(version == VERSION_V1) { "Unsupported SWBK version: $version" }

        val iterationsUnsigned = buf.int.toLong() and 0xFFFFFFFFL
        require(iterationsUnsigned in 1L..MAX_ITERATIONS) {
            "Invalid PBKDF2 iterations in header: $iterationsUnsigned"
        }

        val salt = ByteArray(SALT_LEN).also { buf.get(it) }
        val iv = ByteArray(IV_LEN).also { buf.get(it) }
        val payloadLen = buf.long

        val expectedTotal = HEADER_LEN.toLong() + payloadLen + TAG_LEN_BYTES.toLong()
        require(payloadLen >= 0L && expectedTotal == swbkBytes.size.toLong()) {
            "Corrupted SWBK payload length: payloadLen=$payloadLen, total=${swbkBytes.size}"
        }

        val keyBytes = deriveAesKey(password, salt, iterationsUnsigned.toInt())
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(keyBytes, "AES"), GCMParameterSpec(GCM_TAG_BITS, iv))
            cipher.updateAAD(swbkBytes, 0, AAD_LEN)
            val plainBytes = cipher.doFinal(
                swbkBytes,
                HEADER_LEN,
                (payloadLen + TAG_LEN_BYTES).toInt()
            )
            return String(plainBytes, Charsets.UTF_8)
        } finally {
            keyBytes.fill(0)
        }
    }

    private fun deriveAesKey(password: String, salt: ByteArray, iterations: Int): ByteArray {
        val spec = PBEKeySpec(password.toCharArray(), salt, iterations, AES_KEY_BITS)
        return try {
            val factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
            factory.generateSecret(spec).encoded
        } finally {
            spec.clearPassword()
        }
    }
}
