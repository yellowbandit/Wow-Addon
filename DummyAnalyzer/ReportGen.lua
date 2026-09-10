local AddonName, Addon = ...
-- ============================================
-- MARKDOWN / AI EXPORT + REPORT GENERATION
-- ============================================
local ShortNum = Addon.ShortNum
local NumberOrZero = Addon.NumberOrZero
local JoinLines = Addon.JoinLines
local IsSecretValue = Addon.IsSecretValue
local GetCharDB = Addon.GetCharDB
local LogDisplayName = Addon.LogDisplayName

-- FilterSimCData is assigned in SequenceCore.lua, which loads after this module.
local function FilterSimCData(castCounts, damageData) return Addon.FilterSimCData(castCounts, damageData) end

local function GenerateMarkdownReport(log, elapsed, totalDmg, casts, cData, dData, bUptime, bGaps, notesText, dUptime, rStats)
    local lines = {}
    lines[#lines + 1] = "# Dummy Analyzer Report"
    lines[#lines + 1] = ""

    local dur = elapsed or 0
    local dmg = totalDmg or 0
    local dps = dur > 0 and (dmg / dur) or 0
    local totalCasts = casts or 0

    lines[#lines + 1] = "**Duration:** " .. string.format("%.1fs (%.2f min)", dur, dur / 60)
    lines[#lines + 1] = "**DPS:** " .. ShortNum(dps)
    lines[#lines + 1] = "**Total Damage:** " .. ShortNum(dmg)
    lines[#lines + 1] = "**Total Casts:** " .. totalCasts .. (dur > 0 and string.format(" (%.1f CPM)", (totalCasts / dur) * 60) or "")
    lines[#lines + 1] = ""

    if notesText and notesText ~= "" then
        lines[#lines + 1] = "## Notes"
        lines[#lines + 1] = notesText
        lines[#lines + 1] = ""
    end

    if dData and next(dData) then
        lines[#lines + 1] = "## Damage Breakdown"
        lines[#lines + 1] = "| Spell | Total | % | Casts | DPC |"
        lines[#lines + 1] = "|-------|-------|---|-------|-----|"
        local sorted = {}
        for name, d in pairs(dData) do
            local total = NumberOrZero(d.total)
            local pct = dmg > 0 and (total / dmg) * 100 or 0
            local spellCasts = (cData and cData[name]) or 0
            local dpc = spellCasts > 0 and (total / spellCasts) or 0
            table.insert(sorted, {name = name, total = total, pct = pct, casts = spellCasts, dpc = dpc})
        end
        table.sort(sorted, function(a, b) return a.total > b.total end)
        for _, entry in ipairs(sorted) do
            lines[#lines + 1] = string.format("| %s | %s | %.1f%% | %d | %s |", entry.name, ShortNum(entry.total), entry.pct, entry.casts, ShortNum(entry.dpc))
        end
        lines[#lines + 1] = ""
    end

    if cData and next(cData) then
        lines[#lines + 1] = "## Cast Breakdown"
        lines[#lines + 1] = "| Spell | Casts | % |"
        lines[#lines + 1] = "|-------|-------|---|"
        local sorted = {}
        for name, count in pairs(cData) do
            table.insert(sorted, {name = name, count = count, pct = totalCasts > 0 and (count / totalCasts) * 100 or 0})
        end
        table.sort(sorted, function(a, b) return a.count > b.count end)
        for _, entry in ipairs(sorted) do
            lines[#lines + 1] = string.format("| %s | %d | %.1f%% |", entry.name, entry.count, entry.pct)
        end
        lines[#lines + 1] = ""
    end

    if bUptime and next(bUptime) and dur > 0 then
        lines[#lines + 1] = "## Buff Uptime"
        lines[#lines + 1] = "| Buff | Uptime | % |"
        lines[#lines + 1] = "|------|--------|---|"
        local sorted = {}
        for _, buff in pairs(bUptime) do
            if buff.uptime and buff.uptime > 0.1 then
                local uptime = math.min(buff.uptime, dur)
                table.insert(sorted, {name = buff.name or "?", uptime = uptime, pct = (uptime / dur) * 100})
            end
        end
        table.sort(sorted, function(a, b) return a.uptime > b.uptime end)
        for _, entry in ipairs(sorted) do
            lines[#lines + 1] = string.format("| %s | %.1fs | %.1f%% |", entry.name, entry.uptime, entry.pct)
        end
        lines[#lines + 1] = ""
    end

    if dUptime and next(dUptime) and dur > 0 then
        lines[#lines + 1] = "## Target Debuff Uptime"
        lines[#lines + 1] = "| Debuff | Uptime | % |"
        lines[#lines + 1] = "|--------|--------|---|"
        local sorted = {}
        for _, debuff in pairs(dUptime) do
            if debuff.uptime and debuff.uptime > 0.1 then
                local uptime = math.min(debuff.uptime, dur)
                table.insert(sorted, {name = debuff.name or "?", uptime = uptime, pct = (uptime / dur) * 100})
            end
        end
        table.sort(sorted, function(a, b) return a.uptime > b.uptime end)
        for _, entry in ipairs(sorted) do
            lines[#lines + 1] = string.format("| %s | %.1fs | %.1f%% |", entry.name, entry.uptime, entry.pct)
        end
        lines[#lines + 1] = ""
    end

    if rStats and next(rStats) then
        lines[#lines + 1] = "## Spell Power Costs"
        lines[#lines + 1] = "| Spell | Casts | Total Cost | Avg Cost |"
        lines[#lines + 1] = "|-------|-------|------------|----------|"
        local sorted = {}
        for name, c in pairs(rStats) do
            table.insert(sorted, {name = name, avg = c.totalCost / c.count, total = c.totalCost, count = c.count, ptype = c.powerType or ""})
        end
        table.sort(sorted, function(a, b) return a.total > b.total end)
        for _, entry in ipairs(sorted) do
            lines[#lines + 1] = string.format("| %s | %d | %d | %.0f |", entry.name, entry.count, entry.total, entry.avg)
        end
        lines[#lines + 1] = ""
    end

    if bGaps and next(bGaps) then
        lines[#lines + 1] = "## Buff Refresh Gaps"
        lines[#lines + 1] = "| Buff | Longest Gap | Avg Gap | Count |"
        lines[#lines + 1] = "|------|-------------|---------|-------|"
        local sorted = {}
        for key, data in pairs(bGaps) do
            local total = 0
            local maxGap = 0
            for _, g in ipairs(data.gaps) do
                total = total + g
                if g > maxGap then maxGap = g end
            end
            local avg = #data.gaps > 0 and (total / #data.gaps) or 0
            table.insert(sorted, {name = data.name, maxGap = maxGap, avgGap = avg, count = #data.gaps})
        end
        table.sort(sorted, function(a, b) return a.maxGap > b.maxGap end)
        for _, entry in ipairs(sorted) do
            lines[#lines + 1] = string.format("| %s | %.1fs | %.1fs | %d |", entry.name, entry.maxGap, entry.avgGap, entry.count)
        end
        lines[#lines + 1] = ""
    end

    return JoinLines(lines)
end

-- ============================================
-- REPORT GEN EXPORTS
-- ============================================
Addon.GenerateMarkdownReport = GenerateMarkdownReport

function Addon.GenerateLogReportText(log)
    if not log then return "No log data." end
    local lines = {}

    table.insert(lines, "=== DUMMY ANALYZER REPORT ===")
    table.insert(lines, "Date: " .. (log.date or "Unknown"))
    table.insert(lines, "")
    if log.duration and log.duration > 0 then
        table.insert(lines, string.format("Duration: %.1f sec (%.2f min)", log.duration, log.duration / 60))
    end
    if log.totalDamage and log.totalDamage > 0 then
        table.insert(lines, string.format("Total Dmg: %s", ShortNum(log.totalDamage)))
        table.insert(lines, string.format("DPS: %s", ShortNum(log.dps or (log.totalDamage / log.duration))))
    end
    if log.totalCasts and log.totalCasts > 0 and log.duration and log.duration > 0 then
        local cpm = (log.totalCasts / log.duration) * 60
        table.insert(lines, string.format("Total Casts: %d (%.1f CPM)", log.totalCasts, cpm))
    end
    table.insert(lines, "")

    if log.totalDamage and log.totalDamage > 0 and log.damageData and next(log.damageData) then
        table.insert(lines, "--- Damage Breakdown ---")
        local sorted = {}
        for name, d in pairs(log.damageData) do
            if not IsSecretValue(name) and not IsSecretValue(d) then
                table.insert(sorted, {name = name, d = d})
            end
        end
        table.sort(sorted, function(a, b) return NumberOrZero(a.d.total) > NumberOrZero(b.d.total) end)
        for _, entry in ipairs(sorted) do
            local d = entry.d
            local spellTotal = NumberOrZero(d.total)
            local pct = (spellTotal / log.totalDamage) * 100
            local displayName = #entry.name > 22 and entry.name:sub(1,19) .. "..." or entry.name
            table.insert(lines, string.format("%-22s %8s %6.1f%%", displayName, ShortNum(spellTotal), pct))
        end
        table.insert(lines, "")
    end

    if log.castCounts and next(log.castCounts) then
        table.insert(lines, "--- Cast Breakdown ---")
        local sorted = {}
        for name, count in pairs(log.castCounts) do
            if not IsSecretValue(name) then
                table.insert(sorted, {name = name, count = count})
            end
        end
        table.sort(sorted, function(a, b) return a.count > b.count end)
        for _, ability in ipairs(sorted) do
            local pct = (ability.count / log.totalCasts) * 100
            table.insert(lines, string.format("%s: %d (%.1f%%)", ability.name, ability.count, pct))
        end
        table.insert(lines, "")
    end

    if log.buffUptime and next(log.buffUptime) and log.duration and log.duration > 0 then
        table.insert(lines, "--- Buff Uptime ---")
        local sorted = {}
        for _, buff in pairs(log.buffUptime) do
            if buff and buff.uptime and buff.uptime > 0.1 and not IsSecretValue(buff) then
                table.insert(sorted, {name = buff.name or "?", uptime = math.min(buff.uptime, log.duration)})
            end
        end
        table.sort(sorted, function(a, b) return a.uptime > b.uptime end)
        for i, buff in ipairs(sorted) do
            if i > 15 then break end
            local pct = (buff.uptime / log.duration) * 100
            table.insert(lines, string.format("%s: %.1f sec (%.1f%%)", buff.name, buff.uptime, pct))
        end
        table.insert(lines, "")
    end

    if log.buffGaps and next(log.buffGaps) then
        table.insert(lines, "--- Buff Refresh Gaps ---")
        local sorted = {}
        for key, data in pairs(log.buffGaps) do
            local total = 0
            local maxGap = 0
            for _, g in ipairs(data.gaps) do
                total = total + g
                if g > maxGap then maxGap = g end
            end
            local avg = #data.gaps > 0 and (total / #data.gaps) or 0
            table.insert(sorted, {name = data.name, maxGap = maxGap, avgGap = avg, count = #data.gaps})
        end
        table.sort(sorted, function(a, b) return a.maxGap > b.maxGap end)
        for _, entry in ipairs(sorted) do
            table.insert(lines, string.format("%s: longest %.1fs, avg %.1fs (%d gaps)", entry.name, entry.maxGap, entry.avgGap, entry.count))
        end
        table.insert(lines, "")
    end

    if log.spellHistory and #log.spellHistory > 0 then
        table.insert(lines, "--- Cast Timeline ---")
        local maxTimeline = math.min(#log.spellHistory, 500)
        for i = 1, maxTimeline do
            local s = log.spellHistory[i]
            local costStr = ""
            if s.cost and s.cost.cost then
                costStr = string.format(" [%d %s]", s.cost.cost or 0, s.cost.powerType or "")
            end
            table.insert(lines, string.format("%4d. [%5.1fs]%s %s", i, s.time, costStr, s.name or "?"))
        end
        if #log.spellHistory > 500 then
            table.insert(lines, string.format("  ... (%d more casts not shown)", #log.spellHistory - 500))
        end
        table.insert(lines, "")
    end

    if log.spellPowerCosts and next(log.spellPowerCosts) then
        table.insert(lines, "--- Spell Power Costs ---")
        local sorted = {}
        for name, c in pairs(log.spellPowerCosts) do
            table.insert(sorted, {name = name, avg = c.totalCost / c.count, total = c.totalCost, count = c.count, ptype = c.powerType or ""})
        end
        table.sort(sorted, function(a, b) return a.total > b.total end)
        for _, entry in ipairs(sorted) do
            table.insert(lines, string.format("%s: %d casts, %d total, %.0f avg%s", entry.name, entry.count, entry.total, entry.avg, entry.ptype ~= "" and (" " .. entry.ptype) or ""))
        end
        table.insert(lines, "")
    end

    if log.notes and log.notes ~= "" then
        table.insert(lines, "--- Notes ---")
        table.insert(lines, log.notes)
        table.insert(lines, "")
    end

    return JoinLines(lines)
end

function Addon.CompareLogs(idA, idB)
    local logs = GetCharDB().logs
    local logA, logB
    for _, log in ipairs(logs) do
        if log.id == idA then logA = log end
        if log.id == idB then logB = log end
    end
    if not logA or not logB then return "Select two logs to compare." end

    -- Re-filter SimC data at compare time (handles retroactive cases
    -- where logs were saved before the proc/passive filter existed)
    local simcCastsA, simcDmgA = logA.castCounts, logA.damageData
    local simcCastsB, simcDmgB = logB.castCounts, logB.damageData
    if logA.isSimC then
        simcCastsA, simcDmgA = FilterSimCData(logA.castCounts or {}, logA.damageData)
    end
    if logB.isSimC then
        simcCastsB, simcDmgB = FilterSimCData(logB.castCounts or {}, logB.damageData)
    end

    local function s(n)
        return ShortNum(n or 0)
    end

    local lines = {}
    table.insert(lines, "=== COMPARISON ===")
    table.insert(lines, "")
    local aLabel = LogDisplayName(logA)
    local bLabel = LogDisplayName(logB)
    table.insert(lines, aLabel)
    table.insert(lines, bLabel)
    table.insert(lines, "")
    table.insert(lines, string.rep("-", 60))
    table.insert(lines, "")

    local durA = logA.duration or 0
    local durB = logB.duration or 0
    local dpsA = durA > 0 and ((logA.totalDamage or 0) / durA) or 0
    local dpsB = durB > 0 and ((logB.totalDamage or 0) / durB) or 0
    local castsA = logA.totalCasts or 0
    local castsB = logB.totalCasts or 0

    table.insert(lines, string.format("%-24s %-16s %-16s %-16s", "Metric", "A", "B", "Diff"))
    table.insert(lines, string.rep("-", 75))
    local function f(n) return n and s(n) or "0" end
    table.insert(lines, string.format("%-24s %-16s %-16s %-16s", "DPS", f(dpsA), f(dpsB), f(dpsB-dpsA)))
    table.insert(lines, string.format("%-24s %-16s %-16s %-16s", "Casts", castsA, castsB, string.format("%+d", castsB-castsA)))
    table.insert(lines, string.format("%-24s %-16s %-16s %-16s", "Duration", string.format("%.1fs", durA), string.format("%.1fs", durB), string.format("%+.1fs", durB-durA)))
    if logA.isSimC then
        local simcDPS = dpsA
        local pctOfSimC = simcDPS > 0 and (dpsB / simcDPS) * 100 or 0
        table.insert(lines, string.format("%-24s %-16s", "Your DPS vs SimC:", string.format("%.1f%%", pctOfSimC)))
    elseif logB.isSimC then
        local simcDPS = dpsB
        local pctOfSimC = simcDPS > 0 and (dpsA / simcDPS) * 100 or 0
        table.insert(lines, string.format("%-24s %-16s", "Your DPS vs SimC:", string.format("%.1f%%", pctOfSimC)))
    end
    table.insert(lines, "")

    -- Damage breakdown
    table.insert(lines, "--- Damage Breakdown ---")
    table.insert(lines, string.format("%-24s %-16s %-16s %-16s", "Spell", "A", "B", "Diff"))
    table.insert(lines, string.rep("-", 75))
    -- Damage breakdown: only show spells DummyAnalyzer detected as CASTS.
    -- This excludes passive procs (Phalanx, Lightning Strike, Devastator, etc.)
    -- that appear in damageData but aren't deliberate player actions.
    local allSpells = {}
    if simcCastsA then for name in pairs(simcCastsA) do if not IsSecretValue(name) then allSpells[name] = true end end end

    local sorted = {}
    for name in pairs(allSpells) do
        local dA = (simcDmgA and simcDmgA[name] and simcDmgA[name].total) or 0
        local dB = (simcDmgB and simcDmgB[name] and simcDmgB[name].total) or 0
        if not IsSecretValue(dA) and not IsSecretValue(dB) then
            table.insert(sorted, {name = name, totalA = dA, totalB = dB, total = math.max(dA, dB)})
        end
    end
    table.sort(sorted, function(a, b) return a.total > b.total end)

    for _, entry in ipairs(sorted) do
        local pctA = logA.totalDamage > 0 and (entry.totalA / logA.totalDamage) * 100 or 0
        local pctB = logB.totalDamage > 0 and (entry.totalB / logB.totalDamage) * 100 or 0
        local delta = entry.totalB - entry.totalA
        local deltaPct = pctB - pctA
        local deltaStr = (delta >= 0 and "+" or "") .. s(delta) .. " (" .. string.format("%+.1f", deltaPct) .. "%)"
        local displayName = #entry.name > 24 and entry.name:sub(1,21) .. "..." or entry.name
        local cellA = s(entry.totalA) .. " (" .. string.format("%.1f", pctA) .. "%)"
        local cellB = s(entry.totalB) .. " (" .. string.format("%.1f", pctB) .. "%)"
        table.insert(lines, string.format("%-24s %-16s %-16s %-16s", displayName, cellA, cellB, deltaStr))
    end
    table.insert(lines, "")

    -- Cast breakdown
    table.insert(lines, "--- Cast Breakdown ---")
    table.insert(lines, string.format("%-24s %-16s %-16s %-16s", "Spell", "A", "B", "Diff"))
    table.insert(lines, string.rep("-", 75))
    local allCasts = {}
    if simcCastsA then for name in pairs(simcCastsA) do if not IsSecretValue(name) then allCasts[name] = true end end end

    local sortedCasts = {}
    for name in pairs(allCasts) do
        local cA = (simcCastsA and simcCastsA[name]) or 0
        local cB = (simcCastsB and simcCastsB[name]) or 0
        table.insert(sortedCasts, {name = name, countA = cA, countB = cB, count = math.max(cA, cB)})
    end
    table.sort(sortedCasts, function(a, b) return a.count > b.count end)

    for _, entry in ipairs(sortedCasts) do
        local pctA = castsA > 0 and (entry.countA / castsA) * 100 or 0
        local pctB = castsB > 0 and (entry.countB / castsB) * 100 or 0
        local delta = entry.countB - entry.countA
        local deltaPct = pctB - pctA
        local deltaStr = (delta >= 0 and "+" or "") .. delta .. " (" .. string.format("%+.1f", deltaPct) .. "%)"
        local cellA = entry.countA .. " (" .. string.format("%.1f", pctA) .. "%)"
        local cellB = entry.countB .. " (" .. string.format("%.1f", pctB) .. "%)"
        table.insert(lines, string.format("%-24s %-16s %-16s %-16s", entry.name, cellA, cellB, deltaStr))
    end
    table.insert(lines, "")

    -- Buff uptime comparison
    table.insert(lines, "--- Buff Uptime ---")
    table.insert(lines, string.format("%-24s %-16s %-16s %-16s", "Buff", "A", "B", "Diff"))
    table.insert(lines, string.rep("-", 75))
    local allBuffs = {}
    if logA.buffUptime then
        for key, buff in pairs(logA.buffUptime) do
            if not IsSecretValue(key) and buff and buff.uptime and buff.uptime > 0.1 then
                allBuffs[key] = buff.name or key
            end
        end
    end
    if logB.buffUptime then
        for key, buff in pairs(logB.buffUptime) do
            if not IsSecretValue(key) and buff and buff.uptime and buff.uptime > 0.1 then
                allBuffs[key] = buff.name or key
            end
        end
    end

    local function lookupBuffUptime(log, key, name)
        if not log or not log.buffUptime then return 0 end
        local b = log.buffUptime[key]
        if b and b.uptime then return b.uptime end
        for _, buff in pairs(log.buffUptime) do
            if buff.name == name and buff.uptime then return buff.uptime end
        end
        return 0
    end

    local nameKeys = {}
    for key, name in pairs(allBuffs) do
        if nameKeys[name] then
            allBuffs[nameKeys[name]] = nil
        end
        nameKeys[name] = key
    end

    local sortedBuffs = {}
    for key, name in pairs(allBuffs) do
        local uA = lookupBuffUptime(logA, key, name)
        local uB = lookupBuffUptime(logB, key, name)
        if not IsSecretValue(uA) and not IsSecretValue(uB) then
            uA = math.min(uA, durA)
            uB = math.min(uB, durB)
            table.insert(sortedBuffs, {name = name or key, uptimeA = uA, uptimeB = uB})
        end
    end
    table.sort(sortedBuffs, function(a, b) return a.uptimeB > b.uptimeB end)

    for _, entry in ipairs(sortedBuffs) do
        local pctA = durA > 0 and (entry.uptimeA / durA) * 100 or 0
        local pctB = durB > 0 and (entry.uptimeB / durB) * 100 or 0
        local delta = entry.uptimeB - entry.uptimeA
        local deltaPct = pctB - pctA
        local deltaStr = string.format("%+.1fs (%+.1f%%)", delta, deltaPct)
        local cellA = string.format("%.1fs (%.1f%%)", entry.uptimeA, pctA)
        local cellB = string.format("%.1fs (%.1f%%)", entry.uptimeB, pctB)
        table.insert(lines, string.format("%-24s %-16s %-16s %-16s", entry.name, cellA, cellB, deltaStr))
    end

    -- Buff gap comparison
    local allGaps = {}
    if logA.buffGaps then
        for key, data in pairs(logA.buffGaps) do
            if not IsSecretValue(key) and data.gaps then
                allGaps[key] = data.name or key
            end
        end
    end
    if logB.buffGaps then
        for key, data in pairs(logB.buffGaps) do
            if not IsSecretValue(key) and data.gaps then
                allGaps[key] = data.name or key
            end
        end
    end
    if next(allGaps) then
        table.insert(lines, "--- Buff Gap Comparison ---")
        table.insert(lines, string.format("%-24s %-16s %-16s %-16s", "Buff", "A", "B", "Diff"))
        table.insert(lines, string.rep("-", 75))
        local function getGapData(log, key)
            if not log or not log.buffGaps or not log.buffGaps[key] then return 0, 0, 0 end
            local data = log.buffGaps[key]
            local maxG = 0
            local total = 0
            for _, g in ipairs(data.gaps) do
                total = total + g
                if g > maxG then maxG = g end
            end
            return maxG, #data.gaps > 0 and (total / #data.gaps) or 0, #data.gaps
        end
        local sortedGaps = {}
        for key, name in pairs(allGaps) do
            local maxA, avgA, cntA = getGapData(logA, key)
            local maxB, avgB, cntB = getGapData(logB, key)
            table.insert(sortedGaps, {name = name or key, maxA = maxA, maxB = maxB, avgA = avgA, avgB = avgB, cntA = cntA, cntB = cntB})
        end
        table.sort(sortedGaps, function(a, b) return a.maxB > b.maxB end)
        for _, entry in ipairs(sortedGaps) do
            local cellA = string.format("%.1fs (%.1f) x%d", entry.maxA, entry.avgA, entry.cntA)
            local cellB = string.format("%.1fs (%.1f) x%d", entry.maxB, entry.avgB, entry.cntB)
            local deltaStr = string.format("%+.1fs max", entry.maxB - entry.maxA)
            table.insert(lines, string.format("%-24s %-16s %-16s %-16s", entry.name, cellA, cellB, deltaStr))
        end
        table.insert(lines, "")
    end

    -- Notes comparison
    local notesA = logA.notes and logA.notes ~= "" and logA.notes or nil
    local notesB = logB.notes and logB.notes ~= "" and logB.notes or nil
    if notesA or notesB then
        table.insert(lines, "--- Notes ---")
        table.insert(lines, string.format("%-24s %s", "A:", notesA or "(none)"))
        table.insert(lines, string.format("%-24s %s", "B:", notesB or "(none)"))
        table.insert(lines, "")
    end

    return JoinLines(lines)
end

-- ============================================
-- REPORT GENERATION (original)
-- ============================================
local function GenerateReportText()
    local elapsed = (Addon.testActive and (GetTime() - Addon.startTime)) or (Addon.testEndTime and (Addon.testEndTime - Addon.startTime)) or 0
    local lines = {}
    local totalCasts = #Addon.spellHistory
    local castCounts = {}
    for _, spell in ipairs(Addon.spellHistory) do
        castCounts[spell.name] = (castCounts[spell.name] or 0) + 1
    end

    table.insert(lines, "=== DUMMY ANALYZER REPORT ===")
    table.insert(lines, "")
    if elapsed > 0 then
        table.insert(lines, string.format("Duration: %.1f sec (%.2f min)", elapsed, elapsed / 60))
    end

    if Addon.totalDamage > 0 then
        local dps = Addon.totalDamage / elapsed
        local estSuffix = Addon.damageFromEnemyFallback and " (estimated from enemy damage taken)"
            or (Addon.damageFromHealthFallback and " (estimated from dummy health)" or "")
        table.insert(lines, string.format("Total Dmg: %s%s", ShortNum(Addon.totalDamage), estSuffix))
        table.insert(lines, string.format("DPS: %s%s", ShortNum(dps), estSuffix))
    else
        table.insert(lines, "Total Dmg: 0")
        if Addon.meterDiag then
            table.insert(lines, "--- Damage Meter Diagnostics ---")
            for _, dl in ipairs({strsplit("\n", Addon.meterDiag)}) do
                table.insert(lines, dl)
            end
            table.insert(lines, "")
        end
        if Addon.healthTotal <= 0 then
            table.insert(lines, "--- Health Fallback ---")
            table.insert(lines, string.format("healthBaseHp=%s  healthTotal=%s  track=%s",
                tostring(Addon.healthBaseHp), tostring(Addon.healthTotal), tostring(Addon.healthTrackReady)))
            table.insert(lines, "Tip: keep the training dummy targeted for the whole test. Damage is read")
            table.insert(lines, "from its health bar, which is not available inside an instance or when the")
            table.insert(lines, "client hides HP from addons.")
            table.insert(lines, "")
        end
    end

    if totalCasts > 0 and elapsed > 0 then
        local cpm = (totalCasts / elapsed) * 60
        table.insert(lines, string.format("Total Casts: %d (%.1f CPM)", totalCasts, cpm))
    end
    table.insert(lines, "")

    if Addon.totalDamage > 0 and next(Addon.damageData) then
        table.insert(lines, "--- Damage Breakdown ---")
        local sorted = {}
        for name, d in pairs(Addon.damageData) do
            table.insert(sorted, {name = name, d = d})
        end
        table.sort(sorted, function(a, b) return NumberOrZero(a.d.total) > NumberOrZero(b.d.total) end)

        for _, entry in ipairs(sorted) do
            local d = entry.d
            local spellTotal = NumberOrZero(d.total)
            local pct = Addon.totalDamage > 0 and (spellTotal / Addon.totalDamage) * 100 or 0
            local displayName = #entry.name > 22 and entry.name:sub(1,19).."..." or entry.name
            local hits = NumberOrZero(d.hits)
            local highest = NumberOrZero(d.highest)
            local overkill = NumberOrZero(d.overkill)
            local suffix = ""
            if hits > 0 and highest > 0 and overkill > 0 then
                suffix = string.format("  (%d hits, max %s, %s over)", hits, ShortNum(highest), ShortNum(overkill))
            elseif hits > 0 and highest > 0 then
                suffix = string.format("  (%d hits, max %s)", hits, ShortNum(highest))
            elseif hits > 0 then
                suffix = string.format("  (%d hits)", hits)
            end
            table.insert(lines, string.format("%-22s %8s %6.1f%%%s", displayName, ShortNum(spellTotal), pct, suffix))
        end
        table.insert(lines, "")
    end

    if totalCasts > 0 then
        table.insert(lines, "--- Cast Breakdown ---")
        local sorted = {}
        for name, count in pairs(castCounts) do
            table.insert(sorted, {name = name, count = count})
        end
        table.sort(sorted, function(a, b) return a.count > b.count end)
        for _, ability in ipairs(sorted) do
            local pct = (ability.count / totalCasts) * 100
            table.insert(lines, string.format("%s: %d (%.1f%%)", ability.name, ability.count, pct))
        end
        table.insert(lines, "")
    end

    if Addon.totalDamage > 0 and totalCasts > 0 and next(Addon.damageData) then
        table.insert(lines, "--- Damage Per Cast ---")
        local sorted = {}
        for name, d in pairs(Addon.damageData) do
            local casts = castCounts[name] or 0
            local spellTotal = NumberOrZero(d.total)
            if casts > 0 and spellTotal > 0 then
                table.insert(sorted, {name = name, casts = casts, total = spellTotal, perCast = spellTotal / casts})
            end
        end
        table.sort(sorted, function(a, b) return a.total > b.total end)
        if #sorted == 0 then
            table.insert(lines, "No direct cast/damage name matches.")
        else
            for i, entry in ipairs(sorted) do
                if i > 12 then break end
                table.insert(lines, string.format("%s: %s over %d casts (%s/cast)", entry.name, ShortNum(entry.total), entry.casts, ShortNum(entry.perCast)))
            end
        end
        table.insert(lines, "")
    end

    if totalCasts > 0 then
        table.insert(lines, "--- Opener ---")
        local opener = {}
        for i, spell in ipairs(Addon.spellHistory) do
            if i > 8 and spell.time > 10 then break end
            if i <= 8 or spell.time <= 10 then
                local sName = spell.name
                if sName and not pcall(string.byte, sName, 1) then sName = "?" end
                table.insert(opener, string.format("[%.1fs] %s", spell.time, sName))
            end
        end
        for _, line in ipairs(opener) do
            table.insert(lines, line)
        end
        table.insert(lines, "")
    end

    if #Addon.spellHistory > 1 then
        local delays = {}
        local gaps = {}
        for i = 2, #Addon.spellHistory do
            local d = Addon.spellHistory[i].time - Addon.spellHistory[i - 1].time
            table.insert(delays, d)
            if d > 1.5 then
                table.insert(gaps, {gap = d, a = Addon.spellHistory[i - 1].name, b = Addon.spellHistory[i].name, at = Addon.spellHistory[i - 1].time})
            end
        end
        local sum = 0
        for _, d in ipairs(delays) do sum = sum + d end
        local avg = sum / #delays
        local maxG = 0
        local idleTotal = 0
        for _, g in ipairs(gaps) do
            if g.gap > maxG then maxG = g.gap end
            idleTotal = idleTotal + g.gap - 1.5
        end
        table.insert(lines, "--- Cast Timing ---")
        table.insert(lines, string.format("Avg interval: %.2fs | Longest gap: %.1fs | Idle time: %.1fs", avg, maxG, idleTotal))
        if #gaps > 0 then
            table.sort(gaps, function(a, b) return a.gap > b.gap end)
            for i = 1, math.min(5, #gaps) do
                table.insert(lines, string.format("  [%.1fs] %s -> %s (+%.2fs)", gaps[i].at, gaps[i].a, gaps[i].b, gaps[i].gap))
            end
        end
        table.insert(lines, "")
    end

    -- Buff cast context
    local buffCastData = {}
    for _, entry in ipairs(Addon.spellHistory) do
        local eb = entry.buffs
        if eb and next(eb) then
            for key, bName in pairs(eb) do
                if not buffCastData[key] then
                    buffCastData[key] = {name = bName, total = 0, spells = {}}
                end
                buffCastData[key].total = buffCastData[key].total + 1
                buffCastData[key].spells[entry.name] = (buffCastData[key].spells[entry.name] or 0) + 1
            end
        end
    end
    if next(buffCastData) then
        table.insert(lines, "--- Cast Buff Context ---")
        for key, data in pairs(buffCastData) do
            if data.total >= 3 then
                local spellSummary = {}
                for spell, count in pairs(data.spells) do
                    table.insert(spellSummary, string.format("%s x%d", spell, count))
                end
                table.sort(spellSummary)
                local summary = table.concat(spellSummary, ", ")
                if #summary > 80 then summary = summary:sub(1, 77) .. "..." end
                table.insert(lines, string.format("  %s: %d casts - %s", data.name, data.total, summary))
            end
        end
        table.insert(lines, "")
    end

    if totalCasts > 1 then
        local gaps = {}
        for i = 2, #Addon.spellHistory do
            local gap = Addon.spellHistory[i].time - Addon.spellHistory[i - 1].time
            if gap >= 1.5 then
                table.insert(gaps, {
                    gap = gap,
                    before = Addon.spellHistory[i - 1].name,
                    after = Addon.spellHistory[i].name,
                    time = Addon.spellHistory[i - 1].time,
                })
            end
        end
        if #gaps > 0 then
            table.sort(gaps, function(a, b) return a.gap > b.gap end)
            table.insert(lines, "--- Idle Gaps ---")
            for i, gap in ipairs(gaps) do
                if i > 8 then break end
                table.insert(lines, string.format("%.1fs gap after %.1fs: %s -> %s", gap.gap, gap.time, gap.before, gap.after))
            end
            table.insert(lines, "")
        end
    end

    -- Cast timeline with resource level
    if totalCasts > 0 then
        table.insert(lines, "--- Cast Timeline ---")
        local maxShow = math.min(totalCasts, 2000)
        for i = 1, maxShow do
            local s = Addon.spellHistory[i]
            local sName = s.name
            if sName and not pcall(string.byte, sName, 1) then sName = "?" end
            table.insert(lines, string.format("%4d. [%5.1fs] %s", i, s.time, sName))
        end
        if totalCasts > 2000 then
            table.insert(lines, string.format("  (... %d more)", totalCasts - 2000))
        end
        table.insert(lines, "")
    end

    if next(Addon.buffUptime) and elapsed > 0 then
        table.insert(lines, "--- Buff Uptime ---")
        local sorted = {}
        for _, buff in pairs(Addon.buffUptime) do
            if buff.uptime > 0.1 then
                table.insert(sorted, {name = buff.name, uptime = math.min(buff.uptime, elapsed)})
            end
        end
        table.sort(sorted, function(a, b) return a.uptime > b.uptime end)
        for i, buff in ipairs(sorted) do
            if i > 15 then break end
            local pct = (buff.uptime / elapsed) * 100
            table.insert(lines, string.format("%s: %.1f sec (%.1f%%)", buff.name, buff.uptime, pct))
        end
        table.insert(lines, "")
    end

    if next(Addon.buffGaps) then
        table.insert(lines, "--- Buff Refresh Gaps ---")
        local sorted = {}
        for key, data in pairs(Addon.buffGaps) do
            local total = 0
            local maxGap = 0
            for _, g in ipairs(data.gaps) do
                total = total + g
                if g > maxGap then maxGap = g end
            end
            local avg = #data.gaps > 0 and (total / #data.gaps) or 0
            table.insert(sorted, {name = data.name, maxGap = maxGap, avgGap = avg, count = #data.gaps})
        end
        table.sort(sorted, function(a, b) return a.maxGap > b.maxGap end)
        for _, entry in ipairs(sorted) do
            table.insert(lines, string.format("%s: longest %.1fs, avg %.1fs (%d gaps)", entry.name, entry.maxGap, entry.avgGap, entry.count))
        end
        table.insert(lines, "")
    end

    if next(Addon.debuffUptime) and elapsed > 0 then
        table.insert(lines, "--- Target Debuff Uptime ---")
        local sorted = {}
        for _, debuff in pairs(Addon.debuffUptime) do
            if debuff.uptime > 0.1 then
                table.insert(sorted, {name = debuff.name, uptime = math.min(debuff.uptime, elapsed)})
            end
        end
        table.sort(sorted, function(a, b) return a.uptime > b.uptime end)
        for i, debuff in ipairs(sorted) do
            if i > 15 then break end
            local pct = (debuff.uptime / elapsed) * 100
            table.insert(lines, string.format("%s: %.1f sec (%.1f%%)", debuff.name, debuff.uptime, pct))
        end
        table.insert(lines, "")
    end

    if Addon.spellPowerCosts and next(Addon.spellPowerCosts) then
        table.insert(lines, "--- Spell Power Costs ---")
        local powerType = nil
        for _, c in pairs(Addon.spellPowerCosts) do powerType = c.powerType; break end
        local sorted = {}
        for name, c in pairs(Addon.spellPowerCosts) do
            table.insert(sorted, {name = name, avg = c.totalCost / c.count, total = c.totalCost, count = c.count})
        end
        table.sort(sorted, function(a, b) return a.total > b.total end)
        for _, entry in ipairs(sorted) do
            table.insert(lines, string.format("%s: %d casts, %d total, %.0f avg%s", entry.name, entry.count, entry.total, entry.avg, powerType and (" " .. powerType) or ""))
        end
        table.insert(lines, "")
    end

    return JoinLines(lines)
end

-- ============================================
-- REPORT GENERATION EXPORTS (namespace promotion)
-- ============================================
Addon.GenerateReportText = GenerateReportText