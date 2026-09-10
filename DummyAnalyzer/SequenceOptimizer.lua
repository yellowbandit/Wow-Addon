local AddonName, Addon = ...
-- ============================================
-- SUGGESTED SEQUENCE GENERATION
-- ============================================
-- Heuristic learning solver: hill-climbing optimizer that learns from historical
-- player logs and SimC reference data. 500-generation local search with deficit-
-- driven mutation mechanics. Fully taint-safe (no live combat API reads).
local GetCharDB = Addon.GetCharDB
local NumberOrZero = Addon.NumberOrZero
local DebugLog = Addon.DebugLog
local Ems_Default = Addon.Ems_Default
local IsValidMacroSpell = Addon.IsValidMacroSpell
local GetActionPrefix = Addon.GetActionPrefix
local ScanPlayerTalents = Addon.ScanPlayerTalents
local FilterSimCData = Addon.FilterSimCData
local CAST_BUFF_DURATIONS_LOOKUP = Addon.CAST_BUFF_DURATIONS_LOOKUP

Addon.GenerateSuggestedSequence = function(castCounts, damageData, buffUptime, duration, buffGaps, seedSteps, priorHistory, selLogIds, customJitter, stepScale, requiredSpells)
    if not castCounts or not next(castCounts) then
        return "No cast data.", nil, "No cast data to analyze."
    end

    stepScale = stepScale or 1
    local playerGUID = UnitGUID("player") or "default"
    local db = GetCharDB()
    local cfg = db.settings or {}
    local MAX_GENS = 500
    local POP_SIZE = 1
    local PLATEAU_THRESH = 0.0005
    local PLATEAU_PATIENCE = 15

    -- =====================================================
    -- 1. LOAD HISTORICAL LOGS (DummyAnalyzerDB[playerGUID].logs)
    -- =====================================================
    local historicalLogs = {}
    if DummyAnalyzerDB and DummyAnalyzerDB[playerGUID] and DummyAnalyzerDB[playerGUID].logs then
        for _, logEntry in ipairs(DummyAnalyzerDB[playerGUID].logs) do
            table.insert(historicalLogs, logEntry)
        end
    end

    -- =====================================================
    -- 2. LOAD STORED SIMC DATA BLOCK (DummyAnalyzerDB[playerGUID].simcData)
    -- =====================================================
    local simcData = nil
    if DummyAnalyzerDB and DummyAnalyzerDB[playerGUID] and DummyAnalyzerDB[playerGUID].simcData then
        simcData = DummyAnalyzerDB[playerGUID].simcData
    end
    local simcCasts      = (simcData and simcData.castCounts) or {}
    local simcWeights    = (simcData and simcData.spellWeights) or {}
    local simcAplOrder   = (simcData and simcData.aplOrder) or {}
    local simcBuffBenefit = (simcData and simcData.buffBenefit) or {}
    local simcDuration   = (simcData and simcData.duration) or duration or 0

    local aplPosition = {}
    for i, n in ipairs(simcAplOrder) do aplPosition[n] = i end
    local aplMax = math.max(1, #simcAplOrder)

    -- =====================================================
    -- 3. NORMALIZE BUFF KEYS AND GAP DATA
    -- =====================================================
    local buffByName = {}
    if buffUptime then
        for key, info in pairs(buffUptime) do
            local name = info.name or key
            if name and (info.uptime or 0) > 0 then
                buffByName[name] = { uptime = info.uptime }
            end
        end
    end

    local buffMaxGap = {}
    if buffGaps then
        for key, data in pairs(buffGaps) do
            local name = data.name or key
            if data.gaps and #data.gaps > 0 then
                local maxG = 0
                for _, g in ipairs(data.gaps) do
                    if g > maxG then maxG = g end
                end
                buffMaxGap[name] = maxG
            end
        end
    end

    -- =====================================================
    -- 4. BUILD BASE ENTRIES FROM ACTUAL CAST DATA
    -- =====================================================
    local totalActualDmg, totalActualCasts = 0, 0
    local baseEntries = {}
    for name, count in pairs(castCounts) do
        if IsValidMacroSpell(name) then
            local dmg = (damageData and damageData[name]) and NumberOrZero(damageData[name].total) or 0
            totalActualDmg = totalActualDmg + dmg
            totalActualCasts = totalActualCasts + count
            table.insert(baseEntries, {
                name = name,
                dmg = dmg,
                count = count,
                dpc = count > 0 and dmg / count or 0
            })
        end
    end

    -- Add buff-only spells (have uptime but no cast data)
    if buffUptime then
        for key, info in pairs(buffUptime) do
            local name = info.name or key
            if name and (info.uptime or 0) > 0 then
                local found = false
                for _, e in ipairs(baseEntries) do
                    if e.name == name then found = true; break end
                end
                if not found and IsValidMacroSpell(name) then
                    table.insert(baseEntries, {name = name, dmg = 0, count = 0, dpc = 0})
                end
            end
        end
    end

    -- Add SimC-only spells (present in SimC but not in player data)
    for simcName, simcCount in pairs(simcCasts) do
        local found = false
        for _, e in ipairs(baseEntries) do
            if e.name == simcName then found = true; break end
        end
        if not found and IsValidMacroSpell(simcName) then
            table.insert(baseEntries, {name = simcName, dmg = 0, count = 0, dpc = 0})
        end
    end

    -- Required spells (Spells tab "Always") forced into the rotation.
    -- They become real optimization participants (dpc fill below) and
    -- Always-wins over Never (the neverSet filter keeps them).
    local reqSet = {}
    if requiredSpells and type(requiredSpells) == "table" then
        for _, reqName in ipairs(requiredSpells) do
            if type(reqName) == "string" and reqName ~= "" and IsValidMacroSpell(reqName) then
                reqSet[reqName] = true
                local found = false
                for _, e in ipairs(baseEntries) do
                    if e.name == reqName then found = true; break end
                end
                if not found then
                    table.insert(baseEntries, { name = reqName, dmg = 0, count = 0, dpc = 0 })
                end
            end
        end
    end

    -- Never spells (Spells tab "Never") are excluded from the rotation
    local neverSet = {}
    if cfg and type(cfg.neverSpells) == "table" then
        for _, n in ipairs(cfg.neverSpells) do
            if type(n) == "string" then
                local nn = n:gsub("^%s*(.-)%s*$", "%1")
                if nn ~= "" then neverSet[nn] = true end
            end
        end
    end
    if next(neverSet) then
        local kept = {}
        for _, e in ipairs(baseEntries) do
            if not neverSet[e.name] or reqSet[e.name] then kept[#kept + 1] = e end
        end
        baseEntries = kept
    end

    if #baseEntries == 0 then
        return "No castable spells found.", nil, "All spells filtered out."
    end

    local avgDmg = totalActualCasts > 0 and totalActualDmg / totalActualCasts or 1

    -- =====================================================
    -- 5. DEFICIT MATRIX
    -- =====================================================
    -- DeficitValue = (ActualCastRatio / SimCCastRatio)
    -- ActualCastRatio  = (actual_casts / total_actual_casts)
    -- SimCCastRatio    = (simc_expected       / total_simc_casts)
    -- deficit < 1 means under-cast relative to SimC, > 1 means over-cast
    local totalSimcCasts = 0
    for _, c in pairs(simcCasts) do totalSimcCasts = totalSimcCasts + c end
    local simcMult = (duration and duration > 0 and simcDuration > 0) and (duration / simcDuration) or 1

    local deficitMat  = {}
    local actualRatios = {}
    local simcRatios  = {}
    for _, e in ipairs(baseEntries) do
        local actualRatio = totalActualCasts > 0 and (e.count / totalActualCasts) or 0
        local simcExp = math.floor((simcCasts[e.name] or 0) * simcMult)
        local simcRatio = totalSimcCasts > 0 and (simcExp / math.max(1, totalSimcCasts * simcMult)) or 0
        actualRatios[e.name] = actualRatio
        simcRatios[e.name]  = simcRatio
        deficitMat[e.name]  = (simcRatio > 0) and (actualRatio / simcRatio) or (actualRatio > 0 and 10 or 1)
    end

    -- Required spells ("Always") become REAL optimization participants: give them
    -- a presence (count >= 1) and a damage-per-cast so the hill-climber can move
    -- them around instead of leaving a 0-dmg/0-dpc entry pinned at the bottom.
    -- Patched AFTER the deficit matrix so their deficit stays neutral (=1).
    if next(reqSet) then
        for _, e in ipairs(baseEntries) do
            if reqSet[e.name] and e.dpc <= 0 then
                e.count = math.max(e.count or 0, 1)
                e.dpc = avgDmg
                e.dmg = e.dpc * e.count
            end
        end
    end

    -- =====================================================
    -- 6. HELPER: LONG-CD DETECTION (long-CD spells never duplicated)
    -- =====================================================
    local function isLongCD(name)
        local simcExp = math.floor((simcCasts[name] or 0) * simcMult)
        return simcExp > 0 and simcDuration > 0 and (simcExp / simcDuration * 60) < 2
    end

    -- =====================================================
    -- 7. SIMC pDPS WEIGHT NORMALIZATION
    -- =====================================================
    local maxSimcWeight = 0
    for _, w in pairs(simcWeights) do
        if w > maxSimcWeight then maxSimcWeight = w end
    end

    -- =====================================================
    -- 8. HISTORY BONUS (top-3 prior optimizer runs)
    -- =====================================================
    local historyBonus = {}
    if priorHistory then
        local sortedHist = {}
        for _, h in ipairs(priorHistory) do table.insert(sortedHist, h) end
        table.sort(sortedHist, function(a, b) return (a.score or 0) > (b.score or 0) end)
        for i = 1, math.min(3, #sortedHist) do
            local h = sortedHist[i]
            if h.uniqKey then
                for spellName in h.uniqKey:gmatch("[^|]+") do
                    historyBonus[spellName] = (historyBonus[spellName] or 0) + (4 - i) * 0.05
                end
            end
        end
    end

    -- =====================================================
    -- 9. FITNESS EVALUATION
    -- =====================================================
    local function EvaluateFitness(stepArr)
        local stepCounts = {}
        for _, name in ipairs(stepArr) do
            stepCounts[name] = (stepCounts[name] or 0) + 1
        end

        local theoDps = 0
        local reward  = 0
        local penalty = 0

        for _, e in ipairs(baseEntries) do
            local sc = stepCounts[e.name] or 0
            theoDps = theoDps + sc * e.dpc

            -- SimC pDPS weight alignment reward
            if maxSimcWeight > 0 and simcWeights[e.name] then
                local wRatio = simcWeights[e.name] / maxSimcWeight
                local scRatio = (totalActualCasts > 0) and (e.count / totalActualCasts) or 0
                reward = reward + wRatio * scRatio * 1000 * (1 - math.abs(scRatio - wRatio))
            end

            -- APL position reward: early APL spells get positional bonus
            local aplPos = aplPosition[e.name]
            if aplPos then
                local posBonus = (1 - (aplPos - 1) / aplMax) * 0.1
                reward = reward + posBonus * sc * avgDmg
            end

            -- Mandatory uptime buff penalty: buff shuffled too low or absent
            local upInfo = buffByName[e.name]
            if upInfo and upInfo.uptime > (duration or 120) * 0.1 then
                local firstPos = 0
                for pi, nm in ipairs(stepArr) do
                    if nm == e.name then firstPos = pi; break end
                end
                local pctUp = upInfo.uptime / (duration or 120)
                if firstPos == 0 then
                    penalty = penalty + pctUp * avgDmg * 8
                elseif firstPos > math.ceil(#stepArr * 0.6) then
                    penalty = penalty + pctUp * avgDmg * 4
                end
                -- Known duration gap unaddressed
                local mg = buffMaxGap[e.name] or 0
                if mg >= 12 then
                    penalty = penalty + mg * 10
                elseif mg >= 8 then
                    penalty = penalty + mg * 5
                end
            end

            -- Heavy penalty for missing SimC-critical spells
            local simcExp = math.floor((simcCasts[e.name] or 0) * simcMult)
            if simcExp > 3 and sc == 0 then
                penalty = penalty + simcExp * 2.0
            elseif simcExp > 0 and sc < simcExp * 0.4 then
                penalty = penalty + (simcExp - sc) * 1.5
            end
        end

        -- Over-cast penalty: too many copies wastes priority slots
        for name, sc in pairs(stepCounts) do
            local simcExp = math.floor((simcCasts[name] or 0) * simcMult)
            if simcExp > 0 and sc > simcExp * 1.8 then
                penalty = penalty + (sc - simcExp * 1.8) * 0.5
            end
        end

        return theoDps + reward - penalty
    end

    -- =====================================================
    -- 10. MUTATION OPERATORS
    -- =====================================================
    local function MutateSwap(arr)
        if #arr < 2 then return arr end
        local copy = {unpack(arr)}
        local i = math.random(1, #copy)
        local j = math.random(1, #copy)
        copy[i], copy[j] = copy[j], copy[i]
        return copy
    end

    local function MutateInsertDupe(arr)
        local copy = {unpack(arr)}
        -- Find under-cast spells (deficit < 0.7) with enough SimC expectation
        local candidates = {}
        for _, name in ipairs(copy) do
            local def = deficitMat[name] or 1
            local simcExp = math.floor((simcCasts[name] or 0) * simcMult)
            if def < 0.7 and simcExp >= 3 and not isLongCD(name) then
                table.insert(candidates, name)
            end
        end
        if #candidates == 0 then
            for _, name in ipairs(copy) do
                if not isLongCD(name) then table.insert(candidates, name) end
            end
        end
        if #candidates == 0 then return copy end
        local choice = candidates[math.random(1, #candidates)]
        local pos = math.random(1, #copy + 1)
        table.insert(copy, pos, choice)
        -- Cap sequence length at 30, drop lowest-DPS entry if exceeded
        if #copy > 30 then
            local worstPos, worstDpc = 1, baseEntries[1] and baseEntries[1].dpc or 0
            for pi, nm in ipairs(copy) do
                for _, be in ipairs(baseEntries) do
                    if be.name == nm and be.dpc < worstDpc then
                        worstDpc = be.dpc
                        worstPos = pi
                        break
                    end
                end
            end
            table.remove(copy, worstPos)
        end
        return copy
    end

    local function MutateReposition(arr)
        local copy = {unpack(arr)}
        if #copy < 2 then return copy end
        local defs = {}
        for _, name in ipairs(copy) do defs[name] = deficitMat[name] or 1 end
        table.sort(copy, function(a, b)
            local da, db = defs[a], defs[b]
            if da ~= db then return da < db end
            return a < b
        end)
        return copy
    end

    -- =====================================================
    -- 11. BUILD INITIAL SEQUENCE
    -- =====================================================
    local function BuildInitialSequence()
        if seedSteps and #seedSteps > 0 then
            local seen, result = {}, {}
            for _, name in ipairs(seedSteps) do
                if not seen[name] and IsValidMacroSpell(name) and not neverSet[name] then
                    seen[name] = true
                    table.insert(result, name)
                end
            end
            for _, e in ipairs(baseEntries) do
                if not seen[e.name] then
                    seen[e.name] = true
                    table.insert(result, e.name)
                end
            end
            return result
        end
        -- Score-based initial sort
        local scored = {}
        for _, e in ipairs(baseEntries) do
            local score = e.dmg + e.count * avgDmg
            local upInfo = buffByName[e.name]
            if upInfo and upInfo.uptime > (duration or 120) * 0.1 then
                score = score + (upInfo.uptime / (duration or 120)) * avgDmg * 5
            end
            if simcCasts[e.name] then score = score * 1.3 end
            if historyBonus[e.name] then score = score * (1 + (historyBonus[e.name] or 0)) end
            table.insert(scored, {name = e.name, score = score})
        end
        table.sort(scored, function(a, b) return a.score > b.score end)
        local result = {}
        for _, s in ipairs(scored) do table.insert(result, s.name) end
        return result
    end

    -- =====================================================
    -- 12. HILL-CLIMBING MAIN LOOP (500 generations)
    -- =====================================================
    local current = BuildInitialSequence()
    local currentFitness = EvaluateFitness(current)

    local bestSequence = {unpack(current)}
    local bestFitness = currentFitness

    local plateauCount = 0
    local lastBest = -1
    local generation = 0

    for gen = 1, MAX_GENS do
        generation = gen

        -- Produce mutated variants (5 operators)
        local variants = {
            MutateSwap(current),
            MutateInsertDupe(current),
            MutateReposition(current),
        }
        -- Lateral move: accept equal-score swaps with 20% probability
        if math.random() < 0.2 then
            variants[4] = MutateSwap(current)
        end
        -- Seed-aware mutation: push high-deficit spells toward front
        if seedSteps and #seedSteps > 0 then
            local seedMut = {unpack(current)}
            local defs = {}
            for _, name in ipairs(seedMut) do defs[name] = deficitMat[name] or 1 end
            table.sort(seedMut, function(a, b)
                local da, db = defs[a], defs[b]
                if math.abs(da - db) > 0.1 then return da < db end
                return (aplPosition[a] or 999) < (aplPosition[b] or 999)
            end)
            variants[5] = seedMut
        end

        -- Evaluate all variants, keep best
        for _, variant in ipairs(variants) do
            local vf = EvaluateFitness(variant)
            if vf > currentFitness then
                current = variant
                currentFitness = vf
            end
            if vf > bestFitness then
                bestSequence = {unpack(variant)}
                bestFitness = vf
            end
        end

        -- Plateau detection
        if bestFitness > lastBest then
            if bestFitness - lastBest < PLATEAU_THRESH then
                plateauCount = plateauCount + 1
            else
                plateauCount = 0
            end
            lastBest = bestFitness
        else
            plateauCount = plateauCount + 1
        end

        if plateauCount >= PLATEAU_PATIENCE then
            -- Restart from fresh seed to escape local optimum
            current = BuildInitialSequence()
            currentFitness = EvaluateFitness(current)
            plateauCount = 0
        end
    end

    -- =====================================================
    -- 13. BUILD FINAL STEP ARRAY (with deficit-driven duplicates)
    -- =====================================================
    do
        local uniqCount = {}
        for _, n in ipairs(bestSequence) do uniqCount[n] = true end
        local u, t = 0, 0
        for _ in pairs(uniqCount) do u = u + 1 end
        for _ in ipairs(bestSequence) do t = t + 1 end
        DebugLog("info", "suggest-seq", string.format("hill-climber result: unique=%d total=%d entries=%d", u, t, #baseEntries))
    end
    local finalSteps  = {}
    local stepCounts  = {}
    local uniqueOrder = {}
    local seenUniq    = {}

    for _, name in ipairs(bestSequence) do
        if not seenUniq[name] and not neverSet[name] then
            seenUniq[name] = true
            table.insert(uniqueOrder, name)
        end
    end
    -- ponytail: force all baseEntries into output as safety net against hill-climber dropping spells
    for _, e in ipairs(baseEntries) do
        if not seenUniq[e.name] then
            seenUniq[e.name] = true
            table.insert(uniqueOrder, e.name)
            DebugLog("info", "suggest-seq", string.format("forced back missing spell: %s", e.name))
        end
    end

    -- ponytail: dedup only against last entry to prevent consecutive repeats
    if priorHistory and #priorHistory > 0 then
        local newKey = table.concat(uniqueOrder, "|")
        local last = priorHistory[1]
        if last and last.uniqKey and last.uniqKey == newKey then
            DebugLog("info", "suggest-seq", "dedup: same as last entry, retrying")
            return nil, nil, newKey
        end
    end

    -- Scale up by stepScale (long-CD spells exempt)
    for _, name in ipairs(uniqueOrder) do
        local reps = (isLongCD(name) or CAST_BUFF_DURATIONS_LOOKUP[name]) and 1 or math.max(1, stepScale)
        for r = 1, reps do
            table.insert(finalSteps, name)
            stepCounts[name] = (stepCounts[name] or 0) + 1
        end
    end

    -- Add deficit-driven extra duplicates for under-cast spells
    for _, name in ipairs(uniqueOrder) do
        if not isLongCD(name) then
            local def = deficitMat[name] or 1
            local simcExp = math.floor((simcCasts[name] or 0) * simcMult)
            if def < 0.7 and simcExp >= 3 and (stepCounts[name] or 0) < simcExp * 0.9 then
                local extra = math.min(4, math.max(1, math.floor(simcExp * 0.5)))
                for r = 1, extra do
                    table.insert(finalSteps, name)
                    stepCounts[name] = (stepCounts[name] or 0) + 1
                end
            end
        end
    end

    -- ponytail: Configure > Sequence Preferences post-processing
    do
        local minC = cfg.minCopies or 1
        local maxR = cfg.maxRepeats or 3
        if minC > 1 then
            for _, name in ipairs(uniqueOrder) do
                local cur = stepCounts[name] or 0
                local need = minC - cur
                for r = 1, math.max(0, need) do
                    table.insert(finalSteps, name)
                    stepCounts[name] = (stepCounts[name] or 0) + 1
                end
            end
        end
        if maxR > 0 then
            local filtered = {}
            local runName, runCount = nil, 0
            for _, name in ipairs(finalSteps) do
                if name == runName then
                    runCount = runCount + 1
                else
                    runName, runCount = name, 1
                end
                if runCount <= maxR then
                    table.insert(filtered, name)
                end
            end
            finalSteps = filtered
        end
    end

    -- ponytail: interleave only when explicitly enabled (positive cfg.interleave)
    local interleaveCandidates = {}
    local minInterleave = cfg.interleave
    if minInterleave and minInterleave > 0 then
        local sorted = {}
        for name, cnt in pairs(stepCounts) do
            if not isLongCD(name) then
                table.insert(sorted, {name = name, count = cnt})
            end
        end
        table.sort(sorted, function(a, b) return a.count > b.count end)
        for i = 1, math.min(minInterleave, #sorted) do
            interleaveCandidates[sorted[i].name] = math.max(2, math.floor(#finalSteps / sorted[i].count))
        end
    end

    -- =====================================================
    -- 15. SERIALIZATION: C_EncodingUtil CBOR + Deflate + Base64
    -- =====================================================
    local seqText, importStr, reasoningText

    -- Plain-text sequence
    local classFilename = select(2, UnitClass("player")) or "Unknown"
    local specName = ""
    local spec = GetSpecialization()
    if spec then
        specName = select(2, GetSpecializationInfo(spec)) or ""
    end
    local heroTalentName = nil
    do
        local _, _, hn = ScanPlayerTalents()
        heroTalentName = hn
    end

    local seqLines = {}
    seqLines[#seqLines + 1] = "=== Suggested Sequence ==="
    seqLines[#seqLines + 1] = string.format("Spec: %s %s", classFilename, specName)
    if heroTalentName and heroTalentName ~= "" then
        seqLines[#seqLines + 1] = string.format("Spec: %s %s (%s)", classFilename, specName, heroTalentName)
    end
    seqLines[#seqLines + 1] = string.format("Icon: %s", (uniqueOrder[1] or "INV_Misc_QuestionMark"))
    seqLines[#seqLines + 1] = "Step Function: " .. (cfg.stepFunction or "Priority")
    seqLines[#seqLines + 1] = "Reset: combat/target"
    seqLines[#seqLines + 1] = ""
	local intervalDisplayed = {}
	for i, name in ipairs(finalSteps) do
		local prefix = GetActionPrefix(name)
		local suffix = (interleaveCandidates[name] and not intervalDisplayed[name]) and string.format(" (interval:%d)", interleaveCandidates[name]) or ""
		if suffix ~= "" then
			intervalDisplayed[name] = true
		end
		seqLines[#seqLines + 1] = string.format("%2d. %s [combat] %s%s", i, prefix, name, suffix)
	end
	seqText = table.concat(seqLines, "\n")

    -- Generate !DA01! compressed import string
    if C_EncodingUtil then
        local seq = Addon.BuildSequence(finalSteps, cfg, interleaveCandidates)
        if seq then
            importStr = Addon.SerializeEMSSequence(seq, "DummyAnalyzer Heuristic Sequence")
        end
    end

    -- =====================================================
    -- 16. GENERATE REASONING TEXT
    -- =====================================================
    local reasonLines = {}
    reasonLines[#reasonLines + 1] = "=== Heuristic Solver Report ==="
    reasonLines[#reasonLines + 1] = ""
    reasonLines[#reasonLines + 1] = string.format("Generations: %d  |  Best Fitness: %s", generation, Addon.FormatNumber(bestFitness))
    reasonLines[#reasonLines + 1] = string.format("%d spells, %d unique, %d total steps", #uniqueOrder, #baseEntries, #finalSteps)
    reasonLines[#reasonLines + 1] = ""

    reasonLines[#reasonLines + 1] = "--- Deficit Matrix (actual ratio / simc ratio) ---"
    local sortedDef = {}
    for name, def in pairs(deficitMat) do
        table.insert(sortedDef, {name = name, def = def})
    end
    table.sort(sortedDef, function(a, b) return a.def < b.def end)
    for _, row in ipairs(sortedDef) do
        local flag = ""
        if row.def < 0.7 then flag = " << UNDER"
        elseif row.def > 1.3 then flag = " OVER >>"
        end
        local actualR = actualRatios[row.name] or 0
        local simcR   = simcRatios[row.name] or 0
        reasonLines[#reasonLines + 1] = string.format(
            "  %-28s deficit=%+.2f  actual=%.1f%%  simc=%.1f%%%s",
            row.name, row.def, actualR * 100, simcR * 100, flag
        )
    end
    reasonLines[#reasonLines + 1] = ""

    reasonLines[#reasonLines + 1] = "--- Step Output ---"
    for i, name in ipairs(finalSteps) do
        local def = deficitMat[name] or 1
        local gapNote = (buffMaxGap[name] and buffMaxGap[name] >= 8) and string.format(" [gap %.1fs]", buffMaxGap[name]) or ""
        local note = ""
        if def < 0.7 then note = note .. " undercast"
        elseif def > 1.3 then note = note .. " overcast"
        end
        reasonLines[#reasonLines + 1] = string.format("  %2d. %s%s%s", i, name, gapNote, note)
    end

    reasoningText = table.concat(reasonLines, "\n")
    if not simcData then
        reasoningText = "WARNING: No SimC data imported. Solver used log-only data; weights and APL positions are missing.\nRe-import via Saved Logs -> Import SimC.\n\n" .. reasoningText
    end

    DebugLog("info", "suggest-seq", string.format("Returning seq=%s, bestFitness=%.2f, unique=%d steps=%d", seqText and (#seqText > 0 and "OK" or "empty") or "nil", bestFitness or 0, #uniqueOrder, #finalSteps))
    return seqText, importStr, reasoningText, bestFitness
end

-- ============================================
-- REASONING TEXT GENERATION
-- ============================================
Addon.GenerateReasoningText = function(castCounts, damageData)
    if not castCounts or not next(castCounts) then return "No cast data to analyze." end
    if not damageData or not next(damageData) then return "No damage data available." end
    local sorted = {}
    local totalDmg = 0
    for name, count in pairs(castCounts) do
        local dmg = 0
        if damageData and damageData[name] then
            dmg = NumberOrZero(damageData[name].total)
        end
        totalDmg = totalDmg + dmg
        local hits = (damageData[name] and damageData[name].hits) or 0
        table.insert(sorted, {name = name, dmg = dmg, count = count, hits = hits})
    end
    table.sort(sorted, function(a, b) return a.dmg > b.dmg end)
    local filtered = {}
    local filteredOut = {}
    for _, entry in ipairs(sorted) do
        if IsValidMacroSpell(entry.name) then
            table.insert(filtered, entry)
        else
            table.insert(filteredOut, entry)
        end
    end
    local lines = {}
    lines[#lines + 1] = "=== Rotation Order ==="
    lines[#lines + 1] = ""
    if #filtered == 0 then
        lines[#lines + 1] = "No castable spells found."
        return table.concat(lines, "\n")
    end
    lines[#lines + 1] = "Spells sorted by damage + cast frequency (rotational cooldowns included)"
    lines[#lines + 1] = ""
    local totalCasts = 0
    for _, e in ipairs(filtered) do totalCasts = totalCasts + (e.count or 0) end
    for i, entry in ipairs(filtered) do
        local pct = totalDmg > 0 and (entry.dmg / totalDmg * 100) or 0
        local avgHit = (entry.hits and entry.hits > 0) and entry.dmg / entry.hits or 0
        lines[#lines + 1] = string.format("  %d. %s — %d casts, %s, %.1f%% of total, avg %.0f",
            i, entry.name, entry.count or 0, Addon.FormatNumber(entry.dmg), pct, avgHit)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("%d spells, %d total casts, %s total damage",
        #filtered, totalCasts, Addon.FormatNumber(totalDmg))
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Priority: top steps checked first; first available ability fires."
    -- Add talent awareness section
    local talSpells, modSpells, heroName = ScanPlayerTalents()
    local hasTalentInfo = false
    for _ in pairs(talSpells) do hasTalentInfo = true break end
    if hasTalentInfo or (heroName and heroName ~= "") then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "=== Talent Awareness ==="
        if heroName and heroName ~= "" then
            lines[#lines + 1] = string.format("  Hero Talent: %s", heroName)
        end
        local talentedInLog = {}
        local modifiedInLog = {}
        for _, entry in ipairs(filtered) do
            if talSpells[entry.name] then
                talentedInLog[#talentedInLog + 1] = entry.name
            end
            if modSpells[entry.name] then
                modifiedInLog[#modifiedInLog + 1] = entry.name
            end
        end
        if #talentedInLog > 0 then
            lines[#lines + 1] = string.format("  Talent-granted spells: %s", table.concat(talentedInLog, ", "))
        end
        if #modifiedInLog > 0 then
            lines[#lines + 1] = string.format("  Talent-modified spells: %s", table.concat(modifiedInLog, ", "))
        end
    end
    return table.concat(lines, "\n")
end

-- ============================================
-- GAP REPORT — compares player log vs SimC reference per-spell
-- ============================================
Addon.GenerateGapReport = function(castCounts, damageData, playerDuration)
    if not castCounts or not next(castCounts) then return "No cast data to compare." end
    local db = GetCharDB()
    if not db or not db.simcLogId then return "No SimC reference log linked. Import a SimC log first." end

    -- Find the SimC log
    local simcLog = nil
    for _, l in ipairs(db.logs or {}) do
        if l.id == db.simcLogId and l.isSimC then
            simcLog = l
            break
        end
    end
    if not simcLog then return "SimC reference log not found (ID: " .. tostring(db.simcLogId) .. ")." end

    -- Re-filter in case this SimC log was saved before the proc/passive filter was added
    local simcCasts, simcDmg = FilterSimCData(simcLog.castCounts or {}, simcLog.damageData)
    simcDmg = simcDmg or {}
    local simcDuration = (simcLog.duration or 1) > 0 and simcLog.duration or 1
    local playerDur = (playerDuration or 1) > 0 and playerDuration or 1

    -- Collect all unique spells from both logs
    local allSpells = {}
    for name in pairs(castCounts) do
        if IsValidMacroSpell(name) then allSpells[name] = true end
    end
    for name in pairs(simcCasts) do
        if IsValidMacroSpell(name) then allSpells[name] = true end
    end

    -- Build per-spell rows
    local rows = {}
    for name in pairs(allSpells) do
        local pCasts = castCounts[name] or 0
        local sCasts = simcCasts[name] or 0
        local pDmg = NumberOrZero(damageData and damageData[name] and damageData[name].total or 0)
        local sDmg = NumberOrZero(simcDmg[name] and simcDmg[name].total or 0)

        -- Normalize rates per second
        local pCastsPerSec = pCasts / playerDur
        local sCastsPerSec = sCasts / simcDuration
        local pDps = pDmg / playerDur
        local sDps = sDmg / simcDuration

        -- Cast gap: percentage difference (+ = overcast, - = undercast)
        local castGap = 0
        if sCastsPerSec > 0 then
            castGap = (pCastsPerSec - sCastsPerSec) / sCastsPerSec * 100
        elseif pCastsPerSec > 0 then
            castGap = 100 -- casting when SimC doesn't at all
        end

        -- Priority flag
        local priority = ""
        local absGap = math.abs(castGap)
        if pCasts > 0 or sCasts > 0 then
            local isOffensive = sDmg > 0 or pDmg > 0
            if isOffensive then
                if castGap < -30 then priority = "CRITICAL"
                elseif castGap < -15 then priority = "UNDER"
                elseif castGap > 50 then priority = "OVER"
                elseif castGap > 20 then priority = "SLIGHT OVER"
                end
            else
                if castGap < -50 then priority = "LOW"
                elseif castGap > 100 then priority = "HIGH"
                end
            end
        end

        local gapStr = castGap > 0 and string.format("+%.1f%%", castGap) or string.format("%.1f%%", castGap)
        table.insert(rows, {
            name = name, pCasts = pCasts, sCasts = sCasts, gapStr = gapStr, castGap = castGap,
            pDps = pDps, sDps = sDps, priority = priority
        })
    end

    -- Sort: critical under first, then by absolute gap descending
    local prioOrder = { CRITICAL = 0, UNDER = 1, ["SLIGHT OVER"] = 2, OVER = 3, HIGH = 4, LOW = 5, [""] = 6 }
    table.sort(rows, function(a, b)
        local pa = prioOrder[a.priority] or 6
        local pb = prioOrder[b.priority] or 6
        if pa ~= pb then return pa < pb end
        return math.abs(a.castGap) > math.abs(b.castGap)
    end)

    -- Format the report
    local lines = {}
    lines[#lines + 1] = "=== Gap Report ==="
    lines[#lines + 1] = string.format("Player: %.0fs  |  SimC: %.0fs", playerDur, simcDuration)
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("%-24s %6s %6s %8s %10s %10s %s", "Spell", "P.Cast", "S.Cast", "Gap", "P.DPS", "S.DPS", "Flag")
    lines[#lines + 1] = string.rep("-", 80)
    for _, r in ipairs(rows) do
        local flagColor = ""
        if r.priority == "CRITICAL" then flagColor = "|cffff4444"
        elseif r.priority == "UNDER" then flagColor = "|cffffaa44"
        elseif r.priority == "OVER" or r.priority == "SLIGHT OVER" then flagColor = "|cff44aaff"
        elseif r.priority == "HIGH" then flagColor = "|cff44ff44"
        elseif r.priority == "LOW" then flagColor = "|cff888888"
        end
        local flag = r.priority ~= "" and (flagColor .. r.priority .. "|r") or ""
        local pDpsStr = Addon and Addon.FormatNumber(math.floor(r.pDps)) or tostring(math.floor(r.pDps))
        local sDpsStr = Addon and Addon.FormatNumber(math.floor(r.sDps)) or tostring(math.floor(r.sDps))
        lines[#lines + 1] = string.format("%-24s %6d %6d %8s %10s %10s %s",
            r.name, r.pCasts, r.sCasts, r.gapStr, pDpsStr, sDpsStr, flag)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Gap: +X% = overcast (too many presses), -X% = undercast (too few)"
    lines[#lines + 1] = "Flags: CRITICAL(red) = cooldown 30%+ under | UNDER(orange) = 15-30% under"
    lines[#lines + 1] = "       OVER(blue) = 50%+ over | SLIGHT OVER(light blue) = 20-50% over"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Note: rates are normalized per-second. Short logs (<60s) may skew results."

    return table.concat(lines, "\n")
end