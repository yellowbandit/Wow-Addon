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

local debugMode = false

-- Structured debug log stored in DummyAnalyzerDB for file-system inspection after /reload.
-- I (the AI) read this from the SavedVariables file to trace runtime decisions without guessing.
-- Levels: "error" (always), "info" (debugMode on), "debug" (debugMode on, verbose).
local MAX_DEBUG_LOG = 500
local function DebugLog(level, section, msg, data)
    print(string.format("|cff33ff33[DBG]|r [%s][%s] %s", section, level, msg))
    if level ~= "error" and not debugMode then return end
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
local testActive = false
local startTime = 0
local testEndTime = nil
local spellHistory = {}
local currentDuration = 120
local updateFrame = nil
local timerFrame = nil

-- Singleton-window tracker: when a new window opens, hide the previous one so we don't
-- stack windows. Updated by RegisterAddonWindow; consumed via ClosePriorWindow.
local currentWindow = nil
local function ClosePriorWindow()
    if currentWindow and currentWindow:IsShown() then
        currentWindow:Hide()
    end
end
local function RegisterAddonWindow(frame)
    if not frame then return end
    ClosePriorWindow()
    currentWindow = frame
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
            local spell = trimmed:gsub("^/%a+%s+%[?combat%]?%s*", "")
            local cleanSpell = spell:gsub("%s*%(interval:%d+%)$", ""):gsub("%s*%[dupe%]", ""):gsub("%s*$", "")
            if spell ~= "" then
                macros[#macros + 1] = "/cast [combat] " .. spell
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
    local lines = {}
    if mode == "best" then
        lines[#lines + 1] = "|cff66ff66=== THE BEST SEQUENCE ===|r"
        lines[#lines + 1] = ""
        lines[#lines + 1] = "What this means: I looked at ALL of your training logs combined and"
        if logContext and type(logContext.logsCount) == "number" then
            lines[#lines + 1] = ("figured out a good order to press your buttons. Used |cffffd200%d|r log%s."):format(logContext.logsCount, logContext.logsCount == 1 and "" or "s")
        else
            lines[#lines + 1] = "figured out a good order to press your buttons."
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "|cff66ff66HOW STRONG IS IT|r"
        local dpsScore = score or 0
        lines[#lines + 1] = ("|cffffd200Score:|r %s  (higher = better DPS)"):format(Addon.FormatNumber(dpsScore))
        if duration and duration > 0 then
            lines[#lines + 1] = ("|cffffd200Based on:|r %d seconds of fighting"):format(math.floor(duration))
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "|cff66ff66WHAT THE MACRO DOES (in the order GRIP-EMS will fire)|r"
        lines[#lines + 1] = ""
        if #macros == 0 then
            lines[#lines + 1] = "|cffff4444(Empty - I didn't find any spells to include)|r"
        else
            for i, m in ipairs(macros) do
                local spell = m:match("/%a+ %[combat%] (.+)")
                lines[#lines + 1] = ("|cffd0d0d0Step %d.|r |cffffff66%s|r"):format(i, tostring(spell or m))
            end
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "|cff66ff66WHY THIS ORDER|r"
        lines[#lines + 1] = ""
        if type(deficitInfo) == "table" and #deficitInfo > 0 then
            lines[#lines + 1] = "I compare what |cffffd200you|r actually pressed to what |cffffd200SimulationCraft|r says"
            lines[#lines + 1] = "you SHOULD press. Spells you're NOT pressing enough get pushed earlier."
            lines[#lines + 1] = ""
            for _, d in ipairs(deficitInfo) do
                local arrow = d.deficit and d.deficit > 0 and "<<PUSH EARLIER>>" or "OK"
                local col  = d.deficit and d.deficit > 0 and "|cffff8844" or "|cff66ff66"
                lines[#lines + 1] = ("|cffffff66%-22s|r %sdef=%.2f  actual=%.0f%%  simc=%.0f%%  %s|r"):format(
                    (d.spell or ""):sub(1, 22), col, d.deficit or 0,
                    (d.actualRatio or 0) * 100, (d.simcRatio or 0) * 100, arrow)
            end
        else
            lines[#lines + 1] = "I tried every swap, insert, and reorder to find the best order."
            lines[#lines + 1] = "I picked the one that scored the highest for your character."
        end
        if logContext and type(logContext.logLabelById) == "table" and next(logContext.logLabelById) then
            lines[#lines + 1] = ""
            lines[#lines + 1] = "|cff66ff66LOGS USED|r"
            lines[#lines + 1] = ""
            local anyShown = false
            for id, label in pairs(logContext.logLabelById) do
                lines[#lines + 1] = ("|cffffff66- Log #%d|r  %s"):format(id, tostring(label or "(unnamed)"))
                anyShown = true
            end
            if not anyShown then
                lines[#lines + 1] = "|cffd0d0d0- log details available in Saved Logs tab|r"
            end
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "|cffaaaaaa--- next: hit Push to GRIP-EMS to upload ---|r"
    elseif mode == "next" then
        lines[#lines + 1] = "|cff66aaff=== THE NEXT SEQUENCE (iteration)|r"
        lines[#lines + 1] = ""
        if hasBaseline then
            if logContext and logContext.logLabel then
                lines[#lines + 1] = ("|cffffd200Comparing against LOG:|r |cffffff66%s|r (#%d)"):format(tostring(logContext.logLabel), logContext.id or 0)
                lines[#lines + 1] = ""
            end
            lines[#lines + 1] = "What this means: I took the |cffffd200last sequence|r you saw, shook it up a"
            lines[#lines + 1] = "bit, and ran the optimizer again. The new version should help with these"
            lines[#lines + 1] = "weak spots from your last test:"
            lines[#lines + 1] = ""
        else
            lines[#lines + 1] = "What this means: This is your |cffffd200first sequence|r. Run a training dummy"
            lines[#lines + 1] = "test, then come back and click 'Next Sequence' to iterate and improve it."
            lines[#lines + 1] = ""
            lines[#lines + 1] = "I built this order fresh from your cast data:"
            lines[#lines + 1] = ""
        end
        if type(deficitInfo) == "table" and #deficitInfo > 0 then
            local targetCount = 0
            for _, d in ipairs(deficitInfo) do
                if d.deficit and d.deficit > 0 then targetCount = targetCount + 1 end
            end
            if targetCount == 0 then
                if hasBaseline then
                    lines[#lines + 1] = "|cff66ff66You were already hitting every spell enough - try a fresh log.|r"
                else
                    lines[#lines + 1] = "|cff66ff66Your rotation looks solid. Run a test, then come back to iterate.|r"
                end
            else
                lines[#lines + 1] = ("|cffaaaaaa%d spell%s I'll try to fix:|r"):format(targetCount, targetCount == 1 and "" or "s")
                lines[#lines + 1] = ""
                for _, d in ipairs(deficitInfo) do
                    if d.deficit and d.deficit > 0 then
                        local spell = (d.spell or ""):sub(1, 22)
                        lines[#lines + 1] = ("|cffff8844!! %-22s|r  you pressed |cffffd200%.0f%%|r, should be |cffffd200%.0f%%|r"):format(
                            spell, (d.actualRatio or 0) * 100, (d.simcRatio or 0) * 100)
                        lines[#lines + 1] = ("|cffaaaaaa    (target: use it %d more time%s)|r"):format(
                            math.max(1, math.floor((d.deficit or 1) * 4)),
                            math.max(1, math.floor((d.deficit or 1) * 4)) == 1 and "" or "s")
                    end
                end
            end
        elseif hasBaseline ~= false then
            lines[#lines + 1] = "|cffaaaaaa(no specific weak spots detected - re-running for variety)|r"
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "|cff66aaffWHAT I'M GOING TO TRY (the new macro order)|r"
        lines[#lines + 1] = ""
        if #macros == 0 then
            lines[#lines + 1] = "|cffff4444(Empty - I didn't find spells to improve)|r"
        else
            for i, m in ipairs(macros) do
                local spell = m:match("/%a+ %[combat%] (.+)")
                -- Annotate NEW positions vs the old bestSeq
                lines[#lines + 1] = ("|cffd0d0d0Step %d.|r |cffffff66%s|r"):format(i, tostring(spell or m))
            end
        end
        lines[#lines + 1] = ""
        if duration and duration > 0 then
            lines[#lines + 1] = ("|cffaaaaaaPredicted per %d sec test:|r Score = |cffffd200%s|r"):format(
                math.floor(duration), Addon.FormatNumber(score or 0))
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "|cffaaaaaa--- next: iterate, test, iterate. Push to GRIP-EMS when ready ---|r"
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
local timerText = nil
local armedTest = false
local armedMinutes = nil
local combatWaitTicker = nil
local spellNameCache = {}
local damageData = {}
local totalDamage = 0
local playerGUID = nil
local pendingReport = false
local reportWaitTicker = nil
local activeBuffs = {}
local buffUptime = {}
local buffTicker = nil
local activeDebuffs = {}
local debuffUptime = {}
local buffGaps = {}
local lastBuffExpiry = {}
local spellPowerCosts = {}
local IsSecretValue = issecretvalue or function() return false end
local simcDialog = nil
local clogDialog = nil
local comparisonPopup = nil
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
-- SAVED LOGS DATABASE
-- ============================================
DummyAnalyzerDB = DummyAnalyzerDB or {}

local function GetCharDB()
    local key = playerGUID or "pending"
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
    local cached = spellNameCache[idStr]
    if cached then return cached end
    local nameOk, name = pcall(C_Spell.GetSpellName, spellId)
    if nameOk and name and type(name) == "string" and not IsSecretValue(name) then
        spellNameCache[idStr] = name
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
                    if not spellNameCache[key] then
                        local nameOk, name = pcall(C_Spell.GetSpellName, itemInfo.spellID)
    if nameOk and name and type(name) == "string" and not IsSecretValue(name) and pcall(string.byte, name, 1) then
                            spellNameCache[key] = name
                        end
                    end
                end
            end
        end
    end
end

-- ============================================
-- DAMAGE TRACKING (original C_DamageMeter)
-- ============================================
local function ResetDamageData()
    damageData = {}
    totalDamage = 0
end

local function ReadDamageMeterData()
    if debugMode then print("|cff33ff33[DummyAnalyzer Debug]|r Reading damage data...") end

    if not C_DamageMeter then return false end

    local sessionType = 1
    local meterType = 0

    local source
    local okWithGuid, sourceWithGuid = pcall(C_DamageMeter.GetCombatSessionSourceFromType, sessionType, meterType, playerGUID)
    if okWithGuid then source = sourceWithGuid end
    if not source then
        local okWithoutGuid, sourceWithoutGuid = pcall(C_DamageMeter.GetCombatSessionSourceFromType, sessionType, meterType)
        if okWithoutGuid then source = sourceWithoutGuid end
    end

    if not source then 
        if debugMode then print("|cff33ff33[DummyAnalyzer Debug]|r No source data") end
        return false 
    end

    totalDamage = SafeTableGet(source, "totalAmount") or 0
    if debugMode then print("|cff33ff33[DummyAnalyzer Debug]|r Total Damage:", totalDamage) end

    damageData = {}
    local spells = SafeTableGet(source, "combatSpells")

    if spells and type(spells) == "table" then
        if debugMode then print("|cff33ff33[DummyAnalyzer Debug]|r Found", #spells, "spells") end
        for _, spell in ipairs(spells) do
            if type(spell) == "table" then
                local spellID = SafeTableGet(spell, "spellID")
                local name = GetSpellName(spellID)
                local totalAmt = SafeTableGet(spell, "totalAmount") or 0
                local details = SafeTableGet(spell, "combatSpellDetails")
                local hits = 0
                local highest = 0
                if details and type(details) == "table" then
                    hits = #details
                    for _, d in ipairs(details) do
                        if type(d) == "table" then
                            local amt = SafeTableGet(d, "amount") or 0
                            if amt > highest then highest = amt end
                        end
                    end
                end
                local aps = SafeTableGet(spell, "amountPerSecond") or 0
                local overkill = SafeTableGet(spell, "overkillAmount") or 0
                damageData[name] = {
                    total = totalAmt,
                    hits = hits,
                    highest = highest,
                    aps = aps,
                    overkill = overkill,
                }
            end
        end
    end

    return totalDamage > 0
end

local RecordKnownBuffCast

local function RecordSpell(spellId)
    if not testActive or not spellId or IsSecretValue(spellId) then return end
    local name = GetSpellName(spellId)
    if debugMode then
        print(string.format("|cff33ff33[DEBUG]|r Spell recorded: %s (ID: %s)", name or "?", spellId))
    end
    local elapsed = GetTime() - startTime
    local buffSnapshot = {}
    for key, buff in pairs(activeBuffs) do
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
                    if not spellPowerCosts[safeName] then
                        spellPowerCosts[safeName] = {totalCost = 0, count = 0, powerType = ptName or "?"}
                    end
                    spellPowerCosts[safeName].totalCost = spellPowerCosts[safeName].totalCost + entry.cost
                    spellPowerCosts[safeName].count = spellPowerCosts[safeName].count + 1
                    break
                end
            end
        end
    end
    table.insert(spellHistory, {time = elapsed, name = safeName, buffs = buffSnapshot, cost = costData})
    RecordKnownBuffCast(spellId, name)
end

-- ============================================
-- BUFF UPTIME TRACKING (original)
-- ============================================
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
    if not buffUptime[key] then
        buffUptime[key] = {name = name or key, uptime = 0}
    elseif name and buffUptime[key].name == key then
        buffUptime[key].name = name
    end
    buffUptime[key].uptime = buffUptime[key].uptime + seconds
end

local function CloseExpiredTimedBuffs(now)
    now = now or GetTime()
    for key, buff in pairs(activeBuffs) do
        if buff.expiresAt and now >= buff.expiresAt then
            AddBuffUptime(key, buff.name, buff.expiresAt - buff.activeSince)
            lastBuffExpiry[key] = buff.expiresAt
            activeBuffs[key] = nil
        end
    end
end

local function ResetBuffTracking()
    if buffTicker then
        buffTicker:Cancel()
        buffTicker = nil
    end
    activeBuffs = {}
    buffUptime = {}
    activeDebuffs = {}
    debuffUptime = {}
    buffGaps = {}
    lastBuffExpiry = {}
    spellPowerCosts = {}
end

local function StartBuff(spellId, spellName)
    if not testActive then return end
    local key = BuildBuffKey(spellId, spellName)
    if not key then return end
    if not activeBuffs[key] then
        activeBuffs[key] = {name = spellName or key, activeSince = GetTime()}
    elseif spellName and activeBuffs[key].name == key then
        activeBuffs[key].name = spellName
    end
end

local function RefreshTimedBuff(spellId, spellName, duration)
    if not testActive or not spellId or not duration then return end
    local key = BuildBuffKey(spellId, spellName)
    if not key then return end

    local now = GetTime()
    local expiresAt = now + duration
    local buff = activeBuffs[key]
    if buff and buff.expiresAt and now > buff.expiresAt then
        AddBuffUptime(key, buff.name, buff.expiresAt - buff.activeSince)
        lastBuffExpiry[key] = buff.expiresAt
        buff = nil
    end

    if not buff then
        if lastBuffExpiry[key] then
            local gap = now - lastBuffExpiry[key]
            if gap > 0.5 then
                if not buffGaps[key] then buffGaps[key] = {name = spellName or key, gaps = {}} end
                table.insert(buffGaps[key].gaps, gap)
            end
            lastBuffExpiry[key] = nil
        end
        activeBuffs[key] = {name = spellName or key, activeSince = now, expiresAt = expiresAt}
    else
        buff.name = spellName or buff.name
        buff.expiresAt = math.max(buff.expiresAt or now, expiresAt)
    end
end

RecordKnownBuffCast = function(spellId, spellName)
    if not spellId or IsSecretValue(spellId) then return end
    local config = CAST_BUFF_DURATIONS[spellId]
    if not config then return end
    RefreshTimedBuff(spellId, config.name or spellName, config.duration)
end

local function StopBuff(spellId, spellName)
    if not testActive then return end
    local key = BuildBuffKey(spellId, spellName)
    if not key then return end
    local buff = activeBuffs[key]
    if not buff then return end
    local now = GetTime()
    AddBuffUptime(key, spellName or buff.name, now - buff.activeSince)
    activeBuffs[key] = nil
end

local function PollPlayerBuffs()
    if not testActive or not C_UnitAuras or not C_UnitAuras.GetUnitAuras then return end

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
                    if not activeBuffs[key] then
                        activeBuffs[key] = {name = GetSpellName(spellId), activeSince = GetTime()}
                        -- Record detected cast for off-GCD spells (Shield Block, Ignore Pain) that don't fire UNIT_SPELLCAST_SUCCEEDED
                        if CAST_BUFF_DURATIONS[spellId] then
                            RecordSpell(spellId)
                        end
                    end
                end
            end
        end
    end

    for key, buff in pairs(activeBuffs) do
        if not buff.expiresAt and not seen[key] then
            AddBuffUptime(key, buff.name, GetTime() - buff.activeSince)
            activeBuffs[key] = nil
        end
    end
end

local function AddDebuffUptime(key, name, seconds)
    if not key or not seconds or seconds <= 0 then return end
    if not debuffUptime[key] then
        debuffUptime[key] = {name = name or key, uptime = 0}
    elseif name and debuffUptime[key].name == key then
        debuffUptime[key].name = name
    end
    debuffUptime[key].uptime = debuffUptime[key].uptime + seconds
end

local function PollTargetDebuffs()
    if not testActive or not C_UnitAuras or not C_UnitAuras.GetUnitAuras then return end
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
                    if not activeDebuffs[key] then
                        activeDebuffs[key] = {name = GetSpellName(spellId), activeSince = GetTime()}
                    end
                end
            end
        end
    end

    for key, debuff in pairs(activeDebuffs) do
        if not seen[key] then
            AddDebuffUptime(key, debuff.name, GetTime() - debuff.activeSince)
            activeDebuffs[key] = nil
        end
    end
end

local function PollTestMetrics()
    PollPlayerBuffs()
    PollTargetDebuffs()
end

local function StartBuffTicker()
    if buffTicker then
        buffTicker:Cancel()
        buffTicker = nil
    end
    PollTestMetrics()
    if C_Timer and C_Timer.NewTicker then
        buffTicker = C_Timer.NewTicker(0.5, PollTestMetrics)
    end
end

local function FinalizeBuffTracking()
    if buffTicker then
        buffTicker:Cancel()
        buffTicker = nil
    end
    local now = GetTime()
    for key, buff in pairs(activeBuffs) do
        local endTime = buff.expiresAt and math.min(now, buff.expiresAt) or now
        AddBuffUptime(key, buff.name, endTime - buff.activeSince)
    end
    activeBuffs = {}
    for key, debuff in pairs(activeDebuffs) do
        AddDebuffUptime(key, debuff.name, now - debuff.activeSince)
    end
    activeDebuffs = {}
end

-- ============================================
-- FORMAT HELPERS (original)
-- ============================================
function Addon.FormatNumber(num)
    if not num then return "0" end
    local formatted = tostring(math.floor(num))
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return formatted
end

-- secret-safe concatenation: table.concat is blocked for secret values
local function SecretSafe(val)
    local ok, isSec = pcall(IsSecretValue, val)
    return (ok and isSec) and true or false
end

local function JoinLines(lines)
    local result = ""
    for _, line in ipairs(lines) do
        if not SecretSafe(line) then result = result .. line .. "\n" end
    end
    return result
end

local function ShortNum(n)
    local neg = n and n < 0
    n = math.floor(math.abs(n or 0))
    local result
    if n >= 1000000 then result = string.format("%.2fM", n / 1000000)
    elseif n >= 1000 then result = string.format("%.1fK", n / 1000)
    else result = tostring(n)
    end
    return neg and "-" .. result or result
end
Addon.ShortNum = ShortNum

-- ============================================
-- SAVED LOGS: Save / Delete / Compare
-- ============================================

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
    local s = step:match("^/cast%s+.+%](.+)") or step:match("^/use%s+.+%](.+)") or step:match("^/cast%s+(.+)") or step:match("^/use%s+(.+)") or step
    return s:match("^%s*(.-)%s*$")
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
            local curOrder = OrderCorrelation(spellHistory, names)
            local bestOrder = OrderCorrelation(spellHistory, bestNames)
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

-- Forward declarations: FilterSimCData and ScanPlayerTalents are defined
-- after the functions that call them. Without these, closures in
-- SaveCurrentLog, ShowSimCImportDialog, CompareLogs, and GenerateGapReport
-- would capture nil globals instead of the locals.
local FilterSimCData
local ScanPlayerTalents

local function SaveCurrentLog()
    local elapsed = (testActive and (GetTime() - startTime)) or (testEndTime and (testEndTime - startTime)) or 0
    if elapsed < 1 then return nil end

    local castCounts = {}
    for _, spell in ipairs(spellHistory) do
        local n = spell and spell.name
        if n and not IsSecretValue(n) then
            castCounts[n] = (castCounts[n] or 0) + 1
        end
    end

    local totalCasts = #spellHistory
    local dps = (totalDamage > 0 and elapsed > 0) and math.floor(totalDamage / elapsed) or 0
    local durMin = (currentDuration == 30) and "30s" or (math.floor(currentDuration / 60) .. "min")

    local db = GetCharDB()
    -- Reuse the lowest available ID so deletions don't create gaps
    local used = {}
    for _, l in ipairs(db.logs) do used[l.id] = true end
    local id = 1
    while used[id] do id = id + 1 end
    if id >= db.nextId then db.nextId = id + 1 end

    -- Detect GRIP-EMS sequence FIRST, then use its steps for ensureSpells
    local infFunc = InferStepFunction(spellHistory)
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
            saveImportStr = GenerateEMSImportString(castCounts, damageData, importSpells) or ""
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
        totalDamage = totalDamage,
        totalCasts = totalCasts,
        dps = dps,
        specName = specName,
        castCounts = DeepCopy(castCounts),
        damageData = DeepCopy(damageData),
        spellHistory = DeepCopy(spellHistory),
        buffUptime = DeepCopy(buffUptime),
        debuffUptime = DeepCopy(debuffUptime),
        buffGaps = DeepCopy(buffGaps),
        notes = "",
        spellPowerCosts = DeepCopy(spellPowerCosts),
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
-- SimC IMPORT
-- ============================================
local SIMC_SPELL_MAP = {
    -- Generic
    ["auto_attack"] = "Auto Attack",
    ["autoattack"] = "Auto Attack",
    -- Warrior (Arms/Fury/Prot)
    ["mortal_strike"] = "Mortal Strike",
    ["execute"] = "Execute",
    ["colossus_smash"] = "Colossus Smash",
    ["bladestorm"] = "Bladestorm",
    ["rend"] = "Rend",
    ["slam"] = "Slam",
    ["overpower"] = "Overpower",
    ["thunder_clap"] = "Thunder Clap",
    ["shield_slam"] = "Shield Slam",
    ["revenge"] = "Revenge",
    ["devastate"] = "Devastate",
    ["ignite_weapon"] = "Ignite Weapon",
    ["spear_of_bastion"] = "Spear of Bastion",
    ["condemn"] = "Condemn",
    ["shield_block"] = "Shield Block",
    ["shield_charge"] = "Shield Charge",
    ["ravager"] = "Ravager",
    ["ignore_pain"] = "Ignore Pain",
    ["demoralizing_shout"] = "Demoralizing Shout",
    ["avatar"] = "Avatar",
    ["charge"] = "Charge",
    ["whirlwind"] = "Whirlwind",
    ["cleave"] = "Cleave",
    ["heroic_strike"] = "Heroic Strike",
    ["pummel"] = "Pummel",
    ["spell_reflection"] = "Spell Reflection",
    ["intervene"] = "Intervene",
    ["taunt"] = "Taunt",
    ["last_stand"] = "Last Stand",
    ["shield_wall"] = "Shield Wall",
    ["berserker_rage"] = "Berserker Rage",
    ["victory_rush"] = "Victory Rush",
    ["impending_victory"] = "Impending Victory",
    ["storm_bolt"] = "Storm Bolt",
    ["shockwave"] = "Shockwave",
    ["intimidating_shout"] = "Intimidating Shout",
    -- Paladin (Protection/Holy/Ret)
    ["crusader_strike"] = "Crusader Strike",
    ["judgment"] = "Judgment",
    ["divine_storm"] = "Divine Storm",
    ["templars_verdict"] = "Templar's Verdict",
    ["blade_of_justice"] = "Blade of Justice",
    ["consecration"] = "Consecration",
    ["hammer_of_wrath"] = "Hammer of Wrath",
    ["wake_of_ashes"] = "Wake of Ashes",
    ["final_reckoning"] = "Final Reckoning",
    ["shield_of_the_righteous"] = "Shield of the Righteous",
    ["avengers_shield"] = "Avenger's Shield",
    ["holy_power"] = "Holy Power",
    ["ardent_defender"] = "Ardent Defender",
    ["divine_shield"] = "Divine Shield",
    ["lay_on_hands"] = "Lay on Hands",
    ["blessing_of_protection"] = "Blessing of Protection",
    ["blessing_of_freedom"] = "Blessing of Freedom",
    ["blessing_of_sacrifice"] = "Blessing of Sacrifice",
    ["hand_of_reckoning"] = "Hand of Reckoning",
    ["rebuke"] = "Rebuke",
    ["hammer_of_justice"] = "Hammer of Justice",
    ["turn_evil"] = "Turn Evil",
    ["divine_toll"] = "Divine Toll",
    ["ashen_hallow"] = "Ashen Hallow",
    ["vanquishers_hammer"] = "Vanquisher's Hammer",
    -- Hunter
    ["kill_command"] = "Kill Command",
    ["cobra_shot"] = "Cobra Shot",
    ["steady_shot"] = "Steady Shot",
    ["arcane_shot"] = "Arcane Shot",
    ["multi_shot"] = "Multi-Shot",
    ["barbed_shot"] = "Barbed Shot",
    ["wildfire_bomb"] = "Wildfire Bomb",
    ["chakrams"] = "Chakrams",
    ["flayed_shot"] = "Flayed Shot",
    -- Rogue
    ["sinister_strike"] = "Sinister Strike",
    ["backstab"] = "Backstab",
    ["eviscerate"] = "Eviscerate",
    ["rupture"] = "Rupture",
    ["slice_and_dice"] = "Slice and Dice",
    ["shadowstrike"] = "Shadowstrike",
    ["shuriken_storm"] = "Shuriken Storm",
    ["gloomblade"] = "Gloomblade",
    ["black_powder"] = "Black Powder",
    ["flagellation"] = "Flagellation",
    -- Priest
    ["mind_blast"] = "Mind Blast",
    ["shadow_word_pain"] = "Shadow Word: Pain",
    ["vampiric_touch"] = "Vampiric Touch",
    ["mind_flay"] = "Mind Flay",
    ["devouring_plague"] = "Devouring Plague",
    ["power_word_shield"] = "Power Word: Shield",
    ["penance"] = "Penance",
    ["holy_fire"] = "Holy Fire",
    ["smite"] = "Smite",
    -- Death Knight
    ["death_strike"] = "Death Strike",
    ["heart_strike"] = "Heart Strike",
    ["death_coil"] = "Death Coil",
    ["scourge_strike"] = "Scourge Strike",
    ["festering_strike"] = "Festering Strike",
    ["obliterate"] = "Obliterate",
    ["howling_blast"] = "Howling Blast",
    ["remorseless_winter"] = "Remorseless Winter",
    -- Shaman
    ["lava_burst"] = "Lava Burst",
    ["flame_shock"] = "Flame Shock",
    ["lightning_bolt"] = "Lightning Bolt",
    ["chain_lightning"] = "Chain Lightning",
    ["stormstrike"] = "Stormstrike",
    ["lava_lash"] = "Lava Lash",
    ["earth_shock"] = "Earth Shock",
    ["frost_shock"] = "Frost Shock",
    ["primordial_wave"] = "Primordial Wave",
    -- Mage
    ["fireball"] = "Fireball",
    ["pyroblast"] = "Pyroblast",
    ["fire_blast"] = "Fire Blast",
    ["living_bomb"] = "Living Bomb",
    ["combustion"] = "Combustion",
    ["frostbolt"] = "Frostbolt",
    ["ice_lance"] = "Ice Lance",
    ["flurry"] = "Flurry",
    ["arcane_blast"] = "Arcane Blast",
    ["arcane_missiles"] = "Arcane Missiles",
    ["arcane_barrage"] = "Arcane Barrage",
    -- Warlock
    ["shadow_bolt"] = "Shadow Bolt",
    ["incinerate"] = "Incinerate",
    ["chaos_bolt"] = "Chaos Bolt",
    ["immolate"] = "Immolate",
    ["corruption"] = "Corruption",
    ["agony"] = "Agony",
    ["unstable_affliction"] = "Unstable Affliction",
    ["drain_life"] = "Drain Life",
    ["summon_demonic_tyrant"] = "Summon Demonic Tyrant",
    -- Monk
    ["rising_sun_kick"] = "Rising Sun Kick",
    ["fists_of_fury"] = "Fists of Fury",
    ["blackout_kick"] = "Blackout Kick",
    ["tiger_palm"] = "Tiger Palm",
    ["spinning_crane_kick"] = "Spinning Crane Kick",
    ["touch_of_death"] = "Touch of Death",
    ["whirling_dragon_punch"] = "Whirling Dragon Punch",
    -- Druid
    ["shred"] = "Shred",
    ["rake"] = "Rake",
    ["rip"] = "Rip",
    ["ferocious_bite"] = "Ferocious Bite",
    ["thrash"] = "Thrash",
    ["swipe"] = "Swipe",
    ["moonfire"] = "Moonfire",
    ["sunfire"] = "Sunfire",
    ["starsurge"] = "Starsurge",
    ["wrath"] = "Wrath",
    ["starfire"] = "Starfire",
    -- Demon Hunter
    ["demons_bite"] = "Demon's Bite",
    ["chaos_strike"] = "Chaos Strike",
    ["annihilation"] = "Annihilation",
    ["immolation_aura"] = "Immolation Aura",
    ["eye_beam"] = "Eye Beam",
    ["blade_dance"] = "Blade Dance",
    ["death_sweep"] = "Death Sweep",
    ["fel_rush"] = "Fel Rush",
    ["throw_glaive"] = "Throw Glaive",
    -- Evoker
    ["disintegrate"] = "Disintegrate",
    ["fire_breath"] = "Fire Breath",
    ["eternity_surge"] = "Eternity Surge",
    ["azure_strike"] = "Azure Strike",
    ["living_flame"] = "Living Flame",
    ["spiritbloom"] = "Spiritbloom",
    ["emerald_blossom"] = "Emerald Blossom",
}

local SIMC_BUFF_MAP = {
    -- Warrior
    shield_block = "Shield Block",
    avatar = "Avatar",
    ignore_pain = "Ignore Pain",
    phalanx = "Phalanx",
    shield_wall = "Shield Wall",
    ravager = "Ravager",
    revenge = "Revenge Proc",
    demoralizing_shout_debuff = "Demoralizing Shout",
    devastating_focus = "Devastating Focus",
    violent_outburst = "Violent Outburst",
    seeing_red = "Seeing Red",
    -- Paladin
    shield_of_the_righteous = "Shield of the Righteous",
    avengers_shield = "Avenger's Shield",
    divine_shield = "Divine Shield",
    ardent_defender = "Ardent Defender",
    blessing_of_protection = "Blessing of Protection",
    blessing_of_freedom = "Blessing of Freedom",
    blessing_of_sacrifice = "Blessing of Sacrifice",
    divine_toll = "Divine Toll",
    ashen_hallow = "Ashen Hallow",
}

local function SimCName(name)
    return SIMC_SPELL_MAP[name] or SIMC_BUFF_MAP[name] or name:gsub("_", " "):gsub("(%l)(%w*)", function(a,b) return a:upper()..b end)
end

local ROTATION_EXCLUDE

function Addon.ParseSimC(text)
    if not text or text == "" then return nil end

    local dps = tonumber(text:match("DPS=([%d%.]+)")) or 0
    local maxTime = tonumber(text:match("max_time=(%d+)")) or 120
    local duration = maxTime
    local totalDamage = dps * duration

    local damageData = {}
    local castCounts = {}
    local totalCasts = 0
    local simcBuffs = {}
    local spellWeights = {}
    local buffBenefit = {}
    local rageGains = {}
    local rawApl = ""
    local activeBranch = ""
    local inActions = false
    local inBuffs = false
    local inAPL = false
    local currentBranch = ""
    local inDefaultBranch = false

    for line in text:gmatch("[^\r\n]+") do
        local isSectionHeader = false
        if line:find("^%s*Actions:") then
            inActions = true; inBuffs = false; inAPL = false; isSectionHeader = true
            if debugMode then print("|cff33ff33[DummyAnalyzer Debug]|r Entered Actions section") end
        elseif line:find("^%s*Priorities %(actions%.default%)") then
            inActions = false; inBuffs = false; inAPL = true
            currentBranch = "default"
            inDefaultBranch = true; isSectionHeader = true
            if debugMode then print("|cff33ff33[DummyAnalyzer Debug]|r Entered Priorities (default)") end
        elseif line:find("^%s*Priorities %(actions%.") then
            inActions = false; inBuffs = false; inAPL = true
            local branch = line:match("actions%.([%w_]+)%)")
            currentBranch = branch or ""
            inDefaultBranch = false; isSectionHeader = true
            if debugMode then print("|cff33ff33[DummyAnalyzer Debug]|r Entered Priorities (actions." .. (branch or "?") .. ")") end
        elseif line:find("^%s*Dynamic Buffs:") then
            inActions = false; inBuffs = true; inAPL = false; isSectionHeader = true
            if debugMode then print("|cff33ff33[DummyAnalyzer Debug]|r Entered Buffs section") end
        elseif line:find("^%s*Gains:") then
            inActions = false; inBuffs = false; inAPL = false; isSectionHeader = true
            if debugMode then print("|cff33ff33[DummyAnalyzer Debug]|r Entered Gains section") end
        elseif line:find("^%s*Up%-Times:") or line:find("^%s*Queue:") or line:find("^%s*Player:") or line:find("^%s*Snapshot Stats:") then
            inAPL = false; isSectionHeader = true
        end

        if not isSectionHeader then

        -- Parse Actions
        if inActions then
            local rawName = line:match("^%s+(.-)%s*Count=")
            if rawName then
                local count = tonumber(line:match("Count=%s*([%d%.]+)"))
                local pct = tonumber(line:match("|%s*([%d%.]+)%%"))
                if debugMode then
                    local linePreview = #line > 120 and line:sub(1, 120) .. "..." or line
                    print(string.format("|cff33ff33[DummyAnalyzer Debug]|r Action: %s | count=%s pct=%s", tostring(rawName), tostring(count), tostring(pct)))
                end
                if count and count > 0 then
                    local display = SimCName(rawName)
                    count = math.floor(count + 0.5)
                    totalCasts = totalCasts + count
                    if castCounts[display] then castCounts[display] = castCounts[display] + count
                    else castCounts[display] = count end
                    DebugLog("debug", "ParseSimC", string.format("include count=%d: %s→%s", count, rawName, display))
                    if pct and pct > 0 then
                        local total = totalDamage * (pct / 100)
                        if damageData[display] then damageData[display] = {total = damageData[display].total + total}
                        else damageData[display] = {total = total} end
                    end
                else
                    DebugLog("debug", "ParseSimC", string.format("skip count=%s: %s→%s", tostring(count), rawName, SimCName(rawName)))
                end
                -- pDPS per spell
                local pdps = tonumber(line:match("pDPS=%s*([%d%.]+)"))
                if pdps and pdps > 0 then
                    local display = SimCName(rawName)
                    spellWeights[display] = pdps
                end
            end
        end

        -- Parse Priorities (APL)
        if inAPL then
            -- Strip action branch prefix: actions.branch+=/spell → spell
            local apline = line:match("^%s*actions%.[%w_]+%+?=?/?(.*)") or line
            -- Parse spell name from APL line (first word before ,if= or similar)
            local spellName = apline:match("^%s*([%w_]+)")
            if spellName and spellName ~= "run_action_list" and spellName ~= "" then
                if inDefaultBranch then
                    -- Default branch: could be run_action_list dispatcher or actual spell
                    local branchName = line:match("run_action_list,name=([%w_]+)")
                    if branchName then
                        activeBranch = branchName
                    else
                        -- No dispatcher, parse as direct spell in default branch
                        local display = SimCName(spellName)
                        if display and not ROTATION_EXCLUDE[display] then
                            rawApl = rawApl .. apline .. "\n"
                        end
                    end
                elseif currentBranch ~= "" and currentBranch ~= "default" then
                    -- Named branch: check if this is the active one
                    if currentBranch == activeBranch or activeBranch == "" then
                        local display = SimCName(spellName)
                        if display and not ROTATION_EXCLUDE[display] then
                            rawApl = rawApl .. apline .. "\n"
                        end
                    end
                end
            end
        end

        -- Parse Dynamic Buffs (uptime + benefit)
        if inBuffs then
            local rawName = line:match("^%s*(%S+)")
            local uptime = tonumber(line:match("uptime=%s*([%d%.]+)"))
            if rawName and uptime then
                local display = SimCName(rawName)
                simcBuffs[display] = {name = display, uptime = (uptime / 100) * duration}
                local benefit = tonumber(line:match("benefit=%s*([%d%.]+)"))
                if benefit then buffBenefit[display] = benefit end
                if debugMode then print(string.format("|cff33ff33[DummyAnalyzer Debug]|r Buff: %s uptime=%s benefit=%s", tostring(display), tostring(uptime), tostring(benefit or 0))) end
            end
        end

        end -- if not isSectionHeader

        -- Parse Gains
        local gainAmount, gainSource = line:match("%s*([%d%.]+)%s*:%s*(.+)%s*%((.+)%)")
        if gainAmount and gainSource then
            local gainName = SimCName(gainSource:match("^%s*(.-)%s*$") or gainSource)
            local amt = tonumber(gainAmount)
            if gainName and amt then
                rageGains[gainName] = (rageGains[gainName] or 0) + amt
            end
        end
    end

    -- Build APL order from rawApl
    local aplOrder = {}
    if rawApl and rawApl ~= "" then
        for line in rawApl:gmatch("[^\r\n]+") do
            -- Split on '/' to handle multi-action lines (SimC format: ravager/demoralizing_shout)
            for action in line:gmatch("([^/]+)") do
                local spellName = action:match("^%s*([%w_]+)")
                if spellName then
                    local display = SimCName(spellName)
                    if display and not ROTATION_EXCLUDE[display] and castCounts[display] then
                        local already = false
                        for _, s in ipairs(aplOrder) do if s == display then already = true; break end end
                        if not already then table.insert(aplOrder, display) end
                    end
                end
            end
        end
    end

    -- Parse player stats (haste, crit, etc.)
    local haste = tonumber(text:match("haste=([%d%.]+)")) or 0
    local crit = tonumber(text:match("crit=([%d%.]+)")) or 0
    local spec = text:match("spec=([%w_]+)") or ""
    local heroTree = text:match("hero_tree=([%w_]+)") or ""

    if dps == 0 then return nil end

    return {
        dps = dps,
        duration = duration,
        totalDamage = totalDamage,
        damageData = damageData,
        castCounts = castCounts,
        totalCasts = totalCasts,
        buffs = simcBuffs,
        -- Extended SimC data
        spellWeights = spellWeights,
        aplOrder = aplOrder,
        rawApl = rawApl,
        activeBranch = activeBranch,
        buffBenefit = buffBenefit,
        rageGains = rageGains,
        haste = haste,
        crit = crit,
        spec = spec,
        heroTree = heroTree,
    }
end

local function ShowSimCImportDialog()
    if simcDialog then simcDialog:Hide() simcDialog = nil end

    simcDialog = CreateStyledFrame("Frame", "DummyAnalyzerSimCImport", UIParent); trackDialog(simcDialog)
    simcDialog:SetSize(600, 480)
    simcDialog:SetPoint("CENTER")
    simcDialog:SetFrameStrata("DIALOG")
    simcDialog:SetMovable(true)
    simcDialog:SetClampedToScreen(true)
    simcDialog:EnableMouse(true)
    simcDialog:RegisterForDrag("LeftButton")
    simcDialog:SetScript("OnDragStart", simcDialog.StartMoving)
    simcDialog:SetScript("OnDragStop", simcDialog.StopMovingOrSizing)
    ApplyBackdrop(simcDialog, false)

    local titleBar = CreateStyledFrame("Frame", nil, simcDialog)
    titleBar:SetPoint("TOPLEFT", simcDialog, "TOPLEFT")
    titleBar:SetPoint("TOPRIGHT", simcDialog, "TOPRIGHT")
    titleBar:SetHeight(36)
    titleBar:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
    titleBar:SetBackdropColor(C.title[1], C.title[2], C.title[3], C.title[4])
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() simcDialog:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() simcDialog:StopMovingOrSizing() end)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    SafeSetFont(titleText, BOLD_FONT, 15)
    titleText:SetText("Import SimC Output")
    titleText:SetPoint("CENTER")
    titleText:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])

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
    closeBtn:SetScript("OnClick", function() simcDialog:Hide() end)

    local instrText = simcDialog:CreateFontString(nil, "OVERLAY")
    SafeSetFont(instrText, MAIN_FONT, 11)
    instrText:SetText("Paste SimC output below (Ctrl+V) then click Import:")
    instrText:SetPoint("TOPLEFT", simcDialog, "TOPLEFT", 20, -50)
    instrText:SetTextColor(C.text[1], C.text[2], C.text[3], C.text[4])

    local statusText = simcDialog:CreateFontString(nil, "OVERLAY")
    SafeSetFont(statusText, MAIN_FONT, 11)
    statusText:SetText("")
    statusText:SetPoint("TOPLEFT", simcDialog, "TOPLEFT", 20, -65)
    statusText:SetTextColor(0.5, 1.0, 0.5, 1)

    local scrollFrame = CreateFrame("ScrollFrame", nil, simcDialog, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", simcDialog, "TOPLEFT", 22, -87)
    scrollFrame:SetPoint("BOTTOMRIGHT", simcDialog, "BOTTOMRIGHT", -22, 50)
    scrollFrame:SetClipsChildren(true)
    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetTextColor(1, 1, 1, 1)
    editBox:SetWidth(510)
    editBox:SetHeight(400)
    editBox:SetAutoFocus(true)
    editBox:EnableMouse(true)
    scrollFrame:SetScript("OnMouseDown", function() editBox:SetFocus() end)
    editBox:SetScript("OnEscapePressed", function() editBox:ClearFocus() end)
    editBox:SetScript("OnEditFocusGained", function()
        statusText:SetTextColor(0.5, 1.0, 0.5, 1)
        statusText:SetText("Paste SimC output (Ctrl+V) then click Import")
    end)
    editBox:SetScript("OnEditFocusLost", function()
        if editBox and #(editBox:GetText() or "") == 0 then
            statusText:SetText("")
        end
    end)
    editBox:SetScript("OnTextChanged", function()
        local text = editBox:GetText() or ""
        local len = #text
        if len > 0 then
            local lines = select(2, text:gsub("\n", "\n")) + 1
            statusText:SetText(string.format("Pasted: %d chars (%d lines). Click Import.", len, lines))
        end
    end)
    scrollFrame:SetScrollChild(editBox)
    editBox:SetHeight(300)

    local function doImport()
        local text = editBox:GetText() or ""
        if debugMode then
            print(string.format("|cff33ff33[DummyAnalyzer Debug]|r Import text: %d chars total", #text))
            if #text > 0 then
                print("|cff33ff33[DummyAnalyzer Debug]|r First 200 chars: " .. text:sub(1, 200))
                print("|cff33ff33[DummyAnalyzer Debug]|r Last 200 chars: " .. text:sub(-200))
            end
        end
        if not text or text == "" then
            print("|cff33ff33[DummyAnalyzer]|r Paste SimC output first.")
            return
        end
        local parsed = Addon.ParseSimC(text)
        if not parsed then
            print("|cff33ff33[DummyAnalyzer]|r Could not parse SimC output. Make sure you pasted the full text from the Actions section onwards.")
            return
        end
        -- Filter SimC data to only include spells DummyAnalyzer can track
        -- (removes procs, passives, auto-attacks that don't show in the combat log as casts)
        parsed.castCounts, parsed.damageData = FilterSimCData(parsed.castCounts, parsed.damageData)
        local db = GetCharDB()
        local label = "SimC: " .. string.format("%.0fK DPS", parsed.dps / 1000)
        -- Store extended SimC data for optimizer access
        db.simcData = {
            totalDPS = parsed.dps,
            activeBranch = parsed.activeBranch,
aplOrder = parsed.aplOrder,
              rawApl = parsed.rawApl,
              spellWeights = parsed.spellWeights,
              castCounts = parsed.castCounts,
              buffBenefit = parsed.buffBenefit,
            rageGains = parsed.rageGains,
            haste = parsed.haste,
            crit = parsed.crit,
            spec = parsed.spec,
            heroTree = parsed.heroTree,
        }
        local existingId = db.simcLogId or 0
        if existingId > 0 then
            for i, log in ipairs(db.logs) do
                if log.id == existingId then
                    log.label = label
                    log.dps = parsed.dps
                    log.duration = parsed.duration
                    log.totalDamage = parsed.totalDamage
                    log.damageData = parsed.damageData
                    log.castCounts = parsed.castCounts
                    log.totalCasts = parsed.totalCasts
                    log.buffUptime = parsed.buffs
                    log.date = "SimC Simulation"
                    log.isSimC = true
                    local upCount = 0
                    local upSample = ""
                    if parsed.damageData then
                        for _ in pairs(parsed.damageData) do upCount = upCount + 1 end
                        for name, d in pairs(parsed.damageData) do
                            upSample = upSample .. string.format(" %s=%.0f", name, d.total or 0)
                            if #upSample > 100 then break end
                        end
                    end
                    simcDialog:Hide()
                    print(string.format("|cff33ff33[DummyAnalyzer]|r Updated SimC reference: %s (%d dmg entries%s)", label, upCount, upCount > 0 and (":" .. upSample) or ""))
                    return
                end
            end
        end
        local newId = db.nextId
        db.nextId = newId + 1
        db.simcLogId = newId
        table.insert(db.logs, {
            id = newId,
            label = label,
            dps = parsed.dps,
            duration = parsed.duration,
            totalDamage = parsed.totalDamage,
            damageData = parsed.damageData,
            castCounts = parsed.castCounts,
            totalCasts = parsed.totalCasts,
            buffUptime = parsed.buffs,
            date = "SimC Simulation",
            isSimC = true,
        })
        local dmgCount = 0
        local dmgSample = ""
        if parsed.damageData then
            for _ in pairs(parsed.damageData) do dmgCount = dmgCount + 1 end
            for name, d in pairs(parsed.damageData) do
                dmgSample = dmgSample .. string.format(" %s=%.0f", name, d.total or 0)
                if #dmgSample > 100 then break end
            end
        end
        simcDialog:Hide()
        print(string.format("|cff33ff33[DummyAnalyzer]|r Imported SimC reference: %s (%d dmg entries%s)", label, dmgCount, dmgCount > 0 and (":" .. dmgSample) or ""))
    end

    local bottomBar = CreateStyledFrame("Frame", nil, simcDialog)
    bottomBar:SetPoint("BOTTOMLEFT", simcDialog, "BOTTOMLEFT", 0, 0)
    bottomBar:SetPoint("BOTTOMRIGHT", simcDialog, "BOTTOMRIGHT", 0, 0)
    bottomBar:SetHeight(45)
    bottomBar:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
    bottomBar:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
    bottomBar:SetFrameLevel(simcDialog:GetFrameLevel() + 5)

    local importBtn = CreateStyledButton(bottomBar, "Import", 100, 30, doImport, "primary")
    importBtn:SetPoint("RIGHT", bottomBar, "CENTER", -55, 0)
    importBtn:SetFrameLevel(bottomBar:GetFrameLevel() + 2)

    local cancelBtn = CreateStyledButton(bottomBar, "Cancel", 100, 30, function() simcDialog:Hide() end)
    cancelBtn:SetPoint("LEFT", bottomBar, "CENTER", 55, 0)
    cancelBtn:SetFrameLevel(bottomBar:GetFrameLevel() + 2)

    RegisterAddonWindow(simcDialog)
    simcDialog:Show()
    C_Timer.After(0, function() if editBox and editBox.SetFocus then editBox:SetFocus() end end)
end
-- ============================================
-- MARKDOWN / AI EXPORT
-- ============================================
local function GenerateMarkdownReport(log, elapsed, totalDmg, casts, cData, dData, bUptime, bGaps, notesText, dUptime, rStats)
    local lines = {}
    lines[#lines + 1] = "# Dummy Analyzer Report"
    lines[#lines + 1] = ""

    local dur = elapsed or 0
    local dmg = totalDmg or 0
    local dps = dur > 0 and (dmg / dur) or 0
    local totalCasts = casts or 0

    lines[#lines + 1] = "**Duration:** " .. string.format("%.1fs (%.2f min)", dur, dur / 60)
    lines[#lines + 1] = "**DPS:** " .. ShortNum(dps)
    lines[#lines + 1] = "**Total Damage:** " .. ShortNum(dmg)
    lines[#lines + 1] = "**Total Casts:** " .. totalCasts .. (dur > 0 and string.format(" (%.1f CPM)", (totalCasts / dur) * 60) or "")
    lines[#lines + 1] = ""

    if notesText and notesText ~= "" then
        lines[#lines + 1] = "## Notes"
        lines[#lines + 1] = notesText
        lines[#lines + 1] = ""
    end

    if dData and next(dData) then
        lines[#lines + 1] = "## Damage Breakdown"
        lines[#lines + 1] = "| Spell | Total | % | Casts | DPC |"
        lines[#lines + 1] = "|-------|-------|---|-------|-----|"
        local sorted = {}
        for name, d in pairs(dData) do
            local total = NumberOrZero(d.total)
            local pct = dmg > 0 and (total / dmg) * 100 or 0
            local spellCasts = (cData and cData[name]) or 0
            local dpc = spellCasts > 0 and (total / spellCasts) or 0
            table.insert(sorted, {name = name, total = total, pct = pct, casts = spellCasts, dpc = dpc})
        end
        table.sort(sorted, function(a, b) return a.total > b.total end)
        for _, entry in ipairs(sorted) do
            lines[#lines + 1] = string.format("| %s | %s | %.1f%% | %d | %s |", entry.name, ShortNum(entry.total), entry.pct, entry.casts, ShortNum(entry.dpc))
        end
        lines[#lines + 1] = ""
    end

    if cData and next(cData) then
        lines[#lines + 1] = "## Cast Breakdown"
        lines[#lines + 1] = "| Spell | Casts | % |"
        lines[#lines + 1] = "|-------|-------|---|"
        local sorted = {}
        for name, count in pairs(cData) do
            table.insert(sorted, {name = name, count = count, pct = totalCasts > 0 and (count / totalCasts) * 100 or 0})
        end
        table.sort(sorted, function(a, b) return a.count > b.count end)
        for _, entry in ipairs(sorted) do
            lines[#lines + 1] = string.format("| %s | %d | %.1f%% |", entry.name, entry.count, entry.pct)
        end
        lines[#lines + 1] = ""
    end

    if bUptime and next(bUptime) and dur > 0 then
        lines[#lines + 1] = "## Buff Uptime"
        lines[#lines + 1] = "| Buff | Uptime | % |"
        lines[#lines + 1] = "|------|--------|---|"
        local sorted = {}
        for _, buff in pairs(bUptime) do
            if buff.uptime and buff.uptime > 0.1 then
                local uptime = math.min(buff.uptime, dur)
                table.insert(sorted, {name = buff.name or "?", uptime = uptime, pct = (uptime / dur) * 100})
            end
        end
        table.sort(sorted, function(a, b) return a.uptime > b.uptime end)
        for _, entry in ipairs(sorted) do
            lines[#lines + 1] = string.format("| %s | %.1fs | %.1f%% |", entry.name, entry.uptime, entry.pct)
        end
        lines[#lines + 1] = ""
    end

    if dUptime and next(dUptime) and dur > 0 then
        lines[#lines + 1] = "## Target Debuff Uptime"
        lines[#lines + 1] = "| Debuff | Uptime | % |"
        lines[#lines + 1] = "|--------|--------|---|"
        local sorted = {}
        for _, debuff in pairs(dUptime) do
            if debuff.uptime and debuff.uptime > 0.1 then
                local uptime = math.min(debuff.uptime, dur)
                table.insert(sorted, {name = debuff.name or "?", uptime = uptime, pct = (uptime / dur) * 100})
            end
        end
        table.sort(sorted, function(a, b) return a.uptime > b.uptime end)
        for _, entry in ipairs(sorted) do
            lines[#lines + 1] = string.format("| %s | %.1fs | %.1f%% |", entry.name, entry.uptime, entry.pct)
        end
        lines[#lines + 1] = ""
    end

    if rStats and next(rStats) then
        lines[#lines + 1] = "## Spell Power Costs"
        lines[#lines + 1] = "| Spell | Casts | Total Cost | Avg Cost |"
        lines[#lines + 1] = "|-------|-------|------------|----------|"
        local sorted = {}
        for name, c in pairs(rStats) do
            table.insert(sorted, {name = name, avg = c.totalCost / c.count, total = c.totalCost, count = c.count, ptype = c.powerType or ""})
        end
        table.sort(sorted, function(a, b) return a.total > b.total end)
        for _, entry in ipairs(sorted) do
            lines[#lines + 1] = string.format("| %s | %d | %d | %.0f |", entry.name, entry.count, entry.total, entry.avg)
        end
        lines[#lines + 1] = ""
    end

    if bGaps and next(bGaps) then
        lines[#lines + 1] = "## Buff Refresh Gaps"
        lines[#lines + 1] = "| Buff | Longest Gap | Avg Gap | Count |"
        lines[#lines + 1] = "|------|-------------|---------|-------|"
        local sorted = {}
        for key, data in pairs(bGaps) do
            local total = 0
            local maxGap = 0
            for _, g in ipairs(data.gaps) do
                total = total + g
                if g > maxGap then maxGap = g end
            end
            local avg = #data.gaps > 0 and (total / #data.gaps) or 0
            table.insert(sorted, {name = data.name, maxGap = maxGap, avgGap = avg, count = #data.gaps})
        end
        table.sort(sorted, function(a, b) return a.maxGap > b.maxGap end)
        for _, entry in ipairs(sorted) do
            lines[#lines + 1] = string.format("| %s | %.1fs | %.1fs | %d |", entry.name, entry.maxGap, entry.avgGap, entry.count)
        end
        lines[#lines + 1] = ""
    end

    return JoinLines(lines)
end

function Addon.GenerateLogReportText(log)
    if not log then return "No log data." end
    local lines = {}

    table.insert(lines, "=== DUMMY ANALYZER REPORT ===")
    table.insert(lines, "Date: " .. (log.date or "Unknown"))
    table.insert(lines, "")
    if log.duration and log.duration > 0 then
        table.insert(lines, string.format("Duration: %.1f sec (%.2f min)", log.duration, log.duration / 60))
    end
    if log.totalDamage and log.totalDamage > 0 then
        table.insert(lines, string.format("Total Dmg: %s", ShortNum(log.totalDamage)))
        table.insert(lines, string.format("DPS: %s", ShortNum(log.dps or (log.totalDamage / log.duration))))
    end
    if log.totalCasts and log.totalCasts > 0 and log.duration and log.duration > 0 then
        local cpm = (log.totalCasts / log.duration) * 60
        table.insert(lines, string.format("Total Casts: %d (%.1f CPM)", log.totalCasts, cpm))
    end
    table.insert(lines, "")

    if log.totalDamage and log.totalDamage > 0 and log.damageData and next(log.damageData) then
        table.insert(lines, "--- Damage Breakdown ---")
        local sorted = {}
        for name, d in pairs(log.damageData) do
            if not IsSecretValue(name) and not IsSecretValue(d) then
                table.insert(sorted, {name = name, d = d})
            end
        end
        table.sort(sorted, function(a, b) return NumberOrZero(a.d.total) > NumberOrZero(b.d.total) end)
        for _, entry in ipairs(sorted) do
            local d = entry.d
            local spellTotal = NumberOrZero(d.total)
            local pct = (spellTotal / log.totalDamage) * 100
            local displayName = #entry.name > 22 and entry.name:sub(1,19) .. "..." or entry.name
            table.insert(lines, string.format("%-22s %8s %6.1f%%", displayName, ShortNum(spellTotal), pct))
        end
        table.insert(lines, "")
    end

    if log.castCounts and next(log.castCounts) then
        table.insert(lines, "--- Cast Breakdown ---")
        local sorted = {}
        for name, count in pairs(log.castCounts) do
            if not IsSecretValue(name) then
                table.insert(sorted, {name = name, count = count})
            end
        end
        table.sort(sorted, function(a, b) return a.count > b.count end)
        for _, ability in ipairs(sorted) do
            local pct = (ability.count / log.totalCasts) * 100
            table.insert(lines, string.format("%s: %d (%.1f%%)", ability.name, ability.count, pct))
        end
        table.insert(lines, "")
    end

    if log.buffUptime and next(log.buffUptime) and log.duration and log.duration > 0 then
        table.insert(lines, "--- Buff Uptime ---")
        local sorted = {}
        for _, buff in pairs(log.buffUptime) do
            if buff and buff.uptime and buff.uptime > 0.1 and not IsSecretValue(buff) then
                table.insert(sorted, {name = buff.name or "?", uptime = math.min(buff.uptime, log.duration)})
            end
        end
        table.sort(sorted, function(a, b) return a.uptime > b.uptime end)
        for i, buff in ipairs(sorted) do
            if i > 15 then break end
            local pct = (buff.uptime / log.duration) * 100
            table.insert(lines, string.format("%s: %.1f sec (%.1f%%)", buff.name, buff.uptime, pct))
        end
        table.insert(lines, "")
    end

    if log.buffGaps and next(log.buffGaps) then
        table.insert(lines, "--- Buff Refresh Gaps ---")
        local sorted = {}
        for key, data in pairs(log.buffGaps) do
            local total = 0
            local maxGap = 0
            for _, g in ipairs(data.gaps) do
                total = total + g
                if g > maxGap then maxGap = g end
            end
            local avg = #data.gaps > 0 and (total / #data.gaps) or 0
            table.insert(sorted, {name = data.name, maxGap = maxGap, avgGap = avg, count = #data.gaps})
        end
        table.sort(sorted, function(a, b) return a.maxGap > b.maxGap end)
        for _, entry in ipairs(sorted) do
            table.insert(lines, string.format("%s: longest %.1fs, avg %.1fs (%d gaps)", entry.name, entry.maxGap, entry.avgGap, entry.count))
        end
        table.insert(lines, "")
    end

    if log.spellHistory and #log.spellHistory > 0 then
        table.insert(lines, "--- Cast Timeline ---")
        local maxTimeline = math.min(#log.spellHistory, 80)
        for i = 1, maxTimeline do
            local s = log.spellHistory[i]
            local costStr = ""
            if s.cost and s.cost.cost then
                costStr = string.format(" [%d %s]", s.cost.cost or 0, s.cost.powerType or "")
            end
            table.insert(lines, string.format("%4d. [%5.1fs]%s %s", i, s.time, costStr, s.name or "?"))
        end
        if #log.spellHistory > 80 then
            table.insert(lines, string.format("  ... (%d more casts not shown)", #log.spellHistory - 80))
        end
        table.insert(lines, "")
    end

    if log.spellPowerCosts and next(log.spellPowerCosts) then
        table.insert(lines, "--- Spell Power Costs ---")
        local sorted = {}
        for name, c in pairs(log.spellPowerCosts) do
            table.insert(sorted, {name = name, avg = c.totalCost / c.count, total = c.totalCost, count = c.count, ptype = c.powerType or ""})
        end
        table.sort(sorted, function(a, b) return a.total > b.total end)
        for _, entry in ipairs(sorted) do
            table.insert(lines, string.format("%s: %d casts, %d total, %.0f avg%s", entry.name, entry.count, entry.total, entry.avg, entry.ptype ~= "" and (" " .. entry.ptype) or ""))
        end
        table.insert(lines, "")
    end

    if log.notes and log.notes ~= "" then
        table.insert(lines, "--- Notes ---")
        table.insert(lines, log.notes)
        table.insert(lines, "")
    end

    return JoinLines(lines)
end

function Addon.CompareLogs(idA, idB)
    local logs = GetCharDB().logs
    local logA, logB
    for _, log in ipairs(logs) do
        if log.id == idA then logA = log end
        if log.id == idB then logB = log end
    end
    if not logA or not logB then return "Select two logs to compare." end

    -- Re-filter SimC data at compare time (handles retroactive cases
    -- where logs were saved before the proc/passive filter existed)
    local simcCastsA, simcDmgA = logA.castCounts, logA.damageData
    local simcCastsB, simcDmgB = logB.castCounts, logB.damageData
    if logA.isSimC then
        simcCastsA, simcDmgA = FilterSimCData(logA.castCounts or {}, logA.damageData)
    end
    if logB.isSimC then
        simcCastsB, simcDmgB = FilterSimCData(logB.castCounts or {}, logB.damageData)
    end

    local function s(n)
        return ShortNum(n or 0)
    end

    local lines = {}
    table.insert(lines, "=== COMPARISON ===")
    table.insert(lines, "")
    local aLabel = logA.label or ("Log #" .. (logA.id or "?"))
    local bLabel = logB.label or ("Log #" .. (logB.id or "?"))
    table.insert(lines, aLabel)
    table.insert(lines, bLabel)
    table.insert(lines, "")
    table.insert(lines, string.rep("-", 60))
    table.insert(lines, "")

    local durA = logA.duration or 0
    local durB = logB.duration or 0
    local dpsA = durA > 0 and ((logA.totalDamage or 0) / durA) or 0
    local dpsB = durB > 0 and ((logB.totalDamage or 0) / durB) or 0
    local castsA = logA.totalCasts or 0
    local castsB = logB.totalCasts or 0

    table.insert(lines, string.format("%-24s %-16s %-16s %-16s", "Metric", "A", "B", "Diff"))
    table.insert(lines, string.rep("-", 75))
    local function f(n) return n and s(n) or "0" end
    table.insert(lines, string.format("%-24s %-16s %-16s %-16s", "DPS", f(dpsA), f(dpsB), f(dpsB-dpsA)))
    table.insert(lines, string.format("%-24s %-16s %-16s %-16s", "Casts", castsA, castsB, string.format("%+d", castsB-castsA)))
    table.insert(lines, string.format("%-24s %-16s %-16s %-16s", "Duration", string.format("%.1fs", durA), string.format("%.1fs", durB), string.format("%+.1fs", durB-durA)))
    if logA.isSimC then
        local simcDPS = dpsA
        local pctOfSimC = simcDPS > 0 and (dpsB / simcDPS) * 100 or 0
        table.insert(lines, string.format("%-24s %-16s", "Your DPS vs SimC:", string.format("%.1f%%", pctOfSimC)))
    elseif logB.isSimC then
        local simcDPS = dpsB
        local pctOfSimC = simcDPS > 0 and (dpsA / simcDPS) * 100 or 0
        table.insert(lines, string.format("%-24s %-16s", "Your DPS vs SimC:", string.format("%.1f%%", pctOfSimC)))
    end
    table.insert(lines, "")

    -- Damage breakdown
    table.insert(lines, "--- Damage Breakdown ---")
    table.insert(lines, string.format("%-24s %-16s %-16s %-16s", "Spell", "A", "B", "Diff"))
    table.insert(lines, string.rep("-", 75))
    -- Damage breakdown: only show spells DummyAnalyzer detected as CASTS.
    -- This excludes passive procs (Phalanx, Lightning Strike, Devastator, etc.)
    -- that appear in damageData but aren't deliberate player actions.
    local allSpells = {}
    if simcCastsA then for name in pairs(simcCastsA) do if not IsSecretValue(name) then allSpells[name] = true end end end

    local sorted = {}
    for name in pairs(allSpells) do
        local dA = (simcDmgA and simcDmgA[name] and simcDmgA[name].total) or 0
        local dB = (simcDmgB and simcDmgB[name] and simcDmgB[name].total) or 0
        if not IsSecretValue(dA) and not IsSecretValue(dB) then
            table.insert(sorted, {name = name, totalA = dA, totalB = dB, total = math.max(dA, dB)})
        end
    end
    table.sort(sorted, function(a, b) return a.total > b.total end)

    for _, entry in ipairs(sorted) do
        local pctA = logA.totalDamage > 0 and (entry.totalA / logA.totalDamage) * 100 or 0
        local pctB = logB.totalDamage > 0 and (entry.totalB / logB.totalDamage) * 100 or 0
        local delta = entry.totalB - entry.totalA
        local deltaPct = pctB - pctA
        local deltaStr = (delta >= 0 and "+" or "") .. s(delta) .. " (" .. string.format("%+.1f", deltaPct) .. "%)"
        local displayName = #entry.name > 24 and entry.name:sub(1,21) .. "..." or entry.name
        local cellA = s(entry.totalA) .. " (" .. string.format("%.1f", pctA) .. "%)"
        local cellB = s(entry.totalB) .. " (" .. string.format("%.1f", pctB) .. "%)"
        table.insert(lines, string.format("%-24s %-16s %-16s %-16s", displayName, cellA, cellB, deltaStr))
    end
    table.insert(lines, "")

    -- Cast breakdown
    table.insert(lines, "--- Cast Breakdown ---")
    table.insert(lines, string.format("%-24s %-16s %-16s %-16s", "Spell", "A", "B", "Diff"))
    table.insert(lines, string.rep("-", 75))
    local allCasts = {}
    if simcCastsA then for name in pairs(simcCastsA) do if not IsSecretValue(name) then allCasts[name] = true end end end

    local sortedCasts = {}
    for name in pairs(allCasts) do
        local cA = (simcCastsA and simcCastsA[name]) or 0
        local cB = (simcCastsB and simcCastsB[name]) or 0
        table.insert(sortedCasts, {name = name, countA = cA, countB = cB, count = math.max(cA, cB)})
    end
    table.sort(sortedCasts, function(a, b) return a.count > b.count end)

    for _, entry in ipairs(sortedCasts) do
        local pctA = castsA > 0 and (entry.countA / castsA) * 100 or 0
        local pctB = castsB > 0 and (entry.countB / castsB) * 100 or 0
        local delta = entry.countB - entry.countA
        local deltaPct = pctB - pctA
        local deltaStr = (delta >= 0 and "+" or "") .. delta .. " (" .. string.format("%+.1f", deltaPct) .. "%)"
        local cellA = entry.countA .. " (" .. string.format("%.1f", pctA) .. "%)"
        local cellB = entry.countB .. " (" .. string.format("%.1f", pctB) .. "%)"
        table.insert(lines, string.format("%-24s %-16s %-16s %-16s", entry.name, cellA, cellB, deltaStr))
    end
    table.insert(lines, "")

    -- Buff uptime comparison
    table.insert(lines, "--- Buff Uptime ---")
    table.insert(lines, string.format("%-24s %-16s %-16s %-16s", "Buff", "A", "B", "Diff"))
    table.insert(lines, string.rep("-", 75))
    local allBuffs = {}
    if logA.buffUptime then
        for key, buff in pairs(logA.buffUptime) do
            if not IsSecretValue(key) and buff and buff.uptime and buff.uptime > 0.1 then
                allBuffs[key] = buff.name or key
            end
        end
    end
    if logB.buffUptime then
        for key, buff in pairs(logB.buffUptime) do
            if not IsSecretValue(key) and buff and buff.uptime and buff.uptime > 0.1 then
                allBuffs[key] = buff.name or key
            end
        end
    end

    local function lookupBuffUptime(log, key, name)
        if not log or not log.buffUptime then return 0 end
        local b = log.buffUptime[key]
        if b and b.uptime then return b.uptime end
        for _, buff in pairs(log.buffUptime) do
            if buff.name == name and buff.uptime then return buff.uptime end
        end
        return 0
    end

    local nameKeys = {}
    for key, name in pairs(allBuffs) do
        if nameKeys[name] then
            allBuffs[nameKeys[name]] = nil
        end
        nameKeys[name] = key
    end

    local sortedBuffs = {}
    for key, name in pairs(allBuffs) do
        local uA = lookupBuffUptime(logA, key, name)
        local uB = lookupBuffUptime(logB, key, name)
        if not IsSecretValue(uA) and not IsSecretValue(uB) then
            uA = math.min(uA, durA)
            uB = math.min(uB, durB)
            table.insert(sortedBuffs, {name = name or key, uptimeA = uA, uptimeB = uB})
        end
    end
    table.sort(sortedBuffs, function(a, b) return a.uptimeB > b.uptimeB end)

    for _, entry in ipairs(sortedBuffs) do
        local pctA = durA > 0 and (entry.uptimeA / durA) * 100 or 0
        local pctB = durB > 0 and (entry.uptimeB / durB) * 100 or 0
        local delta = entry.uptimeB - entry.uptimeA
        local deltaPct = pctB - pctA
        local deltaStr = string.format("%+.1fs (%+.1f%%)", delta, deltaPct)
        local cellA = string.format("%.1fs (%.1f%%)", entry.uptimeA, pctA)
        local cellB = string.format("%.1fs (%.1f%%)", entry.uptimeB, pctB)
        table.insert(lines, string.format("%-24s %-16s %-16s %-16s", entry.name, cellA, cellB, deltaStr))
    end

    -- Buff gap comparison
    local allGaps = {}
    if logA.buffGaps then
        for key, data in pairs(logA.buffGaps) do
            if not IsSecretValue(key) and data.gaps then
                allGaps[key] = data.name or key
            end
        end
    end
    if logB.buffGaps then
        for key, data in pairs(logB.buffGaps) do
            if not IsSecretValue(key) and data.gaps then
                allGaps[key] = data.name or key
            end
        end
    end
    if next(allGaps) then
        table.insert(lines, "--- Buff Gap Comparison ---")
        table.insert(lines, string.format("%-24s %-16s %-16s %-16s", "Buff", "A", "B", "Diff"))
        table.insert(lines, string.rep("-", 75))
        local function getGapData(log, key)
            if not log or not log.buffGaps or not log.buffGaps[key] then return 0, 0, 0 end
            local data = log.buffGaps[key]
            local maxG = 0
            local total = 0
            for _, g in ipairs(data.gaps) do
                total = total + g
                if g > maxG then maxG = g end
            end
            return maxG, #data.gaps > 0 and (total / #data.gaps) or 0, #data.gaps
        end
        local sortedGaps = {}
        for key, name in pairs(allGaps) do
            local maxA, avgA, cntA = getGapData(logA, key)
            local maxB, avgB, cntB = getGapData(logB, key)
            table.insert(sortedGaps, {name = name or key, maxA = maxA, maxB = maxB, avgA = avgA, avgB = avgB, cntA = cntA, cntB = cntB})
        end
        table.sort(sortedGaps, function(a, b) return a.maxB > b.maxB end)
        for _, entry in ipairs(sortedGaps) do
            local cellA = string.format("%.1fs (%.1f) x%d", entry.maxA, entry.avgA, entry.cntA)
            local cellB = string.format("%.1fs (%.1f) x%d", entry.maxB, entry.avgB, entry.cntB)
            local deltaStr = string.format("%+.1fs max", entry.maxB - entry.maxA)
            table.insert(lines, string.format("%-24s %-16s %-16s %-16s", entry.name, cellA, cellB, deltaStr))
        end
        table.insert(lines, "")
    end

    -- Notes comparison
    local notesA = logA.notes and logA.notes ~= "" and logA.notes or nil
    local notesB = logB.notes and logB.notes ~= "" and logB.notes or nil
    if notesA or notesB then
        table.insert(lines, "--- Notes ---")
        table.insert(lines, string.format("%-24s %s", "A:", notesA or "(none)"))
        table.insert(lines, string.format("%-24s %s", "B:", notesB or "(none)"))
        table.insert(lines, "")
    end

    return JoinLines(lines)
end

-- ============================================
-- REPORT GENERATION (original)
-- ============================================
local function GenerateReportText()
    local elapsed = (testActive and (GetTime() - startTime)) or (testEndTime and (testEndTime - startTime)) or 0
    local lines = {}
    local totalCasts = #spellHistory
    local castCounts = {}
    for _, spell in ipairs(spellHistory) do
        castCounts[spell.name] = (castCounts[spell.name] or 0) + 1
    end

    table.insert(lines, "=== DUMMY ANALYZER REPORT ===")
    table.insert(lines, "")
    if elapsed > 0 then
        table.insert(lines, string.format("Duration: %.1f sec (%.2f min)", elapsed, elapsed / 60))
    end

    if totalDamage > 0 then
        local dps = totalDamage / elapsed
        table.insert(lines, string.format("Total Dmg: %s", ShortNum(totalDamage)))
        table.insert(lines, string.format("DPS: %s", ShortNum(dps)))
    else
        table.insert(lines, "Total Dmg: 0")
    end

    if totalCasts > 0 and elapsed > 0 then
        local cpm = (totalCasts / elapsed) * 60
        table.insert(lines, string.format("Total Casts: %d (%.1f CPM)", totalCasts, cpm))
    end
    table.insert(lines, "")

    if totalDamage > 0 and next(damageData) then
        table.insert(lines, "--- Damage Breakdown ---")
        local sorted = {}
        for name, d in pairs(damageData) do
            table.insert(sorted, {name = name, d = d})
        end
        table.sort(sorted, function(a, b) return NumberOrZero(a.d.total) > NumberOrZero(b.d.total) end)

        for _, entry in ipairs(sorted) do
            local d = entry.d
            local spellTotal = NumberOrZero(d.total)
            local pct = totalDamage > 0 and (spellTotal / totalDamage) * 100 or 0
            local displayName = #entry.name > 22 and entry.name:sub(1,19).."..." or entry.name
            local hits = NumberOrZero(d.hits)
            local highest = NumberOrZero(d.highest)
            local overkill = NumberOrZero(d.overkill)
            local suffix = ""
            if hits > 0 and highest > 0 and overkill > 0 then
                suffix = string.format("  (%d hits, max %s, %s over)", hits, ShortNum(highest), ShortNum(overkill))
            elseif hits > 0 and highest > 0 then
                suffix = string.format("  (%d hits, max %s)", hits, ShortNum(highest))
            elseif hits > 0 then
                suffix = string.format("  (%d hits)", hits)
            end
            table.insert(lines, string.format("%-22s %8s %6.1f%%%s", displayName, ShortNum(spellTotal), pct, suffix))
        end
        table.insert(lines, "")
    end

    if totalCasts > 0 then
        table.insert(lines, "--- Cast Breakdown ---")
        local sorted = {}
        for name, count in pairs(castCounts) do
            table.insert(sorted, {name = name, count = count})
        end
        table.sort(sorted, function(a, b) return a.count > b.count end)
        for _, ability in ipairs(sorted) do
            local pct = (ability.count / totalCasts) * 100
            table.insert(lines, string.format("%s: %d (%.1f%%)", ability.name, ability.count, pct))
        end
        table.insert(lines, "")
    end

    if totalDamage > 0 and totalCasts > 0 and next(damageData) then
        table.insert(lines, "--- Damage Per Cast ---")
        local sorted = {}
        for name, d in pairs(damageData) do
            local casts = castCounts[name] or 0
            local spellTotal = NumberOrZero(d.total)
            if casts > 0 and spellTotal > 0 then
                table.insert(sorted, {name = name, casts = casts, total = spellTotal, perCast = spellTotal / casts})
            end
        end
        table.sort(sorted, function(a, b) return a.total > b.total end)
        if #sorted == 0 then
            table.insert(lines, "No direct cast/damage name matches.")
        else
            for i, entry in ipairs(sorted) do
                if i > 12 then break end
                table.insert(lines, string.format("%s: %s over %d casts (%s/cast)", entry.name, ShortNum(entry.total), entry.casts, ShortNum(entry.perCast)))
            end
        end
        table.insert(lines, "")
    end

    if totalCasts > 0 then
        table.insert(lines, "--- Opener ---")
        local opener = {}
        for i, spell in ipairs(spellHistory) do
            if i > 8 and spell.time > 10 then break end
            if i <= 8 or spell.time <= 10 then
                local sName = spell.name
                if sName and not pcall(string.byte, sName, 1) then sName = "?" end
                table.insert(opener, string.format("[%.1fs] %s", spell.time, sName))
            end
        end
        for _, line in ipairs(opener) do
            table.insert(lines, line)
        end
        table.insert(lines, "")
    end

    if #spellHistory > 1 then
        local delays = {}
        local gaps = {}
        for i = 2, #spellHistory do
            local d = spellHistory[i].time - spellHistory[i - 1].time
            table.insert(delays, d)
            if d > 1.5 then
                table.insert(gaps, {gap = d, a = spellHistory[i - 1].name, b = spellHistory[i].name, at = spellHistory[i - 1].time})
            end
        end
        local sum = 0
        for _, d in ipairs(delays) do sum = sum + d end
        local avg = sum / #delays
        local maxG = 0
        local idleTotal = 0
        for _, g in ipairs(gaps) do
            if g.gap > maxG then maxG = g.gap end
            idleTotal = idleTotal + g.gap - 1.5
        end
        table.insert(lines, "--- Cast Timing ---")
        table.insert(lines, string.format("Avg interval: %.2fs | Longest gap: %.1fs | Idle time: %.1fs", avg, maxG, idleTotal))
        if #gaps > 0 then
            table.sort(gaps, function(a, b) return a.gap > b.gap end)
            for i = 1, math.min(5, #gaps) do
                table.insert(lines, string.format("  [%.1fs] %s -> %s (+%.2fs)", gaps[i].at, gaps[i].a, gaps[i].b, gaps[i].gap))
            end
        end
        table.insert(lines, "")
    end

    -- Buff cast context
    local buffCastData = {}
    for _, entry in ipairs(spellHistory) do
        local eb = entry.buffs
        if eb and next(eb) then
            for key, bName in pairs(eb) do
                if not buffCastData[key] then
                    buffCastData[key] = {name = bName, total = 0, spells = {}}
                end
                buffCastData[key].total = buffCastData[key].total + 1
                buffCastData[key].spells[entry.name] = (buffCastData[key].spells[entry.name] or 0) + 1
            end
        end
    end
    if next(buffCastData) then
        table.insert(lines, "--- Cast Buff Context ---")
        for key, data in pairs(buffCastData) do
            if data.total >= 3 then
                local spellSummary = {}
                for spell, count in pairs(data.spells) do
                    table.insert(spellSummary, string.format("%s x%d", spell, count))
                end
                table.sort(spellSummary)
                local summary = table.concat(spellSummary, ", ")
                if #summary > 80 then summary = summary:sub(1, 77) .. "..." end
                table.insert(lines, string.format("  %s: %d casts - %s", data.name, data.total, summary))
            end
        end
        table.insert(lines, "")
    end

    if totalCasts > 1 then
        local gaps = {}
        for i = 2, #spellHistory do
            local gap = spellHistory[i].time - spellHistory[i - 1].time
            if gap >= 1.5 then
                table.insert(gaps, {
                    gap = gap,
                    before = spellHistory[i - 1].name,
                    after = spellHistory[i].name,
                    time = spellHistory[i - 1].time,
                })
            end
        end
        if #gaps > 0 then
            table.sort(gaps, function(a, b) return a.gap > b.gap end)
            table.insert(lines, "--- Idle Gaps ---")
            for i, gap in ipairs(gaps) do
                if i > 8 then break end
                table.insert(lines, string.format("%.1fs gap after %.1fs: %s -> %s", gap.gap, gap.time, gap.before, gap.after))
            end
            table.insert(lines, "")
        end
    end

    -- Cast timeline with resource level
    if totalCasts > 0 then
        table.insert(lines, "--- Cast Timeline ---")
        local maxShow = math.min(totalCasts, 100)
        for i = 1, maxShow do
            local s = spellHistory[i]
            local sName = s.name
            if sName and not pcall(string.byte, sName, 1) then sName = "?" end
            table.insert(lines, string.format("%4d. [%5.1fs] %s", i, s.time, sName))
        end
        if totalCasts > 100 then
            table.insert(lines, string.format("  (... %d more)", totalCasts - 100))
        end
        table.insert(lines, "")
    end

    if next(buffUptime) and elapsed > 0 then
        table.insert(lines, "--- Buff Uptime ---")
        local sorted = {}
        for _, buff in pairs(buffUptime) do
            if buff.uptime > 0.1 then
                table.insert(sorted, {name = buff.name, uptime = math.min(buff.uptime, elapsed)})
            end
        end
        table.sort(sorted, function(a, b) return a.uptime > b.uptime end)
        for i, buff in ipairs(sorted) do
            if i > 15 then break end
            local pct = (buff.uptime / elapsed) * 100
            table.insert(lines, string.format("%s: %.1f sec (%.1f%%)", buff.name, buff.uptime, pct))
        end
        table.insert(lines, "")
    end

    if next(buffGaps) then
        table.insert(lines, "--- Buff Refresh Gaps ---")
        local sorted = {}
        for key, data in pairs(buffGaps) do
            local total = 0
            local maxGap = 0
            for _, g in ipairs(data.gaps) do
                total = total + g
                if g > maxGap then maxGap = g end
            end
            local avg = #data.gaps > 0 and (total / #data.gaps) or 0
            table.insert(sorted, {name = data.name, maxGap = maxGap, avgGap = avg, count = #data.gaps})
        end
        table.sort(sorted, function(a, b) return a.maxGap > b.maxGap end)
        for _, entry in ipairs(sorted) do
            table.insert(lines, string.format("%s: longest %.1fs, avg %.1fs (%d gaps)", entry.name, entry.maxGap, entry.avgGap, entry.count))
        end
        table.insert(lines, "")
    end

    if next(debuffUptime) and elapsed > 0 then
        table.insert(lines, "--- Target Debuff Uptime ---")
        local sorted = {}
        for _, debuff in pairs(debuffUptime) do
            if debuff.uptime > 0.1 then
                table.insert(sorted, {name = debuff.name, uptime = math.min(debuff.uptime, elapsed)})
            end
        end
        table.sort(sorted, function(a, b) return a.uptime > b.uptime end)
        for i, debuff in ipairs(sorted) do
            if i > 15 then break end
            local pct = (debuff.uptime / elapsed) * 100
            table.insert(lines, string.format("%s: %.1f sec (%.1f%%)", debuff.name, debuff.uptime, pct))
        end
        table.insert(lines, "")
    end

    if spellPowerCosts and next(spellPowerCosts) then
        table.insert(lines, "--- Spell Power Costs ---")
        local powerType = nil
        for _, c in pairs(spellPowerCosts) do powerType = c.powerType; break end
        local sorted = {}
        for name, c in pairs(spellPowerCosts) do
            table.insert(sorted, {name = name, avg = c.totalCost / c.count, total = c.totalCost, count = c.count})
        end
        table.sort(sorted, function(a, b) return a.total > b.total end)
        for _, entry in ipairs(sorted) do
            table.insert(lines, string.format("%s: %d casts, %d total, %.0f avg%s", entry.name, entry.count, entry.total, entry.avg, powerType and (" " .. powerType) or ""))
        end
        table.insert(lines, "")
    end

    return JoinLines(lines)
end

-- ============================================
-- REPORT WINDOW + COPY DIALOG (original)
-- ============================================
local reportPopup = nil
local copyDialog = nil
local ShowCopyDialog

local function CreateReportPopup()
    if reportPopup then RegisterAddonWindow(reportPopup); reportPopup:Show() return end

    reportPopup = CreateStyledFrame("Frame", "DummyAnalyzerReportFrame", UIParent); trackDialog(reportPopup)
    reportPopup:SetSize(720, 540)
    reportPopup:SetPoint("CENTER")
    reportPopup:SetMovable(true)
    reportPopup:SetClampedToScreen(true)
    reportPopup:EnableMouse(true)
    reportPopup:RegisterForDrag("LeftButton")
    reportPopup:SetScript("OnDragStart", reportPopup.StartMoving)
    reportPopup:SetScript("OnDragStop", reportPopup.StopMovingOrSizing)
    ApplyBackdrop(reportPopup, false)

    local titleBar = CreateStyledFrame("Frame", nil, reportPopup)
    titleBar:SetPoint("TOPLEFT", reportPopup, "TOPLEFT")
    titleBar:SetPoint("TOPRIGHT", reportPopup, "TOPRIGHT")
    titleBar:SetHeight(36)
    titleBar:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
    titleBar:SetBackdropColor(C.title[1], C.title[2], C.title[3], C.title[4])
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() reportPopup:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() reportPopup:StopMovingOrSizing() end)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    SafeSetFont(titleText, BOLD_FONT, 15)
    titleText:SetText("Dummy Analyzer Report")
    titleText:SetPoint("CENTER", titleBar, "CENTER")
    titleText:SetTextColor(1, 0.85, 0.4, 1)

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
    closeBtn:SetScript("OnClick", function() reportPopup:Hide() end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, reportPopup, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", reportPopup, "TOPLEFT", 25, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", reportPopup, "BOTTOMRIGHT", -25, 90)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetTextColor(1, 1, 1, 1)
    editBox:SetWidth(560)
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetScript("OnEscapePressed", function() editBox:ClearFocus() end)
    scrollFrame:SetScrollChild(editBox)
    reportPopup.scrollFrame = scrollFrame
    reportPopup.editBox = editBox
    reportPopup.originalText = ""

    local bottomRow = CreateFrame("Frame", nil, reportPopup)
    bottomRow:SetPoint("BOTTOMLEFT", reportPopup, "BOTTOMLEFT", 10, 48)
    bottomRow:SetPoint("BOTTOMRIGHT", reportPopup, "BOTTOMRIGHT", -10, 48)
    bottomRow:SetHeight(32)

    local selectBtn = CreateStyledButton(bottomRow, "Select All", 120, 32, function()
        if reportPopup.editBox then
            reportPopup.editBox:SetFocus()
            reportPopup.editBox:HighlightText()
        elseif reportPopup.originalText then
            ShowCopyDialog(reportPopup.originalText)
        end
    end, "primary")
    selectBtn:SetPoint("LEFT", bottomRow, "LEFT", 0, 0)

    local mdBtn = CreateStyledButton(bottomRow, "Copy Markdown", 120, 32, function()
        local mdElapsed = (testActive and (GetTime() - startTime)) or (testEndTime and (testEndTime - startTime)) or 0
        local mdCastCounts = {}
        for _, spell in ipairs(spellHistory) do
            mdCastCounts[spell.name] = (mdCastCounts[spell.name] or 0) + 1
        end
        local mdText = GenerateMarkdownReport(nil, mdElapsed, totalDamage, #spellHistory, mdCastCounts, damageData, buffUptime, buffGaps, nil, debuffUptime, spellPowerCosts)
        ShowCopyDialog(mdText)
    end)
    mdBtn:SetPoint("LEFT", selectBtn, "RIGHT", 10, 0)

    local refreshBtn = CreateStyledButton(bottomRow, "Refresh Report", 120, 32, function()
        if reportPopup.originalText then
            reportPopup.editBox:SetText(reportPopup.originalText)
            reportPopup.editBox:SetCursorPosition(0)
            reportPopup.scrollFrame:SetVerticalScroll(0)
        end
    end)
    refreshBtn:SetPoint("LEFT", mdBtn, "RIGHT", 10, 0)

    local closePopupBtn = CreateStyledButton(bottomRow, "Close", 100, 32, function() reportPopup:Hide() end, "danger")
    closePopupBtn:SetPoint("RIGHT", bottomRow, "RIGHT", 0, 0)

    local saveLogBtn = CreateStyledButton(bottomRow, "Save Log", 110, 32, function()
        local id = SaveCurrentLog()
        if id then
            print(string.format("|cff33ff33[DummyAnalyzer]|r Log #%d saved.", id))
        else
            print("|cff33ff33[DummyAnalyzer]|r No test data to save.")
        end
    end)
    saveLogBtn:SetPoint("RIGHT", closePopupBtn, "LEFT", -10, 0)
end

ShowCopyDialog = function(text)
    if copyDialog then copyDialog:Hide() copyDialog = nil end
    copyDialog = CreateStyledFrame("Frame", "DummyAnalyzerCopyDialog", UIParent); trackDialog(copyDialog)
    copyDialog:SetSize(600, 450)
    copyDialog:SetPoint("CENTER")
    copyDialog:SetMovable(true)
    copyDialog:SetClampedToScreen(true)
    copyDialog:EnableMouse(true)
    copyDialog:RegisterForDrag("LeftButton")
    copyDialog:SetScript("OnDragStart", copyDialog.StartMoving)
    copyDialog:SetScript("OnDragStop", copyDialog.StopMovingOrSizing)
    ApplyBackdrop(copyDialog, false)

    local titleBar = CreateStyledFrame("Frame", nil, copyDialog)
    titleBar:SetPoint("TOPLEFT", copyDialog, "TOPLEFT")
    titleBar:SetPoint("TOPRIGHT", copyDialog, "TOPRIGHT")
    titleBar:SetHeight(32)
    titleBar:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
    titleBar:SetBackdropColor(C.title[1], C.title[2], C.title[3], C.title[4])

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    SafeSetFont(titleText, BOLD_FONT, 14)
    titleText:SetText("Copy Report Text")
    titleText:SetPoint("CENTER")
    titleText:SetTextColor(1, 0.85, 0.4, 1)

    local closeX = CreateFrame("Button", nil, titleBar)
    closeX:SetSize(30, 30)
    closeX:SetPoint("RIGHT", -10, 0)
    closeX:SetText("X")
    closeX:SetNormalFontObject(GameFontNormalLarge)
    local closeXFont = closeX:GetFontString()
    if closeXFont then closeXFont:SetTextColor(1, 0.2, 0.2) end
    closeX:SetScript("OnClick", function() copyDialog:Hide() end)

    local instr = copyDialog:CreateFontString(nil, "OVERLAY")
    SafeSetFont(instr, MAIN_FONT, 11)
    instr:SetText("Select text below, then press Ctrl+C to copy:")
    instr:SetPoint("TOPLEFT", copyDialog, "TOPLEFT", 20, -45)
    instr:SetTextColor(0.9, 0.9, 0.9, 1)

    local copyScroll = CreateFrame("ScrollFrame", nil, copyDialog, "UIPanelScrollFrameTemplate")
    copyScroll:SetPoint("TOPLEFT", copyDialog, "TOPLEFT", 20, -75)
    copyScroll:SetPoint("BOTTOMRIGHT", copyDialog, "BOTTOMRIGHT", -20, 20)

    local editBox = CreateFrame("EditBox", nil, copyScroll)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(540)
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetText(text)
    local txtLines = 1
    for _ in string.gmatch(text or "", "\n") do txtLines = txtLines + 1 end
    editBox:SetHeight(math.max(200, txtLines * 14 + 20))
    editBox:SetTextColor(0.2, 1.0, 0.2, 1)
    editBox:SetHighlightColor(0.3, 0.5, 0.9, 0.6)
    copyScroll:SetScrollChild(editBox)
    copyDialog.scrollFrame = copyScroll
    copyDialog.editBox = editBox
    RegisterAddonWindow(copyDialog)
    copyDialog:Show()

    C_Timer.After(0.1, function()
        if copyDialog and copyDialog.editBox then
            copyDialog.editBox:SetFocus()
            copyDialog.editBox:HighlightText()
        end
    end)
end

-- ============================================
-- SAVED LOGS BROWSER UI
-- ============================================
local savedLogsFrame = nil

local function RefreshSavedLogsList()
    if not savedLogsFrame then return end
    local container = savedLogsFrame.listContainer
    savedLogsFrame.rows = {}

    for _, child in ipairs({container:GetChildren()}) do
        child:Hide()
    end

    local logs = GetCharDB().logs
    if #logs == 0 then
        local emptyText = container:CreateFontString(nil, "OVERLAY")
        SafeSetFont(emptyText, MAIN_FONT, 12)
        emptyText:SetText("No saved logs. Run a test to save one.")
        emptyText:SetPoint("TOPLEFT", container, "TOPLEFT", 10, -10)
        emptyText:SetTextColor(0.6, 0.6, 0.6, 1)
        table.insert(savedLogsFrame.rows, {frame = emptyText})
        return
    end

    local yOffset = 0
    for i, log in ipairs(logs) do
        local rowFrame = CreateStyledFrame("Frame", nil, container)
        rowFrame:SetSize(480, 28)
        rowFrame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, yOffset)

        local checkBtn = CreateStyledFrame("Button", nil, rowFrame)
        checkBtn:SetSize(20, 20)
        checkBtn:SetPoint("LEFT", rowFrame, "LEFT", 5, 0)
        checkBtn:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
            checkBtn:SetBackdropColor(C.btn[1], C.btn[2], C.btn[3], C.btn[4])
        checkBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        local checkMark = checkBtn:CreateFontString(nil, "OVERLAY")
        SafeSetFont(checkMark, BOLD_FONT, 12)
        checkMark:SetPoint("CENTER")
        checkMark:SetTextColor(0, 1, 0, 1)

        local isChecked = false
        checkBtn:SetScript("OnClick", function()
            isChecked = not isChecked
            checkMark:SetText(isChecked and "✓" or "")
            if savedLogsFrame.rows and savedLogsFrame.rows[i] then
                savedLogsFrame.rows[i].checked = isChecked
            end
        end)

        if i % 2 == 0 then
            rowFrame:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
            rowFrame:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 0.5)
        end

        local durStr = log.duration and string.format("%.1fs", log.duration) or "?"
        local dpsStr = log.dps and ShortNum(log.dps) or "?"
        local castsStr = log.totalCasts or "?"
        local simcFlag = log.isSimC and "|cff00ccff[SimC]|r " or ""
        local labelText = rowFrame:CreateFontString(nil, "OVERLAY")
        SafeSetFont(labelText, MAIN_FONT, 11)
        labelText:SetText(string.format("%s%s | %s | %s DPS | %d casts", simcFlag, log.label or "#" .. (log.id or "?"), durStr, dpsStr, castsStr))
        labelText:SetPoint("LEFT", checkBtn, "RIGHT", 8, 0)
        labelText:SetTextColor(
            log.isSimC and 0.3 or C.text[1],
            log.isSimC and 0.8 or C.text[2],
            log.isSimC and 1.0 or C.text[3],
            C.text[4])

        table.insert(savedLogsFrame.rows, {
            frame = rowFrame,
            logId = log.id,
            checked = false,
        })

        yOffset = yOffset - 30
    end

    container:SetHeight(math.abs(yOffset) + 10)
end

local function ShowComparisonPopup(text)
    if comparisonPopup then comparisonPopup:Hide() comparisonPopup = nil end

    comparisonPopup = CreateStyledFrame("Frame", "DummyAnalyzerCompareFrame", UIParent); trackDialog(comparisonPopup)
    comparisonPopup:SetSize(760, 540)
    comparisonPopup:SetPoint("CENTER")
    comparisonPopup:SetMovable(true)
    comparisonPopup:SetClampedToScreen(true)
    comparisonPopup:EnableMouse(true)
    comparisonPopup:RegisterForDrag("LeftButton")
    comparisonPopup:SetScript("OnDragStart", comparisonPopup.StartMoving)
    comparisonPopup:SetScript("OnDragStop", comparisonPopup.StopMovingOrSizing)
    ApplyBackdrop(comparisonPopup, false)

    local titleBar = CreateStyledFrame("Frame", nil, comparisonPopup)
    titleBar:SetPoint("TOPLEFT", comparisonPopup, "TOPLEFT")
    titleBar:SetPoint("TOPRIGHT", comparisonPopup, "TOPRIGHT")
    titleBar:SetHeight(36)
    titleBar:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
    titleBar:SetBackdropColor(C.title[1], C.title[2], C.title[3], C.title[4])
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() comparisonPopup:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() comparisonPopup:StopMovingOrSizing() end)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    SafeSetFont(titleText, BOLD_FONT, 15)
    titleText:SetText("Comparison Report")
    titleText:SetPoint("CENTER")
    titleText:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])

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
    closeBtn:SetScript("OnClick", function() comparisonPopup:Hide() end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, comparisonPopup, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", comparisonPopup, "TOPLEFT", 25, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", comparisonPopup, "BOTTOMRIGHT", -25, 45)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(680)

    local columnX = {metric = 5, colA = 215, colB = 375, colC = 535}

    local lines = {}
    for line in text:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end

    local yOffset = 0
    local rowHeight = 18
    local function addLine(textLine, fontSize, isBold, colorR, colorG, colorB)
        local fs = content:CreateFontString(nil, "OVERLAY")
        SafeSetFont(fs, isBold and BOLD_FONT or MAIN_FONT, fontSize)
        fs:SetText(textLine)
        fs:SetPoint("TOPLEFT", content, "TOPLEFT", columnX.metric, yOffset)
        fs:SetTextColor(colorR or C.text[1], colorG or C.text[2], colorB or C.text[3], C.text[4])
        yOffset = yOffset - rowHeight
    end

    local function addColumns(col1, col2, col3, col4, fontSize, isBold, colorR, colorG, colorB)
        local cols = {col1, col2, col3, col4}
        local xs = {columnX.metric, columnX.colA, columnX.colB, columnX.colC}
        for i, txt in ipairs(cols) do
            if txt and txt ~= "" then
                local fs = content:CreateFontString(nil, "OVERLAY")
                SafeSetFont(fs, isBold and BOLD_FONT or MAIN_FONT, fontSize or 11)
                fs:SetText(txt)
                fs:SetPoint("TOPLEFT", content, "TOPLEFT", xs[i], yOffset)
                fs:SetTextColor(colorR or C.text[1], colorG or C.text[2], colorB or C.text[3], C.text[4])
            end
        end
        yOffset = yOffset - rowHeight
    end

    local function addSeparator()
        local fs = content:CreateFontString(nil, "OVERLAY")
        SafeSetFont(fs, MAIN_FONT, 10)
        fs:SetText(string.rep("-", 80))
        fs:SetPoint("TOPLEFT", content, "TOPLEFT", columnX.metric, yOffset)
        fs:SetTextColor(0.4, 0.4, 0.4, 1)
        yOffset = yOffset - rowHeight
    end

    local function trim(s) return s and s:match("^%s*(.-)%s*$") or "" end

    for _, line in ipairs(lines) do
        if line == "" then
            yOffset = yOffset - rowHeight * 0.5
        elseif line:find("^=== ") then
            addLine(line, 14, true, C.textHl[1], C.textHl[2], C.textHl[3])
        elseif line:find("^--- ") then
            addLine(line, 12, true, 0.85, 0.75, 0.5)
        elseif line:find("^%-%-%-%-") then
            addSeparator()
        elseif #line >= 60 and line:sub(60):match("%S") then
            local col1 = trim(line:sub(1, 24))
            local col2 = trim(line:sub(26, 41))
            local col3 = trim(line:sub(43, 58))
            local col4 = trim(line:sub(60, 75))
            if col1 == "" or col2 == "" then
                addLine(line, 11)
            else
                local isHdr = col1 == "Metric" or col1 == "Spell" or col1 == "Buff"
                addColumns(col1, col2, col3, col4, 11, isHdr,
                    isHdr and C.textHl[1] or C.text[1],
                    isHdr and C.textHl[2] or C.text[2],
                    isHdr and C.textHl[3] or C.text[3])
            end
        else
            addLine(line, 11)
        end
    end

    content:SetHeight(math.abs(yOffset) + 10)
    scrollFrame:SetScrollChild(content)

    local copyBtn = CreateStyledButton(comparisonPopup, "Copy Text", 130, 32, function()
        ShowCopyDialog(text)
    end, "primary")
    copyBtn:SetPoint("BOTTOMLEFT", comparisonPopup, "BOTTOMLEFT", 25, 10)

    local closePopupBtn = CreateStyledButton(comparisonPopup, "Close", 110, 32, function() comparisonPopup:Hide() end, "danger")
    closePopupBtn:SetPoint("BOTTOMRIGHT", comparisonPopup, "BOTTOMRIGHT", -25, 10)

    comparisonPopup:Show()
end

local renameDialog = nil

local function ShowRenameDialog(logId, currentLabel)
    if renameDialog then renameDialog:Hide() renameDialog = nil end

    renameDialog = CreateStyledFrame("Frame", "DummyAnalyzerRenameFrame", UIParent); trackDialog(renameDialog)
    renameDialog:SetSize(360, 140)
    renameDialog:SetPoint("CENTER")
    renameDialog:SetFrameStrata("DIALOG")
    renameDialog:SetMovable(true)
    renameDialog:SetClampedToScreen(true)
    renameDialog:EnableMouse(true)
    renameDialog:RegisterForDrag("LeftButton")
    renameDialog:SetScript("OnDragStart", renameDialog.StartMoving)
    renameDialog:SetScript("OnDragStop", renameDialog.StopMovingOrSizing)
    ApplyBackdrop(renameDialog, false)

    local titleBar = CreateStyledFrame("Frame", nil, renameDialog)
    titleBar:SetPoint("TOPLEFT", renameDialog, "TOPLEFT")
    titleBar:SetPoint("TOPRIGHT", renameDialog, "TOPRIGHT")
    titleBar:SetHeight(28)
    titleBar:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
    titleBar:SetBackdropColor(C.title[1], C.title[2], C.title[3], C.title[4])
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() renameDialog:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() renameDialog:StopMovingOrSizing() end)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    SafeSetFont(titleText, BOLD_FONT, 13)
    titleText:SetText("Rename Log")
    titleText:SetPoint("CENTER")
    titleText:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])

    local label = renameDialog:CreateFontString(nil, "OVERLAY")
    SafeSetFont(label, MAIN_FONT, 11)
    label:SetText("Enter a new name for this log:")
    label:SetPoint("TOPLEFT", renameDialog, "TOPLEFT", 20, -45)
    label:SetTextColor(C.text[1], C.text[2], C.text[3], C.text[4])

    local editBox = CreateFrame("EditBox", nil, renameDialog, "InputBoxTemplate")
    editBox:SetSize(320, 24)
    editBox:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -8)
    editBox:SetAutoFocus(true)
    editBox:SetText(currentLabel)
    editBox:SetScript("OnEscapePressed", function() renameDialog:Hide() end)
    editBox:SetScript("OnEnterPressed", function()
        local newLabel = editBox:GetText()
        if newLabel and newLabel ~= "" then
            Addon.RenameLog(logId, newLabel)
            RefreshSavedLogsList()
            renameDialog:Hide()
            print(string.format("|cff33ff33[DummyAnalyzer]|r Log renamed to \"%s\".", newLabel))
        end
    end)

    local okBtn = CreateStyledButton(renameDialog, "OK", 80, 26, function()
        local newLabel = editBox:GetText()
        if newLabel and newLabel ~= "" then
            Addon.RenameLog(logId, newLabel)
            RefreshSavedLogsList()
            renameDialog:Hide()
            print(string.format("|cff33ff33[DummyAnalyzer]|r Log renamed to \"%s\".", newLabel))
        end
    end, "primary")
    okBtn:SetPoint("BOTTOMRIGHT", renameDialog, "BOTTOMRIGHT", -15, 15)

    local cancelBtn = CreateStyledButton(renameDialog, "Cancel", 80, 26, function() renameDialog:Hide() end)
    cancelBtn:SetPoint("RIGHT", okBtn, "LEFT", -10, 0)

    RegisterAddonWindow(renameDialog)
    renameDialog:Show()
    C_Timer.After(0.1, function() editBox:SetFocus() end)
end

local notesDialog = nil



local function CreateSavedLogsBrowser()
    if mainFrame then mainFrame:Hide() end
    if savedLogsFrame then RefreshSavedLogsList() RegisterAddonWindow(savedLogsFrame) savedLogsFrame:Show() return end

    savedLogsFrame = CreateStyledFrame("Frame", "DummyAnalyzerSavedLogsFrame", UIParent); trackDialog(savedLogsFrame)
    savedLogsFrame:SetSize(550, 420)
    savedLogsFrame:SetPoint("CENTER")
    savedLogsFrame:SetMovable(true)
    savedLogsFrame:SetClampedToScreen(true)
    savedLogsFrame:EnableMouse(true)
    savedLogsFrame:RegisterForDrag("LeftButton")
    savedLogsFrame:SetScript("OnDragStart", savedLogsFrame.StartMoving)
    savedLogsFrame:SetScript("OnDragStop", savedLogsFrame.StopMovingOrSizing)
    ApplyBackdrop(savedLogsFrame, false)

    local titleBar = CreateStyledFrame("Frame", nil, savedLogsFrame)
    titleBar:SetPoint("TOPLEFT", savedLogsFrame, "TOPLEFT")
    titleBar:SetPoint("TOPRIGHT", savedLogsFrame, "TOPRIGHT")
    titleBar:SetHeight(36)
    titleBar:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
    titleBar:SetBackdropColor(C.title[1], C.title[2], C.title[3], C.title[4])
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() savedLogsFrame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() savedLogsFrame:StopMovingOrSizing() end)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    SafeSetFont(titleText, BOLD_FONT, 15)
    titleText:SetText("Saved Logs")
    titleText:SetPoint("CENTER")
    titleText:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])

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
    closeBtn:SetScript("OnClick", function() savedLogsFrame:Hide() end)

    local instrText = savedLogsFrame:CreateFontString(nil, "OVERLAY")
    SafeSetFont(instrText, MAIN_FONT, 11)
    instrText:SetText("Select two logs and click Compare to see side-by-side breakdown.")
    instrText:SetPoint("TOPLEFT", savedLogsFrame, "TOPLEFT", 20, -48)
    instrText:SetTextColor(C.text[1], C.text[2], C.text[3], C.text[4])

    local function getSelected()
        local selected = {}
        for _, row in ipairs(savedLogsFrame.rows or {}) do
            if row.checked then table.insert(selected, row.logId) end
        end
        return selected
    end

    local compareBtn = CreateStyledButton(savedLogsFrame, "Compare Selected", 140, 28, function()
        local selected = getSelected()
        if #selected ~= 2 then
            print("|cff33ff33[DummyAnalyzer]|r Select exactly 2 logs to compare.")
            return
        end
        local compareText = Addon.CompareLogs(selected[1], selected[2])
        ShowComparisonPopup(compareText)
    end)
    compareBtn:SetPoint("TOPLEFT", instrText, "BOTTOMLEFT", 0, -10)

    local renameBtn = CreateStyledButton(savedLogsFrame, "Rename", 90, 28, function()
        local selected = getSelected()
        if #selected ~= 1 then
            print("|cff33ff33[DummyAnalyzer]|r Select exactly 1 log to rename.")
            return
        end
        local logId = selected[1]
        local logs = Addon.GetSavedLogs()
        local currentLabel = ""
        for _, log in ipairs(logs) do
            if log.id == logId then
                currentLabel = log.label or ("Log #" .. log.id)
                break
            end
        end
        ShowRenameDialog(logId, currentLabel)
    end)
    renameBtn:SetPoint("LEFT", compareBtn, "RIGHT", 10, 0)

    local viewBtn = CreateStyledButton(savedLogsFrame, "View", 80, 28, function()
        local selected = getSelected()
        if #selected ~= 1 then
            print("|cff33ff33[DummyAnalyzer]|r Select exactly 1 log to view its report.")
            return
        end
        local logs = Addon.GetSavedLogs()
        for _, log in ipairs(logs) do
            if log.id == selected[1] then
                local savedDuration = currentDuration
                local savedStartSeq = Addon.testStartSequence
                local savedTestActive = testActive
                local savedStartTime = startTime
                local savedEndTime = testEndTime
                local savedTotalDmg = totalDamage
                local savedSpellHist = spellHistory
                local savedDamData = damageData
                local savedBuffUp = buffUptime
                local savedBuffGaps = buffGaps
                local savedDebuffUp = debuffUptime
                local savedPowerCosts = spellPowerCosts
                currentDuration = log.duration or 0
                testActive = false
                startTime = 0
                testEndTime = log.duration or 0
                totalDamage = log.totalDamage or 0
                spellHistory = log.spellHistory or {}
                damageData = log.damageData or {}
                buffUptime = log.buffUptime or {}
                buffGaps = log.buffGaps or {}
                debuffUptime = log.debuffUptime or {}
                spellPowerCosts = log.spellPowerCosts or {}
                local reportTextStr = GenerateReportText()
                CreateReportPopup()
                reportPopup.editBox:SetText(reportTextStr)
                local numLines = 1
                for _ in string.gmatch(reportTextStr, "\n") do numLines = numLines + 1 end
                reportPopup.editBox:SetHeight(math.max(200, numLines * 14 + 20))
                reportPopup.editBox:SetCursorPosition(0)
                reportPopup.scrollFrame:SetVerticalScroll(0)
                reportPopup.originalText = reportTextStr
                RegisterAddonWindow(reportPopup)
                reportPopup:Show()
                currentDuration = savedDuration
                Addon.testStartSequence = savedStartSeq
                testActive = savedTestActive
                startTime = savedStartTime
                testEndTime = savedEndTime
                totalDamage = savedTotalDmg
                spellHistory = savedSpellHist
                damageData = savedDamData
                buffUptime = savedBuffUp
                buffGaps = savedBuffGaps
                debuffUptime = savedDebuffUp
                spellPowerCosts = savedPowerCosts
                return
            end
        end
    end)
    viewBtn:SetPoint("LEFT", renameBtn, "RIGHT", 10, 0)

    local simcImportBtn = CreateStyledButton(savedLogsFrame, "Import SimC", 110, 28, ShowSimCImportDialog)
    simcImportBtn:SetPoint("LEFT", viewBtn, "RIGHT", 10, 0)

    local deleteBtn = CreateStyledButton(savedLogsFrame, "Delete Selected", 130, 28, function()
        local toDelete = getSelected()
        if #toDelete == 0 then
            print("|cff33ff33[DummyAnalyzer]|r Select logs to delete.")
            return
        end
        local slDb = GetCharDB()
        for _, slId in ipairs(toDelete) do
            for i, log in ipairs(slDb.logs) do
                if log.id == slId then
                    if log.isSimC then slDb.simcLogId = 0 end
                    table.remove(slDb.logs, i)
                    break
                end
            end
        end
        RefreshSavedLogsList()
        if emsWindow and emsWindow.refresh then emsWindow.refresh() end
        print(string.format("|cff33ff33[DummyAnalyzer]|r Deleted %d log(s).", #toDelete))
    end, "danger")
    deleteBtn:SetPoint("TOPLEFT", compareBtn, "BOTTOMLEFT", 0, -4)

    local viewSeqBtn = CreateStyledButton(savedLogsFrame, "View Seq", 90, 28, function()
        local selected = getSelected()
        if #selected ~= 1 then
            print("|cff33ff33[DummyAnalyzer]|r Select exactly 1 log to view its sequence.")
            return
        end
        local logs = Addon.GetSavedLogs()
        for _, log in ipairs(logs) do
            if log.id == selected[1] then
                local seqText = log.emsSeqText or (log.detectedSeqSteps and table.concat(log.detectedSeqSteps, "\n"))
                if seqText then
                    ShowCopyDialog(seqText)
                else
                    -- Generate sequence from this log's data
                    local seq = GenerateEMSSequence(log.castCounts, log.damageData, nil, log.buffUptime)
                    if seq then ShowCopyDialog(seq)
                    else print("|cff33ff33[DummyAnalyzer]|r No sequence data for this log.") end
                end
                return
            end
        end
    end)
    viewSeqBtn:SetPoint("LEFT", deleteBtn, "RIGHT", 10, 0)

    local clogImportBtn = CreateStyledButton(savedLogsFrame, "Combat Log", 110, 28, Addon.ShowCombatLogImportDialog)
    clogImportBtn:SetPoint("LEFT", viewSeqBtn, "RIGHT", 10, 0)

    local scrollFrame = CreateFrame("ScrollFrame", nil, savedLogsFrame)
    scrollFrame:SetPoint("TOPLEFT", savedLogsFrame, "TOPLEFT", 20, -130)
    scrollFrame:SetPoint("BOTTOMRIGHT", savedLogsFrame, "BOTTOMRIGHT", -40, 50)
    scrollFrame:EnableMouseWheel(true)

    local listContainer = CreateFrame("Frame", nil, scrollFrame)
    listContainer:SetWidth(480)
    scrollFrame:SetScrollChild(listContainer)

    savedLogsFrame.scrollFrame = scrollFrame
    savedLogsFrame.listContainer = listContainer
    savedLogsFrame.rows = {}

    RefreshSavedLogsList()
    RegisterAddonWindow(savedLogsFrame)
    savedLogsFrame:Show()
end

local function ShowReport()
    local reportTextStr = GenerateReportText()
    CreateReportPopup()
    reportPopup.editBox:SetText(reportTextStr)
    local numLines = 1
    for _ in string.gmatch(reportTextStr, "\n") do numLines = numLines + 1 end
    reportPopup.editBox:SetHeight(math.max(200, numLines * 14 + 20))
    reportPopup.editBox:SetCursorPosition(0)
    reportPopup.scrollFrame:SetVerticalScroll(0)
    reportPopup.originalText = reportTextStr
    RegisterAddonWindow(reportPopup)
    reportPopup:Show()
end

-- ============================================
-- TEST CONTROL (original)
-- ============================================
local function FinalizeReport()
    pendingReport = false
    ResetDamageData()
    ReadDamageMeterData()
    ShowReport()
end

local function QueueReportAfterCombat()
    pendingReport = true
    if InCombatLockdown and InCombatLockdown() then
        print("|cff33ff33[DummyAnalyzer]|r Test complete. Waiting until combat ends to build damage report...")
        if reportWaitTicker then
            reportWaitTicker:Cancel()
            reportWaitTicker = nil
        end
        reportWaitTicker = C_Timer.NewTicker(0.5, function(ticker)
            if not InCombatLockdown or not InCombatLockdown() then
                ticker:Cancel()
                reportWaitTicker = nil
                if pendingReport then
                    C_Timer.After(0.5, FinalizeReport)
                end
            end
        end)
    else
        C_Timer.After(0.5, FinalizeReport)
    end
end

local function CreateTimerFrame()
    if not timerFrame then
        timerFrame = CreateStyledFrame("Frame", nil, UIParent); trackDialog(timerFrame)
        timerFrame:SetSize(240, 70)
        timerFrame:SetPoint("TOP", UIParent, "TOP", 0, -100)
        timerFrame:SetFrameStrata("TOOLTIP")
        ApplyBackdrop(timerFrame, true)
        timerFrame:EnableMouse(true)
        timerFrame:RegisterForDrag("LeftButton")
        timerFrame:SetScript("OnDragStart", timerFrame.StartMoving)
        timerFrame:SetScript("OnDragStop", timerFrame.StopMovingOrSizing)

        timerText = timerFrame:CreateFontString(nil, "OVERLAY")
        SafeSetFont(timerText, BOLD_FONT, 20)
        timerText:SetPoint("TOP", timerFrame, "TOP", 0, -5)

    end
    timerFrame:SetHeight(50)
    timerFrame:Show()
end

local function StopTest()
    local wasArmed = armedTest
    armedTest = false
    armedMinutes = nil
    if combatWaitTicker then
        combatWaitTicker:Cancel()
        combatWaitTicker = nil
    end
    if wasArmed and not testActive then
        if timerFrame then timerFrame:Hide() end
        print("|cff33ff33[DummyAnalyzer]|r Armed test canceled.")
        return
    end
    if not testActive and pendingReport then return end
    FinalizeBuffTracking()
    testEndTime = GetTime()
    testActive = false
    if updateFrame then updateFrame:SetScript("OnUpdate", nil) end
    if timerFrame then timerFrame:Hide() end

    if debugMode then print("|cff33ff33[DummyAnalyzer Debug]|r Timer finished - queueing report...") end
    QueueReportAfterCombat()
end

local function BeginActiveTest(minutes)
    currentDuration = minutes * 60
    spellHistory = {}
    ResetDamageData()
    ResetBuffTracking()
    testActive = true
    startTime = GetTime()
    testEndTime = nil
    -- Snapshot which GRIP-EMS sequence is active at test start. Sourced from the public
    -- SEQUENCE_STEP_ADVANCED event (see Ems_RegisterEvents), not from Engine internals.
    Addon.testStartSequence = Addon.lastActiveSequence
    StartBuffTicker()
    local minuteText = minutes == 0.5 and "30 sec" or (minutes .. " min")
    print(string.format("|cff33ff33[DummyAnalyzer]|r Test started: %s", minuteText))

    CreateTimerFrame()

    if updateFrame then updateFrame:SetScript("OnUpdate", nil) end
    updateFrame:SetScript("OnUpdate", function()
        if not testActive then return end
        local elapsed = GetTime() - startTime
        local remaining = currentDuration - elapsed
        if remaining <= 0 then StopTest() return end
        local mins = math.floor(remaining / 60)
        local secs = remaining % 60
        if currentDuration == 30 then
            timerText:SetText(string.format("%d sec", math.floor(remaining)))
        else
            timerText:SetText(string.format("%02d:%02d", mins, secs))
        end
    end)
end

local function StartTest(minutes)
    if testActive then StopTest() end
    if combatWaitTicker then
        combatWaitTicker:Cancel()
        combatWaitTicker = nil
    end

    armedTest = true
    armedMinutes = minutes
    local minuteText = minutes == 0.5 and "30 sec" or (minutes .. " min")
    print(string.format("|cff33ff33[DummyAnalyzer]|r Armed: %s test. Timer starts when you enter combat.", minuteText))
    CreateTimerFrame()
    timerText:SetText("Waiting for combat")

    combatWaitTicker = C_Timer.NewTicker(0.2, function(ticker)
        if not armedTest then
            ticker:Cancel()
            combatWaitTicker = nil
            return
        end
        if InCombatLockdown and InCombatLockdown() then
            ticker:Cancel()
            combatWaitTicker = nil
            armedTest = false
            BeginActiveTest(armedMinutes or minutes)
        end
    end)
end

-- ============================================
-- EMS SEQUENCE EXPORT
-- ============================================
ROTATION_EXCLUDE = {
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
}

local _validSpellCache = {}
local function IsValidMacroSpell(spellName)
    if not spellName then _validSpellCache[spellName] = false; return false end
    if _validSpellCache[spellName] ~= nil then return _validSpellCache[spellName] end
    if ROTATION_EXCLUDE[spellName] then _validSpellCache[spellName] = false; return false end
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

FilterSimCData = function(castCounts, damageData)
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
ScanPlayerTalents = function()
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

GenerateEMSSequence = function(castCounts, damageData, ensureSpells, buffUptime)
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
    local talentedSpells, modifiedSpells, heroTalentName = ScanPlayerTalents()
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
-- SUGGESTED SEQUENCE GENERATION
-- ============================================
-- Heuristic learning solver: hill-climbing optimizer that learns from historical
-- player logs and SimC reference data. 500-generation local search with deficit-
-- driven mutation mechanics. Fully taint-safe (no live combat API reads).
GenerateSuggestedSequence = function(castCounts, damageData, buffUptime, duration, buffGaps, seedSteps, priorHistory, selLogIds, customJitter, stepScale, requiredSpells)
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
                if not seen[name] and IsValidMacroSpell(name) then
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
        if not seenUniq[name] then
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

    -- Generate !EMS1! compressed import string
    if C_EncodingUtil then
        local actions = {}
        local seenAct  = {}
        for _, name in ipairs(uniqueOrder) do
            if not seenAct[name] then
                seenAct[name] = true
                local prefix = GetActionPrefix(name)
                local act = {
                    type = "action",
                    macro = string.format("%s [combat] %s", prefix, name),
                }
                if interleaveCandidates[name] then
                    act.interval = interleaveCandidates[name]
                end
                table.insert(actions, act)
            end
        end
        -- Second-chance duplicates of top 2 spells
        local dupAdded = {}
        for i = 1, math.min(2, #uniqueOrder) do
            local name = uniqueOrder[i]
            if not dupAdded[name] and not isLongCD(name) then
                dupAdded[name] = true
                local prefix = GetActionPrefix(name)
                table.insert(actions, {
                    type = "action",
                    macro = string.format("%s [combat] %s", prefix, name),
                })
            end
	end

	local classID = select(3, UnitClass("player"))
	local specID  = spec and GetSpecializationInfo(spec)
	local sequence = {
		icon = uniqueOrder[1] or "INV_Misc_QuestionMark",
		versions = {
			[1] = {
				stepFunction = cfg.stepFunction or "Priority",
				steps = {},
				actions = actions,
                    keyPress = cfg.keyPress or "/startattack",
                    keyRelease = cfg.keyRelease or "",
                    resetOnCombat = (cfg.resetOnCombat ~= nil) and cfg.resetOnCombat or true,
                    resetOnTarget = (cfg.resetOnTarget ~= nil) and cfg.resetOnTarget or true,
                    resetOnGear = (cfg.resetOnGear ~= nil) and cfg.resetOnGear or false,
                    resetOnSpec = (cfg.resetOnSpec ~= nil) and cfg.resetOnSpec or false,
                    resetTimer = cfg.resetTimer or 0,
                    repeatCount = cfg.repeatCount or 0,
                },
            },
            contextOverrides = {},
            author = "DummyAnalyzer",
            description = "Generated by DummyAnalyzer heuristic solver.",
            help = "",
            helplink = "",
            privacyMode = cfg.privacyMode or "private",
            classID = classID,
        }
        if specID then sequence.specID = specID end

        local hash = 5381
        local seqCBOR = C_EncodingUtil.SerializeCBOR(sequence)
        if seqCBOR then
            for i = 1, #seqCBOR do
                hash = ((hash * 33) + string.byte(seqCBOR, i)) % 4294967296
            end
        end
        local payload = {
            format = "GRIP-EMS",
            version = 5,
            locale = GetLocale() or "enUS",
            name = "DummyAnalyzer Heuristic Sequence",
            sequence = sequence,
            variables = {},
            checksum = tostring(hash),
        }
        local ok, cbor, compressed, base64
        ok, cbor = pcall(C_EncodingUtil.SerializeCBOR, payload)
        if ok and cbor then
            ok, compressed = pcall(C_EncodingUtil.CompressString, cbor)
        end
        if ok and compressed then
            ok, base64 = pcall(C_EncodingUtil.EncodeBase64, compressed)
        end
        if ok and base64 then
            importStr = "!EMS1!" .. base64
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
GenerateReasoningText = function(castCounts, damageData)
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
GenerateGapReport = function(castCounts, damageData, playerDuration)
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

-- ============================================
-- EMS IMPORT STRING GENERATION
-- ============================================
GenerateEMSImportString = function(castCounts, damageData, orderedSteps)
    if not castCounts or not next(castCounts) then return nil end
    if not C_EncodingUtil then return nil end
    local sorted = {}
    if orderedSteps and #orderedSteps > 0 then
        -- Use pre-ordered steps (from positional optimization)
        for _, name in ipairs(orderedSteps) do
            local count = castCounts[name] or 0
            local dmg = 0
            if damageData and damageData[name] then
                dmg = NumberOrZero(damageData[name].total)
            end
            table.insert(sorted, {name = name, dmg = dmg, count = count})
        end
        -- Deduplicate to unique spells for action tree
        local seen = {}
        local deduped = {}
        for _, entry in ipairs(sorted) do
            if not seen[entry.name] then
                seen[entry.name] = true
                table.insert(deduped, entry)
            end
        end
        sorted = deduped
    else
        -- Look up SimC log for rotational importance
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
        local totalDmg, totalCasts = 0, 0
        for name, count in pairs(castCounts) do
            local dmg = 0
            if damageData and damageData[name] then
                dmg = NumberOrZero(damageData[name].total)
            end
            totalDmg = totalDmg + dmg
            totalCasts = totalCasts + count
            table.insert(sorted, {name = name, dmg = dmg, count = count})
        end
        local avgDmg = totalCasts > 0 and totalDmg / totalCasts or 1
        table.sort(sorted, function(a, b)
            local sa = a.dmg + a.count * avgDmg * (simcCasts[a.name] and 2.0 or 1.0)
            local sb = b.dmg + b.count * avgDmg * (simcCasts[b.name] and 2.0 or 1.0)
            return sa > sb
        end)
        local filtered = {}
        for _, entry in ipairs(sorted) do
            if IsValidMacroSpell(entry.name) then
                table.insert(filtered, entry)
            end
        end
        sorted = filtered
    end
    if #sorted == 0 then return nil end

    -- Build action tree with interleave intervals
    local actions = {}
    local maxCount = sorted[1] and sorted[1].count or 1
    local interleaveSpells = {}
    for _, entry in ipairs(sorted) do
        if entry.count >= 5 and entry.count >= maxCount * 0.4 then
            interleaveSpells[entry.name] = math.max(2, math.min(6, math.floor(#sorted / math.min(entry.count, #sorted))))
        end
    end
    for _, entry in ipairs(sorted) do
        local prefix = GetActionPrefix(entry.name)
        local interval = interleaveSpells[entry.name]
        local action = {
            type = "action",
            macro = string.format("%s [combat] %s", prefix, entry.name),
        }
        if interval then action.interval = interval end
        table.insert(actions, action)
    end
    -- Add duplicates of top 2 spells at the end for second-chance coverage
    local added = {}
    for i = 1, math.min(2, #sorted) do
        if not added[sorted[i].name] then
            added[sorted[i].name] = true
            local prefix = GetActionPrefix(sorted[i].name)
            table.insert(actions, {
                type = "action",
                macro = string.format("%s [combat] %s", prefix, sorted[i].name),
            })
        end
    end
    local actionMacros = {}
    for _, a in ipairs(actions) do actionMacros[#actionMacros+1] = a.macro end

    -- Build the version with action tree
    local classID = select(3, UnitClass("player"))
    local spec = GetSpecialization()
    local specID = spec and GetSpecializationInfo(spec)
    local sequence = {
        icon = sorted[1].name,
        versions = {
            [1] = {
                stepFunction = "Priority",
                steps = {},
                actions = actions,
                keyPress = "/startattack",
                keyRelease = "",
                resetOnCombat = true,
                resetOnTarget = true,
                resetOnGear = false,
                resetOnSpec = false,
                resetTimer = 0,
            },
        },
        defaultVersion = 1,
        contextOverrides = {},
        author = "DummyAnalyzer",
        description = "Generated by DummyAnalyzer from training dummy parse.",
        help = "",
        helplink = "",
        classID = classID,
    }
    if specID then sequence.specID = specID end
    local seqCBOR = C_EncodingUtil.SerializeCBOR(sequence)
    local hash = 5381
    for i = 1, #seqCBOR do
        hash = ((hash * 33) + string.byte(seqCBOR, i)) % 4294967296
    end
    local payload = {
        format = "GRIP-EMS",
        version = 5,
        locale = GetLocale() or "enUS",
        name = "DummyAnalyzer Sequence",
        sequence = sequence,
        variables = {},
        checksum = tostring(hash),
    }
    local cbor = C_EncodingUtil.SerializeCBOR(payload)
    local compressed = C_EncodingUtil.CompressString(cbor)
    local base64 = C_EncodingUtil.EncodeBase64(compressed)
    return "!EMS1!" .. base64, actionMacros
end

-- ============================================
-- ITERATIVE FEEDBACK: reorder steps based on test performance
-- ============================================
IterateSequence = function(seqText, castCounts, damageData, duration)
    if not seqText or not castCounts or not next(castCounts) then return nil end
    -- Parse unique spells in order of first occurrence
    local seen, order = {}, {}
    for line in seqText:gmatch("[^\r\n]+") do
        local name = ExtractSpellFromSeqLine(line)
        if name and not seen[name] and IsValidMacroSpell(name) then
            seen[name] = true
            table.insert(order, name)
        end
    end
    if #order < 2 then return nil end
    -- Load SimC reference data for expected counts
    local simcCasts, simcDuration = {}, 0
    local db = GetCharDB()
    if db.simcLogId then
        for _, l in ipairs(db.logs or {}) do
            if l.id == db.simcLogId and l.isSimC and l.castCounts then
                for name, count in pairs(l.castCounts) do
                    if IsValidMacroSpell(name) then simcCasts[name] = count end
                end
                simcDuration = l.duration or 0
                break
            end
        end
    end
    -- Compute performance ratio per spell (actual vs SimC-expected, scaled to test duration)
    local ratios, simcExpected = {}, {}
    local durationScale = (duration and duration > 0 and simcDuration > 0) and duration / simcDuration or 1
    for _, name in ipairs(order) do
        local logCount = castCounts[name] or 0
        local simcCount = simcCasts[name] or 0
        local expected = simcCount * durationScale
        simcExpected[name] = expected
        ratios[name] = expected > 0 and (logCount / expected) or (logCount > 0 and 999 or 1)
    end
    -- Sort: starved spells (ratio < 0.7 with >=3 SimC expected) first, then originals
    local starved, normal = {}, {}
    for _, name in ipairs(order) do
        if ratios[name] < 0.7 and simcExpected[name] >= 3 then
            table.insert(starved, name)
        else
            table.insert(normal, name)
        end
    end
    table.sort(starved, function(a, b) return ratios[a] < ratios[b] end)
    local newOrder = {}
    for _, name in ipairs(starved) do table.insert(newOrder, name) end
    for _, name in ipairs(normal) do table.insert(newOrder, name) end
    if #starved == 0 then return nil end  -- nothing to improve
    -- Dedup against optimizerHistory: skip if this unique spell order was already tried
    local uniqKey = table.concat(newOrder, "|")
    local hist = GetCharDB().optimizerHistory or {}
    for _, h in ipairs(hist) do
        local prevKey = h.uniqOrderKey
        if not prevKey and h.seqText then
            -- backward compat: build key from seqText
            local seen, parts = {}, {}
            for line in h.seqText:gmatch("[^\r\n]+") do
                local n = ExtractSpellFromSeqLine(line)
                if n and not seen[n] then seen[n] = true; parts[#parts+1] = n end
            end
            prevKey = table.concat(parts, "|")
        end
        if prevKey == uniqKey then
            print("|cff33ff33[DummyAnalyzer]|r Iterate: skipping duplicate order (already tried)")
            return nil
        end
    end
    -- Generate expanded 30-step sequence from new order
    local function expandSteps(spellNames)
        local result, totalExpected = {}, 0
        local scaled = {}
        for _, name in ipairs(spellNames) do
            local exp = (simcCasts[name] or 0) * durationScale
            scaled[name] = math.max(0.5, exp)
            totalExpected = totalExpected + scaled[name]
        end
        if totalExpected == 0 then return spellNames end
        for _, name in ipairs(spellNames) do
            local copies = math.max(1, math.floor(scaled[name] / totalExpected * 30 + 0.5))
            for i = 1, copies do table.insert(result, name) end
        end
        return result
    end
    local expanded = expandSteps(newOrder)
    -- Generate output text
    local classF = select(2, UnitClass("player")) or "Unknown"
    local spec = GetSpecialization()
    local specN = spec and (select(2, GetSpecializationInfo(spec)) or "") or ""
    local lines = {}
    lines[#lines+1] = "=== Iterated Sequence ==="
    lines[#lines+1] = string.format("Spec: %s %s", classF, specN)
    lines[#lines+1] = string.format("Icon: %s", expanded[1] or "INV_Misc_QuestionMark")
    lines[#lines+1] = "Step Function: Priority"
    lines[#lines+1] = "Reset: combat/target"
    lines[#lines+1] = ""
    for i, s in ipairs(expanded) do
        lines[#lines+1] = string.format("%2d. /cast [combat] %s", i, s)
    end
    local newText = table.concat(lines, "\n")
    local importStr, actionMacros
    local ok, result = pcall(GenerateEMSImportString, castCounts, damageData, expanded)
    if ok and result then importStr = result end
    return newText, importStr, starved, uniqKey
end

-- ponytail: lightweight configure dialog with Required Spells + Sequence Preferences tabs
ShowConfigureDialog = function(parent)
    local db = GetCharDB()
    if not db.settings then db.settings = {} end
    local s = db.settings

    local dialog = CreateStyledFrame("Frame", nil, UIParent); trackDialog(dialog)
    dialog:SetSize(480, 520)
    dialog:SetPoint("CENTER")
    ApplyBackdrop(dialog, false)
    dialog:SetFrameLevel((parent or UIParent):GetFrameLevel() + 10)
    if parent and parent ~= UIParent and parent.Hide then parent:Hide() end

    local titleBar = CreateStyledFrame("Frame", nil, dialog)
    titleBar:SetPoint("TOPLEFT", dialog, "TOPLEFT")
    titleBar:SetPoint("TOPRIGHT", dialog, "TOPRIGHT")
    titleBar:SetHeight(32)
    titleBar:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
    titleBar:SetBackdropColor(C.title[1], C.title[2], C.title[3], C.title[4])
    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    SafeSetFont(titleText, BOLD_FONT, 14)
    titleText:SetText("Configure")
    titleText:SetPoint("CENTER")
    titleText:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])

    local closeX = CreateStyledFrame("Button", nil, titleBar)
    closeX:SetSize(24, 24)
    closeX:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)
    closeX:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
    closeX:SetBackdropColor(C.btn[1], C.btn[2], C.btn[3], C.btn[4])
    local xlbl = closeX:CreateFontString(nil, "OVERLAY")
    SafeSetFont(xlbl, BOLD_FONT, 14)
    xlbl:SetText("X")
    xlbl:SetPoint("CENTER")
    xlbl:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], C.textMuted[4])
    closeX:SetScript("OnClick", function() dialog:Hide(); if parent and parent ~= UIParent and parent.Show then parent:Show() end end)

    local tabRow = CreateFrame("Frame", nil, dialog)
    tabRow:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, -42)
    tabRow:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -20, -42)
    tabRow:SetHeight(28)

    local panels = {}
    local lastTab
    local function ShowTab(idx)
        for i, p in ipairs(panels) do p:SetShown(i == idx) end
        if lastTab then lastTab:SetBackdropColor(C.btn[1], C.btn[2], C.btn[3], C.btn[4]) end
        lastTab = _G["cfgTab" .. idx]
        if lastTab then lastTab:SetBackdropColor(C.selected[1], C.selected[2], C.selected[3], C.selected[4]) end
    end

    local tabs = {"Required Spells", "Sequence Preferences"}
    for ti, tname in ipairs(tabs) do
        local btn = CreateStyledFrame("Button", nil, tabRow)
        btn:SetPoint("LEFT", tabRow, "LEFT", (ti - 1) * 130, 0)
        btn:SetSize(125, 26)
        btn:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
        btn:SetBackdropColor(C.btn[1], C.btn[2], C.btn[3], C.btn[4])
        _G["cfgTab" .. ti] = btn
        local lbl = btn:CreateFontString(nil, "OVERLAY")
        SafeSetFont(lbl, BOLD_FONT, 11)
        lbl:SetText(tname)
        lbl:SetPoint("CENTER")
        lbl:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])
        btn:SetScript("OnClick", function() ShowTab(ti) end)

        local panel = CreateStyledFrame("Frame", nil, dialog)
        panel:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, -80)
        panel:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -20, -50)
        panel:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
        panel:SetBackdropColor(0.08, 0.08, 0.1, 0.5)
        panels[ti] = panel

        if ti == 1 then
            -- Required Spells tab (dropdown selector rows, same pattern as Suggest dialog)
            local spellPool = {}
            do
                local seen = {}
                if db.logs then
                    for _, log in ipairs(db.logs) do
                        if log.castCounts then
                            for name in pairs(log.castCounts) do
                                if not seen[name] then seen[name] = true; spellPool[#spellPool + 1] = name end
                            end
                        end
                    end
                end
                if db.simcData and db.simcData.castCounts then
                    for name in pairs(db.simcData.castCounts) do
                        if not seen[name] then seen[name] = true; spellPool[#spellPool + 1] = name end
                    end
                end
                table.sort(spellPool)
            end

            local reqScroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
            reqScroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
            reqScroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, -44)
            local reqContainer = CreateFrame("Frame", nil, reqScroll)
            reqContainer:SetWidth(400)
            reqScroll:SetScrollChild(reqContainer)

            local reqRows = {}
            local MAX_REQ_SLOTS = 20
            local function ReflowRowPositions(from)
                for i = from or 1, #reqRows do
                    local r = reqRows[i]
                    r.row:SetPoint("TOPLEFT", reqContainer, "TOPLEFT", 0, -(i - 1) * 26)
                end
            end
            local function AddReqRow(spellName)
                if #reqRows >= MAX_REQ_SLOTS then return end
                local idx = #reqRows + 1
                local row = CreateFrame("Frame", nil, reqContainer)
                row:SetPoint("TOPLEFT", reqContainer, "TOPLEFT", 0, -(idx - 1) * 26)
                row:SetPoint("RIGHT", reqContainer, "RIGHT", 0, 0)
                row:SetHeight(26)
                local label = row:CreateFontString(nil, "OVERLAY")
                SafeSetFont(label, FONT, 12)
                label:SetJustifyH("RIGHT")
                label:SetText(tostring(idx) .. ".")
                label:SetPoint("LEFT", row, "LEFT", 2, 0)
                label:SetWidth(24)
                local removeBtn
                removeBtn = CreateStyledButton(row, "x", 24, 22, function()
                    row:Hide()
                    local newRows = {}
                    for j, r2 in ipairs(reqRows) do
                        if r2 ~= r then
                            newRows[#newRows + 1] = r2
                            r2.label:SetText(tostring(#newRows) .. ".")
                        end
                    end
                    reqRows = newRows
                    ReflowRowPositions()
                    s.requiredSpells = {}
                    for _, r2 in ipairs(reqRows) do
                        if r2.selection then s.requiredSpells[#s.requiredSpells + 1] = r2.selection end
                    end
                    db.settings = s
                end)
                removeBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
                local dropdown = CreateFrame("Frame", nil, row, "UIDropDownMenuTemplate")
                dropdown:SetPoint("LEFT", label, "RIGHT", 6, 0)
                dropdown:SetPoint("RIGHT", removeBtn, "LEFT", -10, 0)
                dropdown:SetHeight(22)
                local function InitDropdown(rec)
                    UIDropDownMenu_SetText(dropdown, spellName or "Select...")
                    UIDropDownMenu_Initialize(dropdown, function(self, level)
                        for _, name in ipairs(spellPool) do
                            local info = UIDropDownMenu_CreateInfo()
                            info.text = name
                            info.arg1 = name
                            info.checked = (name == rec.selection)
                            info.func = function(selfArg)
                                rec.selection = selfArg.arg1
                                UIDropDownMenu_SetText(dropdown, selfArg.arg1 or "")
                                CloseDropDownMenus()
                                s.requiredSpells = {}
                                for _, row in ipairs(reqRows) do
                                    if row.selection then s.requiredSpells[#s.requiredSpells + 1] = row.selection end
                                end
                                db.settings = s
                            end
                            UIDropDownMenu_AddButton(info)
                        end
                    end)
                end
                local r = { row = row, label = label, dropdown = dropdown, removeBtn = removeBtn, selection = spellName or nil }
                InitDropdown(r)
                reqRows[idx] = r
            end
            local addBtn = CreateStyledButton(panel, "+ Add Required Spell", 180, 24, function()
                AddReqRow()
            end)
            addBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 6)
            -- Load existing required spells from settings
            local loaded = s.requiredSpells or {}
            if #loaded > 0 then DebugLog("info", "cfg-req", "Loaded: " .. table.concat(loaded, ", ")) end
            for _, spellName in ipairs(loaded) do
                AddReqRow(spellName)
            end
        elseif ti == 2 then
            -- Sequence Preferences tab
            local y = -8
            local function AddLabeledControl(label, controlFn)
                local lbl = panel:CreateFontString(nil, "OVERLAY")
                SafeSetFont(lbl, FONT, 11)
                lbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
                lbl:SetText(label)
                lbl:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])
                lbl:SetJustifyH("LEFT")
                local ctrl = controlFn(panel)
                ctrl:SetPoint("TOPLEFT", panel, "TOPLEFT", 260, y - 4)
                y = y - 32
                return ctrl
            end

            -- Max consecutive repeats
            local repeatCtrl = AddLabeledControl("Max consecutive repeats (0=unlimited):", function(p)
                local eb = CreateFrame("EditBox", nil, p, "BackdropTemplate")
                eb:SetSize(140, 24)
                eb:SetFontObject(ChatFontNormal)
                eb:SetTextColor(1, 1, 1, 1)
                eb:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
                eb:SetBackdropColor(0.04, 0.04, 0.06, 0.8)
                eb:SetAutoFocus(false)
                eb:SetText(tostring(s.maxRepeats or 3))
                eb:SetScript("OnTextChanged", function()
                    local v = tonumber(eb:GetText())
                    if v and v >= 0 then s.maxRepeats = v else s.maxRepeats = 0 end
                end)
                return eb
            end)

            -- Interleave steps (minimum count, 0 = disabled)
            local interleaveCtrl = AddLabeledControl("Min Interleave Steps (0=off):", function(p)
                local eb = CreateFrame("EditBox", nil, p, "BackdropTemplate")
                eb:SetSize(140, 24)
                eb:SetFontObject(ChatFontNormal)
                eb:SetTextColor(1, 1, 1, 1)
                eb:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
                eb:SetBackdropColor(0.04, 0.04, 0.06, 0.8)
                eb:SetAutoFocus(false)
                eb:SetText(tostring(s.interleave or 0))
                eb:SetScript("OnTextChanged", function()
                    local v = tonumber(eb:GetText())
                    if v and v >= 0 then s.interleave = v else s.interleave = 0 end
                end)
                return eb
            end)

            -- Min copies per spell
            local minCtrl = AddLabeledControl("Min copies per spell:", function(p)
                local eb = CreateFrame("EditBox", nil, p, "BackdropTemplate")
                eb:SetSize(140, 24)
                eb:SetFontObject(ChatFontNormal)
                eb:SetTextColor(1, 1, 1, 1)
                eb:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
                eb:SetBackdropColor(0.04, 0.04, 0.06, 0.8)
                eb:SetAutoFocus(false)
                eb:SetText(tostring(s.minCopies or 1))
                eb:SetScript("OnTextChanged", function()
                    local v = tonumber(eb:GetText())
                    if v and v >= 0 then s.minCopies = v else s.minCopies = 1 end
                end)
                return eb
            end)

            -- Step function dropdown
            local sfLabel = panel:CreateFontString(nil, "OVERLAY")
            SafeSetFont(sfLabel, FONT, 11)
            sfLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
            sfLabel:SetText("Step Function:")
            sfLabel:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])
            local sfDropdown = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
            sfDropdown:SetSize(140, 24)
            sfDropdown:SetPoint("TOPLEFT", panel, "TOPLEFT", 260, y - 4)
            local sfOptions = {"Priority", "Sequential", "Random", "ReversePriority"}
            local sfSel = s.stepFunction or "Priority"
            UIDropDownMenu_SetText(sfDropdown, sfSel)
            UIDropDownMenu_Initialize(sfDropdown, function(self, level)
                for _, opt in ipairs(sfOptions) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = opt
                    info.func = function()
                        s.stepFunction = opt
                        UIDropDownMenu_SetText(sfDropdown, opt)
                        CloseDropDownMenus()
                    end
                    UIDropDownMenu_AddButton(info)
                end
            end)
            UIDropDownMenu_SetWidth(sfDropdown, 140, 0)
            y = y - 32

            -- Auto-push checkbox
            local apLabel = panel:CreateFontString(nil, "OVERLAY")
            SafeSetFont(apLabel, FONT, 11)
            apLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
            apLabel:SetText("Auto-push to GRIP-EMS on Best Sequence:")
            apLabel:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])
            local apBtn = CreateStyledFrame("Button", nil, panel)
            apBtn:SetSize(18, 18)
            apBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 260, y - 2)
            apBtn:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
            apBtn:SetBackdropColor(s.autoPush and 0.2 or 0.05, s.autoPush and 0.8 or 0.05, s.autoPush and 0.2 or 0.05, 0.9)
            apBtn:SetScript("OnClick", function()
                s.autoPush = not s.autoPush
                apBtn:SetBackdropColor(s.autoPush and 0.2 or 0.05, s.autoPush and 0.8 or 0.05, s.autoPush and 0.2 or 0.05, 0.9)
            end)
            local apHint = panel:CreateFontString(nil, "OVERLAY")
            SafeSetFont(apHint, FONT, 9)
            apHint:SetPoint("LEFT", apBtn, "RIGHT", 6, 0)
            apHint:SetText("Auto-push when Best Sequence is generated")
            apHint:SetTextColor(C.text[1], C.text[2], C.text[3], 0.5)
            y = y - 36

            -- KeyPress edit
            AddLabeledControl("KeyPress macro:", function(p)
                local eb = CreateFrame("EditBox", nil, p, "BackdropTemplate")
                eb:SetSize(140, 24)
                eb:SetFontObject(ChatFontNormal)
                eb:SetTextColor(1, 1, 1, 1)
                eb:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
                eb:SetBackdropColor(0.04, 0.04, 0.06, 0.8)
                eb:SetAutoFocus(false)
                eb:SetText(tostring(s.keyPress or "/startattack"))
                eb:SetScript("OnTextChanged", function() s.keyPress = eb:GetText() end)
                return eb
            end)

            -- KeyRelease edit
            AddLabeledControl("KeyRelease macro:", function(p)
                local eb = CreateFrame("EditBox", nil, p, "BackdropTemplate")
                eb:SetSize(140, 24)
                eb:SetFontObject(ChatFontNormal)
                eb:SetTextColor(1, 1, 1, 1)
                eb:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
                eb:SetBackdropColor(0.04, 0.04, 0.06, 0.8)
                eb:SetAutoFocus(false)
                eb:SetText(tostring(s.keyRelease or ""))
                eb:SetScript("OnTextChanged", function() s.keyRelease = eb:GetText() end)
                return eb
            end)

            -- Reset condition checkboxes
            local resetLabel = panel:CreateFontString(nil, "OVERLAY")
            SafeSetFont(resetLabel, FONT, 11)
            resetLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
            resetLabel:SetText("Reset on:")
            resetLabel:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])
            local resetDefs = {
                {key = "resetOnCombat", label = "Combat", default = true},
                {key = "resetOnTarget", label = "Target", default = true},
                {key = "resetOnGear",   label = "Gear",   default = false},
                {key = "resetOnSpec",   label = "Spec",   default = false},
            }
            for ri, rd in ipairs(resetDefs) do
                local cb = CreateStyledFrame("Button", nil, panel)
                cb:SetSize(16, 16)
                cb:SetPoint("TOPLEFT", panel, "TOPLEFT", 260 + (ri - 1) * 75, y - 1)
                cb:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
                local val = (s[rd.key] ~= nil) and s[rd.key] or rd.default
                s[rd.key] = val
                cb:SetBackdropColor(val and 0.2 or 0.05, val and 0.8 or 0.05, val and 0.2 or 0.05, 0.9)
                local clbl = panel:CreateFontString(nil, "OVERLAY")
                SafeSetFont(clbl, FONT, 11)
                clbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
                clbl:SetText(rd.label)
                clbl:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])
                cb:SetScript("OnClick", function()
                    s[rd.key] = not s[rd.key]
                    cb:SetBackdropColor(s[rd.key] and 0.2 or 0.05, s[rd.key] and 0.8 or 0.05, s[rd.key] and 0.2 or 0.05, 0.9)
                end)
            end
            y = y - 32

            -- Reset timer edit
            AddLabeledControl("Reset timer (sec, 0=off):", function(p)
                local eb = CreateFrame("EditBox", nil, p, "BackdropTemplate")
                eb:SetSize(140, 24)
                eb:SetFontObject(ChatFontNormal)
                eb:SetTextColor(1, 1, 1, 1)
                eb:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
                eb:SetBackdropColor(0.04, 0.04, 0.06, 0.8)
                eb:SetAutoFocus(false)
                eb:SetText(tostring(s.resetTimer or 0))
                eb:SetScript("OnTextChanged", function()
                    local v = tonumber(eb:GetText())
                    if v and v >= 0 then s.resetTimer = v else s.resetTimer = 0 end
                end)
                return eb
            end)

            -- Repeat count edit
            AddLabeledControl("Repeat count (0=no wrap):", function(p)
                local eb = CreateFrame("EditBox", nil, p, "BackdropTemplate")
                eb:SetSize(140, 24)
                eb:SetFontObject(ChatFontNormal)
                eb:SetTextColor(1, 1, 1, 1)
                eb:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
                eb:SetBackdropColor(0.04, 0.04, 0.06, 0.8)
                eb:SetAutoFocus(false)
                eb:SetText(tostring(s.repeatCount or 0))
                eb:SetScript("OnTextChanged", function()
                    local v = tonumber(eb:GetText())
                    if v and v >= 0 then s.repeatCount = v else s.repeatCount = 0 end
                end)
                return eb
            end)

            -- Privacy mode dropdown
            local pmLabel = panel:CreateFontString(nil, "OVERLAY")
            SafeSetFont(pmLabel, FONT, 11)
            pmLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
            pmLabel:SetText("Privacy Mode:")
            pmLabel:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])
            local pmDropdown = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
            pmDropdown:SetSize(140, 24)
            pmDropdown:SetPoint("TOPLEFT", panel, "TOPLEFT", 260, y - 4)
            local pmOptions = {"private", "public", "pseudonymous"}
            local pmSel = s.privacyMode or "private"
            UIDropDownMenu_SetText(pmDropdown, pmSel)
            UIDropDownMenu_Initialize(pmDropdown, function(self, level)
                for _, opt in ipairs(pmOptions) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = opt
                    info.func = function()
                        s.privacyMode = opt
                        UIDropDownMenu_SetText(pmDropdown, opt)
                        CloseDropDownMenus()
                    end
                    UIDropDownMenu_AddButton(info)
                end
            end)
            UIDropDownMenu_SetWidth(pmDropdown, 140, 0)
            y = y - 32

            -- Save button
            local saveBtn = CreateStyledButton(panel, "Save Preferences", 170, 26, function()
                db.settings = s
                print("|cff33ff33[DummyAnalyzer]|r Preferences saved.")
            end)
            saveBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 8)
        end
    end

    ShowTab(1)
    dialog:Show()
end

local exportDialogRef = nil
ShowExportDialog = function(castCounts, damageData, buffUptime, playerDuration, suggestMode, buffGaps, selectedLogIds)
    if exportDialogRef and exportDialogRef:IsShown() then exportDialogRef:Hide() end
    local exportDialog = nil
    exportDialog = CreateStyledFrame("Frame", nil, UIParent); trackDialog(exportDialog)
    exportDialogRef = exportDialog
    exportDialog:SetSize(680, 600)
    exportDialog:SetPoint("CENTER")
    exportDialog:SetMovable(true)
    exportDialog:SetClampedToScreen(true)
    exportDialog:EnableMouse(true)
    exportDialog:RegisterForDrag("LeftButton")
    exportDialog:SetScript("OnDragStart", exportDialog.StartMoving)
    exportDialog:SetScript("OnDragStop", exportDialog.StopMovingOrSizing)
    ApplyBackdrop(exportDialog, false)

    local titleBar = CreateStyledFrame("Frame", nil, exportDialog)
    titleBar:SetPoint("TOPLEFT", exportDialog, "TOPLEFT")
    titleBar:SetPoint("TOPRIGHT", exportDialog, "TOPRIGHT")
    titleBar:SetHeight(36)
    titleBar:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
    titleBar:SetBackdropColor(C.title[1], C.title[2], C.title[3], C.title[4])
    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    SafeSetFont(titleText, BOLD_FONT, 15)
    titleText:SetText(suggestMode and "Suggested Sequence" or "Export Sequence")
    titleText:SetPoint("CENTER")
    titleText:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])

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
    closeBtn:SetScript("OnClick", function() exportDialog:Hide() end)

    local tabRow = CreateFrame("Frame", nil, exportDialog)
    tabRow:SetPoint("TOPLEFT", exportDialog, "TOPLEFT", 20, -46)
    tabRow:SetPoint("TOPRIGHT", exportDialog, "TOPRIGHT", -20, -46)
    tabRow:SetHeight(32)

    -- Build spell pool: walk the player's full spellbook (C_SpellBook) per GRIP-EMS SpellCache:SC:Scan
    -- pattern, intersect with names actually cast (saved logs' castCounts), dedupe, sort.
    -- If resulting pool is empty (e.g. no logs yet), fall back to action bar spells, then pure-log names.
    -- C_SpellBook APIs used here are read directly from GRIP-EMS/Data/SpellCache.lua reference.
    local function BuildSpellPool()
        local charDb = GetCharDB()
        local logSpells = {}
        if charDb.logs then
            for _, log in ipairs(charDb.logs) do
                if not log.isSimC and log.castCounts then
                    for spell in pairs(log.castCounts) do logSpells[spell] = true end
                end
            end
        end

        -- Known profession names spelled by skill-line header (GRIP-EMS SpellCache approach).
        local KNOWN_PROFESSIONS = {
            "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Inscription",
            "Jewelcrafting", "Leatherworking", "Tailoring", "Mining", "Herbalism",
            "Skinning", "Cooking", "First Aid", "Archaeology", "Fishing"
        }
        local function IsProfessionName(n)
            if not n then return false end
            for _, k in ipairs(KNOWN_PROFESSIONS) do
                if n == k then return true end
            end
            return false
        end
        local function IsActiveSpellsKnown(name)
            if not name or name == "" then return false end
            return SafeTableGet(logSpells, name) == true
        end

        local pool = {}
        local seen = {}

        local function AddSpell(name)
            if not name or name == "" then return end
            if seen[name] then return end
            seen[name] = true
            if IsValidMacroSpell(name) then pool[#pool + 1] = name end
        end

        -- Primary: spellbook walk (per SpellCache:SC:Scan L341-630)
        local sbOk, numSkillLines = pcall(C_SpellBook.GetNumSpellBookSkillLines)
        if sbOk and numSkillLines and numSkillLines > 0 then
            for i = 1, numSkillLines do
                local _, info = pcall(C_SpellBook.GetSpellBookSkillLineInfo, i)
                if info and not IsProfessionName(info.name) then
                    local offset = info.itemIndexOffset or 0
                    local count = info.numSpellBookItems or 0
                    if offset > 0 and count > 0 then
                        local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
                        for slot = offset + 1, offset + count do
                            local _, itemInfo = pcall(C_SpellBook.GetSpellBookItemInfo, slot, bank)
                            -- Accept any castable, non-passive, non-offspec spell; if itemType is
                            -- null/string/foreign we still accept (defensive against API drift).
                            local itemType = itemInfo and itemInfo.itemType
                            local typeOk = (itemType == nil) or itemType == 1 or itemType == 3
                                or type(itemType) == "string"
                            if itemInfo and type(itemInfo) == "table" and itemInfo.name
                                and not itemInfo.isPassive and not itemInfo.isOffSpec and typeOk then
                                if IsActiveSpellsKnown(itemInfo.name) then
                                    AddSpell(itemInfo.name)
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Fallback 1: action bar (GetActionInfo is stable since 2004)
        if #pool == 0 then
            for slot = 1, 120 do
                local ok, info = pcall(GetActionInfo, slot)
                if ok and info and type(info) == "table" and info.type == "spell" and info.name then
                    AddSpell(info.name)
                end
            end
        end

        -- Fallback 2: pure log list (player may have casts but no spellbook + no action bar entry)
        if #pool == 0 then
            for name in pairs(logSpells) do AddSpell(name) end
        end

        table.sort(pool)
        return pool
    end
    local spellPool = BuildSpellPool()
    local MAX_REQ_SLOTS = 8

    -- Required spells: a self-contained inner panel (visually its own thing)
    local reqPanel = CreateFrame("Frame", nil, exportDialog, "BackdropTemplate")
    reqPanel:SetPoint("TOPLEFT", exportDialog, "TOPLEFT", 16, -86)
    reqPanel:SetPoint("RIGHT", exportDialog, "RIGHT", -16, 0)
    reqPanel:SetHeight(120)
    ApplyBackdrop(reqPanel, false)

    -- Panel header
    local reqPanelHeader = reqPanel:CreateFontString(nil, "OVERLAY")
    SafeSetFont(reqPanelHeader, BOLD_FONT, 11)
    reqPanelHeader:SetPoint("TOPLEFT", reqPanel, "TOPLEFT", 8, -8)
    reqPanelHeader:SetText("Required Spells")
    reqPanelHeader:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], 0.9)

    local reqPanelHint = reqPanel:CreateFontString(nil, "OVERLAY")
    SafeSetFont(reqPanelHint, FONT, 10)
    reqPanelHint:SetPoint("LEFT", reqPanelHeader, "RIGHT", 12, 0)
    reqPanelHint:SetText("(use [+ Add Required Spell] to select spells that must be in the sequence)")
    reqPanelHint:SetTextColor(C.text[1], C.text[2], C.text[3], 0.6)
    reqPanelHint:SetJustifyH("LEFT")

    -- Required spells label
    local reqLabel = reqPanel:CreateFontString(nil, "OVERLAY")
    SafeSetFont(reqLabel, FONT, 12)
    reqLabel:SetPoint("TOPLEFT", reqPanel, "TOPLEFT", 24, -28)
    reqLabel:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], 0.9)
    reqLabel:SetText("Required spells (forced into sequence):")
    reqLabel:SetJustifyH("LEFT")

    -- Container holds all rows; grows in height as rows are added
    local reqContainer = CreateFrame("Frame", nil, reqPanel)
    reqContainer:SetPoint("TOPLEFT", reqPanel, "TOPLEFT", 24, -48)
    reqContainer:SetPoint("RIGHT", reqPanel, "RIGHT", -24, 0)
    reqContainer:SetHeight(1)

    -- Row storage: each entry {label, dropdown, removeBtn, selection}
    local reqRows = {}
    local function ReflowRowPositions(startFrom)
        for i = startFrom or 1, #reqRows do
            local r = reqRows[i]
            local yOff = (i - 1) * 26
            r.label:SetPoint("TOPLEFT", reqContainer, "TOPLEFT", 0, -yOff)
            r.dropdown:SetPoint("TOPLEFT", reqContainer, "TOPLEFT", 28, -yOff - 4)
            r.removeBtn:SetPoint("RIGHT", reqContainer, "RIGHT", -4, -yOff - 2)
        end
        reqContainer:SetHeight(math.max(1, #reqRows * 26))
    end
    local function InitDropdown(r, pool)
        UIDropDownMenu_SetText(r.dropdown, r.selection or "")
        UIDropDownMenu_Initialize(r.dropdown, function(self, level)
            local items = {}
            for _, spellName in ipairs(pool) do
                items[#items + 1] = { text = spellName, arg1 = spellName }
            end
            for _, it in ipairs(items) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = it.text
                info.arg1 = it.arg1
                info.checked = (it.arg1 == r.selection)
                info.func = function(selfArg)
                    r.selection = selfArg.arg1
                    UIDropDownMenu_SetSelectedValue(r.dropdown, selfArg.arg1)
                    UIDropDownMenu_SetText(r.dropdown, selfArg.arg1 or "")
                    CloseDropDownMenus()
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
        UIDropDownMenu_SetWidth(r.dropdown, 300, 0)
    end
    local CollectRequiredSpells -- forward decl; resolved below before suggestMode runs
    local function ResizeReqPanel()
        local headerH = 28
        local labelH = 22
        local rowH = 26
        local btnH = 30
        local pad = 12
        local rowsH = math.max(rowH, #reqRows * rowH)
        reqPanel:SetHeight(headerH + labelH + rowsH + btnH + pad)
    end
    local function AddReqRow()
        if #reqRows >= MAX_REQ_SLOTS then return end
        local idx = #reqRows + 1
        local label = reqContainer:CreateFontString(nil, "OVERLAY")
        SafeSetFont(label, FONT, 12)
        label:SetJustifyH("RIGHT")
        label:SetText(tostring(idx) .. ".")
        local dropdown = CreateFrame("Frame", nil, reqContainer, "UIDropDownMenuTemplate")
        dropdown:SetSize(300, 22)
        local removeBtn
        removeBtn = CreateStyledButton(reqContainer, "x", 24, 22, function()
            dropdown:Hide()
            removeBtn:Hide()
            label:SetText("")
            local newRows = {}
            for i, row in ipairs(reqRows) do
                if i ~= idx then
                    newRows[#newRows + 1] = row
                    row.label:SetText(tostring(#newRows) .. ".")
                end
            end
            reqRows = newRows
            ReflowRowPositions()
            ResizeReqPanel()
            if addSlotBtn then addSlotBtn:SetEnabled(#reqRows < MAX_REQ_SLOTS) end
        end)
        removeBtn:SetFrameLevel(dropdown:GetFrameLevel() + 5)
        local r = { label = label, dropdown = dropdown, removeBtn = removeBtn, selection = nil }
        reqRows[idx] = r
        InitDropdown(r, spellPool)
        ReflowRowPositions()
        ResizeReqPanel()
        if addSlotBtn then addSlotBtn:SetEnabled(#reqRows < MAX_REQ_SLOTS) end
    end

    -- "+ Add Slot" button (lives on the panel border bottom)
    addSlotBtn = CreateStyledButton(reqPanel, "+ Add Required Spell", 200, 22, function()
        AddReqRow()
    end)
    addSlotBtn:SetPoint("BOTTOMLEFT", reqPanel, "BOTTOMLEFT", 8, 6)
    addSlotBtn:SetEnabled(true)
    ResizeReqPanel()

    local scrollFrame = CreateFrame("ScrollFrame", nil, exportDialog, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", reqPanel, "BOTTOMLEFT", 0, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", exportDialog, "BOTTOMRIGHT", -25, 50)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetTextColor(1, 1, 1, 1)
    editBox:SetWidth(580)
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetScript("OnEscapePressed", function() editBox:ClearFocus() end)
    scrollFrame:SetScrollChild(editBox)

    -- Must be defined before suggestMode block runs (uses CollectRequiredSpells at L4791)
    do
        local function impl()
            local required = {}
            local seen = {}
            for _, r in ipairs(reqRows) do
                if r.selection and r.selection ~= "" and not seen[r.selection] then
                    seen[r.selection] = true
                    required[#required + 1] = r.selection
                end
            end
            return #required > 0 and required or nil
        end
        CollectRequiredSpells = impl
    end

    -- Compute data BEFORE closures (Lua 5.1: locals must be declared before use)
    local seqText, importStr, reasoningText
    local err = nil
    local seqScore = 0
    if suggestMode then
        local autoReqSpells = CollectRequiredSpells()
        local rawSeqText
        rawSeqText, importStr, reasoningText, seqScore = GenerateSuggestedSequence(castCounts, damageData, buffUptime, playerDuration, buffGaps, nil, nil, selectedLogIds, nil, nil, autoReqSpells)
        if not rawSeqText then return end
        seqScore = seqScore or 0
        local macros, ordNames = ParseSequenceLines(rawSeqText)
        seqText = table.concat(macros, "\n")
        local normScore = seqScore / math.max(playerDuration or 1, 1)
        if not Addon.bestSequence then Addon.bestSequence = {score = 0, normScore = 0} end
        if not Addon.bestSequence.normScore then Addon.bestSequence.normScore = 0 end
        if normScore > (Addon.bestSequence.normScore or 0) then
            local fullStepNames = {}
            for _, m in ipairs(macros) do
                local sn = ExtractSpellFromSeqLine(m)
                if sn then fullStepNames[#fullStepNames + 1] = sn end
            end
            Addon.bestSequence = {score = seqScore, normScore = normScore, seqText = seqText, importStr = importStr, reasoningText = reasoningText, orderedSpellNames = ordNames, fullSteps = fullStepNames}
        end
        do -- auto-push
            local s = (GetCharDB()).settings or {}
            if s.autoPush and Addon.bestSequence and Addon.bestSequence.fullSteps and #Addon.bestSequence.fullSteps > 0 then
                local fs = Addon.bestSequence.fullSteps
                C_Timer.After(0.5, function() Ems_PushBestSequence(fs) end)
            end
        end
        local persistDb = GetCharDB()
        persistDb.bestSequence = Addon.bestSequence
        if not persistDb.optimizerHistory then persistDb.optimizerHistory = {} end
        table.insert(persistDb.optimizerHistory, 1, {timestamp = time(), score = seqScore, seqText = seqText, importStr = importStr, reasoningText = reasoningText})
        if #persistDb.optimizerHistory > 20 then table.remove(persistDb.optimizerHistory) end
    else
        seqText = GenerateEMSSequence(castCounts, damageData, nil, buffUptime) or "No cast data."
        if not C_EncodingUtil then
            err = "C_EncodingUtil not available (requires WoW 12.0+)"
        else
            local ok, result = pcall(GenerateEMSImportString, castCounts, damageData)
            if ok and result then
                importStr = result
            else
                err = "Encoding failed: " .. tostring(result or "unknown error")
            end
        end
        reasoningText = GenerateReasoningText(castCounts, damageData) or "Unable to generate reasoning."
    end
    local gapReportText = GenerateGapReport(castCounts, damageData, playerDuration)

    local function SetEditText(txt)
        editBox:SetText(txt)
        local lines = 1
        for _ in string.gmatch(txt, "\n") do lines = lines + 1 end
        editBox:SetHeight(math.max(200, lines * 14 + 20))
        editBox:SetCursorPosition(0)
        scrollFrame:SetVerticalScroll(0)
    end

    local emsBtn, bestBtn, nextBtn, simcBtn
    local function ClearHighlights()
        if emsBtn then emsBtn:SetBackdropColor(C.btn[1], C.btn[2], C.btn[3], C.btn[4]) end
        if bestBtn then bestBtn:SetBackdropColor(C.btn[1], C.btn[2], C.btn[3], C.btn[4]) end
        if nextBtn then nextBtn:SetBackdropColor(C.btn[1], C.btn[2], C.btn[3], C.btn[4]) end
        if simcBtn then simcBtn:SetBackdropColor(C.btn[1], C.btn[2], C.btn[3], C.btn[4]) end
    end
    local function GetSimcWarning()
        local dbSim = GetCharDB()
        if not dbSim.simcData or not next(dbSim.simcData or {}) then
            return "|cffff4444WARNING:|r No SimC data imported - results based on log data only.\n|cffff4444WARNING:|r Import via Saved Logs > Import SimC for proper DPS weighting.\n\n"
        end
        return ""
    end
    local function ShowBoth(s, i, r)
        return (s or "") .. "\n\n" .. (i or "") .. "\n\n" .. (r or "")
    end

    -- "Best Sequence" button — aggregates ALL test logs and runs full optimizer
    bestBtn = CreateStyledButton(tabRow, "Best Sequence", 140, 28, function()
        local db = GetCharDB()
        local aggCast, aggDmg, aggBuff, aggBuffGaps = {}, {}, {}, {}
        local totalDuration = 0
        local logCount = 0
        for _, log in ipairs(db.logs) do
            if not log.isSimC and log.castCounts and next(log.castCounts) then
                local dur = (log.duration or 1) > 0 and log.duration or 1
                totalDuration = totalDuration + dur
                logCount = logCount + 1
                for spell, count in pairs(log.castCounts) do
                    aggCast[spell] = (aggCast[spell] or 0) + count
                end
                if log.damageData then
                    for spell, d in pairs(log.damageData) do
                        if not aggDmg[spell] then aggDmg[spell] = { total = 0, hits = 0 } end
                        aggDmg[spell].total = (aggDmg[spell].total or 0) + (d.total or 0)
                        aggDmg[spell].hits = (aggDmg[spell].hits or 0) + (d.hits or 0)
                    end
                end
                if log.buffUptime then
                    for key, info in pairs(log.buffUptime) do
                        if not aggBuff[key] then aggBuff[key] = { name = info.name, uptime = 0, weight = 0 } end
                        aggBuff[key].uptime = aggBuff[key].uptime + (info.uptime or 0) * dur
                        aggBuff[key].weight = aggBuff[key].weight + dur
                    end
                end
                if log.buffGaps then
                    for key, data in pairs(log.buffGaps) do
                        if not aggBuffGaps[key] then aggBuffGaps[key] = { name = data.name, gaps = {} } end
                        for _, g in ipairs(data.gaps) do
                            table.insert(aggBuffGaps[key].gaps, g)
                        end
                    end
                end
            end
        end
        for key, info in pairs(aggBuff) do
            if info.weight > 0 then
                aggBuff[key] = { name = info.name, uptime = info.uptime / info.weight }
            end
        end
        if logCount == 0 then
            print("|cff33ff33[DummyAnalyzer]|r No training logs found. Run tests first.")
            return
        end
        -- Use highest-DPS saved log with a GRIP-EMS sequence directly
        local bestLog, bestDPS = nil, 0
        for _, log in ipairs(db.logs) do
            if not log.isSimC and log.emsSeqText and log.emsSeqText ~= "" and (log.dps or 0) > bestDPS then
                bestLog, bestDPS = log, log.dps or 0
            end
        end
        if bestLog then
            local macros, ordered = ParseSequenceLines(bestLog.emsSeqText)
            if #macros > 0 then
                local ctx = { logsCount = 1, logLabelById = { [bestLog.id or 0] = bestLog.label or ("Log #" .. tostring(bestLog.id or "?")) } }
                local deficit = ComputeDeficitSnapshot(bestLog.castCounts or {}, db.simcData, bestLog.duration or 1)
                local display = BuildKidFriendlyDisplay("best", ctx, bestDPS, bestLog.duration or 1, macros, ordered, deficit)
                local fullStepNames = {}
                for _, m in ipairs(macros) do
                    local sn = ExtractSpellFromSeqLine(m)
                    if sn then fullStepNames[#fullStepNames + 1] = sn end
                end
                Addon.bestSequence = {score = bestDPS, normScore = bestDPS / math.max(bestLog.duration or 1, 1), seqText = table.concat(macros, "\n"), importStr = "", reasoningText = "", orderedSpellNames = ordered, fullSteps = fullStepNames}
                db.bestSequence = Addon.bestSequence
                do -- auto-push
                    local s = db.settings or {}
                    if s.autoPush and fullStepNames and #fullStepNames > 0 then
                        C_Timer.After(0.5, function() Ems_PushBestSequence(fullStepNames) end)
                    end
                end
                seqText = table.concat(macros, "\n")
                importStr = ""; reasoningText = ""
                ClearHighlights()
                if bestBtn then bestBtn:SetBackdropColor(C.selected[1], C.selected[2], C.selected[3], C.selected[4]) end
                SetEditText(GetSimcWarning() .. display)
                print(string.format("|cff33ff33[DummyAnalyzer]|r Best sequence from log: %s (%s DPS)", bestLog.label or ("#" .. tostring(bestLog.id)), Addon.FormatNumber(bestDPS)))
                return
            end
        end
        local reqSpells = CollectRequiredSpells()
        DebugLog("info", "BestSeq", string.format("%d logs total", logCount))
        local bestSeqStr, bestImportStr, bestReasonStr, bestScore = GenerateSuggestedSequence(aggCast, aggDmg, aggBuff, totalDuration, aggBuffGaps, nil, nil, nil, nil, nil, reqSpells)
        if bestSeqStr then
            local macros, ordered = ParseSequenceLines(bestSeqStr)
            local ctx = { logsCount = logCount, logLabelById = {} }
            for _, log in ipairs(db.logs) do
                if not log.isSimC then
                    ctx.logLabelById[log.id or 0] = log.label or ("log #" .. tostring(log.id or "?"))
                end
            end
            local deficit = ComputeDeficitSnapshot(aggCast, db.simcData, totalDuration)
            local display = BuildKidFriendlyDisplay("best", ctx, bestScore, totalDuration, macros, ordered, deficit)
            local fullStepNames = {}
            for _, m in ipairs(macros) do
                local sn = ExtractSpellFromSeqLine(m)
                if sn then fullStepNames[#fullStepNames + 1] = sn end
            end
            Addon.bestSequence = {score = bestScore or 0, normScore = (bestScore or 0) / math.max(totalDuration, 1), seqText = table.concat(macros, "\n"), importStr = bestImportStr, reasoningText = bestReasonStr, orderedSpellNames = ordered, fullSteps = fullStepNames}
            do -- auto-push
                local s = (GetCharDB()).settings or {}
                if s.autoPush and fullStepNames and #fullStepNames > 0 then
                    C_Timer.After(0.5, function() Ems_PushBestSequence(fullStepNames) end)
                end
            end
            local db3 = GetCharDB()
            db3.bestSequence = Addon.bestSequence
            -- Dedup: only save to history if the sequence text differs from the most recent entry
            if not db3.optimizerHistory then db3.optimizerHistory = {} end
            local lastEntry = db3.optimizerHistory[1]
            if not lastEntry or lastEntry.seqText ~= bestSeqStr then
                table.insert(db3.optimizerHistory, 1, {timestamp = time(), score = bestScore, seqText = bestSeqStr, importStr = bestImportStr, reasoningText = bestReasonStr})
                if #db3.optimizerHistory > 20 then table.remove(db3.optimizerHistory) end
            end

            seqText = table.concat(macros, "\n")  -- ONLY /cast lines, so Push fallback always works
            importStr = bestImportStr; reasoningText = bestReasonStr
            ClearHighlights()
            if bestBtn then bestBtn:SetBackdropColor(C.selected[1], C.selected[2], C.selected[3], C.selected[4]) end
            SetEditText(GetSimcWarning() .. display)
            print(string.format("|cff33ff33[DummyAnalyzer]|r Best sequence from %d logs (score: %s)", logCount, Addon.FormatNumber(bestScore or 0)))
        else
            print("|cff33ff33[DummyAnalyzer]|r Failed to generate best sequence from %d logs.", logCount)
        end
    end, "primary")
    bestBtn:SetPoint("LEFT", tabRow, "LEFT", 0, 0)

    -- "From SimC" - generates basic priority sequence from SimC import (no real logs needed)
    simcBtn = CreateStyledButton(tabRow, "From SimC", 100, 28, function()
        local db = GetCharDB()
        if not db.simcData or not db.simcData.castCounts or not next(db.simcData.castCounts) then
            print("|cffff8844[DummyAnalyzer]|r No SimC data imported. Use Saved Logs -> Import SimC first.")
            return
        end
        local simcCastCounts = db.simcData.castCounts
        local simcDamage = db.simcData.damageData or {}
        local simcSeqText = GenerateEMSSequence(simcCastCounts, simcDamage)
        local castCount = 0; for _ in pairs(simcCastCounts) do castCount = castCount + 1 end
        DebugLog("info", "simc-gen", string.format("SimC import generated seq: %s (%d spells in castCounts)", simcSeqText and #simcSeqText > 0 and "OK" or "empty", castCount))
        if not simcSeqText or simcSeqText == "" then
            print("|cffff8844[DummyAnalyzer]|r Failed to generate sequence from SimC data.")
            return
        end
        local macros, ordered = ParseSequenceLines(simcSeqText)
        local fullStepNames = {}
        for _, m in ipairs(macros) do
            local sn = ExtractSpellFromSeqLine(m)
            if sn then fullStepNames[#fullStepNames + 1] = sn end
        end
        local simcImportStr = GenerateEMSImportString(simcCastCounts, simcDamage)
        -- Update closure variables in-place (same pattern as Best/Next buttons)
        seqText = simcSeqText
        importStr = simcImportStr
        reasoningText = "Generated from SimC import (no real logs)."
        Addon.bestSequence = { score = 0, normScore = 0, seqText = seqText, importStr = importStr, reasoningText = reasoningText, orderedSpellNames = ordered, fullSteps = fullStepNames }
        local persistDb = GetCharDB()
        persistDb.bestSequence = Addon.bestSequence
        ClearHighlights()
        if simcBtn then simcBtn:SetBackdropColor(C.selected[1], C.selected[2], C.selected[3], C.selected[4]) end
        local simcCtx = { logLabel = "SimC", id = nil }
        local simcDeficit = ComputeDeficitSnapshot(simcCastCounts, db.simcData, 0)
        local simcDisplay = BuildKidFriendlyDisplay("best", simcCtx, 0, 1, macros, ordered, simcDeficit)
        SetEditText(GetSimcWarning() .. simcDisplay .. "\n\n|cffffff00Run a training dummy test, then click Best Sequence to optimize.|r")
        print("|cff33ff33[DummyAnalyzer]|r Generated basic sequence from SimC import (" .. #ordered .. " spells).")
    end, "secondary")
    simcBtn:SetPoint("LEFT", bestBtn, "RIGHT", 10, 0)

    -- "Next Sequence" — reruns optimizer with current seq as seed + jitter
    nextBtn = CreateStyledButton(tabRow, "Next Sequence", 140, 28, function()
        DebugLog("info", "next-seq", "Next Sequence clicked")
        local db5 = GetCharDB()
        local steps = {}
        if seqText then
            for line in seqText:gmatch("[^\r\n]+") do
                local name = ExtractSpellFromSeqLine(line)
                if name then table.insert(steps, name) end
            end
        end
        local ccCount = 0; if castCounts then for _ in pairs(castCounts) do ccCount = ccCount + 1 end end
        DebugLog("info", "next-seq", string.format("Parsed %d steps from seqText, castCounts keys=%d", #steps, ccCount))
        if #steps == 0 then steps = nil end
        local reqSpells = CollectRequiredSpells()
        local ok, nSeq, nImp, nReason, nScore = pcall(GenerateSuggestedSequence, castCounts, damageData, buffUptime, playerDuration, buffGaps, steps, db5.optimizerHistory, nil, nil, nil, reqSpells)
        if not ok then
            DebugLog("error", "next-seq", "pcall failed: " .. tostring(nSeq))
            print("|cffff4444[DummyAnalyzer]|r Next Sequence error: " .. tostring(nSeq))
            return
        end
        DebugLog("info", "next-seq", string.format("nSeq=%s, nScore=%s", tostring(nSeq and #nSeq > 0), tostring(nScore)))
        if nSeq then
            local macros, ordered = ParseSequenceLines(nSeq)
            -- Find the most recent real log to compare against
            local ctx = { logLabel = nil, id = nil }
            for _, log in ipairs(db5.logs) do
                if not log.isSimC and not ctx.id then
                    ctx.id = log.id or 0
                    ctx.logLabel = log.label or ("Log #" .. tostring(ctx.id))
                end
            end
            local deficit = ComputeDeficitSnapshot(castCounts, db5.simcData, playerDuration)
            local display = BuildKidFriendlyDisplay("next", ctx, nScore, playerDuration, macros, ordered, deficit, steps ~= nil)
            seqText = table.concat(macros, "\n")  -- ONLY /cast lines
            importStr = nImp; reasoningText = nReason
ClearHighlights()
        if nextBtn then nextBtn:SetBackdropColor(C.selected[1], C.selected[2], C.selected[3], C.selected[4]) end
        SetEditText(GetSimcWarning() .. display)
            local normS = nScore and (nScore / math.max(playerDuration, 1)) or 0
            if not Addon.bestSequence then Addon.bestSequence = {score = 0, normScore = 0} end
            if not Addon.bestSequence.normScore then Addon.bestSequence.normScore = 0 end
            if normS > Addon.bestSequence.normScore then
                local fullStepNames = {}
                for _, m in ipairs(macros) do
                    local sn = ExtractSpellFromSeqLine(m)
                    if sn then fullStepNames[#fullStepNames + 1] = sn end
                end
                Addon.bestSequence = {score = nScore or 0, normScore = normS, seqText = table.concat(macros, "\n"), importStr = nImp, reasoningText = nReason, orderedSpellNames = ordered, fullSteps = fullStepNames}
            end
            db5.bestSequence = Addon.bestSequence
            if not db5.optimizerHistory then db5.optimizerHistory = {} end
            table.insert(db5.optimizerHistory, 1, {timestamp = time(), score = nScore, seqText = nSeq, importStr = nImp, reasoningText = nReason, uniqKey = table.concat(ordered or {}, "|")})
            if #db5.optimizerHistory > 20 then table.remove(db5.optimizerHistory) end
            print(string.format("|cff33ff33[DummyAnalyzer]|r Next sequence (score: %s)", Addon.FormatNumber(nScore or 0)))
        else
            print("|cff33ff33[DummyAnalyzer]|r Same order as last, click Next Sequence again for a different variant")
        end
    end)
    nextBtn:SetPoint("LEFT", simcBtn, "RIGHT", 10, 0)

    -- "EMS Import" — show ONLY the current EMS import string
    emsBtn = CreateStyledButton(tabRow, "EMS Import", 120, 28, function()
        ClearHighlights()
        if emsBtn then emsBtn:SetBackdropColor(C.selected[1], C.selected[2], C.selected[3], C.selected[4]) end
        local warn = GetSimcWarning()
        local body = importStr or err or "Failed to generate import string."
        SetEditText(warn .. body)
    end)
    emsBtn:SetPoint("LEFT", nextBtn, "RIGHT", 10, 0)

    local bottomRow = CreateFrame("Frame", nil, exportDialog)
    bottomRow:SetPoint("BOTTOMLEFT", exportDialog, "BOTTOMLEFT", 10, 8)
    bottomRow:SetPoint("BOTTOMRIGHT", exportDialog, "BOTTOMRIGHT", -10, 8)
    bottomRow:SetHeight(32)

    local copyBtn = CreateStyledButton(bottomRow, "Copy to Clipboard", 140, 32, function()
        local txt = editBox:GetText()
        if txt and txt ~= "" then
            C_Timer.After(0.1, function()
                editBox:SetFocus()
                editBox:HighlightText()
                editBox:SetCursorPosition(0)
            end)
        end
        print("|cff33ff33[DummyAnalyzer]|r Text copied to clipboard (Ctrl+V to paste).")
    end, "primary")
    copyBtn:SetPoint("LEFT", bottomRow, "LEFT", 0, 0)

    -- "Push to Grip" — explicitly upload the currently-shown sequence to GRIP-EMS as an owned sequence.
    -- ponytail: push ALL steps including duplicates, not just unique spell names
local function ExtractAllSteps(src)
    if not src or src == "" then return {} end
    local steps = {}
    for line in src:gmatch("[^\n]+") do
        local name = ExtractSpellFromSeqLine(line)
        if name then steps[#steps + 1] = name end
    end
    return steps
end
local pushBtn = CreateStyledButton(bottomRow, "Push to GRIP-EMS", 170, 32, function()
          print("|cff33ff33[DummyAnalyzer EMS]|r Push to GRIP-EMS clicked. Resolving order...")
          local steps = nil
          -- Ponytail: use current seqText first (always matches what's displayed),
          -- fall back to saved bestSequence.fullSteps, then raw editBox text.
          if seqText and seqText ~= "" then
              steps = ExtractAllSteps(seqText)
              print("|cffffff00[DummyAnalyzer EMS]|r From seqText, len=" .. #steps)
          else
              local db2 = GetCharDB()
              if db2 and db2.bestSequence and type(db2.bestSequence.fullSteps) == "table" and #db2.bestSequence.fullSteps > 0 then
                  steps = db2.bestSequence.fullSteps
                  print("|cffffff00[DummyAnalyzer EMS]|r Cache fallback: fullSteps len=" .. #steps)
              elseif editBox then
                  local editText = editBox:GetText() or ""
                  if editText ~= "" then
                      steps = ExtractAllSteps(editText)
                      print("|cffffff00[DummyAnalyzer EMS]|r From editBox, len=" .. (#steps or 0))
                  end
              end
          end
          if not steps or #steps == 0 then
              print("|cffff8844[DummyAnalyzer EMS]|r No sequence available. Click Best Sequence or Next Sequence first.")
              return
          end
        if not emsPluginHandle then
            local ok, reason = Ems_EnsureHandle()
            if not ok then
                print("|cffff8844[DummyAnalyzer EMS]|r GRIP-EMS not ready: " .. tostring(reason) .. ". Reload after EMS is loaded.")
                return
            end
        end
        local pushedName = Ems_PushBestSequence(steps)
        if pushedName then
            print("|cff33ff33[DummyAnalyzer EMS]|r Pushed to GRIP-EMS as '" .. pushedName .. "' (steps=" .. #steps .. ").")
        end
    end, "primary")
    pushBtn:SetPoint("LEFT", copyBtn, "RIGHT", 10, 0)
    -- Distinct color: orange (different from Copy's green and Close's red)
    if pushBtn.SetBackdropColor then
        pushBtn:SetBackdropColor(0.914, 0.271, 0.376, 1) -- accent
    end
    -- Force-width and bright text on label so it's never invisible against any backdrop
    do
        local regions = { pushBtn:GetRegions() }
        for i = 1, #regions do
            local r = regions[i]
            if r and r.GetObjectType and r:GetObjectType() == "FontString" then
                r:ClearAllPoints()
                r:SetPoint("CENTER", pushBtn, "CENTER", 0, 0)
                r:SetText("Push to GRIP-EMS")
                r:SetTextColor(1, 1, 1, 1)
            end
        end
    end
    if debugMode then print("|cffffff00[DummyAnalyzer EMS]|r pushBtn created and anchored: " .. tostring(pushBtn:GetName() or "<anon>")) end

    local cfgBtn = CreateStyledButton(bottomRow, "Configure", 100, 32, function() ShowConfigureDialog(exportDialog) end)
    cfgBtn:SetPoint("LEFT", pushBtn, "RIGHT", 10, 0)

    local closeBtn2 = CreateStyledButton(bottomRow, "Close", 100, 32, function() exportDialog:Hide() end, "danger")
    closeBtn2:SetPoint("RIGHT", bottomRow, "RIGHT", 0, 0)

    local initWarn = ""
    do
        local dbSim = GetCharDB()
        if not dbSim.simcData or not next(dbSim.simcData or {}) then
            initWarn = "|cffff4444WARNING:|r No SimC data imported - results based on log data only.\n|cffff4444WARNING:|r Import via Saved Logs > Import SimC for proper DPS weighting.\n\n"
        end
    end
    local initContent
    if suggestMode and Addon.bestSequence and Addon.bestSequence.seqText and Addon.bestSequence.seqText ~= "" then
        local macros, ordered = ParseSequenceLines(Addon.bestSequence.seqText)
        local ctx = { logLabel = "suggested", id = nil }
        local deficit = ComputeDeficitSnapshot(castCounts, GetCharDB().simcData, playerDuration)
        initContent = GetSimcWarning() .. BuildKidFriendlyDisplay("best", ctx, Addon.bestSequence.score or 0, playerDuration or 1, macros, ordered, deficit)
        seqText = Addon.bestSequence.seqText
        importStr = Addon.bestSequence.importStr or importStr
        reasoningText = Addon.bestSequence.reasoningText or reasoningText
    elseif seqText and seqText ~= "" then
        local macros, ordered = ParseSequenceLines(seqText)
        local ctx = { logLabel = "suggested", id = nil }
        local deficit = ComputeDeficitSnapshot(castCounts, GetCharDB().simcData, playerDuration)
        initContent = GetSimcWarning() .. BuildKidFriendlyDisplay("best", ctx, seqScore or 0, playerDuration or 1, macros, ordered, deficit)
    else
        initContent = (importStr or "") or ""
    end
    local initLines = 1
    for _ in string.gmatch(initContent, "\n") do initLines = initLines + 1 end
    SetEditText(initContent)
    editBox:SetHeight(math.max(200, initLines * 14 + 20))

    RegisterAddonWindow(exportDialog)
    exportDialog:Show()
end

-- ============================================
-- MAIN WINDOW, MINIMAP, SLASH, INIT
-- ============================================
local function ShowEMSComparison(selectedIds)
    local logs = GetCharDB().logs or {}
    local selectedLogs = {}
    for _, log in ipairs(logs) do
        for _, lid in ipairs(selectedIds) do
            if log.id == lid then
                table.insert(selectedLogs, log)
                break
            end
        end
    end
    if #selectedLogs < 2 then return end

    -- Build comparison text
    local lines = {}
    table.insert(lines, "=== SEQUENCE COMPARISON ===\n")
    table.insert(lines, "Comparing " .. #selectedLogs .. " logs:\n")

    -- For each log, show vertical sequence breakdown and DPS
    local allSpells = {}
    local logData = {}
    for _, log in ipairs(selectedLogs) do
        local dpsStr = Addon.FormatNumber(log.dps or 0)
        local label = log.label or ("Log #" .. log.id)
        table.insert(lines, string.format("\n\n=== %s (%s DPS) ===", label, dpsStr))

        -- Build ensure list from detected steps so cooldowns are never dropped
        local logEnsure = {}
        if log.detectedSeqSteps then
            for _, step in ipairs(log.detectedSeqSteps) do
                local s = step:match("%[%w+%] (.+)$") or step:match("/cast (.+)$") or step
                if s and s ~= "" then logEnsure[s:match("^%s*(.-)%s*$")] = true end
            end
        end
        local logEnsureList = {}
        for k in pairs(logEnsure) do table.insert(logEnsureList, k) end

        -- Prefer detected (input) sequence from GRIP-EMS, fall back to generated
        local inputSteps = {}
        local inputLabel = ""
        if log.detectedSeqSteps and #log.detectedSeqSteps > 0 then
            for i, step in ipairs(log.detectedSeqSteps) do
                inputSteps[i] = step
            end
            inputLabel = string.format("GRIP-EMS: %s (%.0f%% match)", log.detectedSeqName or "?", (log.detectedSeqMatch or 0) * 100)
        else
            local seqText = log.emsSeqText and log.emsSeqText ~= "" and log.emsSeqText or GenerateEMSSequence(log.castCounts, log.damageData, logEnsureList, log.buffUptime)
            for line in string.gmatch(seqText or "", "([^\n]+)") do
                local stepNum = line:match("^%s*(%d+)%.")
                if stepNum then
                    local stepText = line:match("^%s*%d+%. (.+)$")
                    if stepText then
                        inputSteps[tonumber(stepNum)] = stepText
                    end
                end
            end
        end
        if inputLabel ~= "" then table.insert(lines, inputLabel) end

        -- Input sequence (vertical numbered)
        table.insert(lines, "Input sequence (what was pressed):")
        for i, s in ipairs(inputSteps) do
            table.insert(lines, string.format("  %d. %s", i, s))
        end

        -- Show optimal (generated) sequence for comparison
        local optSeqText = log.emsSeqText and log.emsSeqText ~= "" and log.emsSeqText or GenerateEMSSequence(log.castCounts, log.damageData, logEnsureList, log.buffUptime)
        local optSteps = {}
        for line in string.gmatch(optSeqText or "", "([^\n]+)") do
            local stepNum = line:match("^%s*(%d+)%.")
            if stepNum then
                local stepText = line:match("^%s*%d+%. (.+)$")
                if stepText then
                    optSteps[tonumber(stepNum)] = stepText
                end
            end
        end
        if #optSteps > 0 then
            table.insert(lines, "Optimal sequence (by damage):")
            for i, s in ipairs(optSteps) do
                local diff = inputSteps[i] and (inputSteps[i] ~= s) and " <-- differs" or ""
                table.insert(lines, string.format("  %d. %s%s", i, s, diff))
            end
        end

        -- Compact summary line
        local topSpell = ""
        if log.damageData then
            local topDmg = 0
            for name, d in pairs(log.damageData) do
                local total = d.total or 0
                if total > topDmg then topDmg = total; topSpell = name end
            end
        end
        local spellCount = log.damageData and 0 or 0
        if log.damageData then for _ in pairs(log.damageData) do spellCount = spellCount + 1 end end
        table.insert(lines, string.format("Spells: %d | Best: %s (%s) | Casts: %d",
            spellCount, topSpell, Addon.FormatNumber(topDmg), log.totalCasts or 0))

        logData[log.id] = { steps = inputSteps, label = label, dps = log.dps or 0 }
    end

    -- Total DPS comparison
    table.insert(lines, "\n=== DPS SUMMARY ===\n")
    local maxDps = 0
    for _, ld in pairs(logData) do
        if ld.dps > maxDps then maxDps = ld.dps end
    end
    for _, log in ipairs(selectedLogs) do
        local ld = logData[log.id]
        local pct = maxDps > 0 and (ld.dps / maxDps * 100) or 0
        local barLen = math.floor(pct / 5)
        local bar = string.rep("#", barLen)
        table.insert(lines, string.format("%-25s %s DPS (%5.1f%%) %s", ld.label, Addon.FormatNumber(ld.dps), pct, bar))
    end

    -- Per-spell positional analysis
    table.insert(lines, "\n=== POSITIONAL ANALYSIS ===\n")
    local posMap = {}
    for _, log in ipairs(selectedLogs) do
        local ld = logData[log.id]
        local dur = (log.duration or 1) > 0 and log.duration or 1
        for pos, stepText in ipairs(ld.steps) do
            local spellName = ExtractSpellFromSeqLine(stepText) or stepText:match("/%a+ (.+)$") or stepText
            if spellName and not log.isSimC then
                local spellDps = 0
                if log.damageData and log.damageData[spellName] then
                    spellDps = (log.damageData[spellName].total or 0) / dur
                end
                if not posMap[spellName] then posMap[spellName] = {} end
                table.insert(posMap[spellName], { log = ld.label, pos = pos, dps = spellDps })
            end
        end
    end
    for spell, entries in pairs(posMap) do
        if #entries >= 2 then
            table.sort(entries, function(a, b) return a.dps > b.dps end)
            local best = entries[1]
            local worst = entries[#entries]
            table.insert(lines, string.format("  %s:", spell))
            table.insert(lines, string.format("    Best: position %d in %s (%s DPS)", best.pos, best.log, Addon.FormatNumber(best.dps)))
            table.insert(lines, string.format("    Worst: position %d in %s (%s DPS)", worst.pos, worst.log, Addon.FormatNumber(worst.dps)))
            if best.pos < worst.pos then
                table.insert(lines, "    -> Performs better at higher priority (lower step number)")
            elseif best.pos > worst.pos then
                table.insert(lines, "    -> Performs better at lower priority (higher step number)")
            end
        end
    end

    -- Analysis: SimC comparison and recommendations
    local simcLog = nil
    for _, log in ipairs(selectedLogs) do
        if log.isSimC then simcLog = log break end
    end

    table.insert(lines, "\n=== ANALYSIS & RECOMMENDATIONS ===\n")
    if simcLog and simcLog.damageData and simcLog.duration and simcLog.duration > 0 then
        local simcDur = simcLog.duration
        -- Compare each spell against SimC
        local simcComparisons = {}
        for _, log in ipairs(selectedLogs) do
            if not log.isSimC and log.damageData and log.duration and log.duration > 0 then
                for spell, d in pairs(log.damageData) do
                    local actualDps = (d.total or 0) / log.duration
                    local simcEntry = simcLog.damageData[spell]
                    local simcDps = simcEntry and ((simcEntry.total or 0) / simcDur) or 0
                    if simcDps > 0 then
                        local ratio = actualDps / simcDps
                        if not simcComparisons[spell] then simcComparisons[spell] = { sum = 0, count = 0 } end
                        simcComparisons[spell].sum = simcComparisons[spell].sum + ratio
                        simcComparisons[spell].count = simcComparisons[spell].count + 1
                    end
                end
            end
        end

        -- Compact SimC comparison (sorted worst→best)
        local simcSorted = {}
        for spell, stats in pairs(simcComparisons) do
            local pct = math.floor((stats.sum / stats.count) * 100 + 0.5)
            table.insert(simcSorted, {spell = spell, pct = pct})
        end
        table.sort(simcSorted, function(a, b) return a.pct < b.pct end)
        table.insert(lines, "\n  SimC comparison (% of target):")
        for _, s in ipairs(simcSorted) do
            local flag = s.pct < 85 and " << under" or (s.pct > 115 and " >> over" or "")
            table.insert(lines, string.format("    %s: %d%%%s", s.spell, s.pct, flag))
        end
        table.insert(lines, "\n  Use 'Generate Optimized' button to blend actual data with SimC targets.")
    else
        table.insert(lines, "\n  No SimC log in selection for target comparison.")
        table.insert(lines, "\n  Tips:")
        table.insert(lines, "  - Import a SimC report to compare actual vs target performance")
        table.insert(lines, "  - Select the best-performing log's sequence as your baseline")
        table.insert(lines, "  - Use 'Generate Optimized Sequence' with multiple logs to smooth RNG variance")
    end

    local comparisonText = table.concat(lines, "\n")

    -- Show in an export dialog-like text window
    local compWindow = CreateStyledFrame("Frame", nil, UIParent); trackDialog(compWindow)
    compWindow:SetSize(700, 550)
    compWindow:SetPoint("CENTER")
    compWindow:SetMovable(true)
    compWindow:SetClampedToScreen(true)
    compWindow:EnableMouse(true)
    compWindow:RegisterForDrag("LeftButton")
    compWindow:SetScript("OnDragStart", compWindow.StartMoving)
    compWindow:SetScript("OnDragStop", compWindow.StopMovingOrSizing)
    ApplyBackdrop(compWindow, false)

    local titleBar = CreateStyledFrame("Frame", nil, compWindow)
    titleBar:SetPoint("TOPLEFT", compWindow, "TOPLEFT")
    titleBar:SetPoint("TOPRIGHT", compWindow, "TOPRIGHT")
    titleBar:SetHeight(36)
    titleBar:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
    titleBar:SetBackdropColor(C.title[1], C.title[2], C.title[3], C.title[4])
    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    SafeSetFont(titleText, BOLD_FONT, 15)
    titleText:SetText("Sequence Comparison")
    titleText:SetPoint("CENTER")
    titleText:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])

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
    closeBtn:SetScript("OnClick", function() compWindow:Hide() end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, compWindow, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", compWindow, "TOPLEFT", 25, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", compWindow, "BOTTOMRIGHT", -25, 50)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetTextColor(1, 1, 1, 1)
    editBox:SetWidth(620)
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetScript("OnEscapePressed", function() editBox:ClearFocus() end)
    scrollFrame:SetScrollChild(editBox)

    editBox:SetText(comparisonText)
    local lineCount = 1
    for _ in string.gmatch(comparisonText, "\n") do lineCount = lineCount + 1 end
    editBox:SetHeight(math.max(200, lineCount * 14 + 20))
    editBox:SetCursorPosition(0)
    scrollFrame:SetVerticalScroll(0)

    -- "Generate Optimized" button with smart aggregation
    local optBtn = CreateStyledButton(compWindow, "Generate Optimized Sequence", 200, 28, function()
        -- Smart optimization across multiple logs
        local spellDps = {}
        local spellDpe = {}
        local totalDuration = 0
        local hasSimC = false
        local simcDps = {}
        local simcLog = nil

        for _, log in ipairs(selectedLogs) do
            local dur = (log.duration or 1) > 0 and log.duration or 1
            totalDuration = totalDuration + dur
            if log.isSimC then
                hasSimC = true
                simcLog = log
            end
            -- Per-spell DPS contribution for this log
            if log.damageData and log.castCounts then
                for spell, d in pairs(log.damageData) do
                    local spellDpsVal = (d.total or 0) / dur
                    if not spellDps[spell] then
                        spellDps[spell] = { sum = 0, weight = 0 }
                    end
                    spellDps[spell].sum = spellDps[spell].sum + spellDpsVal * dur
                    spellDps[spell].weight = spellDps[spell].weight + dur
                end
                for spell, count in pairs(log.castCounts) do
                    local dmgTotal = (log.damageData[spell] and log.damageData[spell].total) or 0
                    local dpe = count > 0 and (dmgTotal / count) or 0
                    if not spellDpe[spell] then
                        spellDpe[spell] = { sum = 0, weight = 0 }
                    end
                    spellDpe[spell].sum = spellDpe[spell].sum + dpe * count
                    spellDpe[spell].weight = spellDpe[spell].weight + count
                end
            end
        end

        -- Extract SimC per-spell DPS for comparison
        if hasSimC and simcLog and simcLog.damageData and simcLog.duration and simcLog.duration > 0 then
            for spell, d in pairs(simcLog.damageData) do
                simcDps[spell] = (d.total or 0) / simcLog.duration
            end
        end

        -- Build weighted cast counts and damage data
        local aggCast = {}
        local aggDmg = {}
        local sortedByDps = {}

        for spell, stats in pairs(spellDps) do
            local avgDps = stats.weight > 0 and (stats.sum / stats.weight) or 0
            local avgDpe = spellDpe[spell] and spellDpe[spell].weight > 0 and (spellDpe[spell].sum / spellDpe[spell].weight) or 0

            -- Count total casts
            local totalCasts = 0
            for _, log in ipairs(selectedLogs) do
                if log.castCounts and log.castCounts[spell] then
                    totalCasts = totalCasts + log.castCounts[spell]
                end
            end

            -- Compute blended DPS: weight actual performance, but boost spells that match SimC targets
            local blendedDps = avgDps
            if hasSimC and simcDps[spell] and simcDps[spell] > 0 then
                local ratio = avgDps / simcDps[spell]
                -- If underperforming SimC by more than 20%, flag it but keep position based on actual data
                -- If overperforming (ratio > 1.1), it's performing well — weight actual more
                if ratio < 0.8 then
                    blendedDps = avgDps * 0.6 + simcDps[spell] * 0.4
                elseif ratio > 1.1 then
                    blendedDps = avgDps * 0.8 + simcDps[spell] * 0.2
                else
                    blendedDps = avgDps * 0.7 + simcDps[spell] * 0.3
                end
            end

            table.insert(sortedByDps, {
                spell = spell,
                avgDps = avgDps,
                blendedDps = blendedDps,
                totalCasts = totalCasts,
                avgDpe = avgDpe,
            })

            -- Build damageData structure with normalized total
            aggDmg[spell] = {
                total = math.floor(blendedDps * totalDuration),
                hits = totalCasts,
                avg = math.floor(avgDpe),
            }
            aggCast[spell] = totalCasts
        end

        -- Include zero-damage rotational spells (buffs, cooldowns) that have casts but no damage entry
        for _, log in ipairs(selectedLogs) do
            if log.castCounts then
                for spell, count in pairs(log.castCounts) do
                    if not aggCast[spell] and count > 0 and IsValidMacroSpell(spell) then
                        local totalCasts = 0
                        for _, l in ipairs(selectedLogs) do
                            if l.castCounts and l.castCounts[spell] then
                                totalCasts = totalCasts + l.castCounts[spell]
                            end
                        end
                        aggCast[spell] = totalCasts
                        aggDmg[spell] = { total = 0, hits = totalCasts, avg = 0 }
                        table.insert(sortedByDps, { spell = spell, avgDps = 0, blendedDps = 0, totalCasts = totalCasts })
                    end
                end
            end
        end

        -- Aggregate buff uptime across all selected logs so defensive/buff spells
        -- (Shield Block, Ignore Pain, etc.) get uptime bonuses in the scoring
        local aggBuff = {}
        for _, log in ipairs(selectedLogs) do
            if log.buffUptime then
                for name, buff in pairs(log.buffUptime) do
                    local uptime = buff.uptime or 0
                    if uptime > 0 then
                        local cur = aggBuff[name]
                        if not cur or uptime > cur.uptime then
                            aggBuff[name] = { name = name, uptime = uptime }
                        end
                    end
                end
            end
        end

        -- Log analysis for the comparison text update
        table.sort(sortedByDps, function(a, b) return (a.blendedDps or 0) > (b.blendedDps or 0) end)

        ShowExportDialog(aggCast, aggDmg, aggBuff, totalDuration, true)
    end, "primary")
    optBtn:SetPoint("BOTTOMLEFT", compWindow, "BOTTOMLEFT", 20, 8)

    -- "Use Best Log" button: opens export dialog with the best-performing log's data
    local bestLog = nil
    local bestDps = 0
    for _, log in ipairs(selectedLogs) do
        if not log.isSimC and (log.dps or 0) > bestDps then
            bestDps = log.dps or 0
            bestLog = log
        end
    end
    local bestBtn = CreateStyledButton(compWindow, "Suggest Best Log", 180, 28, function()
        if bestLog then
            local bGaps = bestLog.buffGaps or {}
            ShowExportDialog(bestLog.castCounts, bestLog.damageData, bestLog.buffUptime, bestLog.duration, true, bGaps)
        end
    end, "secondary")
    bestBtn:SetPoint("LEFT", optBtn, "RIGHT", 10, 0)

    RegisterAddonWindow(compWindow)
    compWindow:Show()
end

-- ============================================
-- EMS EXPORT STANDALONE WINDOW
-- ============================================
local emsWindow = nil
local function ShowEMSExportWindow()
    if mainFrame then mainFrame:Hide() end
    if emsWindow then
        if emsWindow.refresh then emsWindow.refresh() end
        RegisterAddonWindow(emsWindow)
        emsWindow:Show()
        return
    end

    emsWindow = CreateStyledFrame("Frame", "DummyAnalyzerEMSExport", UIParent); trackDialog(emsWindow)
    emsWindow:SetSize(580, 640)
    emsWindow:SetPoint("CENTER")
    emsWindow:SetMovable(true)
    emsWindow:SetClampedToScreen(true)
    emsWindow:EnableMouse(true)
    emsWindow:RegisterForDrag("LeftButton")
    emsWindow:SetScript("OnDragStart", emsWindow.StartMoving)
    emsWindow:SetScript("OnDragStop", emsWindow.StopMovingOrSizing)
    ApplyBackdrop(emsWindow, false)

    local titleBar = CreateStyledFrame("Frame", nil, emsWindow)
    titleBar:SetPoint("TOPLEFT", emsWindow, "TOPLEFT")
    titleBar:SetPoint("TOPRIGHT", emsWindow, "TOPRIGHT")
    titleBar:SetHeight(36)
    titleBar:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
    titleBar:SetBackdropColor(C.title[1], C.title[2], C.title[3], C.title[4])
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() emsWindow:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() emsWindow:StopMovingOrSizing() end)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    SafeSetFont(titleText, BOLD_FONT, 15)
    titleText:SetText("Export EMS Sequence")
    titleText:SetPoint("CENTER")
    titleText:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])

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
    closeBtn:SetScript("OnClick", function() emsWindow:Hide() end)

    local instrText = emsWindow:CreateFontString(nil, "OVERLAY")
    SafeSetFont(instrText, MAIN_FONT, 11)
    instrText:SetText("Click to toggle selection (select multiple). Single = export, Multiple = merge & optimize.")
    instrText:SetPoint("TOPLEFT", emsWindow, "TOPLEFT", 20, -48)
    instrText:SetTextColor(C.text[1], C.text[2], C.text[3], C.text[4])

    -- Top toolbar: Select All + Delete Selected
    local topSelectAll = CreateStyledButton(emsWindow, "Select All", 90, 22, function()
        for _, row in ipairs(emsWindow.rows or {}) do
            row.selected = true
            row.btn:SetBackdropColor(C.selected[1], C.selected[2], C.selected[3], C.selected[4])
            row.cb:SetText("[x]")
            row.cb:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])
        end
    end, "secondary")
    topSelectAll:SetPoint("TOPLEFT", instrText, "BOTTOMLEFT", 0, -6)

    local RefreshEMSLogList
    local topDeleteBtn = CreateStyledButton(emsWindow, "Delete Selected", 110, 22, function()
        local toDelete = {}
        for _, row in ipairs(emsWindow.rows or {}) do
            if row.selected then table.insert(toDelete, row.logId) end
        end
        if #toDelete == 0 then
            print("|cff33ff33[DummyAnalyzer]|r Select logs to delete.")
            return
        end
        local delDb = GetCharDB()
        for _, delId in ipairs(toDelete) do
            for i, log in ipairs(delDb.logs) do
                if log.id == delId then
                    if log.isSimC then delDb.simcLogId = 0 end
                    table.remove(delDb.logs, i)
                    break
                end
            end
        end
        RefreshEMSLogList()
        local sf = _G["DummyAnalyzerSavedLogsFrame"]
        if sf and sf:IsShown() and sf.refresh then sf.refresh() end
        print(string.format("|cff33ff33[DummyAnalyzer]|r Deleted %d log(s).", #toDelete))
    end, "danger")
    topDeleteBtn:SetPoint("LEFT", topSelectAll, "RIGHT", 6, 0)

    local scrollFrame = CreateFrame("ScrollFrame", nil, emsWindow, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", emsWindow, "TOPLEFT", 20, -115)
    scrollFrame:SetPoint("BOTTOMRIGHT", emsWindow, "BOTTOMRIGHT", -40, 50)

    local listContainer = CreateFrame("Frame", nil, scrollFrame)
    listContainer:SetWidth(480)
    scrollFrame:SetScrollChild(listContainer)

    emsWindow.scrollFrame = scrollFrame
    emsWindow.listContainer = listContainer
    emsWindow.rows = {}

    function RefreshEMSLogList()
        local logs = GetCharDB().logs or {}
        local container = emsWindow.listContainer
        for _, row in ipairs(emsWindow.rows or {}) do
            row.btn:Hide()
        end
        emsWindow.rows = {}
        local prevBtn = nil
        for i, log in ipairs(logs) do
            local label = log.label or ("Log #" .. log.id)
            local specName = log.specName or ""
            local elapsed = log.duration or 0
            local dps = log.dps or 0
            local isSimC = log.isSimC
            local hasEMS = log.emsSeqText and log.emsSeqText ~= "" and not isSimC
            local text = string.format("%s | %s | %.1fs | %s DPS", label, specName, elapsed, Addon.FormatNumber(dps))
            if isSimC then
                text = "|cff00ccff[SimC]|r " .. text
            else
                if hasEMS then text = text .. " [EMS]" end
                if log.detectedSeqName then text = text .. string.format(" [GRIP: %s]", log.detectedSeqName) end
            end
            local btn = CreateStyledFrame("Button", nil, container)
            btn:SetSize(460, 24)
            btn:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
            if isSimC then
                btn:SetBackdropColor(C.title[1], C.title[2], C.title[3], C.title[4])
            else
                btn:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
            end
            if prevBtn then
                btn:SetPoint("TOPLEFT", prevBtn, "BOTTOMLEFT", 0, -2)
            else
                btn:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            end
            local cb = btn:CreateFontString(nil, "OVERLAY")
            SafeSetFont(cb, MAIN_FONT, 11)
            cb:SetText("[ ]")
            cb:SetPoint("LEFT", btn, "LEFT", 4, 0)
            cb:SetTextColor(0.6, 0.6, 0.6, 1)
            local txt = btn:CreateFontString(nil, "OVERLAY")
            SafeSetFont(txt, MAIN_FONT, 11)
            txt:SetText(" " .. text)
            txt:SetPoint("LEFT", cb, "RIGHT", 2, 0)
            txt:SetTextColor(C.text[1], C.text[2], C.text[3], C.text[4])
            btn.logId = log.id
            btn:SetScript("OnClick", function(self)
                local row = nil
                for _, r in ipairs(emsWindow.rows or {}) do
                    if r.btn == self then row = r break end
                end
                if not row then return end
                row.selected = not row.selected
                row.btn:SetBackdropColor(
                    row.selected and 0.20 or 0.10,
                    row.selected and 0.40 or 0.10,
                    row.selected and 0.65 or 0.14,
                    1
                )
                row.cb:SetText(row.selected and "[x]" or "[ ]")
                row.cb:SetTextColor(row.selected and 1.0 or 0.6, row.selected and 0.82 or 0.6, row.selected and 0.08 or 0.6, 1)
            end)
            table.insert(emsWindow.rows, {btn = btn, cb = cb, logId = log.id, selected = false})
            prevBtn = btn
        end
        local containerHeight = #logs * 26 + 10
        container:SetHeight(math.max(100, containerHeight))
    end
    emsWindow.refresh = RefreshEMSLogList

    -- Suggest Sequence: aggregates selected logs and generates a human-style Priority sequence
    local genBtn = CreateStyledButton(emsWindow, "Suggest", 110, 28, function()
        local selectedIds = {}
        for _, row in ipairs(emsWindow.rows or {}) do
            if row.selected then table.insert(selectedIds, row.logId) end
        end
        if #selectedIds == 0 then
            print("|cff33ff33[DummyAnalyzer]|r Select a log to analyze.")
            return
        end
        local logs = GetCharDB().logs or {}
        local aggCast, aggDmg, aggBuff, aggGaps = {}, {}, {}, {}
        local totalDuration = 0
        for _, log in ipairs(logs) do
            for _, lid in ipairs(selectedIds) do
                if log.id == lid then
                    if log.castCounts then
                        for name, count in pairs(log.castCounts) do
                            if IsValidMacroSpell(name) then
                                aggCast[name] = (aggCast[name] or 0) + count
                            end
                        end
                    end
                    if log.damageData then
                        for name, d in pairs(log.damageData) do
                            local cur = aggDmg[name] or {total = 0, hits = 0}
                            cur.total = cur.total + (d.total or 0)
                            cur.hits = cur.hits + (d.hits or 0)
                            aggDmg[name] = cur
                        end
                    end
                    if log.buffUptime then
                        for key, buff in pairs(log.buffUptime) do
                            local uptime = buff.uptime or 0
                            if uptime > 0 then
                                local cur = aggBuff[key]
                                if not cur or uptime > cur.uptime then
                                    aggBuff[key] = { name = buff.name or key, uptime = uptime }
                                end
                            end
                        end
                    end
                    if log.buffGaps then
                        for key, data in pairs(log.buffGaps) do
                            if data.gaps and #data.gaps > 0 then
                                local cur = aggGaps[key]
                                if not cur then
                                    aggGaps[key] = { name = data.name or key, gaps = {} }
                                    cur = aggGaps[key]
                                end
                                for _, g in ipairs(data.gaps) do
                                    table.insert(cur.gaps, g)
                                end
                            end
                        end
                    end
                    local dur = log.duration or 0
                    totalDuration = totalDuration + dur
                    break
                end
            end
        end
        ShowExportDialog(aggCast, aggDmg, aggBuff, totalDuration, true, aggGaps, selectedIds)
end, "secondary")
      genBtn:SetPoint("BOTTOMLEFT", emsWindow, "BOTTOMLEFT", 20, 8)

      local compBtn = CreateStyledButton(emsWindow, "Compare", 110, 28, function()
          local selectedIds = {}
          for _, row in ipairs(emsWindow.rows or {}) do
              if row.selected then table.insert(selectedIds, row.logId) end
          end
          if #selectedIds < 2 then
              print("|cff33ff33[DummyAnalyzer]|r Select at least 2 logs to compare.")
              return
          end
          ShowEMSComparison(selectedIds)
      end, "secondary")
      compBtn:SetPoint("LEFT", genBtn, "RIGHT", 5, 0)

    local simcBtn = CreateStyledButton(emsWindow, "SimC Import", 125, 28, function()
        ShowSimCImportDialog()
    end, "secondary")
    simcBtn:SetPoint("LEFT", compBtn, "RIGHT", 5, 0)

    local debugBtn = CreateStyledButton(emsWindow, "Debug", 80, 28, function()
        ShowDebugReport()
    end, "tertiary")
    debugBtn:SetPoint("LEFT", simcBtn, "RIGHT", 5, 0)

    local clogBtn = CreateStyledButton(emsWindow, "CL Import", 100, 28, Addon.ShowCombatLogImportDialog, "secondary")
    clogBtn:SetPoint("LEFT", debugBtn, "RIGHT", 5, 0)

    RefreshEMSLogList()
    RegisterAddonWindow(emsWindow)
    emsWindow:Show()
end

function ShowDebugReport()
    local db = GetCharDB()
    local sd = db.simcData
    local lines = {}

    lines[#lines+1] = "=== SimC Reference Debug Report ==="
    lines[#lines+1] = "SimC Log ID: " .. tostring(db.simcLogId or "none")
    lines[#lines+1] = ""

    lines[#lines+1] = "--- APL Order (" .. tostring(sd and #sd.aplOrder or 0) .. ") ---"
    if sd and sd.aplOrder then
        for i, name in ipairs(sd.aplOrder) do
            lines[#lines+1] = string.format("  %d. %s", i, name)
        end
    else
        lines[#lines+1] = "  (none)"
    end
    lines[#lines+1] = ""

    local rawAplStr = sd and sd.rawApl or ""
    local rawLines = {}
    if rawAplStr ~= "" then
        for line in rawAplStr:gmatch("[^\r\n]+") do
            rawLines[#rawLines+1] = line
        end
    end
    lines[#lines+1] = "--- Raw APL Lines (" .. tostring(#rawLines) .. ") ---"
    for i, line in ipairs(rawLines) do
        if #line > 240 then line = line:sub(1, 240) .. "..." end
        lines[#lines+1] = string.format("  %d. %s", i, line)
    end
    lines[#lines+1] = ""

    lines[#lines+1] = "--- SimC Cast Counts ---"
    local simcCasts = {}
    if db.simcLogId and db.simcLogId > 0 then
        for _, l in ipairs(db.logs or {}) do
            if l.id == db.simcLogId and l.isSimC and l.castCounts then
                for name, count in pairs(l.castCounts) do
                    if IsValidMacroSpell(name) then simcCasts[name] = count end
                end
                break
            end
        end
    end
    local sorted = {}
    for name, count in pairs(simcCasts) do sorted[#sorted+1] = {name, count} end
    table.sort(sorted, function(a, b) return a[2] > b[2] end)
    for _, pair in ipairs(sorted) do
        lines[#lines+1] = string.format("  %s = %.0f", pair[1], pair[2])
    end
    lines[#lines+1] = ""

    lines[#lines+1] = "--- Player Spells in SimC ---"
    for _, pair in ipairs(sorted) do
        local valid = IsValidMacroSpell(pair[1])
        lines[#lines+1] = string.format("  %s (valid=%s)", pair[1], tostring(valid))
    end

    local text = table.concat(lines, "\n")

    local frame = CreateStyledFrame("Frame", nil, UIParent)
    frame:SetSize(750, 600)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    ApplyBackdrop(frame, false)

    local titleBar = CreateStyledFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT")
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
    titleBar:SetHeight(36)
    titleBar:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
    titleBar:SetBackdropColor(C.title[1], C.title[2], C.title[3], C.title[4])
    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    SafeSetFont(titleText, BOLD_FONT, 15)
    titleText:SetText("Debug Report")
    titleText:SetPoint("CENTER")
    titleText:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])

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
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 25, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -25, 40)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetTextColor(1, 1, 1, 1)
    editBox:SetWidth(680)
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetScript("OnEscapePressed", function() editBox:ClearFocus() end)
    scrollFrame:SetScrollChild(editBox)
    editBox:SetText(text)

    local bottomRow = CreateFrame("Frame", nil, frame)
    bottomRow:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 8)
    bottomRow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 8)
    bottomRow:SetHeight(32)

    local copyBtn = CreateStyledButton(bottomRow, "Copy All", 100, 32, function()
        local txt = editBox:GetText()
        if txt and txt ~= "" then
            C_Timer.After(0.1, function()
                editBox:SetFocus()
                editBox:HighlightText()
                editBox:SetCursorPosition(0)
            end)
        end
        print("|cff33ff33[DummyAnalyzer]|r Debug report copied to clipboard (Ctrl+V to paste).")
    end, "primary")
    copyBtn:SetPoint("LEFT", bottomRow, "LEFT", 0, 0)

    local closeBtn2 = CreateStyledButton(bottomRow, "Close", 100, 32, function() frame:Hide() end, "danger")
    closeBtn2:SetPoint("RIGHT", bottomRow, "RIGHT", 0, 0)

    frame:Show()
end

local mainFrame = nil
local function CreateMainFrame()
    if mainFrame then return mainFrame end
    mainFrame = CreateStyledFrame("Frame", "DummyAnalyzerMainFrame", UIParent)
    mainFrame:SetSize(400, 360)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetMovable(true)
    mainFrame:SetClampedToScreen(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
    ApplyBackdrop(mainFrame, false)

    local titleBar = CreateStyledFrame("Frame", nil, mainFrame)
    titleBar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT")
    titleBar:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT")
    titleBar:SetHeight(36)
    titleBar:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
    titleBar:SetBackdropColor(C.title[1], C.title[2], C.title[3], C.title[4])
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() mainFrame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() mainFrame:StopMovingOrSizing() end)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    SafeSetFont(titleText, BOLD_FONT, 15)
    titleText:SetText("Dummy Analyzer")
    titleText:SetPoint("CENTER", titleBar, "CENTER")
    titleText:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])

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
    closeBtn:SetScript("OnClick", function() mainFrame:Hide() end)

    local content = CreateFrame("Frame", nil, mainFrame)
    content:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 15, -15)
    content:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -15, 15)

    local instrText = content:CreateFontString(nil, "OVERLAY")
    SafeSetFont(instrText, MAIN_FONT, 11)
    instrText:SetText("Select test duration and hit the training dummy:")
    instrText:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -5)

    local timeOptions = {{text = "30 Sec", minutes = 0.5}, {text = "2 Min", minutes = 2}, {text = "5 Min", minutes = 5}}
    local lastBtn = nil
    for i, opt in ipairs(timeOptions) do
        local btn = CreateStyledButton(content, opt.text, 80, 32, function() StartTest(opt.minutes) end, "primary")
        btn:SetPoint("TOPLEFT", instrText, "BOTTOMLEFT", (i-1)*90, -15)
        lastBtn = btn
    end

    local stopBtn = CreateStyledButton(content, "Stop Test", 100, 32, StopTest, "danger")
    stopBtn:SetPoint("LEFT", lastBtn, "RIGHT", 15, 0)
    CreateSeparator(content, "TOPLEFT", stopBtn, "BOTTOMLEFT", 0, -25)

    local savedLogsBtn = CreateStyledButton(content, "Compare Logs", 130, 32, function()
        if mainFrame then mainFrame:Hide() end
        CreateSavedLogsBrowser()
    end, "primary")
    savedLogsBtn:SetPoint("TOPLEFT", instrText, "BOTTOMLEFT", 0, -70)

    local emsBtn = CreateStyledButton(content, "Export Sequence", 140, 32, function()
        if mainFrame then mainFrame:Hide() end
        ShowEMSExportWindow()
    end, "primary")
    emsBtn:SetPoint("LEFT", savedLogsBtn, "RIGHT", 10, 0)

    return mainFrame
end

-- ============================================
-- COMBAT LOG IMPORT
-- ============================================
local function SplitCL(line)
    local fields = {}
    local i = 1
    while i <= #line do
        local c = line:sub(i, i)
        if c == '"' then
            local close = line:find('"', i + 1)
            while close and line:sub(close + 1, close + 1) == '"' do
                close = line:find('"', close + 2)
            end
            if close then
                fields[#fields + 1] = line:sub(i + 1, close - 1)
                i = close + 1
                if line:sub(i, i) == ',' then i = i + 1 end
            else
                fields[#fields + 1] = line:sub(i + 1)
                break
            end
        elseif c == ',' then
            fields[#fields + 1] = ""
            i = i + 1
        else
            local nxt = line:find(',', i)
            if nxt then
                fields[#fields + 1] = line:sub(i, nxt - 1)
                i = nxt + 1
            else
                fields[#fields + 1] = line:sub(i)
                break
            end
        end
    end
    return fields
end

function Addon.ParseCombatLogAsync(text, callback)
    if not text or #text == 0 then callback(nil) return end
    local pName, pRealm = UnitName("player"), GetRealmName()
    local pFull = pName and pRealm and (pName .. "-" .. pRealm) or pName
    local hist, cCounts, dmgData = {}, {}, {}
    local totalDmg, firstSec = 0, nil

    local lines, n = {}, 0
    for line in text:gmatch("[^\r\n]+") do
        n = n + 1; lines[n] = line
    end
    if n == 0 then callback(nil) return end

    local idx, CHUNK = 1, 300
    local function chk()
        local endIdx = idx + CHUNK - 1
        if endIdx > n then endIdx = n end
        for i = idx, endIdx do
            local line = lines[i]
            if line ~= "" and not line:match("^COMBAT_LOG_VERSION") and not line:match("^ZONE_") and not line:match("^MAP_") and not line:match("^ENCOUNTER_") then
                local evStart = line:find("SPELL_") or line:find("SWING_") or line:find("RANGE_")
                if evStart then
                    local h, m, s, ms = line:match("(%d+):(%d+):(%d+)%.(%d+)")
                    if h then
                        local sec = tonumber(h)*3600 + tonumber(m)*60 + tonumber(s) + tonumber(ms)/1000
                        if not firstSec then firstSec = sec end
                        local elapsed = sec - firstSec
                        local fields = SplitCL(line:sub(evStart))
                        if #fields >= 12 then
                            local evt, srcName = fields[1], fields[3]
                            if srcName == pName or srcName == pFull then
                                local spellId, spellName = tonumber(fields[9]) or 0, fields[10] or "Unknown"
                                if evt == "SPELL_CAST_SUCCESS" then
                                    local pType, curPow, maxPow = tonumber(fields[23]), tonumber(fields[24]), tonumber(fields[25])
                                    hist[#hist + 1] = {
                                        spell = spellName, spellId = spellId, time = elapsed,
                                        power = (pType and curPow) and { type = pType, current = curPow, max = maxPow } or nil,
                                    }
                                    cCounts[spellName] = (cCounts[spellName] or 0) + 1
                                elseif evt:match("_DAMAGE$") and not evt:match("_CAST_") and not evt:match("_AURA_") then
                                    local amount = tonumber(fields[32]) or 0
                                    if amount > 0 then
                                        local d = dmgData[spellName] or { total = 0, hits = 0 }
                                        d.total = d.total + amount; d.hits = d.hits + 1
                                        dmgData[spellName] = d; totalDmg = totalDmg + amount
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        idx = endIdx + 1
        if idx > n then
            if #hist == 0 then callback(nil) return end
            local dur = hist[#hist].time + 0.5
            callback({
                spellHistory = hist, castCounts = cCounts, damageData = dmgData,
                totalDamage = totalDmg, totalCasts = #hist, duration = dur,
                dps = dur > 0 and math.floor(totalDmg / dur) or 0,
            })
        else
            C_Timer.After(0, chk)
        end
    end
    chk()
end

function Addon.ShowCombatLogImportDialog()
    if clogDialog then clogDialog:Hide(); clogDialog = nil end

    clogDialog = CreateStyledFrame("Frame", "DummyAnalyzerCLImport", UIParent); trackDialog(clogDialog)
    clogDialog:SetSize(600, 480)
    clogDialog:SetPoint("CENTER")
    clogDialog:SetFrameStrata("DIALOG")
    clogDialog:SetMovable(true)
    clogDialog:SetClampedToScreen(true)
    clogDialog:EnableMouse(true)
    clogDialog:RegisterForDrag("LeftButton")
    clogDialog:SetScript("OnDragStart", clogDialog.StartMoving)
    clogDialog:SetScript("OnDragStop", clogDialog.StopMovingOrSizing)
    ApplyBackdrop(clogDialog, false)

    local titleBar = CreateStyledFrame("Frame", nil, clogDialog)
    titleBar:SetPoint("TOPLEFT", clogDialog, "TOPLEFT")
    titleBar:SetPoint("TOPRIGHT", clogDialog, "TOPRIGHT")
    titleBar:SetHeight(36)
    titleBar:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
    titleBar:SetBackdropColor(C.title[1], C.title[2], C.title[3], C.title[4])
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() clogDialog:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() clogDialog:StopMovingOrSizing() end)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    SafeSetFont(titleText, BOLD_FONT, 15)
    titleText:SetText("Import Combat Log")
    titleText:SetPoint("CENTER")
    titleText:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])

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
    closeBtn:SetScript("OnClick", function() clogDialog:Hide() end)

    local instrText = clogDialog:CreateFontString(nil, "OVERLAY")
    SafeSetFont(instrText, MAIN_FONT, 11)
    instrText:SetText("Paste /combatlog file content below (Ctrl+V) then click Import:")
    instrText:SetPoint("TOPLEFT", clogDialog, "TOPLEFT", 20, -50)
    instrText:SetTextColor(C.text[1], C.text[2], C.text[3], C.text[4])

    local statusText = clogDialog:CreateFontString(nil, "OVERLAY")
    SafeSetFont(statusText, MAIN_FONT, 11)
    statusText:SetText("")
    statusText:SetPoint("TOPLEFT", clogDialog, "TOPLEFT", 20, -65)
    statusText:SetTextColor(0.5, 1.0, 0.5, 1)

    local scrollFrame = CreateFrame("ScrollFrame", nil, clogDialog, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", clogDialog, "TOPLEFT", 22, -87)
    scrollFrame:SetPoint("BOTTOMRIGHT", clogDialog, "BOTTOMRIGHT", -22, 50)
    scrollFrame:SetClipsChildren(true)
    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetTextColor(1, 1, 1, 1)
    editBox:SetWidth(510)
    editBox:SetHeight(400)
    editBox:SetAutoFocus(true)
    editBox:EnableMouse(true)
    scrollFrame:SetScript("OnMouseDown", function() editBox:SetFocus() end)
    editBox:SetScript("OnEscapePressed", function() editBox:ClearFocus() end)
    editBox:SetScript("OnEditFocusGained", function()
        statusText:SetTextColor(0.5, 1.0, 0.5, 1)
        statusText:SetText("Paste combat log output (Ctrl+V) then click Import")
    end)
    editBox:SetScript("OnEditFocusLost", function()
        if editBox and #(editBox:GetText() or "") == 0 then
            statusText:SetText("")
        end
    end)
    editBox:SetScript("OnTextChanged", function()
        local text = editBox:GetText() or ""
        local len = #text
        if len > 0 then
            local lines = select(2, text:gsub("\n", "\n")) + 1
            statusText:SetText(string.format("Pasted: %d chars (%d lines). Click Import.", len, lines))
        end
    end)
    scrollFrame:SetScrollChild(editBox)
    editBox:SetHeight(300)

    local function doImport()
        local text = editBox:GetText() or ""
        if not text or text == "" then
            print("|cff33ff33[DummyAnalyzer]|r Paste combat log content first.")
            return
        end
        statusText:SetText("Parsing combat log...")
        importBtn:Disable()
        Addon.ParseCombatLogAsync(text, function(parsed)
            if not parsed then
                print("|cff33ff33[DummyAnalyzer]|r Could not parse combat log. Make sure you pasted the full /comatlog output with SPELL_CAST_SUCCESS lines.")
                statusText:SetText("")
                if importBtn then importBtn:Enable() end
                return
            end
        local db = GetCharDB()
        local newId = db.nextId
        db.nextId = newId + 1
        local durStr = parsed.duration <= 120 and string.format("%.0fs", parsed.duration) or string.format("%.1fmin", parsed.duration / 60)
        table.insert(db.logs, {
            id = newId,
            label = "CL: " .. durStr .. " " .. Addon.FormatNumber(parsed.dps) .. " DPS",
            timestamp = time(),
            date = date("%Y-%m-%d %H:%M"),
            duration = parsed.duration,
            totalDamage = parsed.totalDamage,
            totalCasts = parsed.totalCasts,
            dps = parsed.dps,
            castCounts = parsed.castCounts,
            damageData = parsed.damageData,
            spellHistory = parsed.spellHistory,
            notes = "Imported from /combatlog",
        })
        clogDialog:Hide()
        RefreshSavedLogsList()
        if emsWindow and emsWindow.refresh then emsWindow.refresh() end
        print(string.format("|cff33ff33[DummyAnalyzer]|r Imported combat log: %d casts, %d DPS (%s)", parsed.totalCasts, parsed.dps, durStr))
        end)
    end

    local bottomBar = CreateStyledFrame("Frame", nil, clogDialog)
    bottomBar:SetPoint("BOTTOMLEFT", clogDialog, "BOTTOMLEFT", 0, 0)
    bottomBar:SetPoint("BOTTOMRIGHT", clogDialog, "BOTTOMRIGHT", 0, 0)
    bottomBar:SetHeight(45)
    bottomBar:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
    bottomBar:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
    bottomBar:SetFrameLevel(clogDialog:GetFrameLevel() + 5)

    local importBtn = CreateStyledButton(bottomBar, "Import", 100, 30, doImport, "primary")
    importBtn:SetPoint("RIGHT", bottomBar, "CENTER", -55, 0)
    importBtn:SetFrameLevel(bottomBar:GetFrameLevel() + 2)

    local cancelBtn = CreateStyledButton(bottomBar, "Cancel", 100, 30, function() clogDialog:Hide() end)
    cancelBtn:SetPoint("LEFT", bottomBar, "CENTER", 55, 0)
    cancelBtn:SetFrameLevel(bottomBar:GetFrameLevel() + 2)

    RegisterAddonWindow(clogDialog)
    clogDialog:Show()
    C_Timer.After(0, function() if editBox and editBox.SetFocus then editBox:SetFocus() end end)
end

-- ============================================
-- COMBAT‑SAFE EVENT REGISTRATION
-- ============================================
local spellFrame = nil
local spellRegistered = false

local function RegisterSpellEvents()
    if spellRegistered then return true end
    if InCombatLockdown and InCombatLockdown() then
        return false
    end
    if not spellFrame then
        spellFrame = CreateFrame("Frame")
    end
    spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    spellFrame:SetScript("OnEvent", function(self, event, unit, castGUID, spellId)
        if event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" and spellId then
            RecordSpell(spellId)
        end
    end)
    spellRegistered = true
    if debugMode then print("|cff33ff33[DummyAnalyzer Debug]|r Spell events registered.") end
    return true
end

-- Try to register events now, and retry every 1 second if in combat
local function SafeInit()
    if RegisterSpellEvents() then
        return
    end
    C_Timer.NewTicker(1.0, function(ticker)
        if RegisterSpellEvents() then
            ticker:Cancel()
        end
    end)
end

-- ============================================
-- INITIALISATION (original)
-- ============================================
local minimapBtn = CreateFrame("Button", "DummyAnalyzerMinimapBtn", Minimap)
minimapBtn:SetSize(24, 24)
minimapBtn:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -4, -4)
minimapBtn:SetNormalTexture("Interface\\Icons\\INV_Misc_TargetDummy_01")
minimapBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
minimapBtn:SetScript("OnClick", function()
    local frame = CreateMainFrame()
    if frame:IsShown() then frame:Hide() else frame:Show() frame:Raise() end
end)
minimapBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(minimapBtn, "ANCHOR_RIGHT")
    GameTooltip:SetText("Dummy Analyzer")
    GameTooltip:AddLine("Click to open", 0.5, 0.8, 1)
    GameTooltip:Show()
end)
minimapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

SLASH_DUMMYANALYZER1 = "/dummy"
SlashCmdList["DUMMYANALYZER"] = function(msg)
    if msg == "" or msg == "show" then
        local frame = CreateMainFrame()
        if frame:IsShown() then frame:Hide() else frame:Show() frame:Raise() end
    elseif msg == "30" then StartTest(0.5)
    elseif msg == "2" then StartTest(2)
    elseif msg == "5" then StartTest(5)
    elseif msg == "stop" then StopTest()
    else
        print("|cff33ff33[DummyAnalyzer]|r Commands: /dummy [show|30|2|5|stop]")
    end
end

SLASH_DUMMYDEBUG1 = "/dummydebug"
SlashCmdList["DUMMYDEBUG"] = function(msg)
    msg = msg or ""
    local trimmed = msg:match("^%s*(.-)%s*$") or ""
    if trimmed == "dump" then
        if not DummyAnalyzerDB then print("|cff33ff33[DummyAnalyzer]|r DummyAnalyzerDB is nil"); return end
        local log = DummyAnalyzerDB._debugLog
        if not log or #log == 0 then
            print("|cff33ff33[DummyAnalyzer]|r Debug log is empty.")
            return
        end
        print(string.format("|cff33ff33[DummyAnalyzer]|r Debug log: %d entries. Type /reload so AI can read SavedVariables file.", #log))
    elseif trimmed == "clear" then
        if DummyAnalyzerDB then DummyAnalyzerDB._debugLog = {} end
        print("|cff33ff33[DummyAnalyzer]|r Debug log cleared.")
    else
        debugMode = not debugMode
        print("|cff33ff33[DummyAnalyzer]|r Debug mode " .. (debugMode and "|cff00ff00ENABLED" or "|cffff0000DISABLED"))
        print("|cff33ff33[DummyAnalyzer]|r Subcommands: /dummydebug (toggle), /dummydebug dump, /dummydebug clear")
    end
end

C_Timer.After(0, function()
    playerGUID = UnitGUID("player")
    local initDb = GetCharDB()
    if initDb.bestSequence then Addon.bestSequence = initDb.bestSequence end
    CreateMainFrame()
    CreateTimerFrame()
    timerFrame:Hide()
    updateFrame = CreateFrame("Frame")
    SafeInit()  -- registers spell events only when out of combat
    BuildSpellNameCache()
    if debugMode then
        local count = 0
        for _ in pairs(spellNameCache) do count = count + 1 end
        print("|cff33ff33[DummyAnalyzer Debug]|r Spell name cache built: " .. count .. " entries")
    end
    print("|cff33ff33[DummyAnalyzer]|r Loaded! /dummy | /dummydebug")
end)

-- ============================================
-- GRIP-EMS PLUGIN HANDSHAKE (Tier 0..5)
-- Registers DummyAnalyzer as a reversibly-owned addon.
-- Source of truth: jesperlive.github.io/GRIP-EMS-PluginAPI/reference/ai-context/
-- ============================================
local EMS_PLUGIN_ID = "dummyanalyzer"
local EMS_PLUGIN_NAME = "DummyAnalyzer EMS Plugin"
local EMS_PLUGIN_VERSION = "2.2.0"
emsPluginHandle = nil  -- populated by RegisterPlugin; nil until handshake succeeds
local emsContextCache = "none"
local emsLoadoutDirty = false

local function Ems_Default(value, fallback)
    if value == nil then return fallback end
    return value
end

local function Ems_BuildSequenceData(seqName, orderedSteps)
    -- orderedSteps: array of spell names (built by ParseSequenceLines at the Best/Next button click)
    -- Returns a full CreateSequence table: action tree (actions) + compiled flat steps.
    local cfgSf = (GetCharDB()).settings and (GetCharDB()).settings.stepFunction or "Priority"
    local cfg = (GetCharDB()).settings or {}
    local minInterleave = cfg.interleave or 0
    -- Count freqs per spell (dupes trigger interval)
    local freq = {}
    for _, spell in ipairs(orderedSteps or {}) do
        local s = tostring(spell or ""):gsub("^%s*/%a+%s+%[?combat%]?%s*", ""):gsub("%s*%(interval:%d+%)", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if s ~= "" then freq[s] = (freq[s] or 0) + 1 end
    end
    -- Interleave candidates: exact count when configured, auto-calc when 0
    local interleaveCandidates = {}
    if minInterleave > 0 then
        local sorted = {}
        for name, cnt in pairs(freq) do
            table.insert(sorted, {name = name, count = cnt})
        end
        table.sort(sorted, function(a, b) return a.count > b.count end)
        for i = 1, math.min(minInterleave, #sorted) do
            interleaveCandidates[sorted[i].name] = math.max(2, math.floor(#orderedSteps / sorted[i].count))
        end
    else
        local maxFreq = 0
        for _, cnt in pairs(freq) do
            if cnt > maxFreq then maxFreq = cnt end
        end
        for name, cnt in pairs(freq) do
            if cnt >= 5 and cnt >= maxFreq * 0.4 then
                interleaveCandidates[name] = math.max(2, math.floor(#orderedSteps / cnt))
            end
        end
    end
    local actions, macroSteps = {}, {}
    local intervalApplied = {}
    for _, spell in ipairs(orderedSteps or {}) do
        local s = tostring(spell or "")
        s = s:gsub("^%s*/%a+%s+%[?combat%]?%s*", ""):gsub("%s*%(interval:%d+%)", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if s ~= "" then
            local prefix = GetActionPrefix(s)
            local macro = prefix .. " [combat] " .. s
            local act = { type = "action", macro = macro }
            if interleaveCandidates[s] and not intervalApplied[s] then
                intervalApplied[s] = true
                act.interval = interleaveCandidates[s]
            end
            actions[#actions + 1] = act
            macroSteps[#macroSteps + 1] = macro
        end
    end
    local now = time()
    return {
        name = seqName,
        stepFunction = cfgSf,
        description = "Auto-generated by DummyAnalyzer heuristic (" .. tostring(#macroSteps) .. " steps, context=" .. tostring(emsContextCache) .. ")",
        author = "DummyAnalyzer",
        privacyMode = cfg.privacyMode or "private",
        createdAt = now,
        updatedAt = now,
        versions = {
            [1] = {
                version = "1.0",
                stepFunction = cfgSf,
                activeStepCount = #macroSteps,
                keyPress = cfg.keyPress or "/startattack",
                keyRelease = cfg.keyRelease or "",
                resetOnCombat = Ems_Default(cfg.resetOnCombat, true),
                resetOnTarget = Ems_Default(cfg.resetOnTarget, true),
                resetOnGear = Ems_Default(cfg.resetOnGear, false),
                resetOnSpec = Ems_Default(cfg.resetOnSpec, false),
                resetTimer = cfg.resetTimer or 0,
                repeatCount = cfg.repeatCount or 0,
                actions = actions,
                steps = macroSteps,
            },
        },
        defaultVersion = 1,
        activeVersionIndex = 1,
        contextVersionCount = 1,
    }
end

function Ems_EnsureHandle()
    if emsPluginHandle then return true end
    local API = GRIPEMS and GRIPEMS.API
    if not API then return false, "GRIPEMS.API not available" end
    if not API:RequireVersion(3) then return false, "EMS v3+ required" end
    local ok, handle = pcall(API.RegisterPlugin, API, EMS_PLUGIN_ID, {
        name = EMS_PLUGIN_NAME,
        version = EMS_PLUGIN_VERSION,
        OnEnable = DummyAnalyzer_EMS_OnEnable,
        OnDisable = DummyAnalyzer_EMS_OnDisable,
    })
    if ok and handle then
        emsPluginHandle = handle
        print("|cff33ff33[DummyAnalyzer EMS]|r Registered on-demand (id=" .. EMS_PLUGIN_ID .. ").")
        return true
    end
    return false, "RegisterPlugin failed: " .. tostring(handle)
end

function Ems_PushBestSequence(orderedSteps)
    if not emsPluginHandle then
        local ok, reason = Ems_EnsureHandle()
        if not ok then
            print("|cffff8844[DummyAnalyzer EMS]|r GRIP-EMS not ready: " .. tostring(reason) .. ". Reload after EMS is loaded.")
            return
        end
    end
    local ctx = emsContextCache or "none"
    local name = "DummyAnalyzer > Best (" .. ctx .. ")"
    local seqData = Ems_BuildSequenceData(name, orderedSteps)
    -- Try UpdateSequence first (overwrites existing), fall back to CreateSequence
    local ok, reason = emsPluginHandle:UpdateSequence(name, seqData)
    if ok then
        if debugMode then print("|cff33ff33[DummyAnalyzer EMS]|r UpdateSequence OK: " .. name) end
    else
        ok, reason = emsPluginHandle:CreateSequence(name, seqData)
        if not ok and debugMode then
            print("|cffff8844[DummyAnalyzer EMS]|r CreateSequence failed: " .. tostring(reason))
        end
    end
    return name
end

local function Ems_PushImportExportProviders()
    if not emsPluginHandle then return end
    -- Import provider: detects our compressed format header, decodes via GenerateEMSImportString pipeline
    local ok1, reason1 = emsPluginHandle:RegisterImportProvider({
        id = "dummyanalyzer_ems1",
        name = "DummyAnalyzer !EMS1!",
        Detect = function(_, text)
            return type(text) == "string" and text:sub(1, 5) == "!EMS1!"
        end,
        Parse = function(_, text)
            -- Reuse the inverse of GenerateEMSImportString. We delegate to a fresh decode path.
            if not C_EncodingUtil then return nil end
            local ok, payload = pcall(C_EncodingUtil.DeserializeCBOR, text:sub(6) or "")
            if not ok or type(payload) ~= "table" then return nil end
            local deflated = payload.d
            if type(deflated) ~= "string" then return nil end
            local raw = C_EncodingUtil.DecompressString and C_EncodingUtil.DecompressString(deflated) or deflated
            if type(raw) ~= "string" then return nil end
            local steps = {}
            for s in raw:gmatch("[^\n]+") do
                local clean = s:gsub("^%s*/cast%s+%[?combat%]?%s*", ""):gsub("^%s*", ""):gsub("%s*$", "")
                if clean ~= "" then steps[#steps + 1] = clean end
            end
            return { name = "DummyAnalyzer Imported", stepFunction = "sequential", versions = { [1] = { version = "1.0", stepFunction = "sequential", activeStepCount = #steps, steps = steps } } }
        end,
    })
    if not ok1 and debugMode then
        print("|cffff8844[DummyAnalyzer EMS]|r ImportProvider registration failed: " .. tostring(reason1))
    end
    -- Export provider: invokes GenerateEMSImportString on a sequence name
    local ok2, reason2 = emsPluginHandle:RegisterExportProvider({
        id = "dummyanalyzer_ems1",
        name = "DummyAnalyzer !EMS1!",
        Serialize = function(_, seq)
            if type(seq) ~= "table" or type(seq.versions) ~= "table" then return "" end
            local v = seq.versions[seq.activeVersionIndex or seq.defaultVersion or 1]
            if type(v) ~= "table" or type(v.steps) ~= "table" then return "" end
            local castCounts, damageData = {}, {}
            for _, step in ipairs(v.steps) do
                castCounts[step] = (castCounts[step] or 0) + 1
                damageData[step] = { total = 0, hits = 0 }
            end
            if C_EncodingUtil and GenerateEMSImportString then
                local ok3, s = pcall(GenerateEMSImportString, castCounts, damageData)
                if ok3 and s then return s end
            end
            return "!EMS1!export-error"
        end,
    })
    if not ok2 and debugMode then
        print("|cffff8844[DummyAnalyzer EMS]|r ExportProvider registration failed: " .. tostring(reason2))
    end
end

local function Ems_RegisterRegistries()
    if not emsPluginHandle then return end
    -- Variable provider: returns simcDeficit ratio per spell (non-secret scalar)
    emsPluginHandle:RegisterVariableProvider({
        id = "dummyanalyzer_simc_deficit",
        name = "DummyAnalyzer: SimC Deficit Ratio",
        Resolve = function(_, varName)
            if type(varName) ~= "string" then return nil end
            local spell = varName:match("^dummyanalyzer_simc_deficit%.(.+)$")
            if not spell then return nil end
            local db = GetCharDB and GetCharDB() or nil
            local cache = db and db.deficitCache
            if not cache or type(cache) ~= "table" then return 0 end
            return cache[spell] or 0
        end,
    })
    -- Step function: deficit-aware reorder. EMS passes us resolved step texts, we return them in
    -- a static order previously optimized by our hill-climber. Pure, no side effects.
    emsPluginHandle:RegisterStepFunction({
        id = "dummyanalyzer_deficit_order",
        name = "DummyAnalyzer: Deficit-Ordered",
        Expand = function(_, resolvedStepTexts)
            local steps = resolvedStepTexts or {}
            local function passthrough()
                local out = {}
                for i, t in ipairs(steps) do out[i] = t end
                return out
            end
            -- Ordering key must be the NON-deduplicated spell list. orderedSpellNames is
            -- deduped by ParseSequenceLines, so it cannot express "Kill Command at 1, 5, 9".
            -- fullSteps is one entry per macro line, in order. Addon.bestSequence is the
            -- freshest copy (restored from SavedVariables at load); fall back to the char DB.
            local best = Addon and Addon.bestSequence
            if not best then
                local db = GetCharDB and GetCharDB() or nil
                best = db and db.bestSequence or nil
            end
            local order = best and best.fullSteps
            if type(order) ~= "table" or #order == 0 then
                return passthrough()
            end
            -- EMS hands us resolved MACROTEXT, not spell names. Bucket each entry under the
            -- spell it casts so a spell appearing N times keeps all N of its entries.
            local buckets, bucketOrder = {}, {}
            for _, t in ipairs(steps) do
                local name = ExtractSpellFromSeqLine(t)
                if not name then
                    -- A step shape we do not understand. Never drop steps.
                    return passthrough()
                end
                if not buckets[name] then
                    buckets[name] = {}
                    bucketOrder[#bucketOrder + 1] = name
                end
                local b = buckets[name]
                b[#b + 1] = t
            end
            if #bucketOrder == 0 then
                return passthrough()
            end
            -- Emit in optimizer order, consuming one occurrence at a time.
            local out, taken = {}, {}
            for _, name in ipairs(order) do
                local b = buckets[name]
                if b then
                    local i = (taken[name] or 0) + 1
                    if b[i] then
                        taken[name] = i
                        out[#out + 1] = b[i]
                    end
                end
            end
            -- Append anything the optimizer never saw, in its original order.
            for _, name in ipairs(bucketOrder) do
                local b = buckets[name]
                for i = (taken[name] or 0) + 1, #b do
                    out[#out + 1] = b[i]
                end
            end
            if #out == 0 then
                return passthrough()
            end
            return out
        end,
    })
    -- Condition: "training-dummy log available" — true when we have at least 1 player log
    emsPluginHandle:RegisterCondition({
        id = "dummyanalyzer_has_log",
        name = "DummyAnalyzer: A real log exists",
        Evaluate = function()
            local db = GetCharDB and GetCharDB() or nil
            if not db or type(db.logs) ~= "table" then return false end
            for _, log in ipairs(db.logs) do
                if log and not log.isSimC and log.castCounts and next(log.castCounts) then
                    return true
                end
            end
            return false
        end,
    })
end

local function Ems_RegisterEvents()
    local API = GRIPEMS and GRIPEMS.API
    if not API then return end
    API:On("CONTEXT_CHANGED", function(newCtx, _oldCtx)
        emsContextCache = tostring(newCtx or "none")
    end)
    API:On("LOADOUT_CHANGED", function(_newID, _newName, _oldID, _oldName)
        emsLoadoutDirty = true
    end)
    API:On("SETTING_CHANGED", function(_key, _value) end)
    -- Tracks which sequence is actually executing. This is the public replacement for the old
    -- read of GRIPEMS.Engine._lastClickedSequence. Payload: (seqName, step, numSteps).
    API:On("SEQUENCE_STEP_ADVANCED", function(seqName)
        if type(seqName) == "string" and seqName ~= "" then
            Addon.lastActiveSequence = seqName
        end
    end)
    API:On("PLUGIN_SEQUENCES_LOADED", function()
        emsContextCache = tostring(API:GetCurrentContext() or "none")
    end)
    API:On("GEMS_UI_READY", function()
        if emsPluginHandle then
            Ems_PushImportExportProviders()
        end
    end)
end

-- (Ems_BuildOrderedFromSeqText and Ems_CacheOrdered removed: ParseSequenceLines + inline
--  assignment in Best/Next Seq handlers covers both roles.)

function DummyAnalyzer_EMS_OnEnable(handle)
    -- Save the handle so Push/Copy/etc work after reload (EMS calls OnEnable directly with the handle)
    if handle then emsPluginHandle = handle end
    Ems_RegisterRegistries()
    Ems_RegisterEvents()
    -- GEMS_UI_READY may have already fired before this plugin registered, in which case the
    -- event hook in Ems_RegisterEvents never runs and the providers are never registered.
    -- Call directly too; EMS rejects a duplicate id with (false, reason), which the callee
    -- already handles, so the double call is safe.
    Ems_PushImportExportProviders()
    -- Promote existing bestSequence into EMS if one is already persisted
    local db = GetCharDB()
    if db and db.bestSequence and type(db.bestSequence.seqText) == "string" and db.bestSequence.seqText ~= "" then
        -- fullSteps is the non-deduplicated step list; orderedSpellNames collapses repeats, so
        -- promoting from it would re-create "A B A C A B" in EMS as "A B C" after every reload.
        -- Fall back to orderedSpellNames only for SavedVariables written before fullSteps existed.
        local ordered = db.bestSequence.fullSteps
        if type(ordered) ~= "table" or #ordered == 0 then
            ordered = db.bestSequence.orderedSpellNames
        end
        if type(ordered) == "table" and #ordered > 0 then
            Ems_PushBestSequence(ordered)
        end
    end
    if debugMode then print("|cff33ff33[DummyAnalyzer EMS]|r Plugin enabled.") end
end

function DummyAnalyzer_EMS_OnDisable(_handle)
    -- EMS reverts our contributions automatically. Nothing to clean up here unless we want to.
    if debugMode then print("|cff33ff33[DummyAnalyzer EMS]|r Plugin disabled (contributions reverted by EMS).") end
end

local pluginInitFrame = CreateFrame("Frame")
pluginInitFrame:RegisterEvent("PLAYER_LOGIN")
pluginInitFrame:SetScript("OnEvent", function(_, event)
    if event ~= "PLAYER_LOGIN" then return end
    local API = GRIPEMS and GRIPEMS.API
    if not API then
        print("|cffff8844[DummyAnalyzer EMS]|r GRIPEMS.API not present - EMS not loaded.")
        return
    end
    if not API:RequireVersion(3) then
        print("|cffff8844[DummyAnalyzer EMS]|r EMS v3+ required for plugin support.")
        return
    end
    -- If we already have a handle, we're good
    if emsPluginHandle then
        print("|cff33ff33[DummyAnalyzer EMS]|r Already have plugin handle.")
        return
    end
    emsContextCache = "none"
    -- Try fresh registration
    emsPluginHandle = API:RegisterPlugin(EMS_PLUGIN_ID, {
        name = EMS_PLUGIN_NAME,
        version = EMS_PLUGIN_VERSION,
        OnEnable = DummyAnalyzer_EMS_OnEnable,
        OnDisable = DummyAnalyzer_EMS_OnDisable,
    })
    if emsPluginHandle then
        print("|cff33ff33[DummyAnalyzer EMS]|r Registered as '" .. EMS_PLUGIN_ID .. "' v" .. EMS_PLUGIN_VERSION)
        return
    end
    print("|cffff8844[DummyAnalyzer EMS]|r RegisterPlugin failed. Reload with GRIP-EMS loaded.")
end)

-- Fallback: if PLAYER_LOGIN missed (race condition), try again when EMS UI is ready
local uiReadyFrame = CreateFrame("Frame")
uiReadyFrame:RegisterEvent("ADDON_LOADED")
uiReadyFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" and addonName == "GRIP-EMS" then
        C_Timer.After(2, function()
            if not emsPluginHandle then
                local ok = Ems_EnsureHandle()
                if ok then
                    print("|cff33ff33[DummyAnalyzer EMS]|r Late registration via ADDON_LOADED fallback.")
                end
            end
        end)
    end
end)
