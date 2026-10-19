package com.thejatech.aura.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

class AuraPslValidatorTest {

    private lateinit var validator: AuraPslValidator

    private val testPsl = """
        // Public Suffix List snapshot for testing
        com
        co.uk
        gov.uk
        org
        *.ck
        !city.kobe.jp
        jp
        kobe.jp
    """.trimIndent()

    @Before
    fun setUp() {
        validator = AuraPslValidator(testPsl)
    }

    @Test
    fun testPublicSuffixDetection() {
        assertTrue(validator.isPublicSuffix("com"))
        assertTrue(validator.isPublicSuffix("co.uk"))
        assertTrue(validator.isPublicSuffix("gov.uk"))
        assertTrue(validator.isPublicSuffix("anything.ck")) // *.ck
        assertFalse(validator.isPublicSuffix("example.com"))
        assertFalse(validator.isPublicSuffix("bbc.co.uk"))
        assertFalse(validator.isPublicSuffix("city.kobe.jp")) // Exception rule
    }

    @Test
    fun testRegistrableDomain() {
        assertEquals("example.com", validator.registrableDomain("foo.bar.example.com"))
        assertEquals("bbc.co.uk", validator.registrableDomain("news.bbc.co.uk"))
        assertNull(validator.registrableDomain("co.uk"))
        assertNull(validator.registrableDomain("com"))
    }

    @Test
    fun testValidateRuleDomain_Valid() {
        assertEquals("example.com", validator.validateRuleDomain("example.com"))
        assertEquals("sub.example.com", validator.validateRuleDomain("https://sub.example.com/path?arg=1"))
        assertEquals("example.org", validator.validateRuleDomain("EXAMPLE.ORG."))
    }

    @Test
    fun testValidateRuleDomain_Empty() {
        try {
            validator.validateRuleDomain("   ")
            fail("Expected EmptyDomain error")
        } catch (e: AuraDomainValidationError.EmptyDomain) {
            assertEquals("EMPTY_DOMAIN", e.code)
        }
    }

    @Test
    fun testValidateRuleDomain_SingleLabel() {
        try {
            validator.validateRuleDomain("localhost")
            fail("Expected SingleLabelDomain error")
        } catch (e: AuraDomainValidationError.SingleLabelDomain) {
            assertEquals("SINGLE_LABEL_DOMAIN", e.code)
        }
    }

    @Test
    fun testValidateRuleDomain_PublicSuffix() {
        try {
            validator.validateRuleDomain("co.uk")
            fail("Expected PublicSuffix error")
        } catch (e: AuraDomainValidationError.PublicSuffix) {
            assertEquals("PUBLIC_SUFFIX", e.code)
        }
    }

    @Test
    fun testValidateRuleDomain_IPAddress() {
        try {
            validator.validateRuleDomain("192.168.1.1")
            fail("Expected IpAddress error")
        } catch (e: AuraDomainValidationError.IpAddress) {
            assertEquals("IP_ADDRESS", e.code)
        }

        try {
            validator.validateRuleDomain("2001:db8::1")
            fail("Expected IpAddress error")
        } catch (e: AuraDomainValidationError.IpAddress) {
            assertEquals("IP_ADDRESS", e.code)
        }
    }
}
