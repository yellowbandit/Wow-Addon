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

-- BuildIntervalMap is the SINGLE source of truth for interleave intervals in the
-- EMS pipeline. It accepts ONLY explicit overrides: the optimizer's SelectInterleaves
-- winners (passed as intervalOverrides by GenerateSuggestedSequence), or a previously
-- stored/resolved map (Addon.ResolveInterleaveMap at push time). The old frequency
-- heuristic branch - which invented intervals from cast counts whenever
-- intervalOverrides was nil - was removed so the map can never silently diverge from
-- what the optimizer selected or what the preview shows.
local function BuildIntervalMap(orderedSpellNames, cfg, intervalOverrides)
    local intervalMap = {}
    if type(intervalOverrides) == "table" then
        for name, iv in pairs(intervalOverrides) do
            intervalMap[name] = math.max(1, math.min(50, NumberOrZero(iv)))
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
        if intervalMap[s] and intervalApplied[s] then
            -- Interleaved spell already emitted once with its interval; drop duplicates.
        else
            local act = { type = "action", macro = string.format("%s [combat] %s", GetActionPrefix(s), s) }
            if intervalMap[s] then
                intervalApplied[s] = true
                act.interval = intervalMap[s]
            end
            actions[#actions + 1] = act
        end
    end
    return actions
end

-- Pure expansion of a base spell order + interleave map into the flat cast list that
-- GRIP-EMS weaves at runtime. Mirrors GRIP-EMS ActionCompiler._applyInterleaving: each
-- interleaved spell gains a copy AFTER every Nth original base step (k = interval,
-- 2*interval, ... <= #base). Buckets are keyed by ORIGINAL base index so stacked
-- intervals never drift each other. Uses only the intervalMap semantics, never spell
-- counts. Display-only: the pushed sequence stays the unexpanded flat list produced by
-- BuildActionsFromFlat, which GRIP-EMS expands identically, so the preview always
-- matches what Push to GRIP-EMS builds.
-- @param baseOrdered array of spell names in base order (normalized internally)
-- @param intervalMap table spell name -> interval (GRIP-EMS-emulated clamp: only a
-- minimum of 1 is enforced like GRIP-EMS; non-positive ignored)
-- @param maxCasts number|nil maximum casts to return (defaults PREVIEW_MAX_CASTS)
-- @return table { steps = {name,...}, truncated = boolean }
local PREVIEW_MAX_CASTS = 20
Addon.ExpandSequenceForPreview = function(baseOrdered, intervalMap, maxCasts)
    maxCasts = maxCasts or PREVIEW_MAX_CASTS
    local base = {}
    for _, s in ipairs(baseOrdered or {}) do
        local norm = NormalizeSpellName(s)
        if norm ~= "" then base[#base + 1] = norm end
    end
    local originalCount = #base
    if originalCount == 0 then return { steps = {}, truncated = false } end
    local insertAfter = {}
    local totalInserted = 0
    for _, name in ipairs(base) do
        local iv = type(intervalMap) == "table" and intervalMap[name] or nil
        if iv and iv > 0 then
            -- Match GRIP-EMS exactly: clamp only the MINIMUM to 1, never cap at 50.
            local interval = NumberOrZero(iv)
            if interval < 1 then interval = 1 end
            local k = interval
            while k <= originalCount and totalInserted < 200 do
                local bucket = insertAfter[k]
                if not bucket then bucket = {}; insertAfter[k] = bucket end
                bucket[#bucket + 1] = name
                totalInserted = totalInserted + 1
                k = k + interval
            end
        end
    end
    local steps = {}
    local truncated = false
    for k = 1, originalCount do
        if #steps < maxCasts then steps[#steps + 1] = base[k] else truncated = true end
        local bucket = insertAfter[k]
        if bucket then
            for _, name in ipairs(bucket) do
                if #steps < maxCasts then steps[#steps + 1] = name else truncated = true end
            end
        end
    end
    return { steps = steps, truncated = truncated }
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

-- Deterministic rendering of an interleave map: "Name = N" entries sorted by name,
-- joined with ", ", or "none" when empty/nil. Used in DebugLog lines so generation,
-- preview, and push all log the same value for cross-checks.
Addon.FormatInterleaveMap = function(intervalMap)
    if type(intervalMap) ~= "table" then return "none" end
    local entries = {}
    for name, iv in pairs(intervalMap) do
        if iv and iv > 0 then
            entries[#entries + 1] = name .. " = " .. tostring(iv)
        end
    end
    if #entries == 0 then return "none" end
    table.sort(entries)
    return table.concat(entries, ", ")
end

-- Resolve the interleave map that must be used when storing or pushing a sequence.
-- Priority: the freshest known map wins. An EMPTY table is a real value - a fresh
-- "no interleaves" result - and beats any stale persisted map, preventing a previous
-- optimize/push from resurrecting intervals the user already cleared.
Addon.ResolveInterleaveMap = function(persistedBest)
    if type(Addon.lastInterleaveMap) == "table" then
        return Addon.lastInterleaveMap
    end
    if type(Addon.bestSequence) == "table" and type(Addon.bestSequence.interleaveMap) == "table" then
        return Addon.bestSequence.interleaveMap
    end
    if type(persistedBest) == "table" and type(persistedBest.interleaveMap) == "table" then
        return persistedBest.interleaveMap
    end
    return {}
end