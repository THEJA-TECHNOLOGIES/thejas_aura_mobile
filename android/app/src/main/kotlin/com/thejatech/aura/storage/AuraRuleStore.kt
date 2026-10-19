package com.thejatech.aura.storage

import android.content.Context
import com.thejatech.aura.engine.AuraPslValidator
import com.thejatech.aura.model.AuraRuleItem
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class AuraRuleException(val code: String, override val message: String) : Exception(message)

class AuraRuleStore(private val context: Context) {

    private val rulesFile: File
        get() = File(context.filesDir, "aura_rules.json")

    private val lock = Any()

    fun loadRules(): List<AuraRuleItem> = synchronized(lock) {
        val file = rulesFile
        if (!file.exists()) return emptyList()

        return try {
            val content = file.readText(Charsets.UTF_8)
            val json = JSONObject(content)
            val rulesArray = json.optJSONArray("rules") ?: JSONArray()
            val list = mutableListOf<AuraRuleItem>()
            for (i in 0 until rulesArray.length()) {
                val itemObj = rulesArray.getJSONObject(i)
                AuraRuleItem.fromJsonObject(itemObj)?.let { list.add(it) }
            }
            list
        } catch (_: Exception) {
            // Fallback for raw JSON array
            try {
                val content = file.readText(Charsets.UTF_8)
                val array = JSONArray(content)
                val list = mutableListOf<AuraRuleItem>()
                for (i in 0 until array.length()) {
                    val itemObj = array.getJSONObject(i)
                    AuraRuleItem.fromJsonObject(itemObj)?.let { list.add(it) }
                }
                list
            } catch (e: Exception) {
                emptyList()
            }
        }
    }

    fun saveRules(rules: List<AuraRuleItem>): Unit = synchronized(lock) {
        val json = JSONObject()
        json.put("version", 1)
        val array = JSONArray()
        for (rule in rules) {
            array.put(rule.toJsonObject())
        }
        json.put("rules", array)

        val target = rulesFile
        val temp = File(context.filesDir, "aura_rules.json.tmp")
        temp.writeText(json.toString(2), Charsets.UTF_8)
        if (target.exists()) {
            target.delete()
        }
        if (!temp.renameTo(target)) {
            temp.copyTo(target, overwrite = true)
            temp.delete()
        }
    }

    fun validateDomain(rawDomain: String): String {
        return AuraPslValidator.getInstance(context).validateRuleDomain(rawDomain)
    }

    fun addRule(rawDomain: String, isBlocked: Boolean, isEnabled: Boolean = true): AuraRuleItem = synchronized(lock) {
        val validDomain = validateDomain(rawDomain)
        val current = loadRules().toMutableList()

        if (current.any { it.domain.equals(validDomain, ignoreCase = true) }) {
            throw AuraRuleException("DUPLICATE_RULE", "A rule for domain '$validDomain' already exists.")
        }

        val newRule = AuraRuleItem(
            id = validDomain,
            domain = validDomain,
            isEnabled = isEnabled,
            isBlocked = isBlocked
        )
        current.add(newRule)
        saveRules(current)
        return newRule
    }

    fun updateRule(
        id: String,
        domain: String? = null,
        isBlocked: Boolean? = null,
        isEnabled: Boolean? = null
    ): AuraRuleItem = synchronized(lock) {
        val current = loadRules().toMutableList()
        val index = current.indexOfFirst { it.id == id }
        if (index == -1) {
            throw AuraRuleException("RULE_NOT_FOUND", "Rule with identifier '$id' was not found.")
        }

        val existing = current[index]
        var targetDomain = existing.domain

        if (!domain.isNullOrBlank()) {
            val valid = validateDomain(domain)
            if (!valid.equals(existing.domain, ignoreCase = true) &&
                current.any { it.id != id && it.domain.equals(valid, ignoreCase = true) }
            ) {
                throw AuraRuleException("DUPLICATE_RULE", "A rule for domain '$valid' already exists.")
            }
            targetDomain = valid
        }

        val updated = existing.copy(
            domain = targetDomain,
            isBlocked = isBlocked ?: existing.isBlocked,
            isEnabled = isEnabled ?: existing.isEnabled
        )

        current[index] = updated
        saveRules(current)
        return updated
    }

    fun deleteRule(id: String): AuraRuleItem = synchronized(lock) {
        val current = loadRules().toMutableList()
        val index = current.indexOfFirst { it.id == id }
        if (index == -1) {
            throw AuraRuleException("RULE_NOT_FOUND", "Rule with identifier '$id' was not found.")
        }

        val removed = current.removeAt(index)
        saveRules(current)
        return removed
    }

    fun toggleRule(id: String, isEnabled: Boolean): AuraRuleItem {
        return updateRule(id = id, isEnabled = isEnabled)
    }

    fun syncRules(rules: List<AuraRuleItem>): Boolean = synchronized(lock) {
        return try {
            saveRules(rules)
            true
        } catch (_: Exception) {
            false
        }
    }
}
