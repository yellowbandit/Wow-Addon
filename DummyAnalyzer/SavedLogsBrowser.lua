local AddonName, Addon = ...
-- ============================================
-- SAVED LOGS BROWSER UI
-- ============================================
local GetCharDB = Addon.GetCharDB
local DeleteLog = Addon.DeleteLog
local ShortNum = Addon.ShortNum
local CreateStyledFrame = Addon.CreateStyledFrame
local CreateStyledButton = Addon.CreateStyledButton
local ApplyBackdrop = Addon.ApplyBackdrop
local SafeSetFont = Addon.SafeSetFont
local trackDialog = Addon.trackDialog
local RegisterAddonWindow = Addon.RegisterAddonWindow
local CreateReportPopup = Addon.CreateReportPopup
local ShowCopyDialog = Addon.ShowCopyDialog
local GenerateReportText = Addon.GenerateReportText
local ShowSimCImportDialog = Addon.ShowSimCImportDialog
local C = Addon.C
local MAIN_FONT = Addon.MAIN_FONT
local BOLD_FONT = Addon.BOLD_FONT

-- GenerateEMSSequence is assigned in SequenceCore.lua, which loads after this module.
local function GenerateEMSSequence(castCounts, damageData, ensureSpells, buffUptime)
    return Addon.GenerateEMSSequence(castCounts, damageData, ensureSpells, buffUptime)
end

local function RefreshSavedLogsList()
    if not Addon.savedLogsFrame then return end
    local container = Addon.savedLogsFrame.listContainer
    Addon.savedLogsFrame.rows = {}

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
        table.insert(Addon.savedLogsFrame.rows, {frame = emptyText})
        return
    end

    local yOffset = 0
    for i, log in ipairs(logs) do
        local rowFrame = CreateStyledFrame("Frame", nil, container)
        rowFrame:SetSize(480, 44)
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
            if Addon.savedLogsFrame.rows and Addon.savedLogsFrame.rows[i] then
                Addon.savedLogsFrame.rows[i].checked = isChecked
            end
        end)

        if i % 2 == 0 then
            rowFrame:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
            rowFrame:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 0.5)
        end

        local durStr = log.duration and string.format("%.1fs", log.duration) or "?"
        local dpsStr = log.dps and ShortNum(log.dps) or "?"
        local castsStr = log.totalCasts or "?"
        local castsNum = tonumber(log.totalCasts) or 0
        local simcFlag = log.isSimC and "|cff00ccff[SimC]|r " or ""
        local cleanName = log.detectedSeqName
        if not cleanName and log.label then
            local bn = string.match(log.label, "%[([^%]]+)%]$")
            if bn then cleanName = bn end
        end
        if not cleanName then
            cleanName = log.isSimC and "SimC Reference" or ("#" .. (log.id or "?"))
        end
        local labelText = rowFrame:CreateFontString(nil, "OVERLAY")
        SafeSetFont(labelText, BOLD_FONT, 12)
        labelText:SetText(string.format("%s%s", simcFlag, cleanName))
        labelText:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 32, -2)
        labelText:SetPoint("TOPRIGHT", rowFrame, "TOPRIGHT", -8, -2)
        labelText:SetJustifyH("LEFT")
        labelText:SetHeight(14)
        labelText:SetTextColor(
            log.isSimC and 0.3 or C.text[1],
            log.isSimC and 0.8 or C.text[2],
            log.isSimC and 1.0 or C.text[3],
            C.text[4])

        local statText = rowFrame:CreateFontString(nil, "OVERLAY")
        SafeSetFont(statText, MAIN_FONT, 11)
        statText:SetText(string.format("%s DPS  |  %d casts  |  %s", dpsStr, castsNum, durStr))
        statText:SetPoint("BOTTOMLEFT", rowFrame, "BOTTOMLEFT", 32, 3)
        statText:SetPoint("BOTTOMRIGHT", rowFrame, "BOTTOMRIGHT", -8, 3)
        statText:SetJustifyH("LEFT")
        statText:SetHeight(14)
        statText:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)

        table.insert(Addon.savedLogsFrame.rows, {
            frame = rowFrame,
            logId = log.id,
            checked = false,
        })

        yOffset = yOffset - 46
    end

    container:SetHeight(math.abs(yOffset) + 10)
end

local function ShowComparisonPopup(text)
    if Addon.comparisonPopup then Addon.comparisonPopup:Hide() Addon.comparisonPopup = nil end

    Addon.comparisonPopup = CreateStyledFrame("Frame", "DummyAnalyzerCompareFrame", UIParent); trackDialog(Addon.comparisonPopup)
    Addon.comparisonPopup:SetSize(760, 540)
    Addon.comparisonPopup:SetPoint("CENTER")
    Addon.comparisonPopup:SetMovable(true)
    Addon.comparisonPopup:SetClampedToScreen(true)
    Addon.comparisonPopup:EnableMouse(true)
    Addon.comparisonPopup:RegisterForDrag("LeftButton")
    Addon.comparisonPopup:SetScript("OnDragStart", Addon.comparisonPopup.StartMoving)
    Addon.comparisonPopup:SetScript("OnDragStop", Addon.comparisonPopup.StopMovingOrSizing)
    ApplyBackdrop(Addon.comparisonPopup, false)

    local titleBar = CreateStyledFrame("Frame", nil, Addon.comparisonPopup)
    titleBar:SetPoint("TOPLEFT", Addon.comparisonPopup, "TOPLEFT")
    titleBar:SetPoint("TOPRIGHT", Addon.comparisonPopup, "TOPRIGHT")
    titleBar:SetHeight(36)
    titleBar:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
    titleBar:SetBackdropColor(C.title[1], C.title[2], C.title[3], C.title[4])
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() Addon.comparisonPopup:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() Addon.comparisonPopup:StopMovingOrSizing() end)

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
    closeBtn:SetScript("OnClick", function() Addon.comparisonPopup:Hide() end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, Addon.comparisonPopup, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", Addon.comparisonPopup, "TOPLEFT", 25, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", Addon.comparisonPopup, "BOTTOMRIGHT", -25, 45)

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

    local copyBtn = CreateStyledButton(Addon.comparisonPopup, "Copy Text", 130, 32, function()
        ShowCopyDialog(text)
    end, "primary")
    copyBtn:SetPoint("BOTTOMLEFT", Addon.comparisonPopup, "BOTTOMLEFT", 25, 10)

    local closePopupBtn = CreateStyledButton(Addon.comparisonPopup, "Close", 110, 32, function() Addon.comparisonPopup:Hide() end, "danger")
    closePopupBtn:SetPoint("BOTTOMRIGHT", Addon.comparisonPopup, "BOTTOMRIGHT", -25, 10)

    Addon.comparisonPopup:Show()
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
    if Addon.mainFrame then Addon.mainFrame:Hide() end
    if Addon.savedLogsFrame then RefreshSavedLogsList() RegisterAddonWindow(Addon.savedLogsFrame) Addon.savedLogsFrame:Show() return end

    Addon.savedLogsFrame = CreateStyledFrame("Frame", "DummyAnalyzerSavedLogsFrame", UIParent); trackDialog(Addon.savedLogsFrame)
    Addon.savedLogsFrame:SetSize(550, 420)
    Addon.savedLogsFrame:SetPoint("CENTER")
    Addon.savedLogsFrame:SetMovable(true)
    Addon.savedLogsFrame:SetClampedToScreen(true)
    Addon.savedLogsFrame:EnableMouse(true)
    Addon.savedLogsFrame:RegisterForDrag("LeftButton")
    Addon.savedLogsFrame:SetScript("OnDragStart", Addon.savedLogsFrame.StartMoving)
    Addon.savedLogsFrame:SetScript("OnDragStop", Addon.savedLogsFrame.StopMovingOrSizing)
    ApplyBackdrop(Addon.savedLogsFrame, false)

    local titleBar = CreateStyledFrame("Frame", nil, Addon.savedLogsFrame)
    titleBar:SetPoint("TOPLEFT", Addon.savedLogsFrame, "TOPLEFT")
    titleBar:SetPoint("TOPRIGHT", Addon.savedLogsFrame, "TOPRIGHT")
    titleBar:SetHeight(36)
    titleBar:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
    titleBar:SetBackdropColor(C.title[1], C.title[2], C.title[3], C.title[4])
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() Addon.savedLogsFrame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() Addon.savedLogsFrame:StopMovingOrSizing() end)

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
    closeBtn:SetScript("OnClick", function() Addon.savedLogsFrame:Hide() end)

    local instrText = Addon.savedLogsFrame:CreateFontString(nil, "OVERLAY")
    SafeSetFont(instrText, MAIN_FONT, 11)
    instrText:SetText("Select two logs and click Compare to see side-by-side breakdown.")
    instrText:SetPoint("TOPLEFT", Addon.savedLogsFrame, "TOPLEFT", 20, -48)
    instrText:SetTextColor(C.text[1], C.text[2], C.text[3], C.text[4])

    local function getSelected()
        local selected = {}
        for _, row in ipairs(Addon.savedLogsFrame.rows or {}) do
            if row.checked then table.insert(selected, row.logId) end
        end
        return selected
    end

    local compareBtn = CreateStyledButton(Addon.savedLogsFrame, "Compare Selected", 140, 28, function()
        local selected = getSelected()
        if #selected ~= 2 then
            print("|cff33ff33[DummyAnalyzer]|r Select exactly 2 logs to compare.")
            return
        end
        local compareText = Addon.CompareLogs(selected[1], selected[2])
        ShowComparisonPopup(compareText)
    end)
    compareBtn:SetPoint("TOPLEFT", instrText, "BOTTOMLEFT", 0, -10)

    local renameBtn = CreateStyledButton(Addon.savedLogsFrame, "Rename", 90, 28, function()
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

    local viewBtn = CreateStyledButton(Addon.savedLogsFrame, "View", 80, 28, function()
        local selected = getSelected()
        if #selected ~= 1 then
            print("|cff33ff33[DummyAnalyzer]|r Select exactly 1 log to view its report.")
            return
        end
        local logs = Addon.GetSavedLogs()
        for _, log in ipairs(logs) do
            if log.id == selected[1] then
                local savedDuration = Addon.currentDuration
                local savedStartSeq = Addon.testStartSequence
                local savedTestActive = Addon.testActive
                local savedStartTime = Addon.startTime
                local savedEndTime = Addon.testEndTime
                local savedTotalDmg = Addon.totalDamage
                local savedSpellHist = Addon.spellHistory
                local savedDamData = Addon.damageData
                local savedBuffUp = Addon.buffUptime
                local savedBuffGaps = Addon.buffGaps
                local savedDebuffUp = Addon.debuffUptime
                local savedPowerCosts = Addon.spellPowerCosts
                Addon.currentDuration = log.duration or 0
                Addon.testActive = false
                Addon.startTime = 0
                Addon.testEndTime = log.duration or 0
                Addon.totalDamage = log.totalDamage or 0
                Addon.spellHistory = log.spellHistory or {}
                Addon.damageData = log.damageData or {}
                Addon.buffUptime = log.buffUptime or {}
                Addon.buffGaps = log.buffGaps or {}
                Addon.debuffUptime = log.debuffUptime or {}
                Addon.spellPowerCosts = log.spellPowerCosts or {}
                local reportTextStr = GenerateReportText()
                CreateReportPopup()
                Addon.reportPopup.editBox:SetText(reportTextStr)
                local numLines = 1
                for _ in string.gmatch(reportTextStr, "\n") do numLines = numLines + 1 end
                Addon.reportPopup.editBox:SetHeight(math.max(200, numLines * 14 + 20))
                Addon.reportPopup.editBox:SetCursorPosition(0)
                Addon.reportPopup.scrollFrame:SetVerticalScroll(0)
                Addon.reportPopup.originalText = reportTextStr
                RegisterAddonWindow(Addon.reportPopup)
                Addon.reportPopup:Show()
                Addon.currentDuration = savedDuration
                Addon.testStartSequence = savedStartSeq
                Addon.testActive = savedTestActive
                Addon.startTime = savedStartTime
                Addon.testEndTime = savedEndTime
                Addon.totalDamage = savedTotalDmg
                Addon.spellHistory = savedSpellHist
                Addon.damageData = savedDamData
                Addon.buffUptime = savedBuffUp
                Addon.buffGaps = savedBuffGaps
                Addon.debuffUptime = savedDebuffUp
                Addon.spellPowerCosts = savedPowerCosts
                return
            end
        end
    end)
    viewBtn:SetPoint("LEFT", renameBtn, "RIGHT", 10, 0)

    local simcImportBtn = CreateStyledButton(Addon.savedLogsFrame, "Import SimC", 110, 28, ShowSimCImportDialog)
    simcImportBtn:SetPoint("LEFT", viewBtn, "RIGHT", 10, 0)

    local deleteBtn = CreateStyledButton(Addon.savedLogsFrame, "Delete Selected", 130, 28, function()
        local toDelete = getSelected()
        if #toDelete == 0 then
            print("|cff33ff33[DummyAnalyzer]|r Select logs to delete.")
            return
        end
        for _, slId in ipairs(toDelete) do
            DeleteLog(slId)
        end
        RefreshSavedLogsList()
        if Addon.emsWindow and Addon.emsWindow.refresh then Addon.emsWindow.refresh() end
        print(string.format("|cff33ff33[DummyAnalyzer]|r Deleted %d log(s).", #toDelete))
    end, "danger")
    deleteBtn:SetPoint("TOPLEFT", compareBtn, "BOTTOMLEFT", 0, -4)

    local viewSeqBtn = CreateStyledButton(Addon.savedLogsFrame, "View Seq", 90, 28, function()
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

    local clogImportBtn = CreateStyledButton(Addon.savedLogsFrame, "Combat Log", 110, 28, Addon.ShowCombatLogImportDialog)
    clogImportBtn:SetPoint("LEFT", viewSeqBtn, "RIGHT", 10, 0)

    local scrollFrame = CreateFrame("ScrollFrame", nil, Addon.savedLogsFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", Addon.savedLogsFrame, "TOPLEFT", 20, -130)
    scrollFrame:SetPoint("BOTTOMRIGHT", Addon.savedLogsFrame, "BOTTOMRIGHT", -40, 50)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local step = 46
        if delta > 0 then
            self:SetVerticalScroll(math.max(0, current - step))
        else
            self:SetVerticalScroll(math.min(maxScroll, current + step))
        end
    end)

    local listContainer = CreateFrame("Frame", nil, scrollFrame)
    listContainer:SetWidth(480)
    scrollFrame:SetScrollChild(listContainer)

    Addon.savedLogsFrame.scrollFrame = scrollFrame
    Addon.savedLogsFrame.listContainer = listContainer
    Addon.savedLogsFrame.rows = {}

    RefreshSavedLogsList()
    RegisterAddonWindow(Addon.savedLogsFrame)
    Addon.savedLogsFrame:Show()
end

local function ShowReport()
    local reportTextStr = GenerateReportText()
    CreateReportPopup()
    Addon.reportPopup.editBox:SetText(reportTextStr)
    local numLines = 1
    for _ in string.gmatch(reportTextStr, "\n") do numLines = numLines + 1 end
    Addon.reportPopup.editBox:SetHeight(math.max(200, numLines * 14 + 20))
    Addon.reportPopup.editBox:SetCursorPosition(0)
    Addon.reportPopup.scrollFrame:SetVerticalScroll(0)
    Addon.reportPopup.originalText = reportTextStr
    RegisterAddonWindow(Addon.reportPopup)
    Addon.reportPopup:Show()
end

-- ============================================
-- SAVED LOGS BROWSER EXPORTS (namespace promotion, rule A/B)
-- ============================================
Addon.savedLogsFrame = nil
Addon.CreateSavedLogsBrowser = CreateSavedLogsBrowser
Addon.RefreshSavedLogsList = RefreshSavedLogsList
Addon.ShowReport = ShowReport