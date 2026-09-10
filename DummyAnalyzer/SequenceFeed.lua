local AddonName, Addon = ...
-- ============================================
-- EMS IMPORT STRING GENERATION + ITERATIVE FEEDBACK + EXPORT DIALOG
-- ============================================
local GetCharDB = Addon.GetCharDB
local SafeTableGet = Addon.SafeTableGet
local NumberOrZero = Addon.NumberOrZero
local DebugLog = Addon.DebugLog
local C = Addon.C
local FONT = Addon.FONT
local BOLD_FONT = Addon.BOLD_FONT
local SafeSetFont = Addon.SafeSetFont
local CreateStyledFrame = Addon.CreateStyledFrame
local CreateStyledButton = Addon.CreateStyledButton
local ApplyBackdrop = Addon.ApplyBackdrop
local trackDialog = Addon.trackDialog
local RegisterAddonWindow = Addon.RegisterAddonWindow
local IsValidMacroSpell = Addon.IsValidMacroSpell
local GetActionPrefix = Addon.GetActionPrefix
local ParseSequenceLines = Addon.ParseSequenceLines
local ComputeDeficitSnapshot = Addon.ComputeDeficitSnapshot
local BuildKidFriendlyDisplay = Addon.BuildKidFriendlyDisplay
local LogDisplayName = Addon.LogDisplayName
local ExtractSpellFromSeqLine = Addon.ExtractSpellFromSeqLine
local GenerateEMSSequence = Addon.GenerateEMSSequence
local GenerateSuggestedSequence = Addon.GenerateSuggestedSequence
local GenerateReasoningText = Addon.GenerateReasoningText
local GenerateGapReport = Addon.GenerateGapReport
-- Ems_* helpers are home in PluginHandshake.lua (#16, loads after this file, #14). These
-- run at click-time, so the Addon lookups resolve after load.
local function Ems_EnsureHandle() return Addon.Ems_EnsureHandle() end
local function Ems_PushBestSequence(steps) return Addon.Ems_PushBestSequence(steps) end

-- SetDropText: rewrite a CreateStyledButton's centered label (it has a single FontString region).
local function SetDropText(btn, text)
    for _, r in ipairs({ btn:GetRegions() }) do
        if r.GetText and r:GetObjectType() == "FontString" then
            r:SetText(text)
            break
        end
    end
end

-- Shared styled dropdown: replaces Blizzard UIDropDownMenuTemplate (themed, no overflow).
-- btn label text is rewritten via SetDropText; menu is a themed popup panel.
local function MakeStyledDropdown(parent, options, default, onSelect, width)
    local btn = CreateStyledButton(parent, tostring(default), width or 150, 22, nil)
    local menu = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    ApplyBackdrop(menu, true)
    menu:SetSize(btn:GetWidth(), #options * 24)
    menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    menu:Hide()
    local selected = default

    local function BuildOptions()
        for _, ch in ipairs({ menu:GetChildren() }) do
            if ch.IsShown and ch:GetObjectType() == "Button" then ch:Hide() end
        end
        menu:SetHeight(#options * 24)
        for i, opt in ipairs(options) do
            local ob = CreateStyledButton(menu, tostring(opt), menu:GetWidth() - 8, 22, function()
                selected = opt
                if onSelect then onSelect(opt) end
                SetDropText(btn, tostring(opt))
                menu:Hide()
            end)
            ob:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -((i - 1) * 24 + 1))
            if opt == selected then
                ob:SetBackdropColor(C.selected[1], C.selected[2], C.selected[3], C.selected[4])
            end
        end
    end

    btn:SetScript("OnClick", function()
        BuildOptions()
        if menu:IsShown() then menu:Hide() else menu:Raise(); menu:Show() end
    end)
    return btn, menu
end

local function GenerateEMSImportString(castCounts, damageData, orderedSteps)
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

    -- Single EMS builder owns all sequence fields; serialize here only.
    local names = {}
    for _, entry in ipairs(sorted) do names[#names + 1] = entry.name end
    local overrides = {}
    local maxCount = sorted[1] and sorted[1].count or 1
    for _, entry in ipairs(sorted) do
        if entry.count >= 5 and entry.count >= maxCount * 0.4 then
            overrides[entry.name] = math.max(2, math.min(6, math.floor(#sorted / math.min(entry.count, #sorted))))
        end
    end
    local sequence = Addon.BuildSequence(names, GetCharDB().settings or {}, overrides)
    if not sequence then return nil end
    return Addon.SerializeEMSSequence(sequence, "DummyAnalyzer Sequence")
end

-- ============================================
-- ITERATIVE FEEDBACK: reorder steps based on test performance
-- ============================================
local function IterateSequence(seqText, castCounts, damageData, duration)
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
local function ShowConfigureDialog(parent)
    local db = GetCharDB()
    if not db.settings then db.settings = {} end
    local s = db.settings

    local WIN_W    = 560
    local WIN_PAD  = 20
    local TITLE_H  = 32
    local TAB_H    = 28
    local ROW_H    = 30
    local LABEL_X  = 16
    local CTRL_X   = 280
    local CTRL_W   = 150
    local BTN_W    = 170
    local BTN_H    = 28
    local PANEL_TOP = TITLE_H + 10 + TAB_H + 10 -- title + gap + tab + gap = 80
    local PANEL_INNER_W = WIN_W - 2 * WIN_PAD   -- 520

    local dialog = CreateStyledFrame("Frame", nil, UIParent); trackDialog(dialog)
    dialog:SetSize(WIN_W, 400) -- temporary, resized after content
    dialog:SetPoint("CENTER")
    ApplyBackdrop(dialog, false)
    dialog:SetMovable(true)
    dialog:SetClampedToScreen(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    dialog:SetFrameLevel((parent or UIParent):GetFrameLevel() + 10)
    if parent and parent ~= UIParent and parent.Hide then parent:Hide() end

    local titleBar = CreateStyledFrame("Frame", nil, dialog)
    titleBar:SetPoint("TOPLEFT", dialog, "TOPLEFT")
    titleBar:SetPoint("TOPRIGHT", dialog, "TOPRIGHT")
    titleBar:SetHeight(TITLE_H)
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
    tabRow:SetPoint("TOPLEFT", dialog, "TOPLEFT", WIN_PAD, -(TITLE_H + 10))
    tabRow:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -WIN_PAD, -(TITLE_H + 10))
    tabRow:SetHeight(TAB_H)

    local panels = {}
    local lastTab
    local function ShowTab(idx)
        for i, p in ipairs(panels) do p:SetShown(i == idx) end
        if lastTab then lastTab:SetBackdropColor(C.btn[1], C.btn[2], C.btn[3], C.btn[4]) end
        lastTab = _G["cfgTab" .. idx]
        if lastTab then lastTab:SetBackdropColor(C.selected[1], C.selected[2], C.selected[3], C.selected[4]) end
    end

    local tabNames = {"Playback", "Spells"}
    for ti, tname in ipairs(tabNames) do
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
        panel:SetPoint("TOPLEFT", dialog, "TOPLEFT", WIN_PAD, -PANEL_TOP)
        panel:SetSize(PANEL_INNER_W, 400) -- temporary — resized after content
        panel:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
        panel:SetBackdropColor(0.08, 0.08, 0.1, 0.5)
        panels[ti] = panel
    end

    -- Tab 1: Playback (layout-driven — currentY tracks content depth)
    local tabHeights = {}
    do
        local panel = panels[1]
        local currentY = 8 -- top padding inside panel

        local function MakeEditBox(default, onChange)
            local eb = CreateFrame("EditBox", nil, panel, "BackdropTemplate")
            eb:SetSize(CTRL_W, 24)
            eb:SetFontObject(ChatFontNormal)
            eb:SetTextColor(1, 1, 1, 1)
            eb:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
            eb:SetBackdropColor(0.04, 0.04, 0.06, 0.8)
            eb:SetAutoFocus(false)
            eb:SetText(tostring(default))
            eb:SetScript("OnTextChanged", onChange)
            return eb
        end

        local function MakeDropdown(options, default, onSelect)
            local btn, menu = MakeStyledDropdown(panel, options, default, onSelect, CTRL_W)
            return btn
        end

        local function MakeCheckbox(initial, onToggle)
            local cb = CreateStyledFrame("Button", nil, panel)
            cb:SetSize(16, 16)
            cb:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
            local val = initial
            cb:SetBackdropColor(val and 0.2 or 0.05, val and 0.8 or 0.05, val and 0.2 or 0.05, 0.9)
            cb:SetScript("OnClick", function()
                val = not val
                onToggle(val)
                cb:SetBackdropColor(val and 0.2 or 0.05, val and 0.8 or 0.05, val and 0.2 or 0.05, 0.9)
            end)
            return cb
        end

        -- ponytail: every row goes through PlaceLabel → Place* → advance currentY
        local function PlaceLabel(text)
            local lbl = panel:CreateFontString(nil, "OVERLAY")
            SafeSetFont(lbl, FONT, 11)
            lbl:SetPoint("TOPLEFT", panel, "TOPLEFT", LABEL_X, -currentY)
            lbl:SetText(text)
            lbl:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])
            lbl:SetJustifyH("LEFT")
            return lbl
        end

        local function PlaceEdit(default, onChange)
            local eb = MakeEditBox(default, onChange)
            eb:SetPoint("TOPLEFT", panel, "TOPLEFT", CTRL_X, -(currentY + 4))
            return eb
        end

        local function PlaceDropdown(options, default, onSelect)
            local dd = MakeDropdown(options, default, onSelect)
            dd:SetPoint("TOPLEFT", panel, "TOPLEFT", CTRL_X, -(currentY + 4))
            return dd
        end

        local function PlaceCheckbox(initial, onToggle)
            local cb = MakeCheckbox(initial, onToggle)
            cb:SetPoint("TOPLEFT", panel, "TOPLEFT", CTRL_X, -(currentY + 1))
            return cb
        end

        local function PlaceHeader(text)
            local hdr = panel:CreateFontString(nil, "OVERLAY")
            SafeSetFont(hdr, BOLD_FONT, 11)
            hdr:SetPoint("TOPLEFT", panel, "TOPLEFT", LABEL_X, -(currentY + 4))
            hdr:SetText(text)
            hdr:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], 0.85)
            hdr:SetJustifyH("LEFT")
            currentY = currentY + ROW_H
        end

        -- Solver knobs grouped separately from literal EMS sequence fields.
        PlaceHeader("Copy expansion (solver):")

        -- Row 1
        PlaceLabel("Max consecutive repeats (0=unlimited):")
        PlaceEdit(s.maxRepeats or 3, function(eb)
            local v = tonumber(eb:GetText()); if v and v >= 0 then s.maxRepeats = v else s.maxRepeats = 0 end
        end)
        currentY = currentY + ROW_H

        -- Row 2: Auto-interleave — top N spells by cast-count; interval computed in BuildSequence
        PlaceLabel("Auto-interleave: top N spells (0=off):")
        PlaceEdit(s.interleave or 0, function(eb)
            local v = tonumber(eb:GetText()); if v and v >= 0 then s.interleave = v else s.interleave = 0 end
        end)
        currentY = currentY + ROW_H

        -- Row 3
        PlaceLabel("Min copies per spell:")
        PlaceEdit(s.minCopies or 1, function(eb)
            local v = tonumber(eb:GetText()); if v and v >= 0 then s.minCopies = v else s.minCopies = 1 end
        end)
        currentY = currentY + ROW_H

        PlaceHeader("EMS sequence fields:")

        -- Row 4
        PlaceLabel("Step Function:")
        PlaceDropdown({"Priority", "Sequential", "ReversePriority", "Random"}, s.stepFunction or "Priority", function(opt)
            s.stepFunction = opt
        end)
        currentY = currentY + ROW_H

        -- Row 5: checkbox + hint text
        PlaceLabel("Auto-push to GRIP-EMS:")
        local apCb = PlaceCheckbox(s.autoPush or false, function(val) s.autoPush = val end)
        local apHint = panel:CreateFontString(nil, "OVERLAY")
        SafeSetFont(apHint, FONT, 9)
        apHint:SetPoint("LEFT", apCb, "RIGHT", 6, 0)
        apHint:SetText("Auto-push when Best Sequence is generated")
        apHint:SetTextColor(C.text[1], C.text[2], C.text[3], 0.5)
        currentY = currentY + ROW_H

        -- Row 6
        PlaceLabel("KeyPress macro:")
        PlaceEdit(s.keyPress or "/startattack", function(eb) s.keyPress = eb:GetText() end)
        currentY = currentY + ROW_H

        -- Row 7
        PlaceLabel("KeyRelease macro:")
        PlaceEdit(s.keyRelease or "", function(eb) s.keyRelease = eb:GetText() end)
        currentY = currentY + ROW_H

        -- Row 8: Reset On — 2x2 grid so checkbox + label never clips
        PlaceLabel("Reset on:")
        local resetDefs = {
            {key = "resetOnCombat", label = "Combat", default = true},
            {key = "resetOnTarget", label = "Target", default = true},
            {key = "resetOnGear",   label = "Gear",   default = false},
            {key = "resetOnSpec",   label = "Spec",   default = false},
        }
        local resetSlotW = 130
        for gi = 0, 1 do -- grid row 0 = Combat/Target, row 1 = Gear/Spec
            for ci = 0, 1 do
                local rd = resetDefs[gi * 2 + ci + 1]
                local val = (s[rd.key] ~= nil) and s[rd.key] or rd.default
                s[rd.key] = val
                local cb = MakeCheckbox(val, function(v) s[rd.key] = v end)
                cb:SetPoint("TOPLEFT", panel, "TOPLEFT", CTRL_X + ci * resetSlotW, -(currentY + 1))
                local clbl = panel:CreateFontString(nil, "OVERLAY")
                SafeSetFont(clbl, FONT, 11)
                clbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
                clbl:SetText(rd.label)
                clbl:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])
            end
            currentY = currentY + ROW_H
        end

        -- Row 9
        PlaceLabel("Reset timer (sec, 0=off):")
        PlaceEdit(s.resetTimer or 0, function(eb)
            local v = tonumber(eb:GetText()); if v and v >= 0 then s.resetTimer = v else s.resetTimer = 0 end
        end)
        currentY = currentY + ROW_H

        -- Row 10
        PlaceLabel("Repeat whole list N times (0=no wrap):")
        PlaceEdit(s.repeatCount or 0, function(eb)
            local v = tonumber(eb:GetText()); if v and v >= 0 then s.repeatCount = v else s.repeatCount = 0 end
        end)
        currentY = currentY + ROW_H

        -- Row 11
        PlaceLabel("Privacy Mode:")
        PlaceDropdown({"private", "public", "pseudonymous"}, s.privacyMode or "private", function(opt)
            s.privacyMode = opt
        end)
        currentY = currentY + ROW_H

        -- Save button: placed after content, centered horizontally
        currentY = currentY + 16 -- gap above
        local saveBtn = CreateStyledButton(panel, "Save Preferences", BTN_W, BTN_H, function()
            db.settings = s
            print("|cff33ff33[DummyAnalyzer]|r Preferences saved.")
        end)
        saveBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", (PANEL_INNER_W - BTN_W) / 2, -currentY)
        currentY = currentY + BTN_H + 16 -- gap below

        tabHeights[1] = currentY + 8
        panel:SetHeight(tabHeights[1])
    end


    -- Tab 2: Spells (full spellbook pool; Auto / Always / Never per spell)
    do
        local panel = panels[2]
        local spellY = 8
        local tip = panel:CreateFontString(nil, "OVERLAY")
        SafeSetFont(tip, FONT, 9)
        tip:SetPoint("TOPLEFT", panel, "TOPLEFT", LABEL_X, -spellY)
        tip:SetText("Always = force into sequence | Never = exclude everywhere | Auto = use logs")
        tip:SetTextColor(C.text[1], C.text[2], C.text[3], 0.5)
        spellY = spellY + ROW_H

        local spellPool = {}
        do
            local seen = {}
            local logSpells = {}
            if db.logs then
                for _, log in ipairs(db.logs) do
                    if not log.isSimC and log.castCounts then
                        for name in pairs(log.castCounts) do logSpells[name] = true end
                    end
                end
            end
            local function AddPooled(name)
                if name and name ~= "" and not seen[name] then seen[name] = true; spellPool[#spellPool + 1] = name end
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
            if not C_SpellBook or not C_SpellBook.GetNumSpellBookSkillLines then
                for name in pairs(logSpells) do AddPooled(name) end
            else
                local numLines = C_SpellBook.GetNumSpellBookSkillLines() or 0
                for li = 1, numLines do
                    local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(li)
                    if lineInfo and not IsProfessionName(lineInfo.skillLineName) then
                        local offset = lineInfo.itemIndexOffset or 0
                        for j = 1, lineInfo.numSpellBookItems or 0 do
                            local slot = offset + j
                            local info = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
                            if info then
                                local isPassive = info.isPassive or (info.itemType and info.itemType == 0)
                                if not isPassive then
                                    local id = info.actionID or 0
                                    if id > 0 then
                                        local override = FindSpellOverrideByID and FindSpellOverrideByID(id) or 0
                                        local spellInfo = C_Spell.GetSpellInfo(override > 0 and override or id)
                                        if not spellInfo then spellInfo = C_Spell.GetSpellInfo(id) end
                                        AddPooled(spellInfo and spellInfo.name or nil)
                                    end
                                end
                            end
                        end
                    end
                end
            end
            -- Always union log spells
            for name in pairs(logSpells) do AddPooled(name) end
            table.sort(spellPool, function(a, b) return a < b end)
        end

        local spellScroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
        spellScroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -spellY)
        spellScroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, -44)
        local spellContainer = CreateFrame("Frame", nil, spellScroll)
        spellContainer:SetWidth(PANEL_INNER_W - 16)
        spellScroll:SetScrollChild(spellContainer)

        local function StateOf(name)
            for _, v in ipairs(s.requiredSpells or {}) do if v == name then return "Always" end end
            for _, v in ipairs(s.neverSpells or {}) do if v == name then return "Never" end end
            return "Auto"
        end
        local function SetState(name, st)
            local req, never = {}, {}
            for _, v in ipairs(s.requiredSpells or {}) do if v ~= name then req[#req + 1] = v end end
            for _, v in ipairs(s.neverSpells or {}) do if v ~= name then never[#never + 1] = v end end
            if st == "Always" then req[#req + 1] = name
            elseif st == "Never" then never[#never + 1] = name end
            s.requiredSpells = req
            s.neverSpells = never
            db.settings = s
        end

        local function SetRowState(row, lbl, name, i)
            local st = StateOf(name)
            if st == "Always" then
                row:SetBackdropColor(1, 1, 1, 0.16)
                lbl:SetText(name .. "   [Always]")
                lbl:SetTextColor(1, 1, 1, 1)
            elseif st == "Never" then
                row:SetBackdropColor(0, 0, 0, 0.45)
                lbl:SetText(name .. "   [Never]")
                lbl:SetTextColor(0.45, 0.45, 0.45, 1)
            else
                if math.fmod(i, 2) == 0 then
                    row:SetBackdropColor(0, 0, 0, 0.08)
                else
                    row:SetBackdropColor(1, 1, 1, 0.03)
                end
                lbl:SetText(name)
                lbl:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])
            end
        end

        for i, name in ipairs(spellPool) do
            local row = CreateFrame("Frame", nil, spellContainer, "BackdropTemplate")
            row:SetPoint("TOPLEFT", spellContainer, "TOPLEFT", 0, -(i - 1) * 22)
            row:SetPoint("RIGHT", spellContainer, "RIGHT", 0, 0)
            row:SetHeight(20)
            row:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0 })
            local lbl = row:CreateFontString(nil, "OVERLAY")
            SafeSetFont(lbl, FONT, 11)
            lbl:SetPoint("LEFT", row, "LEFT", 6, 0)
            lbl:SetText(name)
            SetRowState(row, lbl, name, i)
            local stateDd = MakeStyledDropdown(row, {"Auto", "Always", "Never"}, StateOf(name), function(st)
                SetState(name, st)
                SetRowState(row, lbl, name, i)
            end, 80)
            stateDd:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
        end

        spellContainer:SetHeight(math.max(30, #spellPool * 22))

        panel:SetHeight(360)
        tabHeights[2] = 360
    end

    -- Resize dialog from tallest tab
    local maxH = tabHeights[1]
    for _, h in ipairs(tabHeights) do if h > maxH then maxH = h end end
    for i, p in ipairs(panels) do p:SetHeight(tabHeights[i] or maxH) end
    dialog:SetHeight(PANEL_TOP + maxH + WIN_PAD)
    ShowTab(1)
    dialog:Show()
end

local exportDialogRef = nil
Addon.ShowExportDialog = function(castCounts, damageData, buffUptime, playerDuration, suggestMode, buffGaps, selectedLogIds)
    if exportDialogRef and exportDialogRef:IsShown() then exportDialogRef:Hide() end
    local exportDialog = nil
    exportDialog = CreateStyledFrame("Frame", nil, UIParent); trackDialog(exportDialog)
    exportDialogRef = exportDialog
    local addSlotBtn
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
    titleText:SetText(suggestMode and "Suggested Sequence" or "Create Sequence")
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
    -- Required spells come from Configure -> Required Spells tab (persisted in settings)
    local CollectRequiredSpells
    do
        local function impl()
            local db = GetCharDB()
            local spells = (db.settings or {}).requiredSpells
            if spells and #spells > 0 then
                local required = {}
                local seen = {}
                for _, name in ipairs(spells) do
                    if name and name ~= "" and not seen[name] then
                        seen[name] = true
                        required[#required + 1] = name
                    end
                end
                return #required > 0 and required or nil
            end
            return nil
        end
        CollectRequiredSpells = impl
    end

    local scrollFrame = CreateFrame("ScrollFrame", nil, exportDialog, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", exportDialog, "TOPLEFT", 16, -86)
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
        local fullStepNames = {}
        for _, m in ipairs(macros) do
            local sn = ExtractSpellFromSeqLine(m)
            if sn and sn ~= "" then fullStepNames[#fullStepNames + 1] = sn end
        end
        local normScore = seqScore / math.max(playerDuration or 1, 1)
        if not Addon.bestSequence then Addon.bestSequence = {score = 0, normScore = 0} end
        if not Addon.bestSequence.normScore then Addon.bestSequence.normScore = 0 end
        if normScore > (Addon.bestSequence.normScore or 0) then
            Addon.bestSequence = {score = seqScore, normScore = normScore, seqText = seqText, importStr = importStr, reasoningText = reasoningText, orderedSpellNames = ordNames, fullSteps = fullStepNames}
        end
        do -- auto-push: push the CURRENTLY-DISPLAYED steps (fresh seqText-derived),
            -- never a stale persisted bestSequence fullSteps cache.
            local s = (GetCharDB()).settings or {}
            if s.autoPush and #fullStepNames > 0 then
                C_Timer.After(0.5, function() Ems_PushBestSequence(fullStepNames) end)
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

    local bestBtn, nextBtn, simcBtn
    local function ClearHighlights()
        for _, b in ipairs({bestBtn, simcBtn, nextBtn}) do
            if b then
                b._isSelected = false
                b:SetBackdropColor(C.btn[1], C.btn[2], C.btn[3], C.btn[4])
            end
        end
    end
    local function HighlightTab(btn)
        if not btn then return end
        ClearHighlights()
        btn._isSelected = true
        btn:SetBackdropColor(C.btnPrimary[1], C.btnPrimary[2], C.btnPrimary[3], C.btnPrimary[4])
        btn:SetScript("OnLeave", function()
            if btn._isSelected then
                btn:SetBackdropColor(C.btnPrimary[1], C.btnPrimary[2], C.btnPrimary[3], C.btnPrimary[4])
            else
                btn:SetBackdropColor(C.btn[1], C.btn[2], C.btn[3], C.btn[4])
                btn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], C.border[4])
            end
        end)
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

-- "Best Sequence" button — picks the best (highest DPS) training log and shows its stored/generated sequence. Deterministic: does NOT re-run the random hill-climber.
    bestBtn = CreateStyledButton(tabRow, "Best Sequence", 140, 28, function()
        local db = GetCharDB()
        local logCount = 0
        local bestLog, bestDPS = nil, 0
        for _, log in ipairs(db.logs or {}) do
            if not log.isSimC and log.castCounts and next(log.castCounts) then
                logCount = logCount + 1
                local dmgTotal = 0
                if log.damageData then
                    for _, d in pairs(log.damageData) do
                        dmgTotal = dmgTotal + (d.total or 0)
                    end
                end
                local dur = (log.duration or 1) > 0 and log.duration or 1
                local dps = dmgTotal / dur
                if dps > bestDPS then bestDPS, bestLog = dps, log end
            end
        end
        if logCount == 0 then
            print("|cff33ff33[DummyAnalyzer]|r No training logs found. Run tests first.")
            return
        end
        if not bestLog then
            print("|cff33ff33[DummyAnalyzer]|r No training logs contain damage data. Run tests first.")
            return
        end
        DebugLog("info", "BestSeq", string.format("%d logs total, best DPS log: %s", logCount, tostring(bestLog.id)))
        local reqSpells = CollectRequiredSpells()
        -- Prefer the sequence stored with the best log; fall back to a deterministic rebuild from its casts.
        local bestSeqStr = (bestLog.emsSeqText and bestLog.emsSeqText ~= "") and bestLog.emsSeqText
            or GenerateEMSSequence(bestLog.castCounts, bestLog.damageData or {}, reqSpells, bestLog.buffUptime)
        if bestSeqStr and bestSeqStr ~= "" then
            local macros, ordered = ParseSequenceLines(bestSeqStr)
            local bestScore = bestDPS * math.max(bestLog.duration or 1, 1)
            -- Context lists every saved log we considered, marking which one actually drove the sequence.
            local ctx = { logsCount = logCount, logLabelById = {} }
            for _, log in ipairs(db.logs or {}) do
                if not log.isSimC and log.castCounts and next(log.castCounts) then
                    local label = LogDisplayName(log)
                    if log == bestLog then label = label .. " (best DPS — used)" end
                    ctx.logLabelById[log.id or 0] = label
                end
            end
            if db.simcData and next(db.simcData) then
                ctx.logLabelById[0] = ctx.logLabelById[0] or "SimC import (DPS weights)"
            end
            local deficit = ComputeDeficitSnapshot(bestLog.castCounts, db.simcData, bestLog.duration or 1)
            local display = BuildKidFriendlyDisplay("best", ctx, bestScore, math.max(bestLog.duration or 1, 1), macros, ordered, deficit)
            local fullStepNames = {}
            for _, m in ipairs(macros) do
                local sn = ExtractSpellFromSeqLine(m)
                if sn and sn ~= "" then fullStepNames[#fullStepNames + 1] = sn end
            end
            local bestImportStr = ""
            if C_EncodingUtil then
                local ok, s = pcall(GenerateEMSImportString, bestLog.castCounts, bestLog.damageData or {})
                if ok and type(s) == "string" then bestImportStr = s end
            end
            local bestReasonStr = "Best DPS run from training logs."
            Addon.bestSequence = {score = bestScore or 0, normScore = (bestScore or 0) / math.max(bestLog.duration or 1, 1), seqText = table.concat(macros, "\n"), importStr = bestImportStr, reasoningText = bestReasonStr, orderedSpellNames = ordered, fullSteps = fullStepNames}
            do -- auto-push
                local s = (GetCharDB()).settings or {}
                if s.autoPush and fullStepNames and #fullStepNames > 0 then
                    C_Timer.After(0.5, function() Ems_PushBestSequence(fullStepNames) end)
                end
            end
            local db3 = GetCharDB()
            db3.bestSequence = Addon.bestSequence

            seqText = table.concat(macros, "\n")  -- ONLY /cast lines, so Push fallback always works
            importStr = bestImportStr; reasoningText = bestReasonStr
            HighlightTab(bestBtn)
            SetEditText(GetSimcWarning() .. display)
            print(string.format("|cff33ff33[DummyAnalyzer]|r Best sequence from %d logs (best DPS run, score: %s)", logCount, Addon.FormatNumber(bestScore or 0)))
        else
            print("|cff33ff33[DummyAnalyzer]|r Failed to build best sequence from the top DPS log.")
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
            if sn and sn ~= "" then fullStepNames[#fullStepNames + 1] = sn end
        end
        local simcImportStr = GenerateEMSImportString(simcCastCounts, simcDamage)
        -- Update closure variables in-place (same pattern as Best/Next buttons)
        seqText = simcSeqText
        importStr = simcImportStr
        reasoningText = "Generated from SimC import (no real logs)."
        Addon.bestSequence = { score = 0, normScore = 0, seqText = seqText, importStr = importStr, reasoningText = reasoningText, orderedSpellNames = ordered, fullSteps = fullStepNames }
        local persistDb = GetCharDB()
        persistDb.bestSequence = Addon.bestSequence
        HighlightTab(simcBtn)
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
                if name and name ~= "" then table.insert(steps, name) end
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
                    ctx.logLabel = LogDisplayName(log)
                end
            end
            local deficit = ComputeDeficitSnapshot(castCounts, db5.simcData, playerDuration)
            local display = BuildKidFriendlyDisplay("next", ctx, nScore, playerDuration, macros, ordered, deficit, steps ~= nil)
            seqText = table.concat(macros, "\n")  -- ONLY /cast lines
            importStr = nImp; reasoningText = nReason
HighlightTab(nextBtn)
        SetEditText(GetSimcWarning() .. display)
            local normS = nScore and (nScore / math.max(playerDuration, 1)) or 0
            if not Addon.bestSequence then Addon.bestSequence = {score = 0, normScore = 0} end
            if not Addon.bestSequence.normScore then Addon.bestSequence.normScore = 0 end
            if normS > Addon.bestSequence.normScore then
                local fullStepNames = {}
                for _, m in ipairs(macros) do
                    local sn = ExtractSpellFromSeqLine(m)
                    if sn and sn ~= "" then fullStepNames[#fullStepNames + 1] = sn end
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
        if name and name ~= "" then steps[#steps + 1] = name end
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
        if not Addon.emsPluginHandle then
            local ok, reason = Ems_EnsureHandle()
            if not ok then
                print("|cffff8844[DummyAnalyzer EMS]|r GRIP-EMS not ready: " .. tostring(reason) .. ". Reload after EMS is loaded.")
                return
            end
        end
        local pushedName, pushErr = Ems_PushBestSequence(steps)
        if pushedName then
            print("|cff33ff33[DummyAnalyzer EMS]|r Pushed to GRIP-EMS as '" .. pushedName .. "' (steps=" .. #steps .. ").")
        else
            print("|cffff8844[DummyAnalyzer EMS]|r Push refused by GRIP-EMS: " .. tostring(pushErr))
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
    if Addon.debugMode then print("|cffffff00[DummyAnalyzer EMS]|r pushBtn created and anchored: " .. tostring(pushBtn:GetName() or "<anon>")) end

    local cfgBtn = CreateStyledButton(bottomRow, "Configure", 90, 32, function() ShowConfigureDialog(exportDialog) end)
    cfgBtn:SetPoint("LEFT", pushBtn, "RIGHT", 10, 0)

    -- Read-back: pop up a small dialog showing the authored vs execution order of the
    -- sequence last pushed to GRIP-EMS (port of the removed Configure "Live" tab).
    local readBtn = CreateStyledButton(bottomRow, "Read-back", 90, 32, function()
        local rb = CreateStyledFrame("Frame", nil, UIParent)
        trackDialog(rb)
        rb:SetSize(600, 400)
        rb:SetPoint("CENTER")
        ApplyBackdrop(rb, false)
        rb:SetMovable(true)
        rb:SetClampedToScreen(true)
        rb:EnableMouse(true)
        rb:RegisterForDrag("LeftButton")
        rb:SetScript("OnDragStart", rb.StartMoving)
        rb:SetScript("OnDragStop", rb.StopMovingOrSizing)
        local rbTitle = CreateStyledFrame("Frame", nil, rb)
        rbTitle:SetPoint("TOPLEFT", rb, "TOPLEFT")
        rbTitle:SetPoint("TOPRIGHT", rb, "TOPRIGHT")
        rbTitle:SetHeight(30)
        rbTitle:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
        rbTitle:SetBackdropColor(C.title[1], C.title[2], C.title[3], C.title[4])
        local rbTitleText = rbTitle:CreateFontString(nil, "OVERLAY")
        SafeSetFont(rbTitleText, BOLD_FONT, 14)
        rbTitleText:SetText("EMS Read-back")
        rbTitleText:SetPoint("CENTER")
        rbTitleText:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])
        local rbClose = CreateStyledButton(rbTitle, "X", 24, 24, function() rb:Hide() end)
        rbClose:SetPoint("RIGHT", rbTitle, "RIGHT", -6, 0)

        local authScroll = CreateFrame("ScrollFrame", nil, rb, "UIPanelScrollFrameTemplate")
        authScroll:SetPoint("TOPLEFT", rb, "TOPLEFT", 8, -40)
        authScroll:SetPoint("BOTTOMLEFT", rb, "BOTTOMLEFT", 8, 60)
        authScroll:SetPoint("RIGHT", rb, "CENTER", -4, 0)
        local authContainer = CreateFrame("Frame", nil, authScroll)
        authContainer:SetWidth(286)
        authScroll:SetScrollChild(authContainer)

        local execScroll = CreateFrame("ScrollFrame", nil, rb, "UIPanelScrollFrameTemplate")
        execScroll:SetPoint("TOPLEFT", rb, "CENTER", 4, -40)
        execScroll:SetPoint("BOTTOMRIGHT", rb, "BOTTOMRIGHT", -8, 60)
        local execContainer = CreateFrame("Frame", nil, execScroll)
        execContainer:SetWidth(286)
        execScroll:SetScrollChild(execContainer)

        local rbStatus = rb:CreateFontString(nil, "OVERLAY")
        SafeSetFont(rbStatus, FONT, 10)
        rbStatus:SetPoint("BOTTOMLEFT", rb, "BOTTOMLEFT", 8, 6)

        local list = {}
        -- item = {index, spellName, spellID}
        local function FillList(container, steps, label)
            for _, region in ipairs({ container:GetRegions() }) do
                if region.IsShown and region:GetObjectType() == "FontString" then region:Hide() end
            end
            local shown = 0
            local head = container:CreateFontString(nil, "OVERLAY")
            SafeSetFont(head, FONT, 11)
            head:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            head:SetText(label)
            head:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], 0.9)
            shown = shown + 1
            for _, s in ipairs(steps or {}) do
                if shown > 40 then break end
                local line = container:CreateFontString(nil, "OVERLAY")
                SafeSetFont(line, FONT, 10)
                line:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -((shown - 1) * 17))
                line:SetText(string.format("%d. %s (%d)", s.index or shown - 1, s.spellName or "?", s.spellID or 0))
                line:SetTextColor(C.text[1], C.text[2], C.text[3], C.text[4])
                shown = shown + 1
            end
            container:SetHeight(math.max(30, shown * 17))
        end

        local function RefreshReadback()
            local api = GRIPEMS and GRIPEMS.API
            local name = Addon.emsLastPushedName
            if not api or not name then
                rbStatus:SetText("|cff8888ccNo pushed DummyAnalyzer sequence found - push one from this dialog.|r")
                return
            end
            local ok1, a1 = pcall(function()
                if type(api.GetAuthoredSteps) == "function" then return api:GetAuthoredSteps(name) end
            end)
            local ok2, a2 = pcall(function()
                if type(api.GetSequenceSteps) == "function" then return api:GetSequenceSteps(name) end
            end)
            local authored = ok1 and type(a1) == "table" and a1 or nil
            local executed = ok2 and type(a2) == "table" and a2 or nil
            if authored == nil and executed == nil then
                rbStatus:SetText(string.format("|cffff4444%s|r - not found in EMS (deleted or never pushed)", tostring(name)))
                FillList(authContainer, {}, "Authored (unrolled/flattened)")
                FillList(execContainer, {}, "Execution (post step-function)")
                return
            end
            FillList(authContainer, authored or {}, "Authored (unrolled/flattened)")
            FillList(execContainer, executed or {}, "Execution (post step-function)")
            rbStatus:SetText(string.format("|cff33ff33%s|r - %d authored / %d execution", tostring(name), #(authored or {}), #(executed or {})))
        end

        local rbRefresh = CreateStyledButton(rb, "Refresh", 100, 24, RefreshReadback)
        rbRefresh:SetPoint("BOTTOMLEFT", rb, "BOTTOMLEFT", 8, 30)
        rb:Show()
        RefreshReadback()
    end)
    readBtn:SetPoint("LEFT", cfgBtn, "RIGHT", 10, 0)

    local closeBtn2 = CreateStyledButton(bottomRow, "Close", 100, 32, function() exportDialog:Hide() end, "danger")
    closeBtn2:SetPoint("RIGHT", bottomRow, "RIGHT", 0, 0)

    local initContent
    local dbInit = GetCharDB()
    local realLogCount = 0
    if type(dbInit.logs) == "table" then
        for _, log in ipairs(dbInit.logs) do
            if not log.isSimC and log.castCounts and next(log.castCounts) then
                realLogCount = realLogCount + 1
            end
        end
    end
    if suggestMode and realLogCount == 0 then
        -- No real training logs yet: never default to a stale persisted best sequence.
        -- Prefer a clean SimC-derived state (highlight From SimC) or an empty-state message.
        if dbInit.simcData and dbInit.simcData.castCounts and next(dbInit.simcData.castCounts) then
            local simcSeqText = GenerateEMSSequence(dbInit.simcData.castCounts, dbInit.simcData.damageData or {})
            if simcSeqText and simcSeqText ~= "" then
                local macros, ordered = ParseSequenceLines(simcSeqText)
                local fullStepNames = {}
                for _, m in ipairs(macros) do
                    local sn = ExtractSpellFromSeqLine(m)
                    if sn and sn ~= "" then fullStepNames[#fullStepNames + 1] = sn end
                end
                local impOK, simcImportStr
                if C_EncodingUtil then impOK, simcImportStr = pcall(GenerateEMSImportString, dbInit.simcData.castCounts, dbInit.simcData.damageData or {}) end
                seqText = simcSeqText
                importStr = impOK and simcImportStr or ""
                reasoningText = "Generated from SimC import (no real logs)."
                Addon.bestSequence = { score = 0, normScore = 0, seqText = seqText, importStr = importStr, reasoningText = reasoningText, orderedSpellNames = ordered, fullSteps = fullStepNames }
                dbInit.bestSequence = Addon.bestSequence
                HighlightTab(simcBtn)
                local simcDeficit = ComputeDeficitSnapshot(dbInit.simcData.castCounts, dbInit.simcData, 0)
                local simcDisplay = BuildKidFriendlyDisplay("best", { logLabel = "SimC", id = nil }, 0, 1, macros, ordered, simcDeficit)
                initContent = GetSimcWarning() .. simcDisplay .. "\n\n|cffffff00Run a training dummy test, then click Best Sequence to optimize.|r"
            else
                initContent = GetSimcWarning() .. "|cffd0d0d0No sequences yet.|r\n\nClick From SimC, or run a training dummy test and click Best Sequence."
            end
        else
            initContent = GetSimcWarning() .. "|cffd0d0d0No training logs or SimC data yet.|r\n\nRun a training dummy test or import a SimC report, then build your sequence."
        end
    elseif suggestMode and seqText and seqText ~= "" then
        -- Prefer the FRESH precomputed seqText (always what would be pushed).
        -- This keeps the display identical to what auto-push / Push-to-GRIP sends.
        local macros, ordered = ParseSequenceLines(seqText)
        local ctx = { logLabel = "suggested", id = nil }
        local deficit = ComputeDeficitSnapshot(castCounts, GetCharDB().simcData, playerDuration)
        initContent = GetSimcWarning() .. BuildKidFriendlyDisplay("best", ctx, seqScore or 0, playerDuration or 1, macros, ordered, deficit)
    elseif suggestMode and Addon.bestSequence and Addon.bestSequence.seqText and Addon.bestSequence.seqText ~= "" then
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
-- SEQUENCE FEED EXPORTS (namespace promotion, rule B)
-- ============================================
Addon.GenerateEMSImportString = GenerateEMSImportString
Addon.IterateSequence = IterateSequence
Addon.ShowConfigureDialog = ShowConfigureDialog
