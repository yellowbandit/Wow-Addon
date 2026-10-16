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

-- In-combat meter snapshot state. MUST be declared above ReadDamageMeterData:
-- it reads combatSnapValid/Total at the top of the file, so placing these
-- locals below that function would resolve them to nil globals and dead-code
-- the snapshot fallback (a real bug found after the split).
local combatSnapTotal = 0
local combatSnapData = {}
local combatSnapPetTotal = 0
local combatSnapPetData = {}
local combatSnapValid = false

local function ResetDamageData()
    Addon.damageData = {}
    Addon.petDamageData = {}
    Addon.petTotalDamage = 0
    Addon.totalDamage = 0
    Addon.damageFromEnemyFallback = false
    Addon.petSources = nil
    Addon.meterDetailDiag = nil
    Addon.meterSpellKeys = nil
    Addon.meterSpellList = nil
    Addon.meterDiagSpellsTotal = 0
    Addon.meterDiagSpellsWithDetails = 0
    Addon.meterDiagSpellsWithRows = 0
end

-- Amounts can live under several keys depending on the C_DamageMeter build and
-- whether the built-in meter UI is enabled (meter-disabled users see lists but
-- nil "totalAmount"). Try every known alias before giving up; also sum per-spell
-- rows as a last resort when the block-level aggregate is missing.
local function SpellTotal(spell)
    if type(spell) ~= "table" then return 0 end
    local v = SafeTableGet(spell, "totalAmount")
    if not v or v <= 0 then v = SafeTableGet(spell, "amount") end
    if not v or v <= 0 then v = SafeTableGet(spell, "total") end
    if not v or v <= 0 then v = SafeTableGet(spell, "damage") end
    return NumberOrZero(v)
end

-- SpellTotal + hit-by-hit detail amounts (used by the live in-combat capture
-- when block/spell totals are nil, which is exactly what meter-disabled users
-- see).
local function SpellTotalWithDetails(spell)
    local v = SpellTotal(spell)
    if v > 0 then return v end
    local details = type(spell) == "table" and SafeTableGet(spell, "combatSpellDetails")
    if type(details) == "table" then
        for _, d in ipairs(details) do
            if type(d) == "table" then
                v = v + NumberOrZero(SafeTableGet(d, "amount"))
            end
        end
    end
    return NumberOrZero(v)
end

-- Forward declaration: MeterSourceTotal (below) calls MeterSourceSpells, which
-- is assigned later in this chunk. Lua locals are in scope only after their
-- declaration, so declare the name up-front and assign afterwards.
local MeterSourceSpells

local function MeterSourceTotal(block)
    if type(block) ~= "table" then return 0 end
    local v = SafeTableGet(block, "totalAmount")
    if not v or v <= 0 then v = SafeTableGet(block, "amount") end
    if not v or v <= 0 then v = SafeTableGet(block, "total") end
    if not v or v <= 0 then v = SafeTableGet(block, "damage") end
    if not v or v <= 0 then
        -- Block aggregate missing/nil: sum the per-spell totals. Each spell row
        -- may carry a totalAmount OR hit-by-hit combatSpellDetails with `amount`;
        -- sum whichever is present.
        local spells = MeterSourceSpells(block)
        if type(spells) == "table" then
            local sum = 0
            for _, spell in ipairs(spells) do
                local st = SpellTotal(spell)
                if not st or st <= 0 then
                    local details = type(spell) == "table" and SafeTableGet(spell, "combatSpellDetails")
                    if type(details) == "table" then
                        for _, d in ipairs(details) do
                            if type(d) == "table" then
                                st = st + NumberOrZero(SafeTableGet(d, "amount"))
                            end
                        end
                    end
                end
                sum = sum + st
            end
            v = sum
        end
    end
    return NumberOrZero(v)
end

local function SameGuid(a, b)
    if not a or not b then return false end
    if IsSecretValue(a) or IsSecretValue(b) then return false end
    local ok, eq = pcall(function() return a == b end)
    return ok and eq == true
end

MeterSourceSpells = function(block)
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
                Addon.meterDiagSpellsTotal = (Addon.meterDiagSpellsTotal or 0) + 1
                local totalAmt = SpellTotal(spell)
                if not totalAmt or totalAmt <= 0 then
                    local details0 = SafeTableGet(spell, "combatSpellDetails")
                    if type(details0) == "table" then
                        for _, d0 in ipairs(details0) do
                            if type(d0) == "table" then
                                totalAmt = totalAmt + NumberOrZero(SafeTableGet(d0, "amount"))
                            end
                        end
                    end
                end
                local aps = NumberOrZero(SafeTableGet(spell, "amountPerSecond"))
                local overkill = NumberOrZero(SafeTableGet(spell, "overkillAmount"))
                local details = SafeTableGet(spell, "combatSpellDetails")
                local hits = 0
                local highest = 0
                local isPetSpell = false
                if type(details) == "table" then
                    hits = #details
                    for _, d in ipairs(details) do
                        if type(d) == "table" then
                            local amt = NumberOrZero(SafeTableGet(d, "amount"))
                            if amt > highest then highest = amt end
                            if SafeTableGet(d, "isPet") == true then isPetSpell = true end
                        end
                    end
                end
                -- 12.1.5: the meter tags creature-sourced spells by creatureName
                -- (pet/guardian name); player-cast rows carry an empty name.
                local cn = SafeTableGet(spell, "creatureName")
                if not isPetSpell and type(cn) == "string" and cn ~= "" and cn ~= (Addon.playerName or "") then
                    isPetSpell = true
                end
                if not Addon.meterSpellKeys then
                    local sk = {}
                    for k in pairs(spell) do sk[#sk + 1] = tostring(k) end
                    table.sort(sk)
                    Addon.meterSpellKeys = table.concat(sk, ",")
                end
                if type(details) == "table" then
                    Addon.meterDiagSpellsWithDetails = (Addon.meterDiagSpellsWithDetails or 0) + 1
                    if #details > 0 then
                        Addon.meterDiagSpellsWithRows = (Addon.meterDiagSpellsWithRows or 0) + 1
                        if not Addon.meterDetailDiag then
                            local sampleKeys = {}
                            local row1 = details[1]
                            if type(row1) == "table" then
                                for k in pairs(row1) do
                                    sampleKeys[#sampleKeys + 1] = tostring(k)
                                end
                                table.sort(sampleKeys)
                            end
                            local okIsp, ispv = pcall(function() return row1 and row1.isPet end)
                            local okUn, unv = pcall(function() return row1 and row1.unitName end)
                            Addon.meterDetailDiag = {
                                spellID = spellID,
                                name = name,
                                nDetails = #details,
                                sampleKeys = table.concat(sampleKeys, ","),
                                rawIsPet = okIsp and tostring(ispv) or "ERR",
                                rawUnitName = okUn and tostring(unv) or "ERR",
                            }
                        end
                    end
                end
                if not Addon.meterSpellList then Addon.meterSpellList = {} end
                if #Addon.meterSpellList < 20 then
                    local okCN, cnv = pcall(function() return spell.creatureName end)
                    local cnDisp
                    if not okCN then
                        cnDisp = "ERR"
                    else
                        local okSec, isSec = pcall(issecretvalue, cnv)
                        if okSec and isSec then cnDisp = "SECRET" else cnDisp = tostring(cnv) end
                    end
                    Addon.meterSpellList[#Addon.meterSpellList + 1] = string.format("%s#%s cn=%s", tostring(name), tostring(spellID), cnDisp)
                end
                local target = isPetSpell and Addon.petDamageData or Addon.damageData
                if isPetSpell then
                    Addon.petTotalDamage = Addon.petTotalDamage + totalAmt
                end
                local existing = target[name]
                if existing then
                    existing.total = (existing.total or 0) + totalAmt
                    existing.hits = (existing.hits or 0) + hits
                    if highest > existing.highest then existing.highest = highest end
                    existing.aps = (existing.aps or 0) + aps
                    existing.overkill = (existing.overkill or 0) + overkill
                else
                    target[name] = {
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

    -- Pet damage split (meter isPet tag) captured by the in-combat delta path.
    -- Additive reporting only: Addon.totalDamage already includes pet damage, so
    -- this just exposes the pet portion for the report's split-by-pet section.
    if combatSnapValid and combatSnapPetTotal and combatSnapPetTotal > 0 then
        Addon.petDamageData = combatSnapPetData
        Addon.petTotalDamage = combatSnapPetTotal
        if Addon.debugMode then
            print("|cff33ff33[DummyAnalyzer Debug]|r Pet damage split (snapshot): " .. ShortNum(Addon.petTotalDamage))
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
    -- Pet/guardian source split runs on EVERY meter read (not just the fallback
    -- branches above), independent of damage total. Resolved via the namespace
    -- because CollectPetSources is declared below this function in the file.
    Addon.CollectPetSources()
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

    -- Dump the actual keys present on a block/spell row so the report shows what
    -- the meter really returns for a meter-disabled user (field names vary).
    local function DiagKeys(tbl, maxItems)
        if type(tbl) ~= "table" then return tostring(tbl) end
        local keys = {}
        for k in pairs(tbl) do
            table.insert(keys, tostring(k))
        end
        table.sort(keys)
        if maxItems and #keys > maxItems then
            return table.concat(keys, ",", 1, maxItems) .. ",..."
        end
        return table.concat(keys, ",")
    end

    -- ============================================
    -- Pet/guardian source split. The built-in meter's session roster
    -- (combatSources) is the only API that exposes OTHER combatants (a hunter
    -- pet, guardian, totem, etc.) next to the player, so the per-source split
    -- reads the roster directly rather than guessing source struct field names.
    -- Dump the first non-player source's keys into the report so we can confirm
    -- the struct layout in-game before trusting `totalAmount`/`name`.
    -- ============================================
    local function CollectPetSources()
        Addon.petSources = nil
        Addon.petSourceKeys = nil
        Addon.petSourceDiag = nil
        if not C_DamageMeter then
            Addon.petSourceDiag = "no C_DamageMeter"
            return
        end
        local ok, err = pcall(function()
            local meterType = 0
            local petList = {}
            -- The meter rolls each player's own pet damage INTO that player's source
            -- entry, so the roster never lists OUR pets. Collect the owned pet GUIDs
            -- from UnitGUID and probe GetCombatSessionSourceFromID(id, type, petGUID)
            -- per-owned-pet so the meter's own pet block (if any) shows their totals.
            local ownedPets = {}
            -- UnitGUID can return a SECRET value in 12.x; pcall-tostring it into a
            -- plain string key, or drop it (tostring on a secret value THROWS and the
            -- whole collector pcall would abort before petSourceDiag is assigned).
            local function GuideDisplay(guid)
                if not guid then return nil end
                if IsSecretValue(guid) then return "SECRET" end
                local okG, sG = pcall(tostring, guid)
                if okG and type(sG) == "string" and sG ~= "" then return sG end
                return nil
            end
            local function OwnedPetStr(ownedPets, sGuid)
                for i = 1, #ownedPets do
                    if ownedPets[i].disp == sGuid then return ownedPets[i] end
                end
                return nil
            end
            local function noteOwned(rawGuid)
                local sGuid = GuideDisplay(rawGuid)
                if not sGuid then return end
                ownedPets[#ownedPets + 1] = { raw = rawGuid, disp = sGuid }
            end
            local pOk1, g1 = pcall(UnitGUID, "pet")
            local pOk2, g2 = pcall(UnitGUID, "pet2")
            if pOk1 then noteOwned(g1) end
            if pOk2 then noteOwned(g2) end
            local diag = { "meterAvail=" .. tostring(C_DamageMeter.IsDamageMeterAvailable() or false) }
            diag[#diag + 1] = "ownedPetCount=" .. tostring(#ownedPets)
            for i = 1, #ownedPets do
                diag[#diag + 1] = "  ownedPet" .. i .. "=" .. tostring(ownedPets[i].disp)
            end
            local okSessions, sessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
            diag[#diag + 1] = "sessionsOk=" .. tostring(okSessions) .. " sessions=" .. tostring(type(sessions))
            local sessionCount = 0
            if okSessions and type(sessions) == "table" then
                sessionCount = #sessions
                diag[#diag + 1] = "sessionCount=" .. tostring(sessionCount)
                for _, s in ipairs(sessions) do
                    if type(s) == "table" then
                        local id = SafeTableGet(s, "sessionID")
                        diag[#diag + 1] = "sid=" .. tostring(id) .. " keys={" .. tostring(DiagKeys(s, 12)) .. "}"
                        if id then
                            local okSession, session = pcall(C_DamageMeter.GetCombatSessionFromID, id, meterType)
                            diag[#diag + 1] = "  fromID_ok=" .. tostring(okSession) .. " session=" .. tostring(type(session))
                            -- Probe the meter for each OWNED pet GUID: the roster omits pets,
                            -- but the per-source API may still resolve our pets by GUID.
                            for i = 1, #ownedPets do
                                local rawGuid = ownedPets[i].raw
                                local okPS, petBlock = pcall(C_DamageMeter.GetCombatSessionSourceFromID, id, meterType, rawGuid)
                                local pTotal = okPS and type(petBlock) == "table" and MeterSourceTotal(petBlock) or 0
                                diag[#diag + 1] = "    petSrcFromID(" .. tostring(ownedPets[i].disp) .. ") ok=" .. tostring(okPS) .. " type=" .. tostring(type(petBlock)) .. " total=" .. tostring(pTotal)
                                if okPS and type(petBlock) == "table" and pTotal > 0 then
                                    local pname = SafeTableGet(petBlock, "name")
                                    local existing
                                    for _, pe in ipairs(petList) do
                                        if pe.guid == ownedPets[i].disp then existing = pe break end
                                    end
                                    if existing then
                                        existing.total = existing.total + pTotal
                                    else
                                        petList[#petList + 1] = {
                                            guid = ownedPets[i].disp,
                                            name = (pname and not IsSecretValue(pname) and tostring(pname)) or ("Owned pet " .. ownedPets[i].disp),
                                            total = pTotal,
                                            keys = DiagKeys(petBlock, 16),
                                        }
                                        if not Addon.petSourceKeys then
                                            Addon.petSourceKeys = DiagKeys(petBlock, 24)
                                        end
                                    end
                                end
                            end
                            if okSession and type(session) == "table" then
                                local sources = SafeTableGet(session, "combatSources")
                                diag[#diag + 1] = "  srcKey=" .. tostring(DiagKeys(session, 20))
                                diag[#diag + 1] = "  combatSources=" .. tostring(type(sources)) .. " n=" .. tostring(type(sources) == "table" and #sources or -1)
                                if type(sources) == "table" then
                                    for _, pres in ipairs(sources) do
                                        if type(pres) == "table" then
                                            local pguid = SafeTableGet(pres, "sourceGUID")
                                            local plocal = SafeTableGet(pres, "isLocalPlayer") == true
                                            local pname = SafeTableGet(pres, "name")
                                            local pguidStr = pguid and GuideDisplay(pguid)
                                            diag[#diag + 1] = "    src: keys={" .. tostring(DiagKeys(pres, 14)) .. "} guidSecret=" .. tostring(pguid and DiagSecret(pguid)) .. " local=" .. tostring(plocal) .. " name=" .. tostring(pname and (IsSecretValue(pname) and "SECRET" or pname) or "nil")
                                            local isPlayer = plocal or SameGuid(pguid, Addon.playerGUID) or (Addon.playerName and pname and not IsSecretValue(pname) and pname == Addon.playerName)
                                            local isOwnedPet = not isPlayer and pguidStr and pguidStr ~= "SECRET" and OwnedPetStr(ownedPets, pguidStr)
                                            if isOwnedPet then
                                                diag[#diag + 1] = "    OWNED-PET ROSTER MATCH: " .. tostring(pguidStr)
                                                local existing
                                                for _, pe in ipairs(petList) do
                                                    if pe.guid == pguidStr then existing = pe break end
                                                end
                                                local ptotal = NumberOrZero(SafeTableGet(pres, "totalAmount"))
                                                if existing then
                                                    existing.total = existing.total + ptotal
                                                    if not existing.keys then
                                                        existing.keys = DiagKeys(pres, 16)
                                                    end
                                                else
                                                    petList[#petList + 1] = {
                                                        guid = pguidStr,
                                                        name = (pname and not IsSecretValue(pname) and tostring(pname)) or "Owned pet",
                                                        total = ptotal,
                                                        keys = DiagKeys(pres, 16),
                                                    }
                                                    if not Addon.petSourceKeys then
                                                        Addon.petSourceKeys = DiagKeys(pres, 24)
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
            table.sort(petList, function(a, b) return b.total > a.total end)
            Addon.petSources = petList
            Addon.petSourceDiag = table.concat(diag, "\n")
        end)
        if not ok then
            Addon.petSourceDiag = "CollectPetSources error: " .. tostring(err)
            if Addon.debugMode then
                print("|cff33ff33[DummyAnalyzer Debug]|r CollectPetSources error: " .. tostring(err))
            end
        end
        if Addon.debugMode then
            print("|cff33ff33[DummyAnalyzer Debug]|r Pet sources found: " .. tostring(#(Addon.petSources or {})))
        end
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
                    table.insert(out, "    PlayerSource(id," .. tostring(id) .. ") " .. (okPS and (type(playerSource) == "table" and ("spells=" .. tostring(#(MeterSourceSpells(playerSource) or {})) .. " total=" .. tostring(SafeTableGet(playerSource, "totalAmount")) .. " keys={" .. DiagKeys(playerSource, 12) .. "}") or tostring(playerSource)) or "FAILED"))
                    local psSpells = MeterSourceSpells(playerSource)
                    if type(playerSource) == "table" and type(psSpells) == "table" and psSpells[1] and type(psSpells[1]) == "table" then
                        table.insert(out, "      firstSpell keys={" .. DiagKeys(psSpells[1], 12) .. "} totals=" .. tostring(SpellTotal(psSpells[1])))
                    end
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

local function MergeMeterSpellDelta(amount, spell)
    if not (amount and amount > 0) or type(spell) ~= "table" then return end
    local spellID = SafeTableGet(spell, "spellID")
    local name = GetSpellName(spellID)
    if not name then return end
    local aps = NumberOrZero(SafeTableGet(spell, "amountPerSecond"))
    local overkill = NumberOrZero(SafeTableGet(spell, "overkillAmount"))
    local details = SafeTableGet(spell, "combatSpellDetails")
    local hits = 0
    local highest = 0
    local isPetSpell = false
    if type(details) == "table" then
        hits = #details
        for _, d in ipairs(details) do
            if type(d) == "table" then
                if SafeTableGet(d, "isPet") == true then isPetSpell = true end
                local amt = NumberOrZero(SafeTableGet(d, "amount"))
                if amt > highest then highest = amt end
            end
        end
    end
    local cn = SafeTableGet(spell, "creatureName")
    if not isPetSpell and type(cn) == "string" and cn ~= "" and cn ~= (Addon.playerName or "") then
        isPetSpell = true
    end
    local bucket = isPetSpell and combatSnapPetData or combatSnapData
    local existing = bucket[name]
    if isPetSpell then combatSnapPetTotal = combatSnapPetTotal + amount end
    if existing then
        existing.total = (existing.total or 0) + amount
        existing.hits = (existing.hits or 0) + hits
        if highest > (existing.highest or 0) then existing.highest = highest end
        existing.aps = (existing.aps or 0) + aps
        existing.overkill = (existing.overkill or 0) + overkill
    else
        bucket[name] = { total = amount, hits = hits, highest = highest, aps = aps, overkill = overkill }
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
                local curTotal = SpellTotalWithDetails(spell)
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
    combatSnapPetTotal = 0
    combatSnapPetData = {}
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
                                            last[SafeTableGet(spell, "spellID")] = SpellTotal(spell)
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
                            last[SafeTableGet(spell, "spellID")] = SpellTotal(spell)
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
Addon.CollectPetSources = CollectPetSources

-- Read-only accessor for the live in-combat meter snapshot total.
-- Consumed by the Practice Overlay (TestControl.lua) to show current DPS
-- mid-test without re-reading the meter. Secret-safe.
Addon.GetCombatSnapTotal = function()
    if IsSecretValue(combatSnapTotal) then return 0 end
    return combatSnapTotal
end

-- Live current-session damage total for the local player, read straight from the
-- meter roster (DamageMeterCombatSource.totalAmount). This is the value the
-- Blizzard/Elle damage meters display live; the per-spell delta path
-- (AccumulateSourceDelta) can stay empty mid-combat, so the Practice Overlay
-- reads this instead. Returns a plain number (0 when unavailable). Secret-safe.
local function GetLiveDamageTotal()
    if not C_DamageMeter then return 0 end
    local matched, allSum, count, legacyTotal, sessionTotal = 0, 0, 0, 0, 0
    local function addRoster(session)
        if type(session) ~= "table" then return end
        -- Session-level live total (populated even while per-source totalAmount
        -- is still nil mid-combat).
        local sTotal = NumberOrZero(SafeTableGet(session, "totalAmount"))
        if not IsSecretValue(sTotal) and sTotal > sessionTotal then sessionTotal = sTotal end
        local sources = SafeTableGet(session, "combatSources")
        if type(sources) ~= "table" then return end
        for _, src in ipairs(sources) do
            if type(src) == "table" then
                -- MeterSourceTotal falls back through totalAmount/amount/total/
                -- damage and finally per-spell rows, which Blizzard updates live.
                local amt = MeterSourceTotal(src)
                if not IsSecretValue(amt) then
                    allSum = allSum + amt
                    count = count + 1
                    local guid = SafeTableGet(src, "sourceGUID")
                    local isLocal = SafeTableGet(src, "isLocalPlayer") == true
                    local srcName = SafeTableGet(src, "name")
                    if isLocal or SameGuid(guid, Addon.playerGUID)
                        or (Addon.playerName and srcName and not IsSecretValue(srcName) and srcName == Addon.playerName) then
                        matched = matched + amt
                    end
                end
            end
        end
    end

    pcall(function()
        -- 1) Live CURRENT session (mirrors EllesmereUIDamageMeters).
        -- NOTE: the 2nd arg to the session APIs is the METER TYPE (not a
        -- placeholder). Passing 0 returns a roster whose amount fields stay nil
        -- mid-combat; the Damage-Done meter enum carries the live values.
        local sessionType = 1
        if Enum and Enum.DamageMeterSessionType then
            local okC, cv = pcall(function() return Enum.DamageMeterSessionType.Current end)
            if okC and cv then sessionType = cv end
        end
        local meterType = 0
        if Enum and Enum.DamageMeterType then
            local okD, dv = pcall(function() return Enum.DamageMeterType.DamageDone end)
            if okD and dv then meterType = dv end
        end
        pcall(function()
            local okS, session = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, meterType)
            if okS then addRoster(session) end
        end)
        -- 2) Completed sessions roster (only when Current yielded nothing).
        if count == 0 then
            local okSessions, sessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
            if okSessions and type(sessions) == "table" then
                for _, s in ipairs(sessions) do
                    local id = type(s) == "table" and SafeTableGet(s, "sessionID") or nil
                    if id then
                        local okSession, session = pcall(C_DamageMeter.GetCombatSessionFromID, id, meterType)
                        if okSession then addRoster(session) end
                    end
                end
            end
        end
        -- 3) Legacy per-type source (only when the roster path yielded nothing).
        if count == 0 then
            pcall(function()
                local okL, legacy = pcall(C_DamageMeter.GetCombatSessionSourceFromType, sessionType, meterType, Addon.playerGUID)
                if okL and type(legacy) == "table" then legacyTotal = NumberOrZero(MeterSourceTotal(legacy)) end
            end)
        end
    end)
    -- Prefer the player's own source. Fall back to the sole source (solo dummy
    -- test) or the full session sum so the overlay still ticks even when the
    -- mid-combat identity fields (sourceGUID/name/isLocalPlayer) read as secret.
    local best = 0
    if matched > 0 then best = matched
    elseif count == 1 then best = allSum
    elseif allSum > 0 then best = allSum
    elseif sessionTotal > 0 then best = sessionTotal
    elseif legacyTotal > 0 then best = legacyTotal end
    if IsSecretValue(best) then return 0 end
    return best
end
Addon.GetLiveDamageTotal = GetLiveDamageTotal

-- Returns the local player's RAW DamageMeterCombatSource row from the live
-- CURRENT DamageDone session, or nil. In combat this row's totalAmount /
-- amountPerSecond are SECRET values: callers MUST hand them straight to a widget
-- (AbbreviateNumbers + FontString:SetText) and NEVER tostring, divide, compare,
-- boolean-test, or store them. `isLocalPlayer` is never secret, so locating the
-- row here is safe. Mirrors the live read path EllesmereUIDamageMeters uses.
local function GetLivePlayerMeterSource()
    if not C_DamageMeter then return nil end
    local found
    pcall(function()
        local sessionType, meterType = 1, 0
        if Enum and Enum.DamageMeterSessionType then
            local okS, v = pcall(function() return Enum.DamageMeterSessionType.Current end)
            if okS and v then sessionType = v end
        end
        if Enum and Enum.DamageMeterType then
            local okT, v = pcall(function() return Enum.DamageMeterType.DamageDone end)
            if okT and v then meterType = v end
        end
        local okC, session = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, meterType)
        if not okC or type(session) ~= "table" then return end
        local sources = SafeTableGet(session, "combatSources")
        if type(sources) ~= "table" then return end
        for i = 1, #sources do
            local s = sources[i]
            if type(s) == "table" and SafeTableGet(s, "isLocalPlayer") == true then
                found = s
                return
            end
        end
    end)
    return found
end
Addon.GetLivePlayerMeterSource = GetLivePlayerMeterSource

-- One-shot diagnostic for the live meter read (/dummydebug live). Returns a

-- newline-joined report string; never throws. Run it DURING combat.
local function DiagLiveDamage()
    local out = {}
    local ok, err = pcall(function()
        local function add(s) out[#out + 1] = s end
        if not C_DamageMeter then add("C_DamageMeter = nil") return end
        add("apis: FromType=" .. tostring(C_DamageMeter.GetCombatSessionFromType ~= nil)
            .. " AvailSessions=" .. tostring(C_DamageMeter.GetAvailableCombatSessions ~= nil)
            .. " FromID=" .. tostring(C_DamageMeter.GetCombatSessionFromID ~= nil)
            .. " DurationSecs=" .. tostring(C_DamageMeter.GetSessionDurationSeconds ~= nil))
        local function S(v) local okv, r = pcall(tostring, v); if okv then return r end return "<err>" end
        add("api2: CurSessionID=" .. tostring(C_DamageMeter.GetCurrentSessionID ~= nil)
            .. " GetSessions=" .. tostring(C_DamageMeter.GetSessions ~= nil)
            .. " SessionInfo=" .. tostring(C_DamageMeter.GetSessionInfo ~= nil)
            .. " PlayerData=" .. tostring(C_DamageMeter.GetPlayerData ~= nil)
            .. " PartyData=" .. tostring(C_DamageMeter.GetPartyData ~= nil))
        local members = {}
        pcall(function()
            for k, v in pairs(C_DamageMeter) do
                if #members < 40 then members[#members + 1] = tostring(k) .. (type(v) == "function" and "()" or ":" .. type(v)) end
            end
        end)
        add("api3: C_DamageMeter members={" .. table.concat(members, ",") .. "}")
        pcall(function()
            if not C_DamageMeter.GetCurrentSessionID then return end
            local okID, sid = pcall(C_DamageMeter.GetCurrentSessionID)
            add("GetCurrentSessionID ok=" .. tostring(okID) .. " id=" .. S(sid))
            if not (okID and sid) then return end
            if C_DamageMeter.GetSessionInfo then
                local okI, info = pcall(C_DamageMeter.GetSessionInfo, sid)
                local ik, ic = "", 0
                if okI and type(info) == "table" then
                    for k, v in pairs(info) do ic = ic + 1; ik = ik .. tostring(k) .. "=" .. S(v) .. ","; if ic >= 15 then break end end
                end
                add("  SessionInfo ok=" .. tostring(okI) .. " type=" .. tostring(type(info)) .. " {" .. ik .. "}")
            end
            if C_DamageMeter.GetPlayerData then
                local pg = UnitGUID("player")
                local okP, pd = pcall(C_DamageMeter.GetPlayerData, sid, pg)
                local pk, pc = "", 0
                if okP and type(pd) == "table" then
                    for k, v in pairs(pd) do pc = pc + 1; pk = pk .. tostring(k) .. "=" .. S(v) .. ","; if pc >= 20 then break end end
                end
                add("  PlayerData ok=" .. tostring(okP) .. " type=" .. tostring(type(pd)) .. " {" .. pk .. "}")
            end
            if C_DamageMeter.GetPartyData then
                local okPa, party = pcall(C_DamageMeter.GetPartyData, sid)
                local cnt = type(party) == "table" and #party or tostring(party)
                add("  PartyData ok=" .. tostring(okPa) .. " type=" .. tostring(type(party)) .. " count=" .. tostring(cnt))
                if okPa and type(party) == "table" and type(party[1]) == "table" then
                    local qk, qc = "", 0
                    for k, v in pairs(party[1]) do qc = qc + 1; qk = qk .. tostring(k) .. "=" .. S(v) .. ","; if qc >= 20 then break end end
                    add("    party[1] {" .. qk .. "}")
                end
            end
        end)
        if C_Secrets and C_Secrets.ShouldUnitHealthBeSecret then
            local okSH, sh = pcall(C_Secrets.ShouldUnitHealthBeSecret, "target")
            add("C_Secrets.ShouldUnitHealthBeSecret('target') ok=" .. tostring(okSH) .. " = " .. S(sh))
        else
            add("C_Secrets.ShouldUnitHealthBeSecret = nil")
        end
        local sessionType = 1
        if Enum and Enum.DamageMeterSessionType then
            local okC, cv = pcall(function() return Enum.DamageMeterSessionType.Current end)
            if okC and cv then sessionType = cv end
        end
        local meterType = 0
        if Enum and Enum.DamageMeterType then
            local okD, dv = pcall(function() return Enum.DamageMeterType.DamageDone end)
            if okD and dv then meterType = dv end
        end
        add("sessionType=" .. tostring(sessionType) .. " meterType=" .. tostring(meterType)
            .. " (DamageDone=" .. tostring(Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageDone) .. ")")
        add("playerGUID secret=" .. tostring(IsSecretValue(Addon.playerGUID)) .. " playerName=" .. tostring(Addon.playerName))
        local okS, session = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, meterType)
        add("Current(" .. tostring(sessionType) .. ") GetCombatSessionFromType ok=" .. tostring(okS) .. " type=" .. tostring(type(session)))
        if okS and type(session) == "table" then
            local sources = SafeTableGet(session, "combatSources")
            add("  combatSources=" .. tostring(type(sources) == "table" and #sources or tostring(sources)))
            if type(sources) == "table" then
                for i = 1, math.min(#sources, 6) do
                    local src = sources[i]
                    if type(src) == "table" then
                        local ta = SafeTableGet(src, "totalAmount")
                        add(string.format("   src[%d] isLocal=%s guidSecret=%s totalAmount:type=%s secret=%s",
                            i, tostring(SafeTableGet(src, "isLocalPlayer")), tostring(IsSecretValue(SafeTableGet(src, "sourceGUID"))),
                            type(ta), tostring(IsSecretValue(ta))))
                        local okRaw, rawTA = pcall(rawget, src, "totalAmount")
                        add(string.format("    src[%d] rawget.totalAmount ok=%s type=%s secret=%s S=%s",
                            i, tostring(okRaw), type(rawTA), tostring(IsSecretValue(rawTA)), S(rawTA)))
                        local okDir, dirTA = pcall(function() return src.totalAmount end)
                        add(string.format("    src[%d] direct.totalAmount ok=%s type=%s secret=%s S=%s",
                            i, tostring(okDir), type(dirTA), tostring(IsSecretValue(dirTA)), S(dirTA)))
                        local rawAPS = rawget(src, "amountPerSecond")
                        add("    src[" .. i .. "] rawget.amountPerSecond type=" .. type(rawAPS) .. " secret=" .. tostring(IsSecretValue(rawAPS)) .. " S=" .. S(rawAPS))
                        local sk, sn = "", 0
                        for k in pairs(src) do sn = sn + 1; sk = sk .. tostring(k) .. "," ; if sn >= 20 then break end end
                        add("    src[" .. i .. "] keys={" .. sk .. "}")
                        local aps = SafeTableGet(src, "amountPerSecond")
                        add(string.format("    src[%d] amountPerSecond:type=%s secret=%s value=%s",
                            i, type(aps), tostring(IsSecretValue(aps)), tostring(not IsSecretValue(aps) and aps or nil)))
                        add("    src[" .. i .. "] MeterSourceTotal=" .. tostring(MeterSourceTotal(src)))
                        local taOk, taVal = pcall(function() return ta + 0 end)
                        add(string.format("    src[%d] totalAmount arith ok=%s val=%s err=%s",
                            i, tostring(taOk), tostring(taOk and taVal or nil), tostring(not taOk and taVal or nil)))
                    end
                end
            end
            local keys, n = "", 0
            for k in pairs(session) do n = n + 1; keys = keys .. tostring(k) .. "," ; if n >= 15 then break end end
            add("  session keys={" .. keys .. "}")
            local sTotal = SafeTableGet(session, "totalAmount")
            add(string.format("  session.totalAmount:type=%s secret=%s value=%s",
                type(sTotal), tostring(IsSecretValue(sTotal)), tostring(not IsSecretValue(sTotal) and sTotal or nil)))
            local rawST = rawget(session, "totalAmount")
            add("  session rawget.totalAmount type=" .. type(rawST) .. " secret=" .. tostring(IsSecretValue(rawST)) .. " S=" .. S(rawST))
        end
        add("GetLiveDamageTotal()=" .. tostring(Addon.GetLiveDamageTotal and Addon.GetLiveDamageTotal()))
        pcall(function()
            local okA, sess = pcall(C_DamageMeter.GetAvailableCombatSessions)
            add("availSessions ok=" .. tostring(okA) .. " type=" .. type(sess) .. " n=" .. tostring(type(sess) == "table" and #sess or "?"))
            if okA and type(sess) == "table" then
                for i = 1, math.min(#sess, 5) do
                    local s = sess[i]
                    local id = (type(s) == "table" and rawget(s, "sessionID")) or (type(s) == "number" and s) or nil
                    add("  avail[" .. i .. "] id=" .. S(id))
                    if id then
                        local okI, sess2 = pcall(C_DamageMeter.GetCombatSessionFromID, id, meterType)
                        if okI and type(sess2) == "table" then
                            local src2 = rawget(sess2, "combatSources")
                            local r1 = type(src2) == "table" and src2[1] or nil
                            local v1 = type(r1) == "table" and rawget(r1, "totalAmount") or nil
                            add("    FromID(" .. S(id) .. ") src1.totalAmount type=" .. type(v1) .. " secret=" .. tostring(IsSecretValue(v1)) .. " S=" .. S(v1))
                        end
                    end
                end
            end
        end)
        pcall(function()
            local okL, legacy = pcall(C_DamageMeter.GetCombatSessionSourceFromType, sessionType, meterType, Addon.playerGUID)
            add("legacySource ok=" .. tostring(okL) .. " type=" .. tostring(type(legacy)))
            if okL and type(legacy) == "table" then
                local lk, ln = "", 0
                for k in pairs(legacy) do ln = ln + 1; lk = lk .. tostring(k) .. ","; if ln >= 20 then break end end
                add("  legacy keys={" .. lk .. "}")
                local rawL = rawget(legacy, "totalAmount")
                add("  legacy.totalAmount raw type=" .. type(rawL) .. " secret=" .. tostring(IsSecretValue(rawL)) .. " S=" .. S(rawL))
            end
        end)
        add("GetCombatSnapTotal()=" .. tostring(Addon.GetCombatSnapTotal and Addon.GetCombatSnapTotal()))
        add("overlayBaseDamage=" .. tostring(Addon.overlayBaseDamage))
        add("healthTotal secret=" .. tostring(IsSecretValue(Addon.healthTotal))
            .. " value=" .. tostring(Addon.healthTotal)
            .. " healthBaseHp=" .. tostring(Addon.healthBaseHp)
            .. " healthTrackReady=" .. tostring(Addon.healthTrackReady))
        local okH, hp = pcall(UnitHealth, "target")
        local okHM, mhp = pcall(UnitHealthMax, "target")
        add(string.format("target: UnitHealth ok=%s type=%s secret=%s val=%s | UnitHealthMax ok=%s type=%s secret=%s val=%s",
            tostring(okH), type(hp), tostring(IsSecretValue(hp)), tostring(not IsSecretValue(hp) and hp or nil),
            tostring(okHM), type(mhp), tostring(IsSecretValue(mhp)), tostring(not IsSecretValue(mhp) and mhp or nil)))
        if Addon.testActive then add("testActive=true elapsed=" .. string.format("%.1f", GetTime() - (Addon.startTime or GetTime()))) end
        if Addon.overlaySamples and #Addon.overlaySamples > 0 then
            add("overlaySamples (" .. #Addon.overlaySamples .. "), last 10:")
            local start = math.max(1, #Addon.overlaySamples - 9)
            for i = start, #Addon.overlaySamples do
                local s = Addon.overlaySamples[i]
                add(string.format("   t=%.1f", s.t or 0))
            end
        else
            add("overlaySamples: none (overlay never ticked)")
        end
    end)
    if not ok then out[#out + 1] = "DIAG ERROR: " .. tostring(err) end
    return table.concat(out, "\n")
end
Addon.DiagLiveDamage = DiagLiveDamage