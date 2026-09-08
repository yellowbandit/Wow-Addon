local AddonName, Addon = ...
-- ============================================
-- EMS SEQUENCE EXPORT + TALENT SCANNER + SimC FILTER
-- ============================================
local GetCharDB = Addon.GetCharDB
local NumberOrZero = Addon.NumberOrZero
local DebugLog = Addon.DebugLog

-- ROTATION_EXCLUDE is promoted shared mutable state (rule A). Assigned here;
-- SimCImport.lua reads it via Addon.ROTATION_EXCLUDE at runtime.
Addon.ROTATION_EXCLUDE = {
    -- Universal: auto-attack variants (every class has one of these in combat log)
    ["Auto Attack"] = true, ["Attack"] = true, ["Melee"] = true,     ["Shoot"] = true, ["Auto Shot"] = true,
    ["Wand"] = true,
    -- Universal: taunt/threat abilities (never in DPS rotation)
    ["Taunt"] = true, ["Growl"] = true, ["Mind Soothe"] = true,
    -- Stats/sources that SimC reports but aren't castable actions
    ["Leech"] = true,
    -- SimC proc variant names (Lightning Strike / Ground Current Lightning Strike procs)
    ["GCLS Thunder Blast"] = true, ["GCLS Thunder Clap"] = true, ["GCLS Revenge"] = true,
    ["LS Thunder Blast"] = true, ["LS Thunder Clap"] = true, ["LS Revenge"] = true,
    ["Shield Charge (AoE)"] = true, ["Ignore Pain (VO)"] = true,
    -- Non-DPS rotation spells (defensive CDs, utility, openers)
    -- Major defensive CDs — NEVER suggest in rotation (oh-shit buttons)
    ["Shield Wall"] = true, ["Last Stand"] = true, ["Fortifying Brew"] = true,
    ["Dampen Harm"] = true, ["Diffuse Magic"] = true, ["Divine Protection"] = true,
    ["Guardian of Ancient Kings"] = true, ["Ardent Defender"] = true,
    -- Utility / opener / non-rotation
    ["Charge"] = true, ["Heroic Throw"] = true,
    ["Rend"] = true, -- DoT (SimC counts ticks as "casts", not intended for manual rotation in Prot)
    -- Movement (detected by spell school/mechanic — these are the universal names)
    -- Class-specific entries removed: addon now relies on GRIP-EMS detection + SimC
    -- to determine what belongs in a rotation sequence.
    -- Shapeshift forms: switching forms mid-fight is never a rotation action and drops
    -- the current tank form (Cat/Moonkin out of Bear, etc.) — never suggest in a sequence.
    ["Cat Form"] = true, ["Bear Form"] = true, ["Moonkin Form"] = true,
    ["Tree of Life"] = true, ["Travel Form"] = true, ["Aquatic Form"] = true,
    ["Flight Form"] = true, ["Swift Flight Form"] = true,
    -- Heart of the Wild (druid class talent): activating it shifts the druid out of
    -- Bear/Cat form mid-fight — never include in a tanking/dummy sequence. Both SimC
    -- titlecase-variant casings are covered (SimCName produces "Heart Of The Wild").
    ["Heart of the Wild"] = true, ["Heart Of The Wild"] = true,
}

local _validSpellCache = {}
local function IsValidMacroSpell(spellName)
    if not spellName then return false end
    if _validSpellCache[spellName] ~= nil then return _validSpellCache[spellName] end
    if Addon.ROTATION_EXCLUDE[spellName] then _validSpellCache[spellName] = false; return false end
    local itemID = GetItemInfoInstant(spellName)
    if not itemID then
        for slot = 1, 19 do
            local link = GetInventoryItemLink("player", slot)
            if link then
                local id = tonumber(link:match("Hitem:(%d+)"))
                if id then
                    local itemName = C_Item.GetItemInfo(id)
                    if itemName == spellName then itemID = id; break end
                end
            end
        end
    end
    if itemID then
        local ok, info = pcall(C_Item.GetItemInfo, C_Item, itemID)
        if ok and info then
            -- Only on-use items (effectTrigger==0, cooldown>0) are macro-usable
            if info.effectTrigger == 0 and info.effectCooldown and info.effectCooldown > 0 then _validSpellCache[spellName] = true; return true end
            DebugLog("debug", "IsValidMacroSpell", "passive-item:"..spellName.." trigger="..tostring(info.effectTrigger))
            _validSpellCache[spellName] = false; return false
        end
    end
    local exists = false
    if C_Spell and C_Spell.DoesSpellExist then
        exists = C_Spell.DoesSpellExist(spellName)
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, C_Spell, spellName)
        if ok and info then
            if info.isPassive then DebugLog("debug", "IsValidMacroSpell", "passive:"..spellName); _validSpellCache[spellName] = false; return false end
            exists = true
        end
    end
    local result = exists or false
    _validSpellCache[spellName] = result
    return result
end

-- Returns true if a spell can be deliberately cast by the player and tracked
-- in the combat log as a player-initiated action (not a proc, passive, or auto-effect).
-- Used to filter SimC data to only include spells DummyAnalyzer can actually observe.
local function IsTrackableCast(spellName)
    if not IsValidMacroSpell(spellName) then return false end
    -- Items can be used via /use, but only if they have an on-use effect
    if GetItemInfo(spellName) then
        local itemID = GetItemInfoInstant(spellName)
        if itemID then
            local ok, info = pcall(C_Item.GetItemInfo, C_Item, itemID)
            if ok and info then
                local hasOnUse = (info.effectSpellID and info.effectSpellID > 0)
                    or (info.effectCooldown and info.effectCooldown > 0)
                    or (info.effectTrigger and info.effectTrigger > 0)
                if hasOnUse then return true end
                return false
            end
        end
        return true
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, C_Spell, spellName)
        if ok and info then
            -- Passive spells can't be deliberately cast
            if info.passive then return false end
            local spellID = info.spellID or info.id
            if spellID then
                -- Spells in the player's spellbook are castable
                if IsPlayerSpell(spellID) then return true end
                -- Spells with a cast time are deliberate casts
                if info.castTime and info.castTime > 0 then return true end
                -- Not in spellbook, no cast time → proc or passive effect
                return false
            end
        end
    end
    return true
end

Addon.FilterSimCData = function(castCounts, damageData)
    if not castCounts then return castCounts, damageData end
    local filteredCasts = {}
    local filteredDmg = {}
    for name, count in pairs(castCounts) do
        if IsTrackableCast(name) then
            filteredCasts[name] = count
            if damageData and damageData[name] then
                filteredDmg[name] = damageData[name]
            end
        end
    end
    return filteredCasts, filteredDmg
end

-- ============================================
-- TALENT SCANNER
-- ============================================
-- Scans active class + hero talents and returns:
--   talentedSpells: { [spellName] = true } — spells directly granted by talents
--   modifiedSpells: { [spellName] = "TalentName" } — rotation spells boosted by passives
--   heroTalentName: string — active hero talent spec name
Addon.ScanPlayerTalents = function()
    local talentedSpells = {}
    local modifiedSpells = {}
    local heroTalentName = ""

    if not C_ClassTalents or not C_Traits then return talentedSpells, modifiedSpells, heroTalentName end

    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then return talentedSpells, modifiedSpells, heroTalentName end

    local configInfo = C_Traits.GetConfigInfo(configID)
    if not configInfo or not configInfo.treeIDs then return talentedSpells, modifiedSpells, heroTalentName end

    -- Collect all rotation-relevant spell names from available data for tooltip scanning
    local db = GetCharDB()
    local rotationSpells = {}
    if db then
        for _, log in ipairs(db.logs or {}) do
            if log.castCounts then
                for name in pairs(log.castCounts) do
                    if IsValidMacroSpell(name) then
                        rotationSpells[name] = true
                    end
                end
            end
            -- Also pull from SimC data if available
            if log.isSimC and log.castCounts then
                for name in pairs(log.castCounts) do
                    if IsValidMacroSpell(name) then
                        rotationSpells[name] = true
                    end
                end
            end
        end
    end

    for _, treeID in ipairs(configInfo.treeIDs) do
        local nodeIDs = C_Traits.GetTreeNodes(treeID)
        if nodeIDs then
            for _, nodeID in ipairs(nodeIDs) do
                local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
                if nodeInfo and nodeInfo.activeEntry and nodeInfo.activeEntry.rank > 0 then
                    local entryInfo = C_Traits.GetEntryInfo(configID, nodeInfo.activeEntry.entryID)
                    if entryInfo and entryInfo.definitionID then
                        local defInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
                        if defInfo then
                            local spellID = defInfo.overriddenSpellID or defInfo.spellID
                            if spellID then
                                local spellName = nil
                                if C_Spell and C_Spell.GetSpellInfo then
                                    local ok, info = pcall(C_Spell.GetSpellInfo, C_Spell, spellID)
                                    if ok and info then spellName = info.name end
                                end
                                if not spellName then spellName = tostring(spellID) end
                                if spellName and spellName ~= "" then
                                    talentedSpells[spellName] = true
                                    -- Check talent description for spell name mentions (passive modifications)
                                    local spellDesc = ""
                                    if C_Spell and C_Spell.GetSpellInfo then
                                        local ok, info = pcall(C_Spell.GetSpellInfo, C_Spell, spellID)
                                        if ok and info then
                                            local desc = info.description or info.Description or ""
                                            if desc ~= "" then spellDesc = desc end
                                        end
                                    end
                                    if spellDesc ~= "" then
                                        for rotName in pairs(rotationSpells) do
                                            if rotName ~= spellName and spellDesc:find(rotName, 1, true) then
                                                modifiedSpells[rotName] = spellName
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Hero talent spec name
    local heroSpecID = C_ClassTalents.GetActiveHeroTalentSpec()
    if heroSpecID then
        local name, _, _ = GetSpecializationInfoByID(heroSpecID)
        if name then heroTalentName = name end
    end

    return talentedSpells, modifiedSpells, heroTalentName
end

-- Returns the appropriate macro command prefix for a given action.
-- Uses /use for items (trinkets, potions, etc.), /cast for spells.
-- Steps are standard WoW macro strings and support ALL conditionals:
--   [combat] [nocombat] [known:Spell] [mod:ctrl/shift/alt]
--   [@focus] [@mouseover] [@player] [@cursor]
--   [exists] [dead] [help] [harm] [nodead] [stance:N]
--   [channeling] [nochanneling] [mounted] [swimming]
--   [indoors] [outdoors] [flyable] [button:N] [bar:N]
--   [spec:N] [talent:X/Y] [group:party/raid] [pet] [nopet]
--   [equipped:item] [worn:item]
-- Slash commands: /cast, /use, /castsequence, /castrandom,
--   /userandom, /target, /focus, /assist, /stopcasting, /startattack
-- GRIP-EMS handles sequencing/reset internally; /castsequence
-- and reset=N are not needed in step strings.
-- Generate sequential step macro: /cast [combat] AbilityName
-- Generate item step macro:       /use [combat] TrinketName
-- Generate known-conditional:     /cast [known:AbilityName,combat] AbilityName
local function GetActionPrefix(name)
    if GetItemInfo(name) then return "/use" end
    return "/cast"
end

Addon.GenerateEMSSequence = function(castCounts, damageData, ensureSpells, buffUptime)
    if not castCounts or not next(castCounts) then return "No cast data." end
    -- Build ensure set from optional param
    local mustInclude = {}
    if ensureSpells then
        for _, s in ipairs(ensureSpells) do mustInclude[s] = true end
    end
    -- Normalize buffUptime keys: buffUptime is indexed by "spell_<id>" (BuildBuffKey),
    -- but castCounts/damageData use spell name strings. Build a name-indexed map.
    local buffByName = {}
    if buffUptime then
        for key, info in pairs(buffUptime) do
            local name = info.name or key
            if name and (info.uptime or 0) > 0 then
                buffByName[name] = { uptime = info.uptime }
            end
        end
    end
    -- Look up SimC log for rotational importance signals
    local simcCasts = {}
    local db = GetCharDB()
    if db.simcLogId and db.simcLogId > 0 then
        for _, l in ipairs(db.logs) do
            if l.id == db.simcLogId and l.isSimC and l.castCounts then
                for name, count in pairs(l.castCounts) do
                    if IsValidMacroSpell(name) then
                        simcCasts[name] = count
                    end
                end
            end
        end
    end
    -- Scan active talents for scoring boosts
    local talentedSpells, modifiedSpells, heroTalentName = Addon.ScanPlayerTalents()
    local sorted = {}
    local totalDmg, totalCasts = 0, 0
    for name, count in pairs(castCounts) do
        local dmg = 0
        if damageData and damageData[name] then
            dmg = NumberOrZero(damageData[name].total)
        end
        totalDmg = totalDmg + dmg
        totalCasts = totalCasts + count
        local ensureMult = mustInclude[name] and 5.0 or 1.0
        local uptimePct = buffByName[name] and buffByName[name].uptime or 0
        local talentMult = talentedSpells[name] and 1.5 or (modifiedSpells[name] and 1.25 or 1.0)
        local simcMult = simcCasts[name] and 1.3 or 1.0
        table.insert(sorted, {name = name, dmg = dmg, count = count, ensureMult = ensureMult, uptimePct = uptimePct, talentMult = talentMult, simcMult = simcMult})
    end
    local avgDmg = totalCasts > 0 and totalDmg / totalCasts or 1
    local function Score(entry)
        local uptimeBonus = (entry.uptimePct or 0) / 100 * avgDmg * 10
        local zeroDmgBonus = (entry.dmg == 0 and entry.count > 0) and avgDmg * 5 or 0
        return (entry.dmg + entry.count * avgDmg * entry.ensureMult + uptimeBonus + zeroDmgBonus) * entry.talentMult * entry.simcMult
    end
    table.sort(sorted, function(a, b) return Score(a) > Score(b) end)
    local     filtered = {}
    local ensuredLeft = {}
    for k in pairs(mustInclude) do ensuredLeft[k] = true end
    for _, entry in ipairs(sorted) do
        if IsValidMacroSpell(entry.name) then
            table.insert(filtered, entry)
            ensuredLeft[entry.name] = nil
        end
    end
    DebugLog("info", "gen-seq", string.format("Sorted %d entries into %d filtered (avgDmg=%.0f)", #sorted, #filtered, avgDmg), { top5 = { sorted[1] and sorted[1].name, sorted[2] and sorted[2].name, sorted[3] and sorted[3].name, sorted[4] and sorted[4].name, sorted[5] and sorted[5].name } })
    -- Any ensured spell that was filtered out (e.g. zero damage, not in castHistory) — add it anyway if valid
    for name in pairs(ensuredLeft) do
        if IsValidMacroSpell(name) then
            table.insert(filtered, {name = name, dmg = 0, count = 0, ensureMult = 5.0, uptimePct = 0, talentMult = 1.0, simcMult = 1.0})
        end
    end
    sorted = filtered
    if #sorted == 0 then return "No castable spells found." end
    local classFilename = select(2, UnitClass("player")) or "Unknown"
    local specName = ""
    local spec = GetSpecialization()
    if spec then
        specName = select(2, GetSpecializationInfo(spec)) or ""
    end
    -- Identify high-frequency spells for interleave (top third by cast count with >5 casts)
    local maxCount = sorted[1] and sorted[1].count or 1
    local interleaveCandidates = {}
    for _, entry in ipairs(sorted) do
        if entry.count >= 5 and entry.count >= maxCount * 0.4 then
            interleaveCandidates[entry.name] = math.max(2, math.floor(#sorted / math.min(entry.count, #sorted)))
        end
    end
    -- Build output with duplicates and interleave annotations
    local finalSteps = {}
    for i, entry in ipairs(sorted) do
        local prefix = GetActionPrefix(entry.name)
        local stepText = string.format("%s [combat] %s", prefix, entry.name)
        local interval = interleaveCandidates[entry.name]
        if interval then
            stepText = stepText .. string.format(" (interval:%d)", interval)
        end
        table.insert(finalSteps, stepText)
    end
    -- Add duplicates of top 2 spells at lower positions for second-chance coverage
    local dedupNames = {}
    for i = 1, math.min(2, #sorted) do
        local topSpell = sorted[i].name
        if not dedupNames[topSpell] then
            dedupNames[topSpell] = true
            local prefix = GetActionPrefix(topSpell)
            table.insert(finalSteps, string.format("%s [combat] %s [dupe]", prefix, topSpell))
            if #finalSteps >= 15 then break end
        end
    end

    local lines = {}
    lines[#lines + 1] = "=== " .. (sorted[1] and sorted[1].name or "Generated") .. " ==="
    lines[#lines + 1] = "Author: DummyAnalyzer"
    local specLine = string.format("Spec: %s %s", classFilename, specName)
    if heroTalentName and heroTalentName ~= "" then
        specLine = specLine .. string.format(" (%s)", heroTalentName)
    end
    lines[#lines + 1] = specLine
    lines[#lines + 1] = string.format("Icon: %s", sorted[1] and sorted[1].name or "INV_Misc_QuestionMark")
    lines[#lines + 1] = "Step Function: Priority"
    lines[#lines + 1] = "Reset: combat/target"
    lines[#lines + 1] = ""
    for i, entry in ipairs(finalSteps) do
        lines[#lines + 1] = string.format("%2d. %s", i, entry)
    end
    local result = table.concat(lines, "\n")
    DebugLog("info", "gen-seq", string.format("Returning %d steps, #filtered=%d", #finalSteps, #filtered), { topName = sorted[1] and sorted[1].name })
    return result
end

-- ============================================
-- SEQUENCE CORE EXPORTS (namespace promotion, rule B)
-- ============================================
Addon.IsValidMacroSpell = IsValidMacroSpell
Addon.GetActionPrefix = GetActionPrefix