local AddonName, Addon = ...
-- ============================================
-- TEST CONTROL
-- ============================================
local CreateStyledFrame = Addon.CreateStyledFrame
local ApplyBackdrop = Addon.ApplyBackdrop
local SafeSetFont = Addon.SafeSetFont
local trackDialog = Addon.trackDialog
local ShortNum = Addon.ShortNum
local ResetDamageData = Addon.ResetDamageData
local ReadDamageMeterData = Addon.ReadDamageMeterData
local ResetMeterCapture = Addon.ResetMeterCapture
local CaptureCombatSnapshot = Addon.CaptureCombatSnapshot
local ResetHealthFallback = Addon.ResetHealthFallback
local ResetBuffTracking = Addon.ResetBuffTracking
local StartBuffTicker = Addon.StartBuffTicker
local FinalizeBuffTracking = Addon.FinalizeBuffTracking
local BOLD_FONT = Addon.BOLD_FONT
local ShowReport = Addon.ShowReport

local reportRetryCount = 0
local MAX_REPORT_RETRIES = 8

local function FinalizeReport()
    Addon.pendingReport = false
    ResetDamageData()
    ReadDamageMeterData()
    if Addon.totalDamage == 0 and Addon.healthTrackReady and Addon.healthTotal > 0 then
        Addon.totalDamage = Addon.healthTotal
        Addon.damageFromHealthFallback = true
        if Addon.debugMode then
            print("|cff33ff33[DummyAnalyzer Debug]|r Damage meter empty, using target-health fallback: " .. ShortNum(Addon.totalDamage))
        end
    end
    if Addon.totalDamage == 0 and reportRetryCount < MAX_REPORT_RETRIES then
        reportRetryCount = reportRetryCount + 1
        if Addon.debugMode then
            print("|cff33ff33[DummyAnalyzer Debug]|r Damage read empty, retrying (" .. reportRetryCount .. "/" .. MAX_REPORT_RETRIES .. ")...")
        end
        C_Timer.After(0.5, FinalizeReport)
        return
    end
    reportRetryCount = 0
    ShowReport()
end

local function QueueReportAfterCombat()
    Addon.pendingReport = true
    if InCombatLockdown and InCombatLockdown() then
        print("|cff33ff33[DummyAnalyzer]|r Test complete. Waiting until combat ends to build damage report...")
        if Addon.reportWaitTicker then
            Addon.reportWaitTicker:Cancel()
            Addon.reportWaitTicker = nil
        end
        Addon.reportWaitTicker = C_Timer.NewTicker(0.5, function(ticker)
            if not InCombatLockdown or not InCombatLockdown() then
                ticker:Cancel()
                Addon.reportWaitTicker = nil
                if Addon.pendingReport then
                    C_Timer.After(0.5, FinalizeReport)
                end
            end
        end)
    else
        C_Timer.After(0.5, FinalizeReport)
    end
end

local function CreateTimerFrame()
    if not Addon.timerFrame then
        Addon.timerFrame = CreateStyledFrame("Frame", nil, UIParent); trackDialog(Addon.timerFrame)
        Addon.timerFrame:SetSize(240, 70)
        Addon.timerFrame:SetPoint("TOP", UIParent, "TOP", 0, -100)
        Addon.timerFrame:SetFrameStrata("TOOLTIP")
        ApplyBackdrop(Addon.timerFrame, true)
        Addon.timerFrame:EnableMouse(true)
        Addon.timerFrame:RegisterForDrag("LeftButton")
        Addon.timerFrame:SetScript("OnDragStart", Addon.timerFrame.StartMoving)
        Addon.timerFrame:SetScript("OnDragStop", Addon.timerFrame.StopMovingOrSizing)

        Addon.timerText = Addon.timerFrame:CreateFontString(nil, "OVERLAY")
        SafeSetFont(Addon.timerText, BOLD_FONT, 20)
        Addon.timerText:SetPoint("TOP", Addon.timerFrame, "TOP", 0, -5)

    end
    Addon.timerFrame:SetHeight(50)
    Addon.timerFrame:Show()
end

local function StopTest()
    local wasArmed = Addon.armedTest
    Addon.armedTest = false
    Addon.armedMinutes = nil
    if Addon.combatWaitTicker then
        Addon.combatWaitTicker:Cancel()
        Addon.combatWaitTicker = nil
    end
    if wasArmed and not Addon.testActive then
        if Addon.timerFrame then Addon.timerFrame:Hide() end
        print("|cff33ff33[DummyAnalyzer]|r Armed test canceled.")
        return
    end
    if not Addon.testActive and Addon.pendingReport then return end
    FinalizeBuffTracking()
    Addon.testEndTime = GetTime()
    Addon.testActive = false
    if Addon.updateFrame then Addon.updateFrame:SetScript("OnUpdate", nil) end
    if Addon.timerFrame then Addon.timerFrame:Hide() end

    if Addon.debugMode then print("|cff33ff33[DummyAnalyzer Debug]|r Timer finished - queueing report...") end
    QueueReportAfterCombat()
end

local function BeginActiveTest(minutes)
    Addon.currentDuration = minutes * 60
    Addon.spellHistory = {}
    ResetDamageData()
    ResetHealthFallback()
    ResetBuffTracking()
    Addon.testActive = true
    Addon.startTime = GetTime()
    Addon.testEndTime = nil
    -- Seed the in-combat meter capture baseline at test start so later deltas
    -- only count damage dealt after this moment.
    ResetMeterCapture()
    CaptureCombatSnapshot(true)
    -- Snapshot which GRIP-EMS sequence is active at test start. Sourced from the public
    -- SEQUENCE_STEP_ADVANCED event (see Ems_RegisterEvents), not from Engine internals.
    Addon.testStartSequence = Addon.lastActiveSequence
    StartBuffTicker()
    local minuteText = minutes == 0.5 and "30 sec" or (minutes .. " min")
    print(string.format("|cff33ff33[DummyAnalyzer]|r Test started: %s", minuteText))

    CreateTimerFrame()

    if Addon.updateFrame then Addon.updateFrame:SetScript("OnUpdate", nil) end
    Addon.updateFrame:SetScript("OnUpdate", function()
        if not Addon.testActive then return end
        local elapsed = GetTime() - Addon.startTime
        local remaining = Addon.currentDuration - elapsed
        if remaining <= 0 then StopTest() return end
        local mins = math.floor(remaining / 60)
        local secs = remaining % 60
        if Addon.currentDuration == 30 then
            Addon.timerText:SetText(string.format("%d sec", math.floor(remaining)))
        else
            Addon.timerText:SetText(string.format("%02d:%02d", mins, secs))
        end
    end)
end

local function StartTest(minutes)
    if Addon.testActive then StopTest() end
    if Addon.combatWaitTicker then
        Addon.combatWaitTicker:Cancel()
        Addon.combatWaitTicker = nil
    end

    Addon.armedTest = true
    Addon.armedMinutes = minutes
    local minuteText = minutes == 0.5 and "30 sec" or (minutes .. " min")
    print(string.format("|cff33ff33[DummyAnalyzer]|r Armed: %s test. Timer starts when you enter combat.", minuteText))
    CreateTimerFrame()
    Addon.timerText:SetText("Waiting for combat")

    Addon.combatWaitTicker = C_Timer.NewTicker(0.2, function(ticker)
        if not Addon.armedTest then
            ticker:Cancel()
            Addon.combatWaitTicker = nil
            return
        end
        if InCombatLockdown and InCombatLockdown() then
            ticker:Cancel()
            Addon.combatWaitTicker = nil
            Addon.armedTest = false
            BeginActiveTest(Addon.armedMinutes or minutes)
        end
    end)
end

-- ============================================
-- TEST CONTROL EXPORTS (namespace promotion, rule A/B)
-- ============================================
Addon.StartTest = StartTest
Addon.StopTest = StopTest
Addon.CreateTimerFrame = CreateTimerFrame