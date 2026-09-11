local AddonName, Addon = ...
-- ============================================
-- MAIN WINDOW, MINIMAP, SLASH, INIT
-- ============================================
local GetCharDB = Addon.GetCharDB
local DeleteLog = Addon.DeleteLog
local LogDisplayName = Addon.LogDisplayName
local ShortNum = Addon.ShortNum
local GenerateEMSSequence = Addon.GenerateEMSSequence
local ExtractSpellFromSeqLine = Addon.ExtractSpellFromSeqLine
local IsValidMacroSpell = Addon.IsValidMacroSpell
local ShowExportDialog = Addon.ShowExportDialog
local StartTest = Addon.StartTest
local StopTest = Addon.StopTest
local CreateTimerFrame = Addon.CreateTimerFrame
local ShowSimCImportDialog = Addon.ShowSimCImportDialog
local CreateSavedLogsBrowser = Addon.CreateSavedLogsBrowser
local RefreshSavedLogsList = Addon.RefreshSavedLogsList
local BuildSpellNameCache = Addon.BuildSpellNameCache
local C = Addon.C
local FONT = Addon.FONT
local MAIN_FONT = Addon.MAIN_FONT
local BOLD_FONT = Addon.BOLD_FONT
local SafeSetFont = Addon.SafeSetFont
local CreateStyledFrame = Addon.CreateStyledFrame
local CreateStyledButton = Addon.CreateStyledButton
local ApplyBackdrop = Addon.ApplyBackdrop
local CreateSeparator = Addon.CreateSeparator
local trackDialog = Addon.trackDialog
local RegisterAddonWindow = Addon.RegisterAddonWindow
local RecordSpell = Addon.RecordSpell

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
    local bestDpsLog, bestDps = nil, 0
    for _, log in ipairs(selectedLogs) do
        local d = log.dps or 0
        if d > bestDps then bestDps, bestDpsLog = d, log end
    end
    table.insert(lines, "=== SEQUENCE COMPARISON ===\n")
    if bestDpsLog then
        table.insert(lines, string.format("Compared %d logs | Best: %s (%s DPS)",
            #selectedLogs, LogDisplayName(bestDpsLog), Addon.FormatNumber(bestDps)))
    else
        table.insert(lines, "Comparing " .. #selectedLogs .. " logs:")
    end

    -- For each log, show vertical sequence breakdown and DPS
    local allSpells = {}
    local logData = {}
    for _, log in ipairs(selectedLogs) do
        local dpsStr = Addon.FormatNumber(log.dps or 0)
        local label = LogDisplayName(log)
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
        local diff = ld.dps - maxDps
        local diffStr = ld.dps >= maxDps and ("+" .. ShortNum(diff)) or ShortNum(diff)
        table.insert(lines, string.format("%-25s %s DPS (%5.1f%%) %7s  %s", ld.label, Addon.FormatNumber(ld.dps), pct, diffStr, bar))
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
        local underCount, overCount = 0, 0
        for _, s in ipairs(simcSorted) do
            if s.pct < 85 then underCount = underCount + 1
            elseif s.pct > 115 then overCount = overCount + 1 end
        end
        table.insert(lines, "\n  SimC comparison (% of target):")
        table.insert(lines, string.format("    %d spell%s under target, %d spell%s over target",
            underCount, underCount == 1 and "" or "s", overCount, overCount == 1 and "" or "s"))
        for _, s in ipairs(simcSorted) do
            local marker = s.pct < 85 and "« UNDER" or (s.pct > 115 and "» OVER" or "")
            table.insert(lines, string.format("    %-8s%s: %d%%", marker, s.spell, s.pct))
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
        for _, delId in ipairs(toDelete) do
            DeleteLog(delId)
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
            local label = LogDisplayName(log)
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

    local emsBtn = CreateStyledButton(content, "Create Sequence", 140, 32, function()
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
    if Addon.clogDialog then Addon.clogDialog:Hide(); Addon.clogDialog = nil end

    Addon.clogDialog = CreateStyledFrame("Frame", "DummyAnalyzerCLImport", UIParent); trackDialog(Addon.clogDialog)
    Addon.clogDialog:SetSize(600, 480)
    Addon.clogDialog:SetPoint("CENTER")
    Addon.clogDialog:SetFrameStrata("DIALOG")
    Addon.clogDialog:SetMovable(true)
    Addon.clogDialog:SetClampedToScreen(true)
    Addon.clogDialog:EnableMouse(true)
    Addon.clogDialog:RegisterForDrag("LeftButton")
    Addon.clogDialog:SetScript("OnDragStart", Addon.clogDialog.StartMoving)
    Addon.clogDialog:SetScript("OnDragStop", Addon.clogDialog.StopMovingOrSizing)
    ApplyBackdrop(Addon.clogDialog, false)

    local titleBar = CreateStyledFrame("Frame", nil, Addon.clogDialog)
    titleBar:SetPoint("TOPLEFT", Addon.clogDialog, "TOPLEFT")
    titleBar:SetPoint("TOPRIGHT", Addon.clogDialog, "TOPRIGHT")
    titleBar:SetHeight(36)
    titleBar:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
    titleBar:SetBackdropColor(C.title[1], C.title[2], C.title[3], C.title[4])
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() Addon.clogDialog:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() Addon.clogDialog:StopMovingOrSizing() end)

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
    closeBtn:SetScript("OnClick", function() Addon.clogDialog:Hide() end)

    local instrText = Addon.clogDialog:CreateFontString(nil, "OVERLAY")
    SafeSetFont(instrText, MAIN_FONT, 11)
    instrText:SetText("Paste /combatlog file content below (Ctrl+V) then click Import:")
    instrText:SetPoint("TOPLEFT", Addon.clogDialog, "TOPLEFT", 20, -50)
    instrText:SetTextColor(C.text[1], C.text[2], C.text[3], C.text[4])

    local statusText = Addon.clogDialog:CreateFontString(nil, "OVERLAY")
    SafeSetFont(statusText, MAIN_FONT, 11)
    statusText:SetText("")
    statusText:SetPoint("TOPLEFT", Addon.clogDialog, "TOPLEFT", 20, -65)
    statusText:SetTextColor(0.5, 1.0, 0.5, 1)

    local scrollFrame = CreateFrame("ScrollFrame", nil, Addon.clogDialog, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", Addon.clogDialog, "TOPLEFT", 22, -87)
    scrollFrame:SetPoint("BOTTOMRIGHT", Addon.clogDialog, "BOTTOMRIGHT", -22, 50)
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

    local importBtn

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
        Addon.clogDialog:Hide()
        RefreshSavedLogsList()
        if emsWindow and emsWindow.refresh then emsWindow.refresh() end
        print(string.format("|cff33ff33[DummyAnalyzer]|r Imported combat log: %d casts, %d DPS (%s)", parsed.totalCasts, parsed.dps, durStr))
        end)
    end

    local bottomBar = CreateStyledFrame("Frame", nil, Addon.clogDialog)
    bottomBar:SetPoint("BOTTOMLEFT", Addon.clogDialog, "BOTTOMLEFT", 0, 0)
    bottomBar:SetPoint("BOTTOMRIGHT", Addon.clogDialog, "BOTTOMRIGHT", 0, 0)
    bottomBar:SetHeight(45)
    bottomBar:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
    bottomBar:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
    bottomBar:SetFrameLevel(Addon.clogDialog:GetFrameLevel() + 5)

    importBtn = CreateStyledButton(bottomBar, "Import", 100, 30, doImport, "primary")
    importBtn:SetPoint("RIGHT", bottomBar, "CENTER", -55, 0)
    importBtn:SetFrameLevel(bottomBar:GetFrameLevel() + 2)

    local cancelBtn = CreateStyledButton(bottomBar, "Cancel", 100, 30, function() Addon.clogDialog:Hide() end)
    cancelBtn:SetPoint("LEFT", bottomBar, "CENTER", 55, 0)
    cancelBtn:SetFrameLevel(bottomBar:GetFrameLevel() + 2)

    RegisterAddonWindow(Addon.clogDialog)
    Addon.clogDialog:Show()
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
    if Addon.debugMode then print("|cff33ff33[DummyAnalyzer Debug]|r Spell events registered.") end
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
local function GetMinimapIcon()
    -- Probe candidate training-dummy textures. GetFileIDFromPath returns 0
    -- (or nil) for paths the client cannot resolve, so we use whichever dummy
    -- icon actually exists in the 12.x client instead of guessing.
    local candidates = {
        "Interface\\Icons\\INV_Misc_TargetDummy_01",     -- Engineering Target Dummy (item 4366)
        "Interface\\Icons\\INV_Engineering_TargetDummy", -- later-expansion training dummy
    }
    for _, path in ipairs(candidates) do
        local ok, fileID = pcall(GetFileIDFromPath, path)
        if ok and fileID and tonumber(fileID) and tonumber(fileID) ~= 0 then
            return path
        end
    end
    -- Last resort: core-UI skull raid-target icon (always present, still a "target").
    return "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
end

local minimapBtn = CreateFrame("Button", "DummyAnalyzerMinimapBtn", Minimap)
minimapBtn:SetSize(24, 24)
minimapBtn:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -4, -4)
minimapBtn:SetNormalTexture(GetMinimapIcon())
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
SLASH_DUMMYANALYZER2 = "/da"
SlashCmdList["DUMMYANALYZER"] = function(msg)
    if msg == "" or msg == "show" then
        local frame = CreateMainFrame()
        if frame:IsShown() then frame:Hide() else frame:Show() frame:Raise() end
    elseif msg == "30" then StartTest(0.5)
    elseif msg == "2" then StartTest(2)
    elseif msg == "5" then StartTest(5)
    elseif msg == "stop" then StopTest()
    elseif msg == "prune" then
        local keep = (GetCharDB().settings or {}).keepLogsPerSpec or 15
        local pruned = Addon.PruneOldLogs(keep)
        if RefreshSavedLogsList then RefreshSavedLogsList() end
        if Addon.emsWindow and Addon.emsWindow.refresh then Addon.emsWindow.refresh() end
        print(string.format("|cff33ff33[DummyAnalyzer]|r Pruned %d old log(s). Kept last %d per spec.", pruned, keep))
    else
        print("|cff33ff33[DummyAnalyzer]|r Commands: /dummy [show|30|2|5|stop|prune]")
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
        Addon.debugMode = not Addon.debugMode
        print("|cff33ff33[DummyAnalyzer]|r Debug mode " .. (Addon.debugMode and "|cff00ff00ENABLED" or "|cffff0000DISABLED"))
        print("|cff33ff33[DummyAnalyzer]|r Subcommands: /dummydebug (toggle), /dummydebug dump, /dummydebug clear")
    end
end

C_Timer.After(0, function()
    Addon.playerGUID = UnitGUID("player")
    local okName, nm = pcall(UnitName, "player")
    if okName and nm then Addon.playerName = nm end
    -- No CVar gate/warning: the addon does not depend on Blizzard's built-in
    -- damage meter (meter-free health fallback + in-combat snapshot handle it).
    -- EDIT#2: real Midnight damage-meter events mark the session settled so the
    -- report can avoid blind retry loops.
    local meterEventFrame = CreateFrame("Frame")
    meterEventFrame:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
    meterEventFrame:RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED")
    meterEventFrame:RegisterEvent("DAMAGE_METER_RESET")
    meterEventFrame:SetScript("OnEvent", function(_, event)
        if event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" or event == "DAMAGE_METER_CURRENT_SESSION_UPDATED" then
            Addon.meterEventSeen = true
        elseif event == "DAMAGE_METER_RESET" then
            Addon.meterEventSeen = false
        end
    end)
    local initDb = GetCharDB()
    if initDb.bestSequence then Addon.bestSequence = initDb.bestSequence end
    CreateMainFrame()
    CreateTimerFrame()
    Addon.timerFrame:Hide()
    Addon.updateFrame = CreateFrame("Frame")
    SafeInit()  -- registers spell events only when out of combat
    BuildSpellNameCache()
    if Addon.debugMode then
        local count = 0
        for _ in pairs(Addon.spellNameCache) do count = count + 1 end
        print("|cff33ff33[DummyAnalyzer Debug]|r Spell name cache built: " .. count .. " entries")
    end
    print("|cff33ff33[DummyAnalyzer]|r Loaded! /dummy | /dummydebug")
end)