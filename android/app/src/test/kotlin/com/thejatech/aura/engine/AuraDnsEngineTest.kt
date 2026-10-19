package com.thejatech.aura.engine

import com.thejatech.aura.model.AuraRuleItem
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

class AuraDnsEngineTest {

    private lateinit var engine: AuraDnsEngine
    private lateinit var pslValidator: AuraPslValidator

    @Before
    fun setUp() {
        engine = AuraDnsEngine()
        pslValidator = AuraPslValidator("""
            com
            org
            net
            co.uk
        """.trimIndent())
    }

    @Test
    fun testNormalizeDomain() {
        assertEquals("google.com", AuraDnsEngine.normalizeDomain("GOOGLE.COM"))
        assertEquals("google.com", AuraDnsEngine.normalizeDomain("https://google.com:443/test"))
        assertEquals("google.com", AuraDnsEngine.normalizeDomain("google.com."))
    }

    @Test
    fun testGenerateCandidateSuffixes() {
        val suffixes = AuraDnsEngine.generateCandidateSuffixes("ads.track.google.com", pslValidator)
        assertEquals(listOf("ads.track.google.com", "track.google.com", "google.com"), suffixes)
    }

    @Test
    fun testEvaluationPrecedence_AllowlistWinsOverBlocklist() {
        // Custom allow on mail.google.com
        val rules = listOf(
            AuraRuleItem(id = "google.com", domain = "google.com", isEnabled = true, isBlocked = true),
            AuraRuleItem(id = "mail.google.com", domain = "mail.google.com", isEnabled = true, isBlocked = false)
        )
        engine.setRules(rules)

        // mail.google.com should be allowed
        val mailDecision = engine.evaluate("mail.google.com", pslValidator)
        assertFalse(mailDecision.isBlocked)
        assertEquals("allowlist", mailDecision.matchedSource)
        assertEquals("mail.google.com", mailDecision.matchedRule)

        // other.google.com should be blocked by custom block rule
        val otherDecision = engine.evaluate("other.google.com", pslValidator)
        assertTrue(otherDecision.isBlocked)
        assertEquals("custom", otherDecision.matchedSource)
        assertEquals("google.com", otherDecision.matchedRule)
    }

    @Test
    fun testEvaluationPrecedence_DefaultCategories() {
        engine.setRules(emptyList())
        engine.setCategories(
            mapOf(
                "Ads" to setOf("doubleclick.net"),
                "Trackers" to setOf("doubleclick.net", "analytics.com")
            )
        )
        engine.setCategoryPreferences(
            mapOf(
                "Ads" to true,
                "Trackers" to true
            )
        )

        val decision = engine.evaluate("ad.doubleclick.net", pslValidator)
        assertTrue(decision.isBlocked)
        assertEquals("default", decision.matchedSource)
        assertEquals(listOf("Ads", "Trackers"), decision.matchedCategories)
    }

    @Test
    fun testEvaluationPrecedence_DisabledDefaultDomainOverride() {
        engine.setRules(emptyList())
        engine.setCategories(
            mapOf(
                "Ads" to setOf("doubleclick.net")
            )
        )
        engine.setCategoryPreferences(mapOf("Ads" to true))
        engine.setDisabledDefaultDomains(setOf("doubleclick.net"))

        val decision = engine.evaluate("ad.doubleclick.net", pslValidator)
        assertFalse(decision.isBlocked)
        assertEquals("none", decision.matchedSource)
        assertEquals(listOf("Ads"), decision.matchedCategories)
    }

    @Test
    fun testCategoryAttribution_AllowlistPreservesMatchedCategories() {
        engine.setRules(
            listOf(
                AuraRuleItem(id = "doubleclick.net", domain = "doubleclick.net", isEnabled = true, isBlocked = false)
            )
        )
        engine.setCategories(
            mapOf(
                "Ads" to setOf("doubleclick.net"),
                "Trackers" to setOf("doubleclick.net")
            )
        )
        engine.setCategoryPreferences(mapOf("Ads" to true, "Trackers" to true))

        val decision = engine.evaluate("ad.doubleclick.net", pslValidator)
        assertFalse(decision.isBlocked)
        assertEquals("allowlist", decision.matchedSource)
        assertEquals("doubleclick.net", decision.matchedRule)
        assertEquals(listOf("Ads", "Trackers"), decision.matchedCategories)
    }

    @Test
    fun testCategoryAttribution_CaseInsensitivePreferences() {
        engine.setRules(emptyList())
        engine.setCategories(
            mapOf(
                "Ads" to setOf("adservice.google.com"),
                "Crypto_mining" to setOf("crypto.miner.org")
            )
        )
        // Preferences formatted with uppercase or spaces like Dart / UI
        engine.setCategoryPreferences(
            mapOf(
                "ADS" to true,
                "Crypto Mining" to true
            )
        )

        val adDecision = engine.evaluate("adservice.google.com", pslValidator)
        assertTrue(adDecision.isBlocked)
        assertEquals("default", adDecision.matchedSource)
        assertEquals(listOf("Ads"), adDecision.matchedCategories)

        val cryptoDecision = engine.evaluate("crypto.miner.org", pslValidator)
        assertTrue(cryptoDecision.isBlocked)
        assertEquals("default", cryptoDecision.matchedSource)
        assertEquals(listOf("Crypto_mining"), cryptoDecision.matchedCategories)
    }

    @Test
    fun testCategoryAttribution_DisabledCategoryPreservesMatchedCategories() {
        engine.setRules(emptyList())
        engine.setCategories(
            mapOf(
                "Ads" to setOf("doubleclick.net")
            )
        )
        // Ads category disabled by user
        engine.setCategoryPreferences(mapOf("Ads" to false))

        val decision = engine.evaluate("doubleclick.net", pslValidator)
        assertFalse(decision.isBlocked)
        assertEquals("none", decision.matchedSource)
        // Category is preserved in matchedCategories so activity logs reflect the category match
        assertEquals(listOf("Ads"), decision.matchedCategories)
    }

    @Test
    fun testCategoryAttribution_CustomBlockPreservesMatchedCategories() {
        engine.setRules(
            listOf(
                AuraRuleItem(id = "doubleclick.net", domain = "doubleclick.net", isEnabled = true, isBlocked = true)
            )
        )
        engine.setCategories(
            mapOf(
                "Ads" to setOf("doubleclick.net")
            )
        )
        engine.setCategoryPreferences(mapOf("Ads" to true))

        val decision = engine.evaluate("doubleclick.net", pslValidator)
        assertTrue(decision.isBlocked)
        assertEquals("custom", decision.matchedSource)
        assertEquals("doubleclick.net", decision.matchedRule)
        assertEquals(listOf("Ads"), decision.matchedCategories)
    }

    @Test
    fun testSynthesizeBlockedResponse_IPv4() {
        val request = createQueryPacket("example.com", 1) // Type A
        val response = AuraDnsEngine.synthesizeBlockedResponse(request)
        assertNotNull(response)

        val header = AuraDnsEngine.parseHeader(response!!)
        assertNotNull(header)
        assertEquals(0x1234, header!!.id)
        assertEquals(0x8180, header.flags) // Response, NoError
        assertEquals(1, header.qdCount)
        assertEquals(1, header.anCount)

        // Check Answer: 0.0.0.0 (4 bytes of 0x00 at the end)
        val last4 = response.takeLast(4)
        assertEquals(listOf<Byte>(0, 0, 0, 0), last4)
    }

    @Test
    fun testSynthesizeBlockedResponse_IPv6() {
        val request = createQueryPacket("example.com", 28) // Type AAAA
        val response = AuraDnsEngine.synthesizeBlockedResponse(request)
        assertNotNull(response)

        val header = AuraDnsEngine.parseHeader(response!!)
        assertNotNull(header)
        assertEquals(1, header!!.anCount)

        // Check Answer: :: (16 bytes of 0x00 at the end)
        val last16 = response.takeLast(16)
        assertEquals(16, last16.size)
        assertTrue(last16.all { it == 0.toByte() })
    }

    @Test
    fun testSynthesizeServFailResponse() {
        val request = createQueryPacket("example.com", 1)
        val response = AuraDnsEngine.synthesizeServFailResponse(request)
        assertNotNull(response)

        val header = AuraDnsEngine.parseHeader(response!!)
        assertNotNull(header)
        assertEquals(0x8182, header!!.flags) // Response, ServFail
        assertEquals(0, header.anCount)
        assertEquals(1, header.qdCount)
    }

    @Test
    fun testCreateBlockedResponse_UnsupportedType_ReturnsNoData() {
        val request = createQueryPacket("example.com", 65) // Type HTTPS
        val response = AuraDnsEngine.createBlockedResponse(request)
        assertNotNull(response)

        val header = AuraDnsEngine.parseHeader(response!!)
        assertNotNull(header)
        assertEquals(0x1234, header!!.id)
        assertEquals(0x8180, header.flags) // Response, NoError
        assertEquals(1, header.qdCount)
        assertEquals(0, header.anCount) // RFC 1035 NODATA: 0 answer records fabricated
    }

    private fun createQueryPacket(name: String, qType: Int): ByteArray {
        val out = ByteArrayOutputStream()
        val header = ByteBuffer.allocate(12)
        header.putShort(0x1234.toShort()) // Transaction ID
        header.putShort(0x0100.toShort()) // Standard Query, RD=1
        header.putShort(1.toShort())      // QDCOUNT = 1
        header.putShort(0.toShort())
        header.putShort(0.toShort())
        header.putShort(0.toShort())
        out.write(header.array())

        for (label in name.split('.')) {
            val bytes = label.toByteArray(Charsets.UTF_8)
            out.write(bytes.size)
            out.write(bytes)
        }
        out.write(0) // End of name

        val questionTail = ByteBuffer.allocate(4)
        questionTail.putShort(qType.toShort())
        questionTail.putShort(1.toShort()) // IN
        out.write(questionTail.array())

        return out.toByteArray()
    }
}
