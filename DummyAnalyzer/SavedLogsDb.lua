local AddonName, Addon = ...
-- ============================================
-- SAVED LOGS DATABASE
-- ============================================
DummyAnalyzerDB = DummyAnalyzerDB or {}

local IsSecretValue = Addon.IsSecretValue

local function GetCharDB()
    local key = Addon.playerGUID or "pending"
    if key ~= "pending" then
        local pending = DummyAnalyzerDB["pending"]
        if pending then
            local db = DummyAnalyzerDB[key]
            if not db then
                DummyAnalyzerDB[key] = pending
            else
                for k, v in pairs(pending) do
                    if k == "logs" and type(v) == "table" then
                        local maxId = 0
                        for _, lg in ipairs(db.logs or {}) do maxId = math.max(maxId, lg.id or 0) end
                        for _, lg in ipairs(v) do
                            if lg and type(lg) == "table" then
                                if not lg.id or lg.id <= maxId then
                                    maxId = maxId + 1
                                    lg.id = maxId
                                end
                                table.insert(db.logs, lg)
                            end
                        end
                        if (db.nextId or 0) <= maxId then db.nextId = maxId + 1 end
                    elseif db[k] == nil and v ~= nil then
                        db[k] = v
                    end
                end
            end
            DummyAnalyzerDB["pending"] = nil
        end
    end
    DummyAnalyzerDB[key] = DummyAnalyzerDB[key] or {logs = {}, nextId = 1, simcLogId = 0}
    return DummyAnalyzerDB[key]
end

local function DeepCopy(tbl)
    if not tbl then return nil end
    if type(tbl) ~= "table" then return tbl end
    local result = {}
    for k, v in pairs(tbl) do
        if not IsSecretValue(k) and not IsSecretValue(v) then
            if type(v) == "table" then
                result[k] = DeepCopy(v)
            else
                result[k] = v
            end
        end
    end
    return result
end

-- ============================================
-- ULTRA SAFE SPELL NAME HELPER (original)
-- ============================================
local function SafeTableGet(tbl, key)
    if not tbl or IsSecretValue(tbl) or IsSecretValue(key) then return nil end
    local ok, value = pcall(function() return tbl[key] end)
    if ok and not IsSecretValue(value) then return value end
    return nil
end

local function SafeTableSet(tbl, key, value)
    if not tbl or IsSecretValue(key) or IsSecretValue(value) then return end
    pcall(function() tbl[key] = value end)
end

local function GetSpellName(spellId)
    if not spellId or IsSecretValue(spellId) then return "Unknown" end
    local idStr = "UnknownID"
    local strOk, strResult = pcall(tostring, spellId)
    if strOk and strResult and not IsSecretValue(strResult) then
        idStr = "ID_" .. strResult
    end
    local cached = Addon.spellNameCache[idStr]
    if cached then return cached end
    local nameOk, name = pcall(C_Spell.GetSpellName, spellId)
    if nameOk and name and type(name) == "string" and not IsSecretValue(name) then
        Addon.spellNameCache[idStr] = name
        return name
    end
    return "Unknown"
end

local function BuildSpellNameCache()
    if not C_SpellBook then return end
    local numLines = C_SpellBook.GetNumSpellBookSkillLines()
    if not numLines or numLines == 0 then return end
    for skillIndex = 1, numLines do
        local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(skillIndex)
        if lineInfo then
            local offset = lineInfo.itemIndexOffset or 0
            local count = lineInfo.numSpellBookItems or 0
            for slotIdx = offset + 1, offset + count do
                local itemOk, itemInfo = pcall(C_SpellBook.GetSpellBookItemInfo, slotIdx, Enum.SpellBookSpellBank.Player)
                if itemOk and itemInfo and itemInfo.spellID and type(itemInfo.spellID) == "number" then
                    local key = "ID_" .. itemInfo.spellID
                    if not Addon.spellNameCache[key] then
                        local nameOk, name = pcall(C_Spell.GetSpellName, itemInfo.spellID)
    if nameOk and name and type(name) == "string" and not IsSecretValue(name) and pcall(string.byte, name, 1) then
                            Addon.spellNameCache[key] = name
                        end
                    end
                end
            end
        end
    end
end

-- ============================================
-- SPELL EQUIVALENCE (runtime spell folding, Hindsight-style)
-- ============================================
-- User-defined map { [displayNameA] = displayNameB }: wherever a spell named A
-- is compared/aggregated against SimC expectations, it folds into B first.
-- Fold happens at READ time (never mutates saved logs) so the map stays fully
-- reversible — change/clear it, re-import or re-test, and stored data is intact.
local function GetSpellEquiv()
    local db = GetCharDB()
    if not db.settings or not db.settings.spellEquiv then return {} end
    return db.settings.spellEquiv
end

local function ResolveSpellName(name)
    if not name or type(name) ~= "string" then return name end
    local equiv = GetSpellEquiv()
    local resolved = equiv[name]
    if resolved and type(resolved) == "string" and resolved ~= name then
        return resolved
    end
    return name
end

-- Returns NEW tables (originals untouched): castCounts[folded], damageData[folded]
-- with duplicate folded keys merged. nil-only inputs are fine.
local function FoldSpellData(castCounts, damageData)
    local equiv = GetSpellEquiv()
    local hasEquiv = false
    for _ in pairs(equiv) do hasEquiv = true break end
    if not hasEquiv then return castCounts, damageData end

    local outCasts
    if castCounts and type(castCounts) == "table" then
        outCasts = {}
        for name, count in pairs(castCounts) do
            local folded = equiv[name] or name
            if folded ~= name then
                outCasts[folded] = (outCasts[folded] or 0) + count
            else
                outCasts[name] = (outCasts[name] or 0) + count
            end
        end
    end

    local outDmg
    if damageData and type(damageData) == "table" then
        outDmg = {}
        for name, entry in pairs(damageData) do
            local folded = equiv[name] or name
            local total = (type(entry) == "table" and entry.total) or entry
            if folded ~= name then
                local cur = outDmg[folded]
                if not cur then cur = {total = 0} outDmg[folded] = cur end
                cur.total = (cur.total or 0) + (total or 0)
            else
                local cur = outDmg[name]
                if not cur then cur = {total = 0} outDmg[name] = cur end
                cur.total = (cur.total or 0) + (total or 0)
            end
        end
    end

    return outCasts or castCounts, outDmg or damageData
end

-- ============================================
-- SAVEDLOGSDB EXPORTS (namespace promotion, rule A/B)
-- ============================================
Addon.GetCharDB = GetCharDB
Addon.DeepCopy = DeepCopy
Addon.SafeTableGet = SafeTableGet
Addon.SafeTableSet = SafeTableSet
Addon.GetSpellName = GetSpellName
Addon.BuildSpellNameCache = BuildSpellNameCache
Addon.GetSpellEquiv = GetSpellEquiv
Addon.ResolveSpellName = ResolveSpellName
Addon.FoldSpellData = FoldSpellData