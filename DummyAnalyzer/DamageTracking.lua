local AddonName, Addon = ...
-- ============================================
-- DAMAGE TRACKING (original C_DamageMeter)
-- ============================================
local SafeTableGet = Addon.SafeTableGet
local GetSpellName = Addon.GetSpellName
local ShortNum = Addon.ShortNum
local IsSecretValue = Addon.IsSecretValue

-- NumberOrZero / RecordKnownBuffCast are homes of BuffTracking.lua (#5), which
-- loads AFTER this module. Deferred resolution via Addon keeps the load order safe.
local function NumberOrZero(v) return Addon.NumberOrZero(v) end
local function RecordKnownBuffCast(spellId, spellName) return Addon.RecordKnownBuffCast(spellId, spellName) end

-- Forward declaration (moved from Init range line 480). Assigned + used only here.
local BuildMeterDiag

local function ResetDamageData()
    Addon.damageData = {}
    Addon.totalDamage = 0
    Addon.damageFromEnemyFallback = false
end

local function MeterSourceTotal(block)
    return NumberOrZero(SafeTableGet(block, "totalAmount")) 
end

local function SameGuid(a, b)
    if not a or not b then return false end
    if IsSecretValue(a) or IsSecretValue(b) then return false end
    local ok, eq = pcall(function() return a == b end)
    return ok and eq == true
end

local function MeterSourceSpells(block)
    local spells = SafeTableGet(block, "combatSpells")
    if type(spells) ~= "table" then
        spells = SafeTableGet(block, "spells")
    end
    return type(spells) == "table" and spells or nil
end

local function AddMeterSource(block)
    if type(block) ~= "table" then return 0 end
    local total = MeterSourceTotal(block)
    if total <= 0 then return 0 end
    local spells = MeterSourceSpells(block)
    if not spells or #spells == 0 then return 0 end
    for _, spell in ipairs(spells) do
        if type(spell) == "table" then
            local okSpell, spellErr = pcall(function()
                local spellID = SafeTableGet(spell, "spellID")
                local name = GetSpellName(spellID)
                if not name or name == "" then
                    return
                end
                local totalAmt = NumberOrZero(SafeTableGet(spell, "totalAmount"))
                local aps = NumberOrZero(SafeTableGet(spell, "amountPerSecond"))
                local overkill = NumberOrZero(SafeTableGet(spell, "overkillAmount"))
                local details = SafeTableGet(spell, "combatSpellDetails")
                local hits = 0
                local highest = 0
                if type(details) == "table" then
                    hits = #details
                    for _, d in ipairs(details) do
                        if type(d) == "table" then
                            local amt = NumberOrZero(SafeTableGet(d, "amount"))
                            if amt > highest then highest = amt end
                        end
                    end
                end
                local existing = Addon.damageData[name]
                if existing then
                    existing.total = (existing.total or 0) + totalAmt
                    existing.hits = (existing.hits or 0) + hits
                    if highest > existing.highest then existing.highest = highest end
                    existing.aps = (existing.aps or 0) + aps
                    existing.overkill = (existing.overkill or 0) + overkill
                else
                    Addon.damageData[name] = {
                        total = totalAmt,
                        hits = hits,
                        highest = highest,
                        aps = aps,
                        overkill = overkill,
                    }
                end
            end)
        end
    end
    return total
end

local function ReadDamageMeterData()
    if Addon.debugMode then print("|cff33ff33[DummyAnalyzer Debug]|r Reading damage data...") end

    ResetDamageData()
    if not C_DamageMeter then return false end

    local ok, err = pcall(function()
        local meterType = 0

        -- Session types: prefer Expired (just-finalized, locked duration, ready
        -- immediately after combat ends), then Current. CombatAnalytics pattern.
        local currentType = 1
        local expiredType
        if Enum and Enum.DamageMeterSessionType then
            local okC, cv = pcall(function() return Enum.DamageMeterSessionType.Current end)
            if okC and cv then currentType = cv end
            local okE, ev = pcall(function() return Enum.DamageMeterSessionType.Expired end)
            if okE and ev then expiredType = ev end
        end
        local sessionTypes = {}
        if expiredType then table.insert(sessionTypes, expiredType) end
        table.insert(sessionTypes, currentType)

        -- 1) Legacy per-type source (Expired first, falling through to Current).
        --    In Midnight the 'current' session often rolls over right after combat
        --    ends, so this may return nil or an empty block.
        local function tryLegacy(sessionType)
            local source
            local okWithGuid, sourceWithGuid = pcall(C_DamageMeter.GetCombatSessionSourceFromType, sessionType, meterType, Addon.playerGUID)
            if okWithGuid and sourceWithGuid then source = sourceWithGuid end
            if not source then
                local okWithoutGuid, sourceWithoutGuid = pcall(C_DamageMeter.GetCombatSessionSourceFromType, sessionType, meterType)
                if okWithoutGuid then source = sourceWithoutGuid end
            end
            return source
        end

        for _, st in ipairs(sessionTypes) do
            local legacy = tryLegacy(st)
            if type(legacy) == "table" and MeterSourceTotal(legacy) > 0 then
                local mergedTotal = AddMeterSource(legacy)
                if mergedTotal > 0 then
                    Addon.totalDamage = Addon.totalDamage + mergedTotal
                else
                    -- Block has a total but no per-spell rows (secret/empty spell list);
                    -- still count the raw total so the report shows damage.
                    Addon.totalDamage = Addon.totalDamage + MeterSourceTotal(legacy)
                end
            end
            if Addon.totalDamage > 0 then break end
        end

        -- 2) Midnight session-based APIs: GetAvailableCombatSessions() -> list of
        --    {sessionID, name, durationSeconds}; GetCombatSessionFromID(sessionID,
        --    type) -> {combatSources, maxAmount, totalAmount}; and the player's
        --    per-spell breakdown comes from GetCombatSessionSourceFromID(sessionID,
        --    type, sourceGUID). DamageMeterCombatSource has NO combatSpells field,
        --    so per-spell data must come from GetCombatSessionSourceFromID; the
        --    session's combatSources only gives each combatant's totalAmount.
        if Addon.totalDamage == 0 then
            local okSessions, sessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
            if okSessions and type(sessions) == "table" then
                for _, s in ipairs(sessions) do
                    if type(s) == "table" then
                        local id = SafeTableGet(s, "sessionID")
                        if id then
                            -- Player's total from the session roster.
                            local playerTotal = 0
                            local playerIsLocal = false
                            local okSession, session = pcall(C_DamageMeter.GetCombatSessionFromID, id, meterType)
                            if okSession and type(session) == "table" then
                                local sources = SafeTableGet(session, "combatSources")
                                if type(sources) == "table" then
                                    for _, src in ipairs(sources) do
                                        if type(src) == "table" then
                                            local guid = SafeTableGet(src, "sourceGUID")
                                            local isLocal = SafeTableGet(src, "isLocalPlayer") == true
                                            local srcName = SafeTableGet(src, "name")
                                            if isLocal then playerIsLocal = true end
                                            if isLocal or SameGuid(guid, Addon.playerGUID) or (Addon.playerName and srcName and not IsSecretValue(srcName) and srcName == Addon.playerName) then
                                                playerTotal = playerTotal + NumberOrZero(SafeTableGet(src, "totalAmount"))
                                            end
                                        end
                                    end
                                end
                            end
                            -- Player's per-spell breakdown. If the GUID-keyed read
                            -- fails but the roster flagged the player as local,
                            -- retry with nil source args (supported).
                            local okSource, playerBlock = pcall(C_DamageMeter.GetCombatSessionSourceFromID, id, meterType, Addon.playerGUID)
                            if (not okSource or (type(playerBlock) ~= "table") or MeterSourceTotal(playerBlock) == 0) and playerIsLocal then
                                okSource, playerBlock = pcall(C_DamageMeter.GetCombatSessionSourceFromID, id, meterType, nil, nil)
                            end
                            if okSource and type(playerBlock) == "table" and MeterSourceTotal(playerBlock) > 0 then
                                local blockTotal = AddMeterSource(playerBlock)
                                if blockTotal > 0 then
                                    Addon.totalDamage = Addon.totalDamage + blockTotal
                                elseif playerTotal > 0 then
                                    Addon.totalDamage = Addon.totalDamage + playerTotal
                                end
                            elseif playerTotal > 0 then
                                -- No spell breakdown available; count the roster total only.
                                Addon.totalDamage = Addon.totalDamage + playerTotal
                            end
                        end
                    end
                end
            end
        end
    end)

    if not ok then
        Addon.meterReadError = "Meter read error: " .. tostring(err)
        print("|cffff4444[DummyAnalyzer]|r " .. Addon.meterReadError)
    elseif Addon.totalDamage == 0 and Addon.debugMode then
        print("|cff33ff33[DummyAnalyzer Debug]|r No damage found in any meter session/source")
    end

    -- Fallback: the built-in meter's current session rolls over at combat end,
    -- so the post-combat read above can legitimately return nothing. Use the
    -- in-combat delta snapshot accumulated by CaptureCombatSnapshot instead.
    if Addon.totalDamage == 0 and combatSnapValid and combatSnapTotal > 0 then
        Addon.damageData = combatSnapData
        Addon.totalDamage = combatSnapTotal
        if Addon.debugMode then
            print("|cff33ff33[DummyAnalyzer Debug]|r Using in-combat meter snapshot: " .. ShortNum(Addon.totalDamage))
        end
    end

    -- EnemyDamageTaken fallback (EDIT#6, CombatAnalytics pattern): for a training
    -- dummy the damage the dummy "took" equals the player's damage dealt, so the
    -- EnemyDamageTaken meter type (10) is a reliable source when the DamageDone
    -- session hasn't settled yet. Mark the report as estimated.
    if Addon.totalDamage == 0 then
        local enemyType = 10
        if Enum and Enum.DamageMeterType then
            local okEt, ev2 = pcall(function() return Enum.DamageMeterType.EnemyDamageTaken end)
            if okEt and ev2 then enemyType = ev2 end
        end
        local okSessions2, sessions2 = pcall(C_DamageMeter.GetAvailableCombatSessions)
        if okSessions2 and type(sessions2) == "table" then
            local enemyTotal = 0
            for _, s2 in ipairs(sessions2) do
                if type(s2) == "table" then
                    local id2 = SafeTableGet(s2, "sessionID")
                    if id2 then
                        local okEnemy, enemyBlock = pcall(C_DamageMeter.GetCombatSessionSourceFromID, id2, enemyType, nil, nil)
                        if okEnemy and type(enemyBlock) == "table" then
                            enemyTotal = enemyTotal + MeterSourceTotal(enemyBlock)
                        else
                            local okEnemy2, enemySession = pcall(C_DamageMeter.GetCombatSessionFromID, id2, enemyType)
                            if okEnemy2 and type(enemySession) == "table" then
                                enemyTotal = enemyTotal + NumberOrZero(SafeTableGet(enemySession, "totalAmount"))
                            end
                        end
                    end
                end
            end
            if enemyTotal > 0 then
                Addon.totalDamage = enemyTotal
                Addon.damageFromEnemyFallback = true
                if Addon.debugMode then
                    print("|cff33ff33[DummyAnalyzer Debug]|r Using EnemyDamageTaken fallback: " .. ShortNum(Addon.totalDamage))
                end
            end
        end
    end

    if Addon.totalDamage == 0 then
        Addon.meterDiag = BuildMeterDiag()
    end
    return Addon.totalDamage > 0
end

-- ============================================
-- Meter diagnostics (report-aided debugging). Whenever the meter read comes
-- back empty, GenerateReportText includes this so we can see exactly what the
-- C_DamageMeter APIs return in-game (and whether amounts are secret values).
-- ============================================
-- MUST be declared before BuildMeterDiag (lexical scope) - calls through pcall
    -- so a missing/misbehaving issecretvalue global can't crash the report.
    local function DiagSecret(val)
        local ok, isSec = pcall(isecretvalue, val)
        return ok and isSec and "YES" or "no"
    end

 BuildMeterDiag = function()
    local out = {}
    if Addon.meterReadError then
        table.insert(out, "READ-ERROR: " .. tostring(Addon.meterReadError))
    end

    local okAvail, availOk, availReason = pcall(function()
        return C_DamageMeter.IsDamageMeterAvailable()
    end)
    if okAvail then
        table.insert(out, "IsDamageMeterAvailable: " .. tostring(availOk) .. (availReason and (" (" .. tostring(availReason) .. ")") or ""))
    else
        table.insert(out, "IsDamageMeterAvailable: ERROR " .. tostring(availOk))
    end

    local okSess, sessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
    if okSess and type(sessions) == "table" then
        table.insert(out, "AvailableSessions: " .. tostring(#sessions))
        for _, s in ipairs(sessions) do
            if type(s) == "table" then
                local id = SafeTableGet(s, "sessionID")
                table.insert(out, "  session id=" .. tostring(id) .. " name=" .. tostring(SafeTableGet(s, "name")) .. " dur=" .. tostring(SafeTableGet(s, "durationSeconds")))
                local okCS, cs = pcall(C_DamageMeter.GetCombatSessionFromID, id, 0)
                if okCS and type(cs) == "table" then
                    local tot = SafeTableGet(cs, "totalAmount")
                    local srcs = SafeTableGet(cs, "combatSources")
                    table.insert(out, "    FromID(" .. tostring(id) .. ") total=" .. tostring(tot) .. " secret=" .. tostring(DiagSecret(tot)) .. " sources=" .. (type(srcs) == "table" and tostring(#srcs) or "none"))
                    if type(srcs) == "table" then
                        for _, src in ipairs(srcs) do
                            if type(src) == "table" then
                                table.insert(out, "      src guid=" .. tostring(SafeTableGet(src, "sourceGUID")) .. " local=" .. tostring(SafeTableGet(src, "isLocalPlayer") == true) .. " total=" .. tostring(SafeTableGet(src, "totalAmount")))
                            end
                        end
                    end
                    local okPS, playerSource = pcall(C_DamageMeter.GetCombatSessionSourceFromID, id, 0, Addon.playerGUID)
                    table.insert(out, "    PlayerSource(id," .. tostring(id) .. ") " .. (okPS and (type(playerSource) == "table" and ("spells=" .. tostring(#(MeterSourceSpells(playerSource) or {})) .. " total=" .. tostring(SafeTableGet(playerSource, "totalAmount"))) or tostring(playerSource)) or "FAILED"))
                else
                    table.insert(out, "    GetCombatSessionFromID FAILED" .. (okCS and (" nil=" .. tostring(cs)) or ""))
                end
            end
        end
    else
        table.insert(out, "GetAvailableCombatSessions FAILED returned: " .. tostring(sessions))
    end

    local function probeLegacy(guid)
        local okL, l = pcall(C_DamageMeter.GetCombatSessionSourceFromType, 1, 0, guid)
        return okL and l or nil
    end
    local legacy = probeLegacy(Addon.playerGUID)
    if not legacy then legacy = probeLegacy() end
    if type(legacy) == "table" then
        local tot = SafeTableGet(legacy, "totalAmount")
        local spells = MeterSourceSpells(legacy)
        table.insert(out, "Legacy(1,0) total=" .. tostring(tot) .. " secret=" .. tostring(DiagSecret(tot)) .. " spells=" .. (type(spells) == "table" and tostring(#spells) or "none"))
    else
        table.insert(out, "Legacy(1,0) returned: " .. tostring(legacy))
    end

    local okSrc, src = pcall(C_DamageMeter.GetCombatSessionSourceFromID, 0, 0, Addon.playerGUID)
    table.insert(out, "SourceFromID(0,0,guid): " .. (okSrc and (type(src) == "table" and ("total=" .. tostring(SafeTableGet(src, "totalAmount"))) or tostring(src)) or "FAILED"))

    return table.concat(out, "\n")
end

-- ============================================
-- In-combat damage meter capture.
-- The built-in meter's 'current' session rolls over when combat ends, so the
-- post-combat read in ReadDamageMeterData can come back empty. We poll the
-- meter every tick DURING the test instead and accumulate the per-session
-- delta, so damage data survives even if the post-combat read returns nothing.
-- ============================================
local meterSessionLast = {}
local combatSnapTotal = 0
local combatSnapData = {}
local combatSnapValid = false

local function MergeMeterSpellDelta(amount, spell)
    if not (amount and amount > 0) or type(spell) ~= "table" then return end
    local spellID = SafeTableGet(spell, "spellID")
    local name = GetSpellName(spellID)
    if not name then return end
    local existing = combatSnapData[name]
    local aps = NumberOrZero(SafeTableGet(spell, "amountPerSecond"))
    local overkill = NumberOrZero(SafeTableGet(spell, "overkillAmount"))
    local details = SafeTableGet(spell, "combatSpellDetails")
    local hits = 0
    local highest = 0
    if type(details) == "table" then
        hits = #details
        for _, d in ipairs(details) do
            if type(d) == "table" then
                local amt = NumberOrZero(SafeTableGet(d, "amount"))
                if amt > highest then highest = amt end
            end
        end
    end
    if existing then
        existing.total = (existing.total or 0) + amount
        existing.hits = (existing.hits or 0) + hits
        if highest > (existing.highest or 0) then existing.highest = highest end
        existing.aps = (existing.aps or 0) + aps
        existing.overkill = (existing.overkill or 0) + overkill
    else
        combatSnapData[name] = { total = amount, hits = hits, highest = highest, aps = aps, overkill = overkill }
    end
end

-- Accumulates the per-tick delta from the meter for one source block.
local function AccumulateSourceDelta(key, src)
    local spells = MeterSourceSpells(src)
    if not spells then return end
    local last = meterSessionLast[key] or { spells = {} }
    for _, spell in ipairs(spells) do
        if type(spell) == "table" then
            local spellID = SafeTableGet(spell, "spellID")
            if spellID then
                local curTotal = NumberOrZero(SafeTableGet(spell, "totalAmount"))
                local prevTotal = last.spells[spellID] or 0
                local delta = curTotal - prevTotal
                if delta < 0 then delta = curTotal end -- session reset
                if delta > 0 then
                    MergeMeterSpellDelta(delta, spell)
                    combatSnapTotal = combatSnapTotal + delta
                end
                last.spells[spellID] = curTotal
            end
        end
    end
    meterSessionLast[key] = last
    combatSnapValid = true
end

local function ResetMeterCapture()
    meterSessionLast = {}
    combatSnapTotal = 0
    combatSnapData = {}
    combatSnapValid = false
end

-- baselineOnly=true seeds the previous totals (called at test start) without
-- adding anything, so later ticks only count damage dealt during the test.
local function CaptureCombatSnapshot(baselineOnly)
    if not Addon.testActive or not C_DamageMeter then return end
    local ok, err = pcall(function()
        local okAvail, sessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
        if okAvail and type(sessions) == "table" then
            for _, s in ipairs(sessions) do
                if type(s) == "table" then
                    local id = SafeTableGet(s, "sessionID")
                    if id then
                        local okSrc, src = pcall(C_DamageMeter.GetCombatSessionSourceFromID, id, 0, Addon.playerGUID)
                        if okSrc and type(src) == "table" then
                            local key = "session_" .. tostring(id)
                            if baselineOnly then
                                local spells = MeterSourceSpells(src)
                                if spells then
                                    local last = {}
                                    for _, spell in ipairs(spells) do
                                        if type(spell) == "table" and SafeTableGet(spell, "spellID") then
                                            last[SafeTableGet(spell, "spellID")] = NumberOrZero(SafeTableGet(spell, "totalAmount"))
                                        end
                                    end
                                    meterSessionLast[key] = last
                                end
                            else
                                AccumulateSourceDelta(key, src)
                            end
                        end
                    end
                end
            end
        end

        -- Legacy per-type source handled the same way.
        local okLegacy, legacy = pcall(C_DamageMeter.GetCombatSessionSourceFromType, 1, 0, Addon.playerGUID)
        if not okLegacy or type(legacy) ~= "table" then
            okLegacy, legacy = pcall(C_DamageMeter.GetCombatSessionSourceFromType, 1, 0)
        end
        if okLegacy and type(legacy) == "table" then
            if baselineOnly then
                local spells = MeterSourceSpells(legacy)
                if spells then
                    local last = {}
                    for _, spell in ipairs(spells) do
                        if type(spell) == "table" and SafeTableGet(spell, "spellID") then
                            last[SafeTableGet(spell, "spellID")] = NumberOrZero(SafeTableGet(spell, "totalAmount"))
                        end
                    end
                    meterSessionLast["legacy"] = last
                end
            else
                AccumulateSourceDelta("legacy", legacy)
            end
        end
    end)
    if Addon.debugMode and not ok then
        print("|cff33ff33[DummyAnalyzer Debug]|r Capture snapshot error: " .. tostring(err))
    end
end

local function RecordSpell(spellId)
    if not Addon.testActive or not spellId or IsSecretValue(spellId) then return end
    local name = GetSpellName(spellId)
    if Addon.debugMode then
        print(string.format("|cff33ff33[DEBUG]|r Spell recorded: %s (ID: %s)", name or "?", spellId))
    end
    local elapsed = GetTime() - Addon.startTime
    local buffSnapshot = {}
    for key, buff in pairs(Addon.activeBuffs) do
        if not buff.expiresAt or buff.expiresAt > GetTime() then
            buffSnapshot[key] = buff.name or key
        end
    end
    local safeName = name
    if safeName and not pcall(string.byte, safeName, 1) then safeName = "Unknown" end
    local costData = nil
    if safeName and safeName ~= "Unknown" then
        local costOk, costInfo = pcall(C_Spell.GetSpellPowerCost, spellId)
        if costOk and type(costInfo) == "table" then
            for _, entry in ipairs(costInfo) do
                if type(entry) == "table" and type(entry.cost) == "number" and entry.cost > 0 then
                    local ptName = entry.name
                    if ptName and IsSecretValue(ptName) then ptName = "?" end
                    costData = {cost = entry.cost, powerType = ptName or "?"}
                    if not Addon.spellPowerCosts[safeName] then
                        Addon.spellPowerCosts[safeName] = {totalCost = 0, count = 0, powerType = ptName or "?"}
                    end
                    Addon.spellPowerCosts[safeName].totalCost = Addon.spellPowerCosts[safeName].totalCost + entry.cost
                    Addon.spellPowerCosts[safeName].count = Addon.spellPowerCosts[safeName].count + 1
                    break
                end
            end
        end
    end
    table.insert(Addon.spellHistory, {time = elapsed, name = safeName, buffs = buffSnapshot, cost = costData})
    RecordKnownBuffCast(spellId, name)
end

-- ============================================
-- DAMAGETRACKING EXPORTS (namespace promotion, rule A/B)
-- ============================================
Addon.ResetDamageData = ResetDamageData
Addon.ReadDamageMeterData = ReadDamageMeterData
Addon.ResetMeterCapture = ResetMeterCapture
Addon.CaptureCombatSnapshot = CaptureCombatSnapshot
Addon.RecordSpell = RecordSpell