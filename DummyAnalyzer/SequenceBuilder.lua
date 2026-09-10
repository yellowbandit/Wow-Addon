local AddonName, Addon = ...

local GetActionPrefix = Addon.GetActionPrefix or function() return "/cast" end
local Ems_Default = Addon.Ems_Default or function(v, d) return (v == nil) and d or v end
local DebugLog = Addon.DebugLog or function() end
local NumberOrZero = Addon.NumberOrZero or function(v) return v or 0 end

local EMS_SEQUENCE_FORMAT = "GRIP-EMS"
local EMS_SEQUENCE_VERSION = 5
local EMS_IMPORT_PREFIX = "!DA01!"

local function NormalizeSpellName(s)
    s = tostring(s or "")
    s = s:gsub("^%s*/%a+%s+%[?combat%]?%s*", "")
    s = s:gsub("%s*%(interval:%d+%)", "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

local function ComputeFreq(orderedSpellNames)
    local freq = {}
    for _, spell in ipairs(orderedSpellNames or {}) do
        local s = NormalizeSpellName(spell)
        if s ~= "" then
            freq[s] = (freq[s] or 0) + 1
        end
    end
    return freq
end

local function ComputeIntervalFromFreq(orderedSpellNames, freq, count)
    return math.max(2, math.floor(#orderedSpellNames / math.max(1, count)))
end

local function BuildIntervalMap(orderedSpellNames, cfg, intervalOverrides)
    local intervalMap = {}
    if intervalOverrides ~= nil then
        if type(intervalOverrides) == "table" then
            for name, iv in pairs(intervalOverrides) do
                intervalMap[name] = math.max(1, math.min(50, NumberOrZero(iv)))
            end
        end
        return intervalMap
    end
    local freq = ComputeFreq(orderedSpellNames)
    local rawInterleave = cfg.interleave
    local minInterleave = NumberOrZero(rawInterleave)
    if minInterleave > 0 then
        local sorted = {}
        for name, cnt in pairs(freq) do
            table.insert(sorted, { name = name, count = cnt })
        end
        table.sort(sorted, function(a, b) return a.count > b.count end)
        for i = 1, math.min(minInterleave, #sorted) do
            intervalMap[sorted[i].name] = ComputeIntervalFromFreq(orderedSpellNames, freq, sorted[i].count)
        end
    elseif rawInterleave == nil then
        -- Legacy data without an interleave setting: keep the old auto-spacing.
        local maxFreq = 0
        for _, cnt in pairs(freq) do
            if cnt > maxFreq then maxFreq = cnt end
        end
        for name, cnt in pairs(freq) do
            if cnt >= 5 and cnt >= maxFreq * 0.4 then
                intervalMap[name] = ComputeIntervalFromFreq(orderedSpellNames, freq, cnt)
            end
        end
    end
    return intervalMap
end

local function ApplyRequiredAndNever(orderedSpellNames, cfg)
    local never = {}
    for _, n in ipairs(cfg.neverSpells or {}) do
        never[NormalizeSpellName(n)] = true
    end
    local out = {}
    for _, spell in ipairs(orderedSpellNames or {}) do
        local s = NormalizeSpellName(spell)
        if s ~= "" and not never[s] then
            out[#out + 1] = s
        end
    end
    local seen = {}
    for _, s in ipairs(out) do seen[s] = true end
    for _, r in ipairs(cfg.requiredSpells or {}) do
        local rs = NormalizeSpellName(r)
        if rs ~= "" and not never[rs] and not seen[rs] then
            seen[rs] = true
            table.insert(out, 1, rs)
        end
    end
    return out
end

local function BuildActionsFromFlat(orderedSpellNames, intervalMap)
    local actions = {}
    local intervalApplied = {}
    for _, s in ipairs(orderedSpellNames) do
        local act = { type = "action", macro = string.format("%s [combat] %s", GetActionPrefix(s), s) }
        if intervalMap[s] and not intervalApplied[s] then
            intervalApplied[s] = true
            act.interval = intervalMap[s]
        end
        actions[#actions + 1] = act
    end
    return actions
end

local function BuildActionsFromStructure(structure)
    local actions = {}
    local function appendNode(node, depth)
        if not node or depth > 10 then return end
        if node.disabled then return end
        if node.type == "action" then
            local act = { type = "action", macro = node.macro or "/cast " .. node.spell or "" }
            if node.interval and node.interval > 0 then
                act.interval = math.max(1, math.min(50, NumberOrZero(node.interval)))
            end
            actions[#actions + 1] = act
        elseif node.type == "loop" then
            local children = {}
            local saved = actions
            actions = children
            for _, child in ipairs(node.children or {}) do appendNode(child, depth + 1) end
            actions = saved
            actions[#actions + 1] = {
                type = "loop",
                children = children,
                ["repeat"] = math.max(1, math.min(50, NumberOrZero(node["repeat"] and node["repeat"] > 0 and node["repeat"] or 1))),
                stepFunction = node.stepFunction,
            }
        elseif node.type == "if" then
            local cond = node.variable or "[combat]"
            if cond == "" or cond:find(";") then
                DebugLog("error", "SequenceBuilder", 'Invalid if-condition "' .. tostring(cond) .. '"; node compiles to nothing.', node)
                return
            end
            local tActions, fActions, saved = {}, {}, actions
            actions = tActions
            for _, child in ipairs((node.children and node.children[1]) or {}) do appendNode(child, depth + 1) end
            actions = fActions
            for _, child in ipairs((node.children and node.children[2]) or {}) do appendNode(child, depth + 1) end
            actions = saved
            if #tActions == 0 and #fActions == 0 then return end
            actions[#actions + 1] = { type = "if", variable = cond, children = { tActions, fActions } }
        elseif node.type == "pause" then
            actions[#actions + 1] = { type = "pause", clicks = math.max(1, NumberOrZero(node.clicks)) }
        elseif node.type == "embed" then
            actions[#actions + 1] = { type = "embed", sequence = node.sequence or "" }
        end
    end
    for _, node in ipairs(structure or {}) do appendNode(node, 1) end
    return actions
end

Addon.BuildSequence = function(orderedSpellNames, cfg, intervalOverrides)
    cfg = cfg or {}
    local spells = ApplyRequiredAndNever(orderedSpellNames, cfg)
    if #spells == 0 then
        return nil, {}
    end
    local intervalMap = BuildIntervalMap(spells, cfg, intervalOverrides)
    local actions = BuildActionsFromFlat(spells, intervalMap)
    -- Structure-tab overlay removed per user request; flat spells only.

    local classID = select(3, UnitClass("player"))
    local spec = GetSpecialization()
    local specID = spec and GetSpecializationInfo(spec)

    local sequence = {
        icon = spells[1] or "INV_Misc_QuestionMark",
        versions = {
            [1] = {
                version = "1.0",
                stepFunction = cfg.stepFunction or "Priority",
                actions = actions,
                keyPress = cfg.keyPress or "/startattack",
                keyRelease = cfg.keyRelease or "",
                resetOnCombat = Ems_Default(cfg.resetOnCombat, true),
                resetOnTarget = Ems_Default(cfg.resetOnTarget, true),
                resetOnGear = Ems_Default(cfg.resetOnGear, false),
                resetOnSpec = Ems_Default(cfg.resetOnSpec, false),
                resetTimer = NumberOrZero(cfg.resetTimer),
                repeatCount = NumberOrZero(cfg.repeatCount),
            },
        },
        defaultVersion = 1,
        contextOverrides = {},
        author = "DummyAnalyzer",
        description = "Generated by DummyAnalyzer.",
        help = "",
        helplink = "",
        privacyMode = cfg.privacyMode or "private",
        classID = classID,
    }
    if specID then
        sequence.specID = specID
    end
    return sequence, intervalMap
end

Addon.ValidateSequenceActions = function(actions)
    local AC = _G.GRIPEMS and _G.GRIPEMS.ActionCompiler
    if type(AC) ~= "table" or type(AC.ValidateActions) ~= "function" then
        return nil, nil, nil
    end
    local ok, isValid, errors, warnings = pcall(AC.ValidateActions, actions)
    if not ok then
        return nil, nil, nil
    end
    if type(isValid) ~= "boolean" then isValid = nil end
    if type(errors) ~= "table" then errors = nil end
    if type(warnings) ~= "table" then warnings = nil end
    return isValid, errors, warnings
end

Addon.SerializeEMSSequence = function(sequence, seqName)
    if not sequence or not C_EncodingUtil then return nil end
    local seqCBOR = C_EncodingUtil.SerializeCBOR(sequence)
    local hash = 5381
    if seqCBOR then
        for i = 1, #seqCBOR do
            hash = ((hash * 33) + string.byte(seqCBOR, i)) % 4294967296
        end
    end
    local payload = {
        format = EMS_SEQUENCE_FORMAT,
        version = EMS_SEQUENCE_VERSION,
        locale = GetLocale() or "enUS",
        name = seqName or "DummyAnalyzer Sequence",
        sequence = sequence,
        variables = {},
        checksum = tostring(hash),
    }
    local ok, cbor = pcall(C_EncodingUtil.SerializeCBOR, payload)
    if not ok or not cbor then return nil end
    local ok2, compressed = pcall(C_EncodingUtil.CompressString, cbor)
    if not ok2 or not compressed then return nil end
    local ok3, base64 = pcall(C_EncodingUtil.EncodeBase64, compressed)
    if not ok3 or not base64 then return nil end
    return EMS_IMPORT_PREFIX .. base64
end