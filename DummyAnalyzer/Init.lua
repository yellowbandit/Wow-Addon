local AddonName, Addon = ...
-- ============================================
-- PATHS & CONSTANTS
-- ============================================
local SKINS_DIR = "Interface\\AddOns\\" .. AddonName .. "\\Skins\\"
-- Fonts are bundled in Skins/ (Atkinson Hyperlegible, SIL OFL 1.1 -- see Skins/OFL.txt).
-- These previously pointed into GRIP-EMS's own Media/Fonts folder, coupling this addon to
-- another addon's internal file layout. An EMS reorg would make SetFont fail silently and
-- render text invisible rather than erroring.
local FONT = SKINS_DIR .. "AtkinsonHyperlegible-Regular.ttf"
local FONT_BOLD = SKINS_DIR .. "AtkinsonHyperlegible-Bold.ttf"
local MAIN_FONT = FONT
local BOLD_FONT = FONT_BOLD

Addon.debugMode = false

-- Structured debug log stored in DummyAnalyzerDB for file-system inspection after /reload.
-- I (the AI) read this from the SavedVariables file to trace runtime decisions without guessing.
-- Levels: "error" (always), "info" (debugMode on), "debug" (debugMode on, verbose).
local MAX_DEBUG_LOG = 500
local function DebugLog(level, section, msg, data)
    print(string.format("|cff33ff33[DBG]|r [%s][%s] %s", section, level, msg))
    if level ~= "error" and not Addon.debugMode then return end
    local entry = {
        t = GetTime(),
        l = level,
        s = section,
        m = msg,
    }
    if data then entry.d = data end
    if not DummyAnalyzerDB then return end
    local log = DummyAnalyzerDB._debugLog
    if not log then log = {}; DummyAnalyzerDB._debugLog = log end
    table.insert(log, entry)
    if #log > MAX_DEBUG_LOG then table.remove(log, 1) end
end

local function SafeSetFont(fontString, fontFile, size, flags)
    pcall(function()
        fontString:SetFont(fontFile, size, flags or "")
    end)
end

-- Colors (GRIP-EMS palette)
local AllDialogs = {}
local function trackDialog(f)
    tinsert(AllDialogs, f)
    f:HookScript("OnShow", function()
        for _, d in ipairs(AllDialogs) do
            if d ~= f and d:IsShown() then d:Hide() end
        end
    end)
end
local C = {
    bg = {0.102, 0.102, 0.180, 1},
    bgLight = {0.086, 0.129, 0.243, 1},
    border = {0.200, 0.200, 0.333, 1},
    borderHl = {0.333, 0.333, 0.667, 1},
    text = {0.933, 0.933, 1.000, 1},
    textHl = {1.000, 0.843, 0.000, 1},
    textMuted = {0.533, 0.533, 0.667, 1},
    title = {0.051, 0.051, 0.102, 1},
    btn = {0.118, 0.176, 0.290, 1},
    btnHover = {0.059, 0.204, 0.376, 1},
    btnPrimary = {0.100, 0.280, 0.150, 1},
    btnPrimaryHover = {0.150, 0.380, 0.200, 1},
    btnDanger = {1.000, 0.267, 0.267, 1},
    selected = {0.325, 0.204, 0.514, 1},
}

-- ============================================
-- HELPER FUNCTIONS
-- ============================================
local function CreateStyledFrame(frameType, name, parent)
    return CreateFrame(frameType, name, parent, "BackdropTemplate")
end

local function ApplyBackdrop(frame, useLight)
    if not frame then return end
    frame:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
        insets = {left = 0, right = 0, top = 0, bottom = 0}
    })
    if useLight then
        frame:SetBackdropColor(C.bgLight[1], C.bgLight[2], C.bgLight[3], C.bgLight[4])
    else
        frame:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
    end
    frame:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], C.border[4])
end

local function CreateStyledButton(parent, text, width, height, onClick, style)
    local btn = CreateStyledFrame("Button", nil, parent)
    btn:SetSize(width or 85, height or 28)
    btn:SetScript("OnClick", onClick)
    btn:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
    btn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], C.border[4])
    if style == "primary" then
        btn:SetBackdropColor(C.btnPrimary[1], C.btnPrimary[2], C.btnPrimary[3], C.btnPrimary[4])
    elseif style == "danger" then
        btn:SetBackdropColor(C.btnDanger[1], C.btnDanger[2], C.btnDanger[3], C.btnDanger[4])
    else
        btn:SetBackdropColor(C.btn[1], C.btn[2], C.btn[3], C.btn[4])
    end
    local label = btn:CreateFontString(nil, "OVERLAY")
    SafeSetFont(label, MAIN_FONT, 12)
    label:SetText(text)
    label:SetPoint("CENTER")
    label:SetTextColor(C.text[1], C.text[2], C.text[3], C.text[4])
    btn:SetScript("OnEnter", function()
        if style == "primary" then
            btn:SetBackdropColor(C.btnPrimaryHover[1], C.btnPrimaryHover[2], C.btnPrimaryHover[3], C.btnPrimaryHover[4])
            btn:SetBackdropBorderColor(C.borderHl[1], C.borderHl[2], C.borderHl[3], C.borderHl[4])
        elseif style == "danger" then
            btn:SetBackdropColor(0.95, 0.15, 0.15, 1)
            btn:SetBackdropBorderColor(C.borderHl[1], C.borderHl[2], C.borderHl[3], C.borderHl[4])
        else
            btn:SetBackdropColor(C.btnHover[1], C.btnHover[2], C.btnHover[3], C.btnHover[4])
            btn:SetBackdropBorderColor(C.borderHl[1], C.borderHl[2], C.borderHl[3], C.borderHl[4])
        end
        label:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])
    end)
    btn:SetScript("OnLeave", function()
        if style == "primary" then btn:SetBackdropColor(C.btnPrimary[1], C.btnPrimary[2], C.btnPrimary[3], C.btnPrimary[4])
        elseif style == "danger" then btn:SetBackdropColor(C.btnDanger[1], C.btnDanger[2], C.btnDanger[3], C.btnDanger[4])
        else btn:SetBackdropColor(C.btn[1], C.btn[2], C.btn[3], C.btn[4]) end
        btn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], C.border[4])
        label:SetTextColor(C.text[1], C.text[2], C.text[3], C.text[4])
    end)
    return btn
end

local function CreateSeparator(parent, point, relativeTo, relPoint, x, y)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    line:SetVertexColor(C.border[1], C.border[2], C.border[3], 0.5)
    line:SetPoint(point or "TOPLEFT", relativeTo, relPoint or "BOTTOMLEFT", x or 0, y or -10)
    line:SetPoint("RIGHT", parent, "RIGHT", -20, 0)
    line:SetHeight(1)
    return line
end

-- ============================================
-- DIALOG TEMPLATE
-- ============================================
local function CreateDialog(parent, title, width, height, showClose)
    local overlay = CreateFrame("Frame", nil, parent or UIParent, "BackdropTemplate")
    overlay:SetAllPoints(parent or UIParent)
    overlay:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
    overlay:SetBackdropColor(0, 0, 0, 0.4)
    overlay:SetFrameLevel(100)
    overlay:EnableMouse(true)
    overlay:SetScript("OnMouseDown", function() overlay:Hide() frame:Hide() end)

    local frame = CreateStyledFrame("Frame", nil, overlay)
    frame:SetSize(width, height)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    tinsert(UISpecialFrames, frame)
    ApplyBackdrop(frame, false)

    local titleBar = CreateStyledFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT")
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
    titleBar:SetHeight(36)
    titleBar:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
    titleBar:SetBackdropColor(C.title[1], C.title[2], C.title[3], C.title[4])
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    SafeSetFont(titleText, BOLD_FONT, 15)
    titleText:SetText(title)
    titleText:SetPoint("CENTER")
    titleText:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])

    if showClose then
        local closeBtn = CreateStyledFrame("Button", nil, titleBar)
        closeBtn:SetSize(28, 28)
        closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -8, 0)
        closeBtn:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
        closeBtn:SetBackdropColor(C.btn[1], C.btn[2], C.btn[3], C.btn[4])
        closeBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], C.border[4])
        local closeX = closeBtn:CreateFontString(nil, "OVERLAY")
        SafeSetFont(closeX, BOLD_FONT, 16)
        closeX:SetText("X")
        closeX:SetPoint("CENTER")
        closeX:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], C.textMuted[4])
        closeBtn:SetScript("OnEnter", function()
            closeX:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])
        end)
        closeBtn:SetScript("OnLeave", function()
            closeX:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], C.textMuted[4])
        end)
        closeBtn:SetScript("OnClick", function() frame:Hide() overlay:Hide() end)
    end

    frame:HookScript("OnHide", function() overlay:Hide() end)

    return frame, titleBar
end

-- ============================================
-- CORE VARIABLES (identical to original)
-- ============================================
Addon.testActive = false
Addon.startTime = 0
Addon.testEndTime = nil
Addon.spellHistory = {}
Addon.currentDuration = 120
Addon.updateFrame = nil
Addon.timerFrame = nil

-- Singleton-window tracker: when a new window opens, hide the previous one so we don't
-- stack windows. Updated by RegisterAddonWindow; consumed via ClosePriorWindow.
Addon.currentWindow = nil
local function ClosePriorWindow()
    if Addon.currentWindow and Addon.currentWindow:IsShown() then
        Addon.currentWindow:Hide()
    end
end
local function RegisterAddonWindow(frame)
    if not frame then return end
    ClosePriorWindow()
    Addon.currentWindow = frame
end

-- Pure helper: turn a raw heuristic seqText (which may include headings/metadata) into a
-- clean list of /cast lines AND a deduped spell-name array. Step lines come in two
-- formats: "1. /cast [combat] X" (generated text, legacy logs) and bare "1. Fireball"
-- (logs whose steps were resolved through the EMS public API). Pure: no global state.
-- Used by both the generation handlers and the Push button, so the closure never has to
-- chase upvalues.
local function ParseSequenceLines(rawSeq)
    if type(rawSeq) ~= "string" or rawSeq == "" then return {}, {} end
    local macros, ordered, seen = {}, {}, {}
    for line in rawSeq:gmatch("[^\n]+") do
        local trimmed = line:gsub("^%s*", ""):gsub("%s*$", "")
        local numbered
        trimmed, numbered = trimmed:gsub("^%d+%.%s*", "")  -- strip "1. " numbered prefix
        local first = trimmed:sub(1, 1)
        if first == "/" then
            local verb, payload = trimmed:match("^/(%a+)%s+(.+)$")
            verb = verb or "cast"
            local spell = payload and payload:gsub("^%[?combat%]?%s*", "") or ""
            local cleanSpell = spell:gsub("%s*%(interval:%d+%)$", ""):gsub("%s*%[dupe%]", ""):gsub("%s*$", "")
            if spell ~= "" then
                macros[#macros + 1] = "/" .. verb .. " [combat] " .. spell
                if not seen[cleanSpell] then
                    seen[cleanSpell] = true
                    ordered[#ordered + 1] = cleanSpell
                end
            end
        elseif numbered > 0 and first ~= "" and first ~= "#" and first ~= "=" then
            -- Numbered line with no slash command: a bare spell name ("1. Fireball").
            -- The numbered gate keeps this branch closed to generated-text metadata
            -- lines (Spec:, Icon:, Step Function:, Reset: are never numbered); the
            -- "#" exclusion skips macro directives from legacy multi-line macros.
            local cleanSpell = trimmed:gsub("%s*%(interval:%d+%)$", ""):gsub("%s*%[dupe%]", ""):gsub("%s*$", "")
            if cleanSpell ~= "" then
                macros[#macros + 1] = "/cast [combat] " .. cleanSpell
                if not seen[cleanSpell] then
                    seen[cleanSpell] = true
                    ordered[#ordered + 1] = cleanSpell
                end
            end
        end
    end
    return macros, ordered
end

-- Kid-friendly display: turns a generated sequence into a Grade-3-reading-level report
-- that the user can scan without prior WoW-macro knowledge.
-- mode = "best" or "next"
local function BuildKidFriendlyDisplay(mode, logContext, score, duration, macros, ordered, deficitInfo, hasBaseline)
    -- logContext: { name="...", id=..., logsCount=N, logLabelById={id=label,...} } or nil
    -- SHORT-FOCUSED output: only the macro order + a one-line score context. No deficit walls,
    -- no step numbers, no logs-used list. What you see here is exactly what gets pushed.
    local lines = {}
    local spellLines = {}
    if type(macros) == "table" then
        for _, m in ipairs(macros) do
            local spell = type(m) == "string" and m:match("/%a+ %[combat%] (.+)")
            table.insert(spellLines, tostring(spell or m or ""))
        end
    end
    if mode == "best" then
        lines[#lines + 1] = "|cff66ff66=== THE BEST SEQUENCE ===|r"
        lines[#lines + 1] = ""
        if score and score > 0 then
            lines[#lines + 1] = ("|cffffd200Score:|r %s"):format(Addon.FormatNumber(score))
        end
        if logContext and type(logContext.logsCount) == "number" then
            lines[#lines + 1] = ("From |cffffd200%d|r training log%s."):format(logContext.logsCount, logContext.logsCount == 1 and "" or "s")
        end
        if logContext and type(logContext.logLabelById) == "table" then
            local labels = {}
            for _, lbl in pairs(logContext.logLabelById) do
                table.insert(labels, tostring(lbl))
            end
            if #labels > 0 then
                table.sort(labels)
                local shown = labels[1]
                for i = 2, math.min(#labels, 4) do
                    shown = shown .. ", " .. labels[i]
                end
                if #labels > 4 then
                    shown = shown .. (" (+%d more)"):format(#labels - 4)
                end
                lines[#lines + 1] = ("Using logs: |cffd0d0d0%s|r"):format(shown)
            end
        end
        lines[#lines + 1] = ""
        if #spellLines == 0 then
            lines[#lines + 1] = "|cffff4444(No spells found - run a test first)|r"
        else
            for _, s in ipairs(spellLines) do
                lines[#lines + 1] = ("|cffffff66%s|r"):format(s)
            end
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "|cffaaaaaa--- Push to GRIP-EMS to upload ---|r"
    elseif mode == "next" then
        lines[#lines + 1] = "|cff66aaff=== THE NEXT SEQUENCE ===|r"
        lines[#lines + 1] = ""
        if hasBaseline then
            lines[#lines + 1] = "|cffd0d0d0New iteration of your last sequence.|r"
        else
            lines[#lines + 1] = "|cffd0d0d0Your first sequence. Run a test, then hit Next to improve it.|r"
        end
        lines[#lines + 1] = ""
        if #spellLines == 0 then
            lines[#lines + 1] = "|cffff4444(No spells found - run a test first)|r"
        else
            for _, s in ipairs(spellLines) do
                lines[#lines + 1] = ("|cffffff66%s|r"):format(s)
            end
        end
        lines[#lines + 1] = ""
        if duration and duration > 0 and score then
            lines[#lines + 1] = ("|cffaaaaaaPredicted per %d sec test:|r Score = |cffffd200%s|r"):format(math.floor(duration), Addon.FormatNumber(score))
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "|cffaaaaaa--- Push to GRIP-EMS when ready ---|r"
    end
    return table.concat(lines, "\n")
end

-- Crude deficit-matrix snapshot pulled from SimC data + the latest log's cast counts.
-- Returns an array of { spell, actualRatio, simcRatio, deficit } sorted by worst deficit.
local function ComputeDeficitSnapshot(logSpells, simCData, duration)
    -- Pure data assembly. We avoid calling the heavyweight GenerateSuggestedSequence here -
    -- we already have the source arrays in scope from outside.
    local result = {}
    if type(logSpells) ~= "table" or type(simCData) ~= "table" then return result end
    -- logSpells is { spellName = count }; simCData may carry APL counters/cpes in different schema.
    local totalActual, totalSimc = 0, 0
    local perSpellActual, perSpellSimc = {}, {}
    for s, c in pairs(logSpells) do
        perSpellActual[s] = (perSpellActual[s] or 0) + (tonumber(c) or 0)
        totalActual = totalActual + (tonumber(c) or 0)
    end
    if type(simCData.castCounts) == "table" then
        for s, c in pairs(simCData.castCounts) do
            perSpellSimc[s] = (perSpellSimc[s] or 0) + (tonumber(c) or 0)
            totalSimc = totalSimc + (tonumber(c) or 0)
        end
    end
    -- Union of both spell sets, plus any from the runner-up log
    local seen = {}
    for s in pairs(perSpellActual) do seen[s] = true end
    for s in pairs(perSpellSimc) do seen[s] = true end
    for s in pairs(seen) do
        local a = perSpellActual[s] or 0
        local sc = perSpellSimc[s] or 0
        result[#result + 1] = {
            spell = s,
            actualCount = a,
            simcCount = sc,
            actualRatio = (totalActual > 0) and (a / totalActual) or 0,
            simcRatio = (totalSimc > 0) and (sc / totalSimc) or 0,
            deficit = (sc > 0) and (math.max(0, (sc - a) / sc)) or 0,
        }
    end
    -- Sort: worst deficit first (i.e., largest deficit with non-zero simc)
    table.sort(result, function(x, y) return (y.deficit or 0) < (x.deficit or 0) end)
    -- Truncate to top 12 so the kid-friendly view isn't a wall
    if #result > 12 then
        local trimmed = {}
        for i = 1, 12 do trimmed[i] = result[i] end
        return trimmed
    end
    return result
end
Addon.timerText = nil
Addon.armedTest = false
Addon.armedMinutes = nil
Addon.combatWaitTicker = nil
Addon.spellNameCache = {}
Addon.damageData = {}
Addon.totalDamage = 0
Addon.playerGUID = nil
Addon.playerName = nil
Addon.meterDiag = nil
Addon.meterReadError = nil
Addon.damageFromEnemyFallback = false
Addon.damageFromHealthFallback = false
Addon.healthBaseHp = nil
Addon.healthTotal = 0
Addon.healthTrackReady = false
Addon.meterEventSeen = false
Addon.pendingReport = false
Addon.reportWaitTicker = nil
Addon.activeBuffs = {}
Addon.buffUptime = {}
Addon.buffTicker = nil
Addon.activeDebuffs = {}
Addon.debuffUptime = {}
Addon.buffGaps = {}
Addon.lastBuffExpiry = {}
Addon.spellPowerCosts = {}
-- Robust secret detection (CombatAnalytics ApiCompat pattern): a secret value
-- cannot be concatenated with tostring (throws) and/or compares unequally to "".
local function IsSecretValue(val)
    if val == nil then return false end
    local okConcat, asStr = pcall(function() return tostring(val) .. "" end)
    if not okConcat then return true end
    if type(asStr) ~= "string" then return true end
    local okCmp = pcall(function() return asStr == "" end)
    return not okCmp
end
Addon.simcDialog = nil
Addon.clogDialog = nil
Addon.comparisonPopup = nil
local MAX_TRACKED_BUFF_DURATION = 120
local MAX_TRACKED_DEBUFF_DURATION = 300
local ALWAYS_TRACK_BUFFS = {
    [2565] = true,
    [132404] = true,
    [190456] = true,
}
local IGNORED_BUFFS = {
    [6673] = true,
}
local BUFF_KEY_ALIASES = {
    [2565] = "shield_block",
    [132404] = "shield_block",
    [190456] = "ignore_pain",
}
local CAST_BUFF_DURATIONS = {
    [2565] = {name = "Shield Block", duration = 8},
    [132404] = {name = "Shield Block", duration = 8},
    [190456] = {name = "Ignore Pain", duration = 15},
}
local CAST_BUFF_DURATIONS_LOOKUP = {}
for _, config in pairs(CAST_BUFF_DURATIONS) do
    CAST_BUFF_DURATIONS_LOOKUP[config.name] = true
end

-- ============================================
-- INIT-LUA EXPORTS (namespace promotion, rule A/B)
-- ============================================
Addon.DebugLog = DebugLog
Addon.SafeSetFont = SafeSetFont
Addon.trackDialog = trackDialog
Addon.CreateStyledFrame = CreateStyledFrame
Addon.ApplyBackdrop = ApplyBackdrop
Addon.CreateStyledButton = CreateStyledButton
Addon.CreateSeparator = CreateSeparator
Addon.CreateDialog = CreateDialog
Addon.RegisterAddonWindow = RegisterAddonWindow
Addon.C = C
Addon.MAIN_FONT = MAIN_FONT
Addon.BOLD_FONT = BOLD_FONT
Addon.FONT = FONT
Addon.ParseSequenceLines = ParseSequenceLines
Addon.BuildKidFriendlyDisplay = BuildKidFriendlyDisplay
Addon.ComputeDeficitSnapshot = ComputeDeficitSnapshot
Addon.IsSecretValue = IsSecretValue
Addon.MAX_TRACKED_BUFF_DURATION = MAX_TRACKED_BUFF_DURATION
Addon.MAX_TRACKED_DEBUFF_DURATION = MAX_TRACKED_DEBUFF_DURATION
Addon.ALWAYS_TRACK_BUFFS = ALWAYS_TRACK_BUFFS
Addon.IGNORED_BUFFS = IGNORED_BUFFS
Addon.BUFF_KEY_ALIASES = BUFF_KEY_ALIASES
Addon.CAST_BUFF_DURATIONS = CAST_BUFF_DURATIONS
Addon.CAST_BUFF_DURATIONS_LOOKUP = CAST_BUFF_DURATIONS_LOOKUP