local AddonName, Addon = ...
-- ============================================
-- SAVED LOGS: Save / Delete / Compare
-- ============================================
local GetCharDB = Addon.GetCharDB
local DeepCopy = Addon.DeepCopy
local IsSecretValue = Addon.IsSecretValue

-- ScanPlayerTalents (SequenceCore #12) and GenerateEMSImportString (SequenceFeed
-- #13) load AFTER this module, so both are resolved through Addon at call time,
-- not aliased at load time.
local function ScanPlayerTalents() return Addon.ScanPlayerTalents() end
local function GenerateEMSImportString(castCounts, damageData, orderedSteps) return Addon.GenerateEMSImportString(castCounts, damageData, orderedSteps) end

-- Walk action tree recursively to collect macro strings
local function CollectActionMacros(node, out)
    if type(node) ~= "table" then return end
    if node.type == "action" and node.macro then
        out[#out + 1] = node.macro
    elseif node.type == "loop" and node.children then
        for _, child in ipairs(node.children) do
            CollectActionMacros(child, out)
        end
    elseif node.type == "if" and node.children then
        if node.children[1] then
            for _, child in ipairs(node.children[1]) do
                CollectActionMacros(child, out)
            end
        end
        if node.children[2] then
            for _, child in ipairs(node.children[2]) do
                CollectActionMacros(child, out)
            end
        end
    elseif node.type == "embed" and node.sequence then
        -- Can't resolve embedded sequence here, skip
    end
end

local function GetStepMacros(ver)
    local macros = {}
    -- Prefer actions tree when available: it preserves the intended base order
    -- without interleave-injected duplicates that distort detection.
    if ver.actions and #ver.actions > 0 then
        for _, node in ipairs(ver.actions) do
            CollectActionMacros(node, macros)
        end
    elseif ver.steps and #ver.steps > 0 then
        for _, step in ipairs(ver.steps) do
            macros[#macros + 1] = step
        end
    end
    return macros
end

-- Detects the active GRIP-EMS sequence by matching its steps against what was cast
local function ExtractSpellName(step)
    if type(step) ~= "string" then return nil end
    local s = step:match("^/cast%s+.+%](.+)") or step:match("^/use%s+.+%](.+)") or step:match("^/cast%s+(.+)") or step:match("^/use%s+(.+)") or step
    s = s:match("^%s*(.-)%s*$")
    -- An inventory slot ("/use [combat] 13") or an item link is not a spell name.
    -- Returning one as if it were puts a token in the match list that no cast event
    -- can produce. Callers already guard for nil.
    if s == "" or s:match("^%d+$") or s:match("^item:") then return nil end
    return s
end

-- Extract clean spell name from a sequence text line, stripping annotations like (interval:N) and [dupe]
local function ExtractSpellFromSeqLine(line)
    local name = line:match("%[combat%] (.+)")
    if name then
        name = name:gsub(" %(interval:%d+%)", "")
        name = name:gsub(" %[dupe%]", "")
        name = name:match("^%s*(.-)%s*$")
    end
    return name
end

local function GetCandidateSequences()
    local out = {}
    local API = _G.GRIPEMS and _G.GRIPEMS.API
    if API and API.GetAuthoredSteps and API.GetSequenceList then
        -- Public path (EMS v2.3.7+): authored base order, interleave copies
        -- suppressed, spell names resolved by EMS itself. Active version.
        local list = API:GetSequenceList() or {}
        for _, summary in ipairs(list) do
            local seqName = summary and summary.name
            if type(seqName) == "string" and seqName ~= "" then
                local entries = API:GetAuthoredSteps(seqName)
                if type(entries) == "table" and #entries > 0 then
                    local names = {}
                    for _, e in ipairs(entries) do
                        local sn = e and e.spellName
                        if type(sn) == "string" and sn ~= "" then
                            names[#names + 1] = sn
                        end
                    end
                    if #names > 0 then
                        out[#out + 1] = {
                            name = seqName,
                            names = names,
                            stepFunction = summary.stepFunction,
                        }
                    end
                end
            end
        end
        return out
    end
    -- Legacy fallback (EMS v2.3.6 and older: GetAuthoredSteps not on the API
    -- surface). Raw SavedVariables walk. Delete this branch when the minimum
    -- supported EMS version reaches v2.3.7.
    if not _G.GRIP_EMS_CHAR or not _G.GRIP_EMS_CHAR.sequences then
        return out
    end
    for seqName, seq in pairs(_G.GRIP_EMS_CHAR.sequences) do
        local ver = seq.versions and seq.versions[seq.defaultVersion or 1]
        if ver then
            local macros = GetStepMacros(ver)
            local names = {}
            for _, step in ipairs(macros) do
                local sn = ExtractSpellName(step)
                if sn and sn ~= "" then
                    names[#names + 1] = sn
                end
            end
            if #names > 0 then
                out[#out + 1] = {
                    name = seqName,
                    names = names,
                    stepFunction = ver.stepFunction,
                }
            end
        end
    end
    return out
end

local function InferStepFunction(history)
    if not history or #history < 4 then return nil end
    local names = {}
    for i = 1, math.min(12, #history) do
        names[i] = history[i].name
    end
    for cycleLen = 3, 6 do
        local isRR = true
        for i = 1, cycleLen do
            if names[i] ~= names[i + cycleLen] then isRR = false; break end
        end
        if isRR then return "RoundRobin" end
    end
    return "Priority"
end

-- Cast-order tiebreaker: when frequency scores are close, prefers the sequence
-- whose early-step order better matches the player's actual cast sequence.
-- Compares first N unique spells cast against their first occurrence position
-- in the sequence steps. Lower average position = better correlation.
local function OrderCorrelation(history, macros)
    if not history or #history < 2 or not macros or #macros < 2 then return 0 end
    local seen = {}
    local firstUnique = {}
    for _, entry in ipairs(history) do
        local name = entry.name or entry
        if not seen[name] and type(name) == "string" then
            seen[name] = true
            firstUnique[#firstUnique + 1] = name
            if #firstUnique >= 5 then break end
        end
    end
    if #firstUnique < 2 then return 0 end
    local stepSpells = {}
    for _, step in ipairs(macros) do
        local s = ExtractSpellName(step)
        if s and s ~= "" then
            stepSpells[#stepSpells + 1] = s
        end
    end
    if #stepSpells == 0 then return 0 end
    -- Weighted: early history spells (TC, IP) matter more than later ones (SB, SS).
    -- A sequence that places TC at step 1 scores higher than one that buries it at step 4.
    local totalWeight = 0
    local weightedPos = 0
    for histPos, spellName in ipairs(firstUnique) do
        local w = 1 / histPos  -- weight decays: 1, 0.5, 0.333, 0.25, 0.2
        totalWeight = totalWeight + w
        for seqPos, seqSpell in ipairs(stepSpells) do
            if seqSpell == spellName then
                weightedPos = weightedPos + seqPos * w
                break
            end
        end
    end
    local avgWeighted = totalWeight > 0 and weightedPos / totalWeight or 5
    return math.max(0, 1 - avgWeighted / 10)
end

-- Candidates come from GetCandidateSequences: the EMS public API when
-- available (authored order, resolved names), the raw SavedVariables walk
-- on older EMS builds. All candidate step lists are bare spell names.
local function DetectGRIPSequence(castCounts, testStartSeq, inferredFunction)
    local candidates = GetCandidateSequences()
    if #candidates == 0 then return nil end

    local totalCasts = 0
    for _, c in pairs(castCounts) do totalCasts = totalCasts + c end
    if totalCasts == 0 then return nil end

    local byName = {}
    for _, cand in ipairs(candidates) do byName[cand.name] = cand end

    -- Test-start snapshot is the most reliable signal for which sequence was active
    if testStartSeq and byName[testStartSeq] then
        local cand = byName[testStartSeq]
        return {
            name = testStartSeq,
            steps = DeepCopy(cand.names),
            stepFunction = cand.stepFunction,
            matchScore = 1.0,
        }
    end

    -- Fall back: frequency + order matching across all candidates.
    -- lastActiveSequence is sourced from the public SEQUENCE_STEP_ADVANCED
    -- event (see Ems_RegisterEvents) rather than the undocumented
    -- GRIPEMS.Engine._lastClickedSequence field. It also reflects real
    -- execution instead of a click that may never have fired a step.
    local clickName = Addon.lastActiveSequence
    local directMatchName = nil
    if clickName and testStartSeq and clickName == testStartSeq then
        directMatchName = clickName
    elseif clickName and byName[clickName] then
        directMatchName = clickName
    end

    local bestMatch = nil
    local bestScore = 0
    local bestNames = nil

    for _, cand in ipairs(candidates) do
        local names = cand.names

        local seqStepCount = {}
        local totalSteps = 0
        for _, spellName in ipairs(names) do
            seqStepCount[spellName] = (seqStepCount[spellName] or 0) + 1
            totalSteps = totalSteps + 1
        end

        local presenceMatchCount = 0
        local freqScore = 0
        local totalSeq = 0
        for spellName, stepCount in pairs(seqStepCount) do
            totalSeq = totalSeq + 1
            if castCounts[spellName] then
                presenceMatchCount = presenceMatchCount + 1
                local seqRatio = stepCount / totalSteps
                local castRatio = castCounts[spellName] / totalCasts
                local ratio = castRatio > 0 and seqRatio / castRatio or 0
                if ratio >= 0.5 and ratio <= 2.0 then
                    freqScore = freqScore + seqRatio
                end
            end
        end
        local presenceScore = totalSeq > 0 and (presenceMatchCount / totalSeq) or 0
        local score = (presenceScore * 0.6) + (freqScore * 0.4)

        if cand.name == directMatchName then
            score = math.min(1.0, score + 0.3)
        end

        if inferredFunction and cand.stepFunction and cand.stepFunction ~= inferredFunction then
            score = score * 0.7
        end

        if bestScore > 0 and score > bestScore - 0.15 and score < bestScore + 0.15 and bestNames then
            local curOrder = OrderCorrelation(Addon.spellHistory, names)
            local bestOrder = OrderCorrelation(Addon.spellHistory, bestNames)
            if curOrder > bestOrder + 0.01 then
                score = bestScore + 0.01
            elseif curOrder < bestOrder - 0.01 then
                score = -1
            end
        end
        local totalScore = score

        if totalScore > bestScore then
            bestScore = totalScore
            bestMatch = {
                name = cand.name,
                steps = DeepCopy(names),
                stepFunction = cand.stepFunction,
                matchScore = score,
            }
            bestNames = names
        end
    end
    return bestScore >= 0.5 and bestMatch or nil
end

local function SaveCurrentLog()
    local elapsed = (Addon.testActive and (GetTime() - Addon.startTime)) or (Addon.testEndTime and (Addon.testEndTime - Addon.startTime)) or 0
    if elapsed < 1 then return nil end

    local castCounts = {}
    for _, spell in ipairs(Addon.spellHistory) do
        local n = spell and spell.name
        if n and not IsSecretValue(n) then
            castCounts[n] = (castCounts[n] or 0) + 1
        end
    end

    local totalCasts = #Addon.spellHistory
    local dps = (Addon.totalDamage > 0 and elapsed > 0) and math.floor(Addon.totalDamage / elapsed) or 0
    local durMin = (Addon.currentDuration == 30) and "30s" or (math.floor(Addon.currentDuration / 60) .. "min")

    local db = GetCharDB()
    -- Reuse the lowest available ID so deletions don't create gaps
    local used = {}
    for _, l in ipairs(db.logs) do used[l.id] = true end
    local id = 1
    while used[id] do id = id + 1 end
    if id >= db.nextId then db.nextId = id + 1 end

    -- Detect GRIP-EMS sequence FIRST, then use its steps for ensureSpells
    local infFunc = InferStepFunction(Addon.spellHistory)
    local detected = DetectGRIPSequence(castCounts, Addon.testStartSequence, infFunc)
    local detectedSeqName = detected and detected.name or nil
    local detectedSeqSteps = detected and detected.steps or nil
    local detectedSeqFunction = detected and detected.stepFunction or nil

    -- Generate sequence text and import string from detected steps
    local saveSeqText = nil
    local saveImportStr = nil
    if detectedSeqSteps and #detectedSeqSteps > 0 then
        local seqLines = {"=== " .. detectedSeqName .. " ==="}
        local importSpells = {}
        for i, step in ipairs(detectedSeqSteps) do
            seqLines[#seqLines + 1] = string.format("%d. %s", i, step)
            local sn = ExtractSpellName(step)
            if sn and sn ~= "" then importSpells[#importSpells + 1] = sn end
        end
        saveSeqText = table.concat(seqLines, "\n")
        if #importSpells > 0 then
            saveImportStr = GenerateEMSImportString(castCounts, Addon.damageData, importSpells) or ""
        end
    end

    -- Snapshot current talents for provenance
    local talSpells, modSpells, heroName = ScanPlayerTalents()
    local talSpellsList = {}
    for s in pairs(talSpells) do talSpellsList[#talSpellsList + 1] = s end
    local modSpellsList = {}
    for s in pairs(modSpells) do modSpellsList[#modSpellsList + 1] = s end

    local log = {
        id = id,
        label = "#" .. id .. " " .. durMin .. " " .. Addon.FormatNumber(dps) .. (detectedSeqName and (" [" .. detectedSeqName .. "]") or " DPS"),
        timestamp = time(),
        date = date("%Y-%m-%d %H:%M"),
        duration = elapsed,
        totalDamage = Addon.totalDamage,
        totalCasts = totalCasts,
        dps = dps,
        specName = specName,
        castCounts = DeepCopy(castCounts),
        damageData = DeepCopy(Addon.damageData),
        spellHistory = DeepCopy(Addon.spellHistory),
        buffUptime = DeepCopy(Addon.buffUptime),
        debuffUptime = DeepCopy(Addon.debuffUptime),
        buffGaps = DeepCopy(Addon.buffGaps),
        notes = "",
        spellPowerCosts = DeepCopy(Addon.spellPowerCosts),
        emsSeqText = saveSeqText,
        emsImportString = saveImportStr,
        detectedSeqName = detectedSeqName,
        detectedSeqSteps = detectedSeqSteps,
        detectedSeqFunction = detectedSeqFunction,
        detectedSeqMatch = detected and detected.matchScore or nil,
        talentedSpells = #talSpellsList > 0 and talSpellsList or nil,
        talentModifiedSpells = #modSpellsList > 0 and modSpellsList or nil,
        heroTalentName = (heroName and heroName ~= "") and heroName or nil,
    }

    table.insert(db.logs, 1, log)

    -- Keep max 50 logs
    while #db.logs > 50 do
        table.remove(db.logs)
    end

    return id
end

function Addon.GetSavedLogs()
    return GetCharDB().logs or {}
end

function Addon.DeleteLog(id)
    if not id then return end
    local db = GetCharDB()
    for i, log in ipairs(db.logs) do
        if log.id == id then
            if log.isSimC then
                db.simcLogId = 0
            end
            table.remove(db.logs, i)
            return
        end
    end
end

function Addon.RenameLog(id, newLabel)
    if not id or not newLabel then return end
    for _, log in ipairs(GetCharDB().logs) do
        if log.id == id then
            log.label = newLabel
            return
        end
    end
end

-- ============================================
-- SAVEDLOGSLGIC EXPORTS (namespace promotion, rule A/B)
-- ============================================
Addon.SaveCurrentLog = SaveCurrentLog
Addon.ExtractSpellName = ExtractSpellName
Addon.ExtractSpellFromSeqLine = ExtractSpellFromSeqLine