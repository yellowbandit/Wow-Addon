local AddonName, Addon = ...
-- ============================================
-- REPORT WINDOW + COPY DIALOG
-- ============================================
local RegisterAddonWindow = Addon.RegisterAddonWindow
local trackDialog = Addon.trackDialog
local CreateStyledFrame = Addon.CreateStyledFrame
local CreateStyledButton = Addon.CreateStyledButton
local ApplyBackdrop = Addon.ApplyBackdrop
local SafeSetFont = Addon.SafeSetFont
local GenerateMarkdownReport = Addon.GenerateMarkdownReport
local SaveCurrentLog = Addon.SaveCurrentLog
local C = Addon.C
local MAIN_FONT = Addon.MAIN_FONT
local BOLD_FONT = Addon.BOLD_FONT

Addon.reportPopup = nil
local copyDialog = nil
local ShowCopyDialog

local function CreateReportPopup()
    if Addon.reportPopup then RegisterAddonWindow(Addon.reportPopup); Addon.reportPopup:Show() return end

    Addon.reportPopup = CreateStyledFrame("Frame", "DummyAnalyzerReportFrame", UIParent); trackDialog(Addon.reportPopup)
    Addon.reportPopup:SetSize(720, 540)
    Addon.reportPopup:SetPoint("CENTER")
    Addon.reportPopup:SetMovable(true)
    Addon.reportPopup:SetClampedToScreen(true)
    Addon.reportPopup:EnableMouse(true)
    Addon.reportPopup:RegisterForDrag("LeftButton")
    Addon.reportPopup:SetScript("OnDragStart", Addon.reportPopup.StartMoving)
    Addon.reportPopup:SetScript("OnDragStop", Addon.reportPopup.StopMovingOrSizing)
    ApplyBackdrop(Addon.reportPopup, false)

    local titleBar = CreateStyledFrame("Frame", nil, Addon.reportPopup)
    titleBar:SetPoint("TOPLEFT", Addon.reportPopup, "TOPLEFT")
    titleBar:SetPoint("TOPRIGHT", Addon.reportPopup, "TOPRIGHT")
    titleBar:SetHeight(36)
    titleBar:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
    titleBar:SetBackdropColor(C.title[1], C.title[2], C.title[3], C.title[4])
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() Addon.reportPopup:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() Addon.reportPopup:StopMovingOrSizing() end)

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
    closeBtn:SetScript("OnClick", function() Addon.reportPopup:Hide() end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, Addon.reportPopup, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", Addon.reportPopup, "TOPLEFT", 25, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", Addon.reportPopup, "BOTTOMRIGHT", -25, 90)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetTextColor(1, 1, 1, 1)
    editBox:SetWidth(560)
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetScript("OnEscapePressed", function() editBox:ClearFocus() end)
    scrollFrame:SetScrollChild(editBox)
    Addon.reportPopup.scrollFrame = scrollFrame
    Addon.reportPopup.editBox = editBox
    Addon.reportPopup.originalText = ""

    local bottomRow = CreateFrame("Frame", nil, Addon.reportPopup)
    bottomRow:SetPoint("BOTTOMLEFT", Addon.reportPopup, "BOTTOMLEFT", 10, 48)
    bottomRow:SetPoint("BOTTOMRIGHT", Addon.reportPopup, "BOTTOMRIGHT", -10, 48)
    bottomRow:SetHeight(32)

    local selectBtn = CreateStyledButton(bottomRow, "Select All", 120, 32, function()
        if Addon.reportPopup.editBox then
            Addon.reportPopup.editBox:SetFocus()
            Addon.reportPopup.editBox:HighlightText()
        elseif Addon.reportPopup.originalText then
            ShowCopyDialog(Addon.reportPopup.originalText)
        end
    end, "primary")
    selectBtn:SetPoint("LEFT", bottomRow, "LEFT", 0, 0)

    local refreshBtn = CreateStyledButton(bottomRow, "Refresh Report", 120, 32, function()
        if Addon.reportPopup.originalText then
            Addon.reportPopup.editBox:SetText(Addon.reportPopup.originalText)
            Addon.reportPopup.editBox:SetCursorPosition(0)
            Addon.reportPopup.scrollFrame:SetVerticalScroll(0)
        end
    end)
    refreshBtn:SetPoint("LEFT", selectBtn, "RIGHT", 10, 0)

    local closePopupBtn = CreateStyledButton(bottomRow, "Close", 100, 32, function() Addon.reportPopup:Hide() end, "danger")
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
-- REPORT WINDOW EXPORTS (namespace promotion, rule A/B)
-- ============================================
Addon.CreateReportPopup = CreateReportPopup
Addon.ShowCopyDialog = ShowCopyDialog