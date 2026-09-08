local AddonName, Addon = ...
-- ============================================
-- BUFF UPTIME TRACKING (original)
-- ============================================
local IsSecretValue = Addon.IsSecretValue
local SafeTableGet = Addon.SafeTableGet
local GetSpellName = Addon.GetSpellName
-- DamageTracking.lua (#4) loads before this module; alias is load-order-safe.
local RecordSpell = Addon.RecordSpell
local CaptureCombatSnapshot = Addon.CaptureCombatSnapshot

local MAX_TRACKED_BUFF_DURATION = Addon.MAX_TRACKED_BUFF_DURATION
local MAX_TRACKED_DEBUFF_DURATION = Addon.MAX_TRACKED_DEBUFF_DURATION
local ALWAYS_TRACK_BUFFS = Addon.ALWAYS_TRACK_BUFFS
local IGNORED_BUFFS = Addon.IGNORED_BUFFS
local BUFF_KEY_ALIASES = Addon.BUFF_KEY_ALIASES
local CAST_BUFF_DURATIONS = Addon.CAST_BUFF_DURATIONS

local function BuildBuffKey(spellId, spellName)
    if spellId and IsSecretValue(spellId) then return nil end
    if spellName and IsSecretValue(spellName) then spellName = nil end
    if spellId and BUFF_KEY_ALIASES[spellId] then return BUFF_KEY_ALIASES[spellId] end
    if spellId then return "spell_" .. tostring(spellId) end
    if spellName then return "name_" .. tostring(spellName) end
    return nil
end

local function SafeNumber(value)
    if value == nil or IsSecretValue(value) then return nil end
    local ok, numberValue = pcall(function() return tonumber(value) end)
    if ok then return numberValue end
    return nil
end

local function NumberOrZero(value)
    return SafeNumber(value) or 0
end

local function Ems_Default(value, fallback)
    if value == nil then return fallback end
    return value
end

local function ShouldTrackBuff(spellId, duration)
    if not spellId or IsSecretValue(spellId) then return false end
    if IGNORED_BUFFS[spellId] then return false end
    if ALWAYS_TRACK_BUFFS[spellId] then return true end

    local plainDuration = SafeNumber(duration)
    if not plainDuration or plainDuration <= 0 then return false end
    return plainDuration <= MAX_TRACKED_BUFF_DURATION
end

local function AddBuffUptime(key, name, seconds)
    if not key or not seconds or seconds <= 0 then return end
    if not Addon.buffUptime[key] then
        Addon.buffUptime[key] = {name = name or key, uptime = 0}
    elseif name and Addon.buffUptime[key].name == key then
        Addon.buffUptime[key].name = name
    end
    Addon.buffUptime[key].uptime = Addon.buffUptime[key].uptime + seconds
end

local function CloseExpiredTimedBuffs(now)
    now = now or GetTime()
    for key, buff in pairs(Addon.activeBuffs) do
        if buff.expiresAt and now >= buff.expiresAt then
            AddBuffUptime(key, buff.name, buff.expiresAt - buff.activeSince)
            Addon.lastBuffExpiry[key] = buff.expiresAt
            Addon.activeBuffs[key] = nil
        end
    end
end

local function ResetBuffTracking()
    if Addon.buffTicker then
        Addon.buffTicker:Cancel()
        Addon.buffTicker = nil
    end
    Addon.activeBuffs = {}
    Addon.buffUptime = {}
    Addon.activeDebuffs = {}
    Addon.debuffUptime = {}
    Addon.buffGaps = {}
    Addon.lastBuffExpiry = {}
    Addon.spellPowerCosts = {}
end

local function StartBuff(spellId, spellName)
    if not Addon.testActive then return end
    local key = BuildBuffKey(spellId, spellName)
    if not key then return end
    if not Addon.activeBuffs[key] then
        Addon.activeBuffs[key] = {name = spellName or key, activeSince = GetTime()}
    elseif spellName and Addon.activeBuffs[key].name == key then
        Addon.activeBuffs[key].name = spellName
    end
end

local function RefreshTimedBuff(spellId, spellName, duration)
    if not Addon.testActive or not spellId or not duration then return end
    local key = BuildBuffKey(spellId, spellName)
    if not key then return end

    local now = GetTime()
    local expiresAt = now + duration
    local buff = Addon.activeBuffs[key]
    if buff and buff.expiresAt and now > buff.expiresAt then
        AddBuffUptime(key, buff.name, buff.expiresAt - buff.activeSince)
        Addon.lastBuffExpiry[key] = buff.expiresAt
        buff = nil
    end

    if not buff then
        if Addon.lastBuffExpiry[key] then
            local gap = now - Addon.lastBuffExpiry[key]
            if gap > 0.5 then
                if not Addon.buffGaps[key] then Addon.buffGaps[key] = {name = spellName or key, gaps = {}} end
                table.insert(Addon.buffGaps[key].gaps, gap)
            end
            Addon.lastBuffExpiry[key] = nil
        end
        Addon.activeBuffs[key] = {name = spellName or key, activeSince = now, expiresAt = expiresAt}
    else
        buff.name = spellName or buff.name
        buff.expiresAt = math.max(buff.expiresAt or now, expiresAt)
    end
end

local function RecordKnownBuffCast(spellId, spellName)
    if not spellId or IsSecretValue(spellId) then return end
    local config = CAST_BUFF_DURATIONS[spellId]
    if not config then return end
    RefreshTimedBuff(spellId, config.name or spellName, config.duration)
end

local function StopBuff(spellId, spellName)
    if not Addon.testActive then return end
    local key = BuildBuffKey(spellId, spellName)
    if not key then return end
    local buff = Addon.activeBuffs[key]
    if not buff then return end
    local now = GetTime()
    AddBuffUptime(key, spellName or buff.name, now - buff.activeSince)
    Addon.activeBuffs[key] = nil
end

local function PollPlayerBuffs()
    if not Addon.testActive or not C_UnitAuras or not C_UnitAuras.GetUnitAuras then return end

    CloseExpiredTimedBuffs()
    local ok, allBuffs = pcall(C_UnitAuras.GetUnitAuras, "player", "HELPFUL")
    if not ok or type(allBuffs) ~= "table" then return end

    local seen = {}
    for i = 1, #allBuffs do
        local auraInfo = allBuffs[i]
        if type(auraInfo) == "table" then
            local spellId = SafeTableGet(auraInfo, "spellId")
            local duration = SafeTableGet(auraInfo, "duration")
            if ShouldTrackBuff(spellId, duration) then
                local key = BuildBuffKey(spellId)
                if key then
                    seen[key] = true
                    if not Addon.activeBuffs[key] then
                        Addon.activeBuffs[key] = {name = GetSpellName(spellId), activeSince = GetTime()}
                        -- Record detected cast for off-GCD spells (Shield Block, Ignore Pain) that don't fire UNIT_SPELLCAST_SUCCEEDED
                        if CAST_BUFF_DURATIONS[spellId] then
                            RecordSpell(spellId)
                        end
                    end
                end
            end
        end
    end

    for key, buff in pairs(Addon.activeBuffs) do
        if not buff.expiresAt and not seen[key] then
            AddBuffUptime(key, buff.name, GetTime() - buff.activeSince)
            Addon.activeBuffs[key] = nil
        end
    end
end

local function AddDebuffUptime(key, name, seconds)
    if not key or not seconds or seconds <= 0 then return end
    if not Addon.debuffUptime[key] then
        Addon.debuffUptime[key] = {name = name or key, uptime = 0}
    elseif name and Addon.debuffUptime[key].name == key then
        Addon.debuffUptime[key].name = name
    end
    Addon.debuffUptime[key].uptime = Addon.debuffUptime[key].uptime + seconds
end

local function PollTargetDebuffs()
    if not Addon.testActive or not C_UnitAuras or not C_UnitAuras.GetUnitAuras then return end
    local existsOk, exists = pcall(UnitExists, "target")
    if not existsOk or not exists then return end

    local ok, allDebuffs = pcall(C_UnitAuras.GetUnitAuras, "target", "HARMFUL PLAYER")
    if not ok or type(allDebuffs) ~= "table" then return end

    local seen = {}
    for i = 1, #allDebuffs do
        local auraInfo = allDebuffs[i]
        if type(auraInfo) == "table" then
            local spellId = SafeTableGet(auraInfo, "spellId")
            local duration = SafeNumber(SafeTableGet(auraInfo, "duration"))
            if spellId and not IsSecretValue(spellId) and duration and duration > 0 and duration <= MAX_TRACKED_DEBUFF_DURATION then
                local key = BuildBuffKey(spellId)
                if key then
                    seen[key] = true
                    if not Addon.activeDebuffs[key] then
                        Addon.activeDebuffs[key] = {name = GetSpellName(spellId), activeSince = GetTime()}
                    end
                end
            end
        end
    end

    for key, debuff in pairs(Addon.activeDebuffs) do
        if not seen[key] then
            AddDebuffUptime(key, debuff.name, GetTime() - debuff.activeSince)
            Addon.activeDebuffs[key] = nil
        end
    end
end

local function ResetHealthFallback()
    Addon.healthBaseHp = nil
    Addon.healthTotal = 0
    Addon.healthTrackReady = false
    Addon.damageFromHealthFallback = false
end

-- Track the training dummy's health bar so totalDamage still works even when
-- Blizzard's built-in damage meter is disabled (user preference). Accumulates
-- positive health deltas on "target"; a spike upward (dummy reset/re-target)
-- only re-baselines without counting. Health may be a secret value in some
-- contexts, so every read is pcall-guarded and skipped if we can't read it.
local function TrackTargetHealth()
    if not Addon.testActive then return end
    local okMax, mhp = pcall(UnitHealthMax, "target")
    if not okMax or type(mhp) ~= "number" or IsSecretValue(mhp) then
        Addon.healthTrackReady = false
        return
    end
    if mhp <= 0 then return end
    local okCur, hp = pcall(UnitHealth, "target")
    if not okCur or type(hp) ~= "number" or IsSecretValue(hp) then
        Addon.healthTrackReady = false
        return
    end
    if hp < 0 then hp = 0 end
    if hp > mhp then hp = mhp end
    if not Addon.healthBaseHp then
        Addon.healthBaseHp = hp
        Addon.healthTotal = 0
        Addon.healthTrackReady = true
        return
    end
    local delta = Addon.healthBaseHp - hp
    if delta > 0 then
        Addon.healthTotal = Addon.healthTotal + delta
    end
    Addon.healthBaseHp = hp
    Addon.healthTrackReady = true
end

local function PollTestMetrics()
    CaptureCombatSnapshot(false)
    TrackTargetHealth()
    PollPlayerBuffs()
    PollTargetDebuffs()
end

local function StartBuffTicker()
    if Addon.buffTicker then
        Addon.buffTicker:Cancel()
        Addon.buffTicker = nil
    end
    PollTestMetrics()
    if C_Timer and C_Timer.NewTicker then
        Addon.buffTicker = C_Timer.NewTicker(0.5, PollTestMetrics)
    end
end

local function FinalizeBuffTracking()
    if Addon.buffTicker then
        Addon.buffTicker:Cancel()
        Addon.buffTicker = nil
    end
    local now = GetTime()
    for key, buff in pairs(Addon.activeBuffs) do
        local endTime = buff.expiresAt and math.min(now, buff.expiresAt) or now
        AddBuffUptime(key, buff.name, endTime - buff.activeSince)
    end
    Addon.activeBuffs = {}
    for key, debuff in pairs(Addon.activeDebuffs) do
        AddDebuffUptime(key, debuff.name, now - debuff.activeSince)
    end
    Addon.activeDebuffs = {}
end

-- ============================================
-- BUFFTRACKING EXPORTS (namespace promotion, rule A/B)
-- ============================================
Addon.SafeNumber = SafeNumber
Addon.NumberOrZero = NumberOrZero
Addon.RecordKnownBuffCast = RecordKnownBuffCast
Addon.Ems_Default = Ems_Default
Addon.ResetBuffTracking = ResetBuffTracking
Addon.StartBuffTicker = StartBuffTicker
Addon.FinalizeBuffTracking = FinalizeBuffTracking
Addon.ResetHealthFallback = ResetHealthFallback