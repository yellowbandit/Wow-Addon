local AddonName, Addon = ...
-- ============================================
-- SAVED LOGS DATABASE
-- ============================================
DummyAnalyzerDB = DummyAnalyzerDB or {}

local IsSecretValue = Addon.IsSecretValue

local function GetCharDB()
    local key = Addon.playerGUID or "pending"
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
-- SAVEDLOGSDB EXPORTS (namespace promotion, rule A/B)
-- ============================================
Addon.GetCharDB = GetCharDB
Addon.DeepCopy = DeepCopy
Addon.SafeTableGet = SafeTableGet
Addon.SafeTableSet = SafeTableSet
Addon.GetSpellName = GetSpellName
Addon.BuildSpellNameCache = BuildSpellNameCache