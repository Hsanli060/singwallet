package com.singwallet.app.security

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder
import javax.crypto.AEADBadTagException

class SwbkCryptoCodecTest {

    @Test
    fun encryptAndDecrypt_roundTrip_matchesSpecHeaderAndPayload() {
        val sampleJson = """{"manifest":{"version":"1.0","platform":"Android"},"transactions":[{"id":"tx1","amount":32.5}]}"""
        val password = "SingWallet#StrongPassword2026"

        val swbk = SwbkCryptoCodec.encrypt(sampleJson, password)
        assertTrue(SwbkCryptoCodec.isSwbkContainer(swbk))

        val buf = ByteBuffer.wrap(swbk).order(ByteOrder.BIG_ENDIAN)
        val magic = ByteArray(4).also { buf.get(it) }
        assertArrayEquals("SWBK".toByteArray(Charsets.US_ASCII), magic)

        val version = buf.short
        assertEquals(0x0001.toShort(), version)

        val iterations = buf.int
        assertEquals(100_000, iterations)

        buf.position(0x26)
        val payloadLen = buf.long
        assertEquals(swbk.size.toLong() - 46L - 16L, payloadLen)

        val decrypted = SwbkCryptoCodec.decrypt(swbk, password)
        assertEquals(sampleJson, decrypted)
    }

    @Test(expected = AEADBadTagException::class)
    fun decrypt_wrongPassword_throwsAeadBadTag() {
        val swbk = SwbkCryptoCodec.encrypt("""{"ok":true}""", "correct-password")
        SwbkCryptoCodec.decrypt(swbk, "wrong-password")
    }

    @Test(expected = AEADBadTagException::class)
    fun decrypt_tamperedCiphertext_throwsAeadBadTag() {
        val swbk = SwbkCryptoCodec.encrypt("""{"amount":100}""", "secret")
        swbk[46] = (swbk[46].toInt() xor 0xFF).toByte()
        SwbkCryptoCodec.decrypt(swbk, "secret")
    }

    @Test
    fun isSwbkContainer_rejectsPlainJson() {
        assertFalse(SwbkCryptoCodec.isSwbkContainer("""{"transactions":[]}""".toByteArray()))
    }
}
