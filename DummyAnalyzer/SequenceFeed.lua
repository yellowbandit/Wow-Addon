local AddonName, Addon = ...
-- ============================================
-- EMS IMPORT STRING GENERATION + ITERATIVE FEEDBACK + EXPORT DIALOG
-- ============================================
local GetCharDB = Addon.GetCharDB
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
    return "!DA01!" .. base64, actionMacros
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

    local tabNames = {"Required Spells", "Sequence Preferences"}
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

    -- Tab 1: Required Spells (scrollable, height set after prefs tab)
    do
        local panel = panels[1]
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
        local loaded = s.requiredSpells or {}
        if #loaded > 0 then DebugLog("info", "cfg-req", "Loaded: " .. table.concat(loaded, ", ")) end
        for _, spellName in ipairs(loaded) do
            AddReqRow(spellName)
        end
    end

    -- Tab 2: Sequence Preferences (layout-driven — currentY tracks content depth)
    do
        local panel = panels[2]
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
            local dd = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
            UIDropDownMenu_SetText(dd, default)
            UIDropDownMenu_Initialize(dd, function()
                for _, opt in ipairs(options) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = opt
                    info.func = function()
                        onSelect(opt)
                        UIDropDownMenu_SetText(dd, opt)
                        CloseDropDownMenus()
                    end
                    UIDropDownMenu_AddButton(info)
                end
            end)
            UIDropDownMenu_SetWidth(dd, CTRL_W, 0)
            return dd
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

        -- Row 1
        PlaceLabel("Max consecutive repeats (0=unlimited):")
        PlaceEdit(s.maxRepeats or 3, function(eb)
            local v = tonumber(eb:GetText()); if v and v >= 0 then s.maxRepeats = v else s.maxRepeats = 0 end
        end)
        currentY = currentY + ROW_H

        -- Row 2
        PlaceLabel("Min Interleave Steps (0=off):")
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

        -- Row 4
        PlaceLabel("Step Function:")
        PlaceDropdown({"Priority", "Sequential", "Random", "ReversePriority"}, s.stepFunction or "Priority", function(opt)
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

        -- Row 8: Reset On — checkboxes equally spaced across available width
        PlaceLabel("Reset on:")
        local resetDefs = {
            {key = "resetOnCombat", label = "Combat", default = true},
            {key = "resetOnTarget", label = "Target", default = true},
            {key = "resetOnGear",   label = "Gear",   default = false},
            {key = "resetOnSpec",   label = "Spec",   default = false},
        }
        local resetSlotW = (PANEL_INNER_W - CTRL_X) / #resetDefs
        for ri, rd in ipairs(resetDefs) do
            local val = (s[rd.key] ~= nil) and s[rd.key] or rd.default
            s[rd.key] = val
            local cb = MakeCheckbox(val, function(v) s[rd.key] = v end)
            cb:SetPoint("TOPLEFT", panel, "TOPLEFT", CTRL_X + (ri - 1) * resetSlotW, -(currentY + 1))
            local clbl = panel:CreateFontString(nil, "OVERLAY")
            SafeSetFont(clbl, FONT, 11)
            clbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
            clbl:SetText(rd.label)
            clbl:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])
        end
        currentY = currentY + ROW_H

        -- Row 9
        PlaceLabel("Reset timer (sec, 0=off):")
        PlaceEdit(s.resetTimer or 0, function(eb)
            local v = tonumber(eb:GetText()); if v and v >= 0 then s.resetTimer = v else s.resetTimer = 0 end
        end)
        currentY = currentY + ROW_H

        -- Row 10
        PlaceLabel("Repeat count (0=no wrap):")
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

        -- ponytail: resize panel and dialog from content depth — no hardcoded height
        local panelH = currentY + 8
        panel:SetHeight(panelH)
        panels[1]:SetHeight(panelH)
        dialog:SetHeight(PANEL_TOP + panelH + WIN_PAD)
    end

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
        for _, b in ipairs({bestBtn, simcBtn, nextBtn, emsBtn}) do
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
                local ctx = { logsCount = 1, logLabelById = { [bestLog.id or 0] = LogDisplayName(bestLog) } }
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
                HighlightTab(bestBtn)
                SetEditText(GetSimcWarning() .. display)
                print(string.format("|cff33ff33[DummyAnalyzer]|r Best sequence from log: %s (%s DPS)", LogDisplayName(bestLog), Addon.FormatNumber(bestDPS)))
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
                    ctx.logLabelById[log.id or 0] = LogDisplayName(log)
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
            HighlightTab(bestBtn)
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
        HighlightTab(emsBtn)
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
-- SEQUENCE FEED EXPORTS (namespace promotion, rule B)
-- ============================================
Addon.GenerateEMSImportString = GenerateEMSImportString
Addon.IterateSequence = IterateSequence
Addon.ShowConfigureDialog = ShowConfigureDialog