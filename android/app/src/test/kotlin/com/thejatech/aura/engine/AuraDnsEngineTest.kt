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

    // =========================================================================
    // M8: DNS Rebinding Protection Tests
    // =========================================================================

    @Test
    fun testIsPrivateIpv4() {
        // Private ranges
        assertTrue(AuraDnsEngine.isPrivateIpv4(10, 0, 0, 1))          // 10.0.0.0/8
        assertTrue(AuraDnsEngine.isPrivateIpv4(172, 16, 0, 1))        // 172.16.0.0/12
        assertTrue(AuraDnsEngine.isPrivateIpv4(172, 31, 255, 255))    // 172.31.255.255
        assertTrue(AuraDnsEngine.isPrivateIpv4(192, 168, 0, 1))       // 192.168.0.0/16
        assertTrue(AuraDnsEngine.isPrivateIpv4(127, 0, 0, 1))         // 127.0.0.0/8
        assertTrue(AuraDnsEngine.isPrivateIpv4(169, 254, 0, 1))       // 169.254.0.0/16
        assertTrue(AuraDnsEngine.isPrivateIpv4(224, 0, 0, 1))         // 224.0.0.0/4
        assertTrue(AuraDnsEngine.isPrivateIpv4(239, 255, 255, 255))   // 239.255.255.255

        // Public IPs
        assertFalse(AuraDnsEngine.isPrivateIpv4(9, 9, 9, 9))          // Quad9
        assertFalse(AuraDnsEngine.isPrivateIpv4(1, 1, 1, 1))          // Cloudflare
        assertFalse(AuraDnsEngine.isPrivateIpv4(8, 8, 8, 8))          // Google
        assertFalse(AuraDnsEngine.isPrivateIpv4(172, 15, 255, 255))   // Just outside 172.16/12
        assertFalse(AuraDnsEngine.isPrivateIpv4(172, 32, 0, 0))       // Just outside 172.16/12
    }

    @Test
    fun testIsPrivateIpv6() {
        // Loopback ::1
        val loopback = ByteArray(16).apply { this[15] = 1 }
        assertTrue(AuraDnsEngine.isPrivateIpv6(loopback))

        // Unique local fc00::/7
        val ulaFc = ByteArray(16).apply { this[0] = 0xFC.toByte() }
        assertTrue(AuraDnsEngine.isPrivateIpv6(ulaFc))
        val ulaFd = ByteArray(16).apply { this[0] = 0xFD.toByte() }
        assertTrue(AuraDnsEngine.isPrivateIpv6(ulaFd))

        // Link-local fe80::/10
        val linkLocal = ByteArray(16).apply { this[0] = 0xFE.toByte(); this[1] = 0x80.toByte() }
        assertTrue(AuraDnsEngine.isPrivateIpv6(linkLocal))

        // Multicast ff00::/8
        val multicast = ByteArray(16).apply { this[0] = 0xFF.toByte() }
        assertTrue(AuraDnsEngine.isPrivateIpv6(multicast))

        // IPv4-mapped private ::ffff:10.0.0.1
        val mapped = ByteArray(16).apply {
            this[11] = 0xFF.toByte()
            this[12] = 10
            this[13] = 0
            this[14] = 0
            this[15] = 1
        }
        assertTrue(AuraDnsEngine.isPrivateIpv6(mapped))

        // Public IPv6 (2001:db8:: - documentation range)
        val publicIpv6 = ByteArray(16).apply { this[0] = 0x20.toByte(); this[1] = 0x01.toByte() }
        assertFalse(AuraDnsEngine.isPrivateIpv6(publicIpv6))

        // Invalid length
        assertFalse(AuraDnsEngine.isPrivateIpv6(byteArrayOf(1, 2, 3)))
    }

    @Test
    fun testHasPrivateIpAnswers() {
        // Build a response with an A record pointing to 10.0.0.1 (private)
        val privateResponse = buildResponseWithAnswer("example.com", 1, byteArrayOf(10, 0, 0, 1))
        assertTrue(AuraDnsEngine.hasPrivateIpAnswers(privateResponse))

        // Build a response with an A record pointing to 9.9.9.9 (public)
        val publicResponse = buildResponseWithAnswer("example.com", 1, byteArrayOf(9, 9, 9, 9))
        assertFalse(AuraDnsEngine.hasPrivateIpAnswers(publicResponse))

        // Empty response should not have private IPs
        assertFalse(AuraDnsEngine.hasPrivateIpAnswers(byteArrayOf()))
    }

    @Test
    fun testQuestionsMatch() {
        val query = createQueryPacket("example.com", 1)

        // Matching response (same question section)
        val matchingResponse = query.copyOf().apply {
            this[2] = 0x81.toByte() // QR=1
            this[3] = 0x80.toByte() // RA, NoError
        }
        assertTrue(AuraDnsEngine.questionsMatch(query, matchingResponse))

        // Non-matching response (different domain - evil.com)
        val differentDomain = createQueryPacket("evil.com", 1)
        assertFalse(AuraDnsEngine.questionsMatch(query, differentDomain))
    }

    /**
     * Builds a minimal DNS response with an A record answer containing the given IP bytes.
     */
    private fun buildResponseWithAnswer(domain: String, qType: Int, ipBytes: ByteArray): ByteArray {
        val out = ByteArrayOutputStream()
        val header = ByteBuffer.allocate(12)
        header.putShort(0x1234.toShort()) // Transaction ID
        header.putShort(0x8180.toShort()) // Response, NoError
        header.putShort(1.toShort())      // QDCOUNT = 1
        header.putShort(1.toShort())      // ANCOUNT = 1
        header.putShort(0.toShort())      // NSCOUNT = 0
        header.putShort(0.toShort())      // ARCOUNT = 0
        out.write(header.array())

        // Question section
        for (label in domain.split('.')) {
            val bytes = label.toByteArray(Charsets.UTF_8)
            out.write(bytes.size)
            out.write(bytes)
        }
        out.write(0)
        val qTail = ByteBuffer.allocate(4)
        qTail.putShort(qType.toShort())
        qTail.putShort(1.toShort()) // IN
        out.write(qTail.array())

        // Answer section: name pointer, type, class, TTL, rdlength, rdata
        out.write(0xC0) // Name pointer to offset 12
        out.write(0x0C)
        val aTail = ByteBuffer.allocate(10)
        aTail.putShort(qType.toShort())    // TYPE
        aTail.putShort(1.toShort())        // CLASS IN
        aTail.putInt(300)                  // TTL
        aTail.putShort(ipBytes.size.toShort()) // RDLENGTH
        out.write(aTail.array())
        out.write(ipBytes)

        return out.toByteArray()
    }
}
